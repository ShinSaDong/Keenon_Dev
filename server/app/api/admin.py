"""관제 대시보드용 API + 실시간 웹소켓 (테스트 단계: 인증 없음)"""
from __future__ import annotations

from typing import Any

from fastapi import APIRouter, Request, WebSocket, WebSocketDisconnect
from fastapi.responses import FileResponse, Response
from sqlalchemy import select

from ..db import AuditLog, Point, Robot, Scene, Store, Task, session_scope
from ..services.core import ApiError, ControlCore, fmt_kst
from pathlib import Path

router = APIRouter()
STATIC = Path(__file__).resolve().parent.parent / "static"


def core_of(request: Request) -> ControlCore:
    return request.app.state.core


@router.get("/", include_in_schema=False)
def dashboard():
    return FileResponse(STATIC / "dashboard.html")


@router.get("/health")
def health(request: Request):
    return {"ok": True, **core_of(request).link.status()}


@router.get("/admin/api/overview")
def overview(request: Request) -> dict[str, Any]:
    with session_scope() as s:
        stores = [{"storeId": st.id, "storeName": st.name} for st in s.scalars(select(Store).order_by(Store.id))]
        robots = [{
            "sn": r.sn, "name": r.name, "model": r.model, "kind": r.kind, "storeId": r.store_id,
            "sceneCode": r.scene_code, "online": r.online, "onlineType": r.online_type, "battery": r.battery,
            "charging": r.charging, "workState": r.work_state, "canBeCalled": r.can_be_called,
            "x": r.x, "y": r.y, "angle": r.angle, "floor": r.floor, "currentTask": r.current_task,
            "lastSeen": fmt_kst(r.last_seen),
        } for r in s.scalars(select(Robot).order_by(Robot.sn))]
        tasks = [{
            "taskNo": t.task_no, "storeId": t.store_id, "robotSn": t.robot_sn, "type": t.task_type,
            "point": t.point_name, "status": t.status, "errorCode": t.error_code, "remaining": t.remaining,
            "mileage": round(t.mileage, 1), "requestedBy": t.requested_by, "createdAt": fmt_kst(t.created_at),
            "finishedAt": fmt_kst(t.finished_at),
        } for t in s.scalars(select(Task).order_by(Task.created_at.desc()).limit(30))]
    return {"link": core_of(request).link.status(), "stores": stores, "robots": robots, "tasks": tasks}


@router.get("/admin/api/scenes")
def scenes() -> list[dict[str, Any]]:
    with session_scope() as s:
        out = []
        for sc in s.scalars(select(Scene).order_by(Scene.code)):
            pts = s.scalars(select(Point).where(Point.scene_code == sc.code))
            out.append({"sceneCode": sc.code, "name": sc.name, "storeId": sc.store_id, "originX": sc.origin_x,
                        "originY": sc.origin_y, "resolution": sc.resolution, "width": sc.width, "height": sc.height,
                        "points": [{"uuid": p.uuid, "pointId": p.point_id, "name": p.name, "kind": p.kind,
                                    "x": p.x, "y": p.y} for p in pts]})
        return out


@router.get("/admin/api/scenes/{code}/map.png", include_in_schema=False)
def scene_png(code: str):
    with session_scope() as s:
        sc = s.get(Scene, code)
        if sc is None or not sc.map_png:
            return Response(status_code=404)
        return Response(content=sc.map_png, media_type="image/png")


@router.post("/admin/api/call")
async def admin_call(request: Request):
    b = await request.json()
    return {"code": 610000, "data": core_of(request).create_call(
        store_id=b["storeId"], uuid=b.get("uuid", ""), point_id=b.get("pointId", ""), scene_code=b.get("sceneCode"),
        robot_sn=b.get("robotSn") or None, robot_type=None, actor="dashboard")}


@router.post("/admin/api/return")
async def admin_return(request: Request):
    b = await request.json()
    return {"code": 610000, "data": core_of(request).create_return(
        store_id=b["storeId"], robot_sn=b.get("robotSn") or None, actor="dashboard")}


@router.post("/admin/api/cancel")
async def admin_cancel(request: Request):
    b = await request.json()
    core_of(request).cancel(b["taskNo"], "dashboard")
    return {"code": 610000}


@router.get("/admin/api/audit")
def audit(limit: int = 100):
    with session_scope() as s:
        return [{"at": fmt_kst(a.at), "actor": a.actor, "action": a.action, "target": a.target, "detail": a.detail}
                for a in s.scalars(select(AuditLog).order_by(AuditLog.id.desc()).limit(min(limit, 500)))]


@router.websocket("/ws/events")
async def ws_events(ws: WebSocket):
    await ws.accept()
    hub = ws.app.state.core.events
    hub.add_socket(ws)
    try:
        while True:
            await ws.receive_text()  # 클라이언트 메시지는 무시 (연결 유지용)
    except WebSocketDisconnect:
        pass
    finally:
        hub.remove_socket(ws)


__all__ = ["router", "ApiError"]
