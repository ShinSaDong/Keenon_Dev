"""가상 로봇 시뮬레이터 (전송 방식과 무관)

실제 로봇 대신 접속해서 상태·위치·작업 진행을 올리고, 서버 명령(호출·취소·복귀)에 반응한다.
Fleet(publish=...) 의 publish 콜백으로 메시지를 내보내고, deliver() 로 명령을 받는다.
"""
from __future__ import annotations

import logging
import math
import queue
import threading
import time
from typing import Any, Callable

from app import protocol as P
from app.layouts import LAYOUTS, RobotDef, SceneLayout, plan_path

log = logging.getLogger("simulator")

SPEED = 0.9          # m/s
CALL_DELAY = 2.0     # 호출 접수 → 출발까지
BACK_DELAY = 1.0
ARRIVE_DWELL = 8.0   # 도착 후 수령 대기
POS_MOVING = 0.4     # 이동 중 위치 전송 간격(초)
POS_IDLE = 5.0
POWER_EVERY = 10.0
TASK_EVERY = 1.0


class SimRobot:
    def __init__(self, d: RobotDef, layout: SceneLayout, publish: Callable[[dict[str, Any]], None]):
        self.d = d
        self.layout = layout
        self._publish = publish
        self.x, self.y = d.dock
        self.heading = math.pi / 2
        self.path: list[tuple[float, float]] = []
        self.battery = float(d.battery)
        self.online = d.online
        self.task: dict[str, Any] | None = None
        self._ws: tuple[int, bool] | None = None
        self._charging: bool | None = None
        self._last_pos = 0.0
        self._last_power = 0.0
        self._last_task = 0.0

    # ------------------------------------------------------------ 송신
    def emit(self, action: str, data: dict[str, Any], task_no: str | None = None, code: int = P.SUCCESS) -> None:
        self._publish(P.envelope(action, self.d.sn, data, task_no, code=code))

    def _ack(self, msg: dict[str, Any], ok: bool, error_code: int | None = None) -> None:
        self.emit(P.ACK, {"ackMessageId": msg.get("messageId"), "ackAction": msg.get("action"),
                          "result": 1 if ok else 0, "errorCode": error_code}, msg.get("taskNo"),
                  code=P.SUCCESS if ok else 615000)

    def at_dock(self) -> bool:
        return math.hypot(self.x - self.d.dock[0], self.y - self.d.dock[1]) < 0.1

    def boot(self) -> None:
        if not self.online:
            return
        self.emit(P.HELLO, {"name": self.d.name, "model": self.d.model, "appVersion": self.d.app_version,
                            "kind": self.d.kind, "storeId": self.layout.store_id, "sceneCode": self.layout.scene_code})
        self.emit(P.ONLINE, {"onlineStatus": True, "onlineType": "Wi-Fi"})
        self._send_power(force=True)
        self._send_work_state(force=True)
        self._send_position()

    # ------------------------------------------------------------ 명령 처리
    def handle(self, msg: dict[str, Any]) -> None:
        action = msg.get("action")
        data = msg.get("data") or {}
        task_no = msg.get("taskNo")
        now = time.monotonic()
        if not self.online:
            return  # 오프라인 로봇은 응답 없음 → 서버가 시간 초과/오프라인 처리
        if action == P.CREATE_TASK:
            if self.task is not None:
                return self._ack(msg, False, 302)  # 다른 작업 수행 중
            if self.battery <= 20:
                return self._ack(msg, False, 303)  # 작업 거부(배터리 부족)
            pt = self.layout.point_by_uuid(str(data.get("uuid", "")))
            if pt is None:
                pt = next((p for p in self.layout.points if p.point_id == str(data.get("pointId", ""))), None)
            if pt is None:
                return self._ack(msg, False, 305)  # 목적지 인식 불가
            self.task = {"no": task_no, "kind": "call", "target": (pt.x, pt.y), "phase": "calling",
                         "t": now, "mileage": 0.0, "name": pt.name}
            self._ack(msg, True)
            self._send_task(2)
        elif action == P.RETURN_ORIGIN:
            if self.task is not None:
                self._send_task(5, error_code=None)  # 기존 작업 취소
            self.task = {"no": task_no, "kind": "back", "target": self.d.dock, "phase": "calling",
                         "t": now, "mileage": 0.0, "name": "원점"}
            self._ack(msg, True)
            self._send_task(2)
        elif action == P.CANCEL_TASK:
            if self.task is None or self.task["no"] != task_no:
                return self._ack(msg, False, 304)  # 해당 작업 없음
            self._ack(msg, True)
            self._send_task(5)
            self.task = None
            self.path = plan_path(self.x, self.y, self.d.dock, self.layout.aisle_y)
        else:
            self._ack(msg, False, 290001)

    # ------------------------------------------------------------ 상태 전송
    def _send_task(self, state: int, error_code: int | None = None) -> None:
        t = self.task
        if t is None:
            return
        remaining = self._remaining() if t["phase"] == "moving" else (0.0 if t["phase"] == "arrived" else None)
        self.emit(P.TASK_STATE, {"taskState": state, "errorCode": error_code,
                                 "remainingDistance": None if remaining is None else round(remaining, 1),
                                 "mileage": round(t["mileage"], 1), "target": t["name"]}, t["no"])
        self._last_task = time.monotonic()

    def _send_position(self) -> None:
        self.emit(P.POSITION, {"x": round(self.x, 2), "y": round(self.y, 2), "rotation": round(self.heading, 3),
                               "floor": "1", "building": "", "takeElevatorStatus": 0,
                               "sceneCode": self.layout.scene_code})
        self._last_pos = time.monotonic()

    def _send_power(self, force: bool = False) -> None:
        charging = self.at_dock() and self.task is None and self.battery < 100
        if force or charging != self._charging or time.monotonic() - self._last_power >= POWER_EVERY:
            self._charging = charging
            self.emit(P.POWER, {"chargeStatus": 1 if charging else -1, "batteryLevel": int(self.battery)})
            self._last_power = time.monotonic()

    def _send_work_state(self, force: bool = False) -> None:
        if self.task is not None:
            ws = 1
        elif self.path:
            ws = 4  # 복귀 이동 중(스케줄링)
        elif self.at_dock() and self.battery < 100:
            ws = 5
        else:
            ws = 2
        can = self.task is None and self.battery > 20
        if force or self._ws != (ws, can):
            self._ws = (ws, can)
            self.emit(P.WORK_STATE, {"robotState": ws, "canBeCalled": can})

    def _remaining(self) -> float:
        d, cx, cy = 0.0, self.x, self.y
        for px, py in self.path:
            d += math.hypot(px - cx, py - cy)
            cx, cy = px, py
        return d

    # ------------------------------------------------------------ 주기 처리
    def tick(self, dt: float) -> None:
        if not self.online:
            return
        now = time.monotonic()
        moved = self._move(dt)
        if moved > 0:
            self.battery = max(0.0, self.battery - 0.03 * dt)
            if self.task is not None:
                self.task["mileage"] += moved
        elif self.at_dock() and self.task is None:
            self.battery = min(100.0, self.battery + 0.2 * dt)

        t = self.task
        if t is not None:
            if t["phase"] == "calling":
                delay = BACK_DELAY if t["kind"] == "back" else CALL_DELAY
                if now - t["t"] >= delay:
                    t["phase"] = "moving"
                    self.path = plan_path(self.x, self.y, t["target"], self.layout.aisle_y)
                    self._send_task(3)
            elif t["phase"] == "moving":
                if not self.path:
                    if t["kind"] == "back":
                        t["phase"] = "arrived"
                        self._send_task(4)
                        self.task = None
                    else:
                        t["phase"] = "arrived"
                        t["t"] = now
                        self._send_task(6)
                elif now - self._last_task >= TASK_EVERY:
                    self._send_task(3)
            elif t["phase"] == "arrived" and now - t["t"] >= ARRIVE_DWELL:
                self._send_task(4)
                self.task = None
                self.path = plan_path(self.x, self.y, self.d.dock, self.layout.aisle_y)

        if now - self._last_pos >= (POS_MOVING if self.path else POS_IDLE):
            self._send_position()
        self._send_power()
        self._send_work_state()

    def _move(self, dt: float) -> float:
        budget = SPEED * dt
        moved = 0.0
        while budget > 1e-9 and self.path:
            tx, ty = self.path[0]
            dx, dy = tx - self.x, ty - self.y
            d = math.hypot(dx, dy)
            if d < 1e-6:
                self.path.pop(0)
                continue
            self.heading = math.atan2(dy, dx)
            step = min(d, budget)
            self.x += dx / d * step
            self.y += dy / d * step
            budget -= step
            moved += step
            if step >= d:
                self.path.pop(0)
        return moved


