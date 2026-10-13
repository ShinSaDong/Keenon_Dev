"""관제 핵심 로직: 로봇 메시지 처리, 작업(호출·복귀·취소) 관리, 오프라인 감시"""
from __future__ import annotations

import json
import logging
import math
import secrets
import threading
from datetime import datetime, timedelta
from typing import Any

from sqlalchemy import select

from .. import protocol as P
from ..db import AuditLog, Point, Robot, Scene, Task, TaskEvent, session_scope, utcnow
from ..link.base import RobotLink
from .events import EventHub

log = logging.getLogger("core")

FINAL = {0, 4, 5}
ONLINE_TYPE_CODE = {"wi-fi": 2, "wifi": 2, "3g": 3, "4g": 4}


class ApiError(Exception):
    """Keenon 형식 오류 (HTTP 200 + code/msg)"""

    def __init__(self, code: int, msg: str):
        super().__init__(msg)
        self.code = code
        self.msg = msg


def new_task_no() -> str:
    return secrets.token_hex(16)


class ControlCore:
    def __init__(self, link: RobotLink, events: EventHub, offline_timeout: int = 30):
        self.link = link
        self.events = events
        self.offline_timeout = offline_timeout
        self._stop = threading.Event()
        self._watchdog: threading.Thread | None = None

    # ================================================================ 시작/종료
    def start(self) -> None:
        with session_scope() as s:  # 재시작 시 모든 로봇은 오프라인에서 시작
            for r in s.scalars(select(Robot)):
                r.online = False
                r.can_be_called = False
        self.link.start(self.on_robot_message)
        self._watchdog = threading.Thread(target=self._watch, name="offline-watchdog", daemon=True)
        self._watchdog.start()

    def stop(self) -> None:
        self._stop.set()
        self.link.stop()

    def _watch(self) -> None:
        while not self._stop.wait(5):
            limit = utcnow() - timedelta(seconds=self.offline_timeout)
            changed: list[str] = []
            with session_scope() as s:
                for r in s.scalars(select(Robot).where(Robot.online.is_(True))):
                    if r.last_seen is None or r.last_seen < limit:
                        r.online = False
                        r.can_be_called = False
                        changed.append(r.sn)
            for sn in changed:
                log.info("오프라인 처리: %s", sn)
                self.events.publish("RobotOnlineStatus", {"robotSn": sn, "onlineStatus": False})

    # ================================================================ 로봇 → 서버
    def on_robot_message(self, sn: str, msg: dict[str, Any]) -> None:
        action = msg.get("action")
        data = msg.get("data") or {}
        task_no = msg.get("taskNo")
        events: list[tuple[str, dict[str, Any], bool]] = []
        with session_scope() as s:
            r = s.get(Robot, sn)
            if r is None:
                # 등록되지 않은 로봇: 미배정 상태로 자동 등록 (관리자가 매장 배정)
                r = Robot(sn=sn, name=str(data.get("name") or sn), online=False)
                s.add(r)
                log.warning("미등록 로봇 접속: %s", sn)
            was_online = r.online
            r.last_seen = utcnow()
            r.online = True if action != P.ONLINE else bool(data.get("onlineStatus", True))

            if action == P.HELLO:
                r.name = str(data.get("name") or r.name)
                r.model = str(data.get("model") or r.model)
                r.app_version = str(data.get("appVersion") or r.app_version)
                if data.get("kind") in ("serving", "hotel"):
                    r.kind = data["kind"]
                if data.get("sceneCode"):
                    r.scene_code = str(data["sceneCode"])
            elif action == P.ONLINE:
                r.online_type = str(data.get("onlineType") or r.online_type)
                events.append(("RobotOnlineType", {"robotSn": sn, "onlineType": r.online_type}, True))
            elif action == P.POWER:
                r.battery = _int(data.get("batteryLevel"), r.battery)
                r.charging = _int(data.get("chargeStatus"), -1) == 1
                events.append(("RobotPowerInfo", {"robotSn": sn, "power": {
                    "chargeStatus": 1 if r.charging else -1, "batteryLevel": r.battery}}, True))
            elif action == P.WORK_STATE:
                r.work_state = _int(data.get("robotState"), r.work_state)
                r.can_be_called = bool(data.get("canBeCalled")) and r.current_task is None
                events.append(("RobotWorkState", {"robotSn": sn, "robotState": r.work_state,
                                                  "canBeCalled": r.can_be_called}, True))
            elif action == P.POSITION:
                r.x = _float(data.get("x"), r.x)
                r.y = _float(data.get("y"), r.y)
                r.angle = _float(data.get("rotation"), r.angle)
                r.floor = str(data.get("floor") or r.floor or "1")
                r.in_elevator = _int(data.get("takeElevatorStatus"), 0) == 1
                if data.get("sceneCode"):
                    r.scene_code = str(data["sceneCode"])
                events.append(("RobotPositionType", {"robotSn": sn, "robotPos": {
                    "x": r.x, "y": r.y, "rotation": r.angle}, "floor": r.floor}, False))
            elif action == P.TASK_STATE and task_no:
                ev = self._apply_task_state(s, r, task_no, data)
                if ev:
                    events.append(ev)
            elif action == P.ACK:
                ok = _int(data.get("result"), 0) == 1
                if not ok and task_no:
                    t = s.get(Task, task_no)
                    if t is not None and t.status not in FINAL and data.get("ackAction") != P.CANCEL_TASK:
                        ev = self._apply_task_state(s, r, task_no, {
                            "taskState": 0, "errorCode": _int(data.get("errorCode"), 303)})
                        if ev:
                            events.append(ev)

            if not was_online and r.online:
                events.append(("RobotOnlineStatus", {"robotSn": sn, "onlineStatus": True}, True))
            if not r.online:
                r.can_be_called = False
                events.append(("RobotOnlineStatus", {"robotSn": sn, "onlineStatus": False}, True))

        for biz, d, wh in events:
            self.events.publish(biz, d, webhook=wh)

    def _apply_task_state(self, s, r: Robot, task_no: str, data: dict[str, Any]):  # noqa: ANN001
        t = s.get(Task, task_no)
        if t is None:
            return None
        if t.status in FINAL:
            return None
        status = _int(data.get("taskState"), t.status)
        now = utcnow()
        t.status = status
        t.error_code = _int(data.get("errorCode"), None)
        rem = data.get("remainingDistance")
        if rem is not None:
            t.remaining = _float(rem, t.remaining)
        if data.get("mileage") is not None:
            t.mileage = _float(data.get("mileage"), t.mileage) or 0.0
        if status == 3 and t.started_at is None:
            t.started_at = now
        if status == 6 and t.arrived_at is None:
            t.arrived_at = now
            t.remaining = 0.0
        if status in FINAL:
            t.finished_at = now
            if status == 4:
                t.remaining = 0.0
            if r.current_task == task_no:
                r.current_task = None
        t.updated_at = now
        s.add(TaskEvent(task_no=task_no, status=status, error_code=t.error_code,
                        detail=json.dumps(data, ensure_ascii=False)))
        return ("CreateTask", self.task_payload(t), True)

    # ================================================================ 작업
    def _pick_robot(self, s, store_id: str, robot_sn: str | None, robot_type: str | None,  # noqa: ANN001
                    target: Point | None) -> Robot:
        if robot_sn:
            r = s.get(Robot, robot_sn)
            if r is None or r.store_id != store_id:
                raise ApiError(610601, "로봇을 찾을 수 없습니다")
            if not r.online:
                raise ApiError(615001, "로봇이 오프라인입니다")
            if r.current_task is not None or not r.can_be_called:
                raise ApiError(5001, "로봇이 대기 상태가 아닙니다")
            return r
        q = select(Robot).where(Robot.store_id == store_id, Robot.online.is_(True),
                                Robot.can_be_called.is_(True), Robot.current_task.is_(None))
        cands = [r for r in s.scalars(q) if (r.battery or 0) > 20]
        if robot_type == "hotel":
            cands = [r for r in cands if r.kind == "hotel"] or cands
        elif robot_type == "food":
            cands = [r for r in cands if r.kind == "serving"] or cands
        if not cands:
            raise ApiError(610500, "사용 가능한 로봇이 없습니다")
        if target is not None and target.x is not None and target.y is not None:
            cands.sort(key=lambda r: math.hypot((r.x or 0) - target.x, (r.y or 0) - target.y))
        return cands[0]

    def create_call(self, *, store_id: str, uuid: str, point_id: str, scene_code: str | None,
                    robot_sn: str | None, robot_type: str | None, actor: str) -> dict[str, Any]:
        with session_scope() as s:
            p = s.get(Point, uuid) if uuid else None
            if p is None and point_id:
                q = select(Point).where(Point.point_id == str(point_id))
                if scene_code:
                    q = q.where(Point.scene_code == scene_code)
                p = s.scalars(q).first()
            if p is None:
                raise ApiError(610601, "목적지 포인트를 찾을 수 없습니다")
            scene = s.get(Scene, p.scene_code)
            if scene is None or scene.store_id != store_id:
                raise ApiError(610601, "매장과 포인트가 일치하지 않습니다")
            r = self._pick_robot(s, store_id, robot_sn, robot_type, p)
            t = Task(task_no=new_task_no(), store_id=store_id, robot_sn=r.sn, task_type="call",
                     scene_code=p.scene_code, point_uuid=p.uuid, point_id=p.point_id, point_name=p.name,
                     status=1, requested_by=actor)
            s.add(t)
            r.current_task = t.task_no
            r.can_be_called = False
            s.add(TaskEvent(task_no=t.task_no, status=1, detail="created"))
            s.add(AuditLog(actor=actor, action="CALL", target=r.sn, detail=f"{p.name} ({p.uuid}) task={t.task_no}"))
            waiting = len(list(s.scalars(select(Task.task_no).where(Task.store_id == store_id, Task.status == 1))))
            cmd = P.envelope(P.CREATE_TASK, r.sn, {"uuid": p.uuid, "pointId": p.point_id, "pointName": p.name,
                                                   "sceneCode": p.scene_code}, t.task_no)
            task_no, sn = t.task_no, r.sn
        self._send_or_fail(sn, task_no, cmd)
        self.events.publish("CreateTask", self.get_task(task_no))
        return {"taskNo": task_no, "waitQueuing": waiting}

    def create_return(self, *, store_id: str, robot_sn: str | None, actor: str) -> dict[str, Any]:
        with session_scope() as s:
            if robot_sn:
                r = s.get(Robot, robot_sn)
                if r is None or r.store_id != store_id:
                    raise ApiError(610601, "로봇을 찾을 수 없습니다")
            else:
                r = s.scalars(select(Robot).where(Robot.store_id == store_id, Robot.online.is_(True))).first()
                if r is None:
                    raise ApiError(610500, "사용 가능한 로봇이 없습니다")
            if not r.online:
                raise ApiError(615001, "로봇이 오프라인입니다")
            if r.current_task:  # 수행 중 작업은 취소 처리
                old = s.get(Task, r.current_task)
                if old is not None and old.status not in FINAL:
                    old.status, old.finished_at = 5, utcnow()
                    s.add(TaskEvent(task_no=old.task_no, status=5, detail="replaced by return"))
            t = Task(task_no=new_task_no(), store_id=store_id, robot_sn=r.sn, task_type="return",
                     scene_code=r.scene_code or "", point_name="원점", status=1, requested_by=actor)
            s.add(t)
            r.current_task = t.task_no
            r.can_be_called = False
            s.add(TaskEvent(task_no=t.task_no, status=1, detail="created"))
            s.add(AuditLog(actor=actor, action="RETURN", target=r.sn, detail=f"task={t.task_no}"))
            cmd = P.envelope(P.RETURN_ORIGIN, r.sn, {}, t.task_no)
            task_no, sn = t.task_no, r.sn
        self._send_or_fail(sn, task_no, cmd)
        return {"taskNo": task_no, "waitQueuing": 0}

    def _send_or_fail(self, sn: str, task_no: str, cmd: dict[str, Any]) -> None:
        if self.link.send(sn, cmd):
            return
        with session_scope() as s:
            t = s.get(Task, task_no)
            r = s.get(Robot, sn)
            if t is not None and t.status not in FINAL:
                t.status, t.error_code, t.finished_at = 0, 502, utcnow()
                s.add(TaskEvent(task_no=task_no, status=0, error_code=502, detail="send failed"))
            if r is not None and r.current_task == task_no:
                r.current_task = None
        raise ApiError(615001, "로봇에 명령을 전달하지 못했습니다 (연결 끊김)")

    def cancel(self, task_no: str, actor: str) -> None:
        with session_scope() as s:
            t = s.get(Task, task_no)
            if t is None:
                raise ApiError(610601, "작업을 찾을 수 없습니다")
            if t.status in FINAL:
                raise ApiError(5004, "이미 종료된 작업입니다")
            r = s.get(Robot, t.robot_sn) if t.robot_sn else None
            s.add(AuditLog(actor=actor, action="CANCEL", target=t.robot_sn or "", detail=f"task={task_no}"))
            sn = r.sn if r is not None else None
            online = bool(r and r.online)
        if sn and online and self.link.send(sn, P.envelope(P.CANCEL_TASK, sn, {}, task_no)):
            return  # 로봇이 TaskState 5 로 확정
        with session_scope() as s:  # 로봇이 없거나 오프라인이면 서버에서 바로 취소
            t = s.get(Task, task_no)
            r = s.get(Robot, sn) if sn else None
            if t is not None and t.status not in FINAL:
                t.status, t.finished_at = 5, utcnow()
                s.add(TaskEvent(task_no=task_no, status=5, detail="canceled by server"))
            if r is not None and r.current_task == task_no:
                r.current_task = None

    def get_task(self, task_no: str) -> dict[str, Any]:
        with session_scope() as s:
            t = s.get(Task, task_no)
            if t is None:
                raise ApiError(610601, "작업을 찾을 수 없습니다")
            return self.task_payload(t)

    @staticmethod
    def task_payload(t: Task) -> dict[str, Any]:
        return {
            "taskNo": t.task_no,
            "taskStatus": t.status,
            "errorCode": t.error_code,
            "remark": "원점 복귀" if t.task_type == "return" else f"호출 → {t.point_name}",
            "deviceId": t.requested_by,
            "taskData": {
                "remainingDistance": t.remaining,
                "robotId": t.robot_sn,
                "robotSn": t.robot_sn,
                "waitQueuing": 1 if t.status == 1 else 0,
                "lastUpdateTime": fmt_kst(t.updated_at),
            },
        }


# ------------------------------------------------------------------ 유틸
def _int(v: Any, default: Any) -> Any:
    try:
        return int(v) if v is not None else default
    except (TypeError, ValueError):
        return default


def _float(v: Any, default: Any) -> Any:
    try:
        return float(v) if v is not None else default
    except (TypeError, ValueError):
        return default


KST = timedelta(hours=9)


def fmt_kst(dt: datetime | None) -> str:
    return "" if dt is None else (dt + KST).strftime("%Y-%m-%d %H:%M:%S")
