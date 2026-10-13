"""Keenon Cloud Open API 호환 엔드포인트 (문서 V2.4.0 기준)

경로·파라미터·응답 형식({code, msg, data})을 Keenon 과 같게 맞춰서,
기존 앱(Keenon API 클라이언트)이 서버 주소만 바꾸면 그대로 동작하게 한다.
"""
from __future__ import annotations

import base64
import secrets
import threading
import time
from datetime import datetime, timedelta, timezone
from typing import Any

from fastapi import APIRouter, Depends, Form, Header, Request
from fastapi.responses import JSONResponse
from sqlalchemy import select

from ..config import get_settings
from ..db import Point, Robot, Scene, Store, Task, session_scope
from ..services.core import FINAL, ONLINE_TYPE_CODE, ApiError, ControlCore, fmt_kst

router = APIRouter()

SUCCESS = 610000


def ok(data: Any = None, msg: str = "success") -> dict[str, Any]:
    body: dict[str, Any] = {"code": SUCCESS, "msg": msg}
    if data is not None:
        body["data"] = data
    return body


# ------------------------------------------------------------------ 토큰
class TokenStore:
    def __init__(self) -> None:
        self._tokens: dict[str, tuple[str, float]] = {}
        self._lock = threading.Lock()

    def issue(self, client_id: str, ttl: int) -> str:
        token = secrets.token_hex(16)
        with self._lock:
            now = time.time()
            self._tokens = {k: v for k, v in self._tokens.items() if v[1] > now}
            self._tokens[token] = (client_id, now + ttl)
        return token

    def check(self, token: str) -> str | None:
        with self._lock:
            v = self._tokens.get(token)
            if v is None or v[1] < time.time():
                return None
            return v[0]


tokens = TokenStore()


def core_of(request: Request) -> ControlCore:
    return request.app.state.core


def require_client(authorization: str | None = Header(default=None)) -> str:
    if not authorization or not authorization.lower().startswith("bearer "):
        raise ApiError(610401, "Token verification failed")
    client = tokens.check(authorization.split(" ", 1)[1].strip())
    if client is None:
        raise ApiError(610401, "Token verification failed")
    return client


@router.post("/api/open/oauth/token")
def get_token(client_id: str = Form(""), client_secret: str = Form(""), grant_type: str = Form("")):
    st = get_settings()
    if grant_type != "client_credentials" or st.clients().get(client_id) != client_secret or not client_secret:
        return JSONResponse({"code": 610001, "msg": "Wrong user name or password"})
    token = tokens.issue(client_id, st.token_ttl_seconds)
    return {"access_token": token, "token_type": "bearer", "expires_in": st.token_ttl_seconds, "scope": "all"}


# ------------------------------------------------------------------ 매장·로봇
@router.get("/api/open/data/v1/store/list")
def store_list(client: str = Depends(require_client)):
    with session_scope() as s:
        return ok([{"storeId": st.id, "storeName": st.name, "customerName": st.customer, "brandName": st.brand,
                    "address": st.address, "country": "Korea", "province": ""}
                   for st in s.scalars(select(Store).order_by(Store.id))])


def _store_robots(s, store_id: str) -> list[Robot]:  # noqa: ANN001
    return list(s.scalars(select(Robot).where(Robot.store_id == store_id).order_by(Robot.sn)))


@router.get("/api/open/data/v1/store/robot/list")
def robot_list(storeId: str, client: str = Depends(require_client)):  # noqa: N803
    with session_scope() as s:
        st = s.get(Store, storeId)
        if st is None:
            raise ApiError(610403, "Insufficient operation permission")
        return ok([{
            "robotId": r.sn, "robotName": r.name, "onlineStatus": 1 if r.online else 0, "power": r.battery,
            "robotModel": r.model, "appVersion": r.app_version, "city": st.address,
            "onlineType": ONLINE_TYPE_CODE.get(r.online_type.lower(), 5) if r.online_type else 5,
        } for r in _store_robots(s, storeId)])