class Fleet:
    """여러 가상 로봇을 한 스레드에서 돌린다. 명령은 큐로 받아 같은 스레드에서 처리."""

    def __init__(self, publish: Callable[[str, dict[str, Any]], None], layouts: list[SceneLayout] | None = None,
                 tick: float = 0.1):
        self.robots: dict[str, SimRobot] = {}
        for lay in layouts or LAYOUTS:
            for d in lay.robots:
                self.robots[d.sn] = SimRobot(d, lay, lambda m, sn=d.sn: publish(sn, m))
        self._tick = tick
        self._inbox: queue.Queue[tuple[str, dict[str, Any]]] = queue.Queue()
        self._stop = threading.Event()
        self._thread: threading.Thread | None = None

    def deliver(self, sn: str, msg: dict[str, Any]) -> None:
        self._inbox.put((sn, msg))

    def start(self) -> None:
        self._thread = threading.Thread(target=self._run, name="sim-fleet", daemon=True)
        self._thread.start()

    def stop(self) -> None:
        self._stop.set()
        if self._thread:
            self._thread.join(timeout=2)

    def _run(self) -> None:
        for r in self.robots.values():
            r.boot()
        last = time.monotonic()
        while not self._stop.is_set():
            while True:
                try:
                    sn, msg = self._inbox.get_nowait()
                except queue.Empty:
                    break
                r = self.robots.get(sn)
                if r is not None:
                    try:
                        r.handle(msg)
                    except Exception:  # pragma: no cover
                        log.exception("명령 처리 오류 %s", sn)
            now = time.monotonic()
            dt, last = now - last, now
            for r in self.robots.values():
                try:
                    r.tick(dt)
                except Exception:  # pragma: no cover
                    log.exception("시뮬레이션 오류 %s", r.d.sn)
            self._stop.wait(self._tick)