@router.get("/api/open/scene/v1/robot/status")
def robot_status(robotId: str, client: str = Depends(require_client)):  # noqa: N803
    with session_scope() as s:
        r = s.get(Robot, robotId)
        if r is None:
            return ok({"list": []})
        scene = s.get(Scene, r.scene_code) if r.scene_code else None
        return ok({"list": [{
            "robotId": r.sn, "onlineStatus": r.online, "robotName": r.name,
            "canBeCalled": bool(r.online and r.can_be_called and r.current_task is None),
            "chargeStatus": 1 if r.charging else -1, "power": r.battery,
            "sceneCode": r.scene_code or "", "sceneName": scene.name if scene else "",
        }]})


@router.get("/api/open/custom/robot/battery/level")
def battery(robotSn: str, client: str = Depends(require_client)):  # noqa: N803
    with session_scope() as s:
        r = s.get(Robot, robotSn)
        if r is None:
            raise ApiError(610601, "Request parameter exception")
        return ok({"batteryLevel": r.battery})


# ------------------------------------------------------------------ 씬·포인트·맵·위치
@router.get("/api/open/scene/v1/info/list")
def scene_list(storeId: str, client: str = Depends(require_client)):  # noqa: N803
    with session_scope() as s:
        return ok({"list": [{"sceneCode": sc.code, "sceneName": sc.name}
                            for sc in s.scalars(select(Scene).where(Scene.store_id == storeId))]})


@router.get("/api/open/scene/v1/target/list")
def point_list(sceneCode: str, client: str = Depends(require_client)):  # noqa: N803
    with session_scope() as s:
        pts = s.scalars(select(Point).where(Point.scene_code == sceneCode, Point.kind != "dock"))
        return ok({"list": [{"pointName": p.name, "area": p.area, "uuid": p.uuid, "pointId": p.point_id}
                            for p in pts]})


@router.get("/api/open/custom/robot/map")
def map_data(sceneCode: str, floorInfo: str = "1", buildingInfo: str = "",  # noqa: N803
             client: str = Depends(require_client)):
    with session_scope() as s:
        sc = s.get(Scene, sceneCode)
        if sc is None or not sc.map_png:
            raise ApiError(610601, "Request parameter exception")
        return ok({"content": base64.b64encode(sc.map_png).decode("ascii"),
                   "originPosition": {"isDynamic": False, "width": sc.width, "height": sc.height,
                                      "originX": sc.origin_x, "originY": sc.origin_y,
                                      "resolution": sc.resolution}})


@router.get("/api/open/custom/robot/v2/map/position")
@router.get("/api/open/custom/robot/map/position")
def map_points(sceneCode: str, floorInfo: str = "1", buildingInfo: str = "", caseType: str = "",  # noqa: N803
               client: str = Depends(require_client)):
    with session_scope() as s:
        pts = s.scalars(select(Point).where(Point.scene_code == sceneCode))
        return ok({"targetList": [{
            "id": i + 1, "targetId": int(p.point_id) if p.point_id.isdigit() else i + 1, "name": p.name,
            "type": p.kind, "floor": floorInfo, "positionX": p.x, "positionY": p.y, "positionZ": 0,
            "floorInfo": floorInfo, "buildingInfo": buildingInfo,
        } for i, p in enumerate(pts)]})


def _location(r: Robot) -> dict[str, Any]:
    coord = "" if r.x is None else f"{r.x:.2f},{r.y:.2f},{(r.angle or 0):.2f}"
    return {"building": "", "floor": r.floor or "1", "coordinate": coord,
            "takeElevatorStatus": 1 if r.in_elevator else 0}


@router.get("/api/open/custom/robot/location")
def location(robotSn: str, client: str = Depends(require_client)):  # noqa: N803
    with session_scope() as s:
        r = s.get(Robot, robotSn)
        if r is None:
            raise ApiError(610601, "Request parameter exception")
        return ok(_location(r))


@router.get("/api/open/custom/robot/position")
def position(robotSn: str, storeId: str = "", client: str = Depends(require_client)):  # noqa: N803
    return location(robotSn, client)


# ------------------------------------------------------------------ 호출·복귀·취소·상태
@router.post("/api/open/scene/v3/robot/call/task")
async def call_task(request: Request, client: str = Depends(require_client)):
    body = await _json(request)
    if not body.get("storeId") or not (body.get("uuid") or body.get("pointId")):
        raise ApiError(610601, "Request parameter exception")
    data = core_of(request).create_call(
        store_id=str(body["storeId"]), uuid=str(body.get("uuid") or ""), point_id=str(body.get("pointId") or ""),
        scene_code=body.get("sceneCode"), robot_sn=body.get("robotId") or None,
        robot_type=body.get("robotType"), actor=client)
    return ok(data)


@router.post("/api/open/scene/v2/robot/call/back/task")
async def back_task(request: Request, client: str = Depends(require_client)):
    body = await _json(request)
    store_id = request.query_params.get("storeId") or body.get("storeId")
    robot_id = request.query_params.get("robotId") or body.get("robotId")
    if not store_id:
        raise ApiError(610601, "Request parameter exception")
    return ok(core_of(request).create_return(store_id=str(store_id), robot_sn=robot_id or None, actor=client))


@router.get("/api/open/scene/v1/robot/call/task")
def task_status(request: Request, taskNo: str, client: str = Depends(require_client)):  # noqa: N803
    return ok(core_of(request).get_task(taskNo))


@router.delete("/api/open/scene/v1/robot/call/task")
def cancel_task(request: Request, taskNo: str, client: str = Depends(require_client)):  # noqa: N803
    core_of(request).cancel(taskNo, client)
    return ok()


# ------------------------------------------------------------------ 이력
def _records(store_id: str, hotel: bool, page: int, size: int, start: int | None, end: int | None):
    size = max(1, min(100, size))
    page = max(1, page)
    with session_scope() as s:
        kinds = {r.sn: r.kind for r in s.scalars(select(Robot).where(Robot.store_id == store_id))}
        q = select(Task).where(Task.store_id == store_id, Task.status.in_(FINAL)).order_by(Task.created_at.desc())
        if start:
            q = q.where(Task.created_at >= datetime.fromtimestamp(start / 1000, timezone.utc).replace(tzinfo=None))
        if end:
            q = q.where(Task.created_at <= datetime.fromtimestamp(end / 1000, timezone.utc).replace(tzinfo=None))
        rows = [t for t in s.scalars(q) if (kinds.get(t.robot_sn or "") == "hotel") == hotel]
        total = len(rows)
        out = []
        for t in rows[(page - 1) * size: page * size]:
            back = (t.finished_at + timedelta(seconds=30)) if t.task_type == "call" and t.finished_at else None
            if hotel:
                out.append({"robotId": t.robot_sn, "startTime": fmt_kst(t.created_at), "endTime": fmt_kst(t.finished_at),
                            "totalMileage": round(t.mileage, 1), "storeId": t.store_id,
                            "bizType": 4 if t.task_type == "return" else 1})
            else:
                out.append({"robotId": t.robot_sn, "startTime": fmt_kst(t.created_at), "endTime": fmt_kst(t.finished_at),
                            "backTime": fmt_kst(back), "taskMileage": round(t.mileage), "storeId": t.store_id,
                            "taskMode": 2, "taskStatus": 1 if t.status == 4 else -1})
        return ok({"total": total, "list": out})


@router.get("/api/open/data/v1/store/task/food/list")
def food_records(storeId: str, page: int = 1, size: int = 20, startTime: int | None = None,  # noqa: N803
                 endTime: int | None = None, client: str = Depends(require_client)):  # noqa: N803
    return _records(storeId, False, page, size, startTime, endTime)


@router.get("/api/open/data/v1/store/task/hotel/list")
def hotel_records(storeId: str, page: int = 1, size: int = 20, startTime: int | None = None,  # noqa: N803
                  endTime: int | None = None, client: str = Depends(require_client)):  # noqa: N803
    return _records(storeId, True, page, size, startTime, endTime)


async def _json(request: Request) -> dict[str, Any]:
    try:
        body = await request.json()
        return body if isinstance(body, dict) else {}
    except Exception:
        return {}
