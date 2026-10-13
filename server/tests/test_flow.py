"""관제 서버 통합 테스트 (가상 로봇 local 모드, 시간 단축)

실행:  cd server && pytest -q
"""
from __future__ import annotations

import os
import time

import pytest
from fastapi.testclient import TestClient

HALL_STORE = "DEMO-S001"
HALL_SCENE = "DEMO-HALL"
R1, R3 = "AA:BB:CC:00:00:01", "AA:BB:CC:00:00:03"


@pytest.fixture(scope="module")
def client(tmp_path_factory):
    import simulator.sim as sim

    # 시뮬레이터 시간 단축 (테스트 속도)
    sim.SPEED, sim.CALL_DELAY, sim.BACK_DELAY, sim.ARRIVE_DWELL = 15.0, 0.3, 0.2, 0.8

    db = tmp_path_factory.mktemp("db") / "t.db"
    mp = pytest.MonkeyPatch()
    mp.setenv("DATABASE_URL", os.getenv("TEST_DATABASE_URL", f"sqlite:///{db}"))
    mp.setenv("ROBOT_LINK", "local")
    from app.config import get_settings

    get_settings.cache_clear()
    from app.main import app

    with TestClient(app) as c:
        yield c
    mp.undo()
    get_settings.cache_clear()


@pytest.fixture(scope="module")
def auth(client):
    r = client.post("/api/open/oauth/token", data={
        "client_id": "demo-client", "client_secret": "demo-secret", "grant_type": "client_credentials"})
    body = r.json()
    assert body["token_type"] == "bearer" and body["expires_in"] == 7200
    return {"Authorization": f"Bearer {body['access_token']}"}


def wait_for(fn, timeout=15.0, step=0.1):
    end = time.time() + timeout
    last = None
    while time.time() < end:
        last = fn()
        if last:
            return last
        time.sleep(step)
    raise AssertionError(f"timeout, last={last!r}")


def test_token_errors(client):
    r = client.post("/api/open/oauth/token", data={
        "client_id": "demo-client", "client_secret": "wrong", "grant_type": "client_credentials"})
    assert r.json()["code"] == 610001
    r = client.get("/api/open/data/v1/store/list", headers={"Authorization": "Bearer nope"})
    assert r.status_code == 200 and r.json()["code"] == 610401


def test_store_robot_lists(client, auth):
    stores = client.get("/api/open/data/v1/store/list", headers=auth).json()
    assert stores["code"] == 610000
    assert {s["storeId"] for s in stores["data"]} >= {HALL_STORE, "DEMO-S002"}

    def online():
        d = client.get("/api/open/data/v1/store/robot/list", params={"storeId": HALL_STORE}, headers=auth).json()
        on = {r["robotId"]: r["onlineStatus"] for r in d["data"]}
        return d if on.get(R1) == 1 else None

    d = wait_for(online)
    by = {r["robotId"]: r for r in d["data"]}
    assert by[R3]["onlineStatus"] == 0  # 오프라인 데모 로봇
    assert isinstance(by[R1]["power"], int)


def test_scene_points_map(client, auth):
    sc = client.get("/api/open/scene/v1/info/list", params={"storeId": HALL_STORE}, headers=auth).json()
    assert sc["data"]["list"][0]["sceneCode"] == HALL_SCENE
    pts = client.get("/api/open/scene/v1/target/list", params={"sceneCode": HALL_SCENE}, headers=auth).json()
    names = [p["pointName"] for p in pts["data"]["list"]]
    assert len(names) >= 8
    m = client.get("/api/open/custom/robot/map", params={"sceneCode": HALL_SCENE}, headers=auth).json()
    assert m["data"]["content"].startswith("iVBOR")  # PNG base64
    assert m["data"]["originPosition"]["resolution"] == 0.05
    st = client.get("/api/open/scene/v1/robot/status", params={"robotId": R1}, headers=auth).json()
    assert st["data"]["list"][0]["robotId"] == R1
    loc = client.get("/api/open/custom/robot/location", params={"robotSn": R1}, headers=auth).json()
    assert loc["data"]["coordinate"].count(",") == 2


def _point(client, auth, name):
    pts = client.get("/api/open/scene/v1/target/list", params={"sceneCode": HALL_SCENE}, headers=auth).json()
    return next(p for p in pts["data"]["list"] if p["pointName"] == name)


def _status(client, auth, task_no):
    return client.get("/api/open/scene/v1/robot/call/task", params={"taskNo": task_no}, headers=auth).json()


def test_call_full_cycle(client, auth):
    p = _point(client, auth, "1번 테이블")
    r = client.post("/api/open/scene/v3/robot/call/task", headers=auth, json={
        "storeId": HALL_STORE, "sceneCode": HALL_SCENE, "uuid": p["uuid"], "robotId": R1}).json()
    assert r["code"] == 610000, r
    task_no = r["data"]["taskNo"]

    seen: set[int] = set()

    def finished():
        d = _status(client, auth, task_no)["data"]
        seen.add(d["taskStatus"])
        return d if d["taskStatus"] in (0, 4, 5) else None

    d = wait_for(finished, timeout=20)
    assert d["taskStatus"] == 4, d
    assert {3, 6} <= seen, seen  # 이동 중 → 도착 → 완료

    # 이력 조회 (서빙)
    rec = client.get("/api/open/data/v1/store/task/food/list", params={"storeId": HALL_STORE}, headers=auth).json()
    assert rec["data"]["total"] >= 1


def test_busy_and_cancel(client, auth):
    # 로봇이 도킹 위치로 돌아와 호출 가능해질 때까지 대기
    def idle():
        d = client.get("/api/open/scene/v1/robot/status", params={"robotId": R1}, headers=auth).json()
        return d["data"]["list"][0]["canBeCalled"]

    wait_for(idle, timeout=20)
    p = _point(client, auth, "5번 테이블")
    first = client.post("/api/open/scene/v3/robot/call/task", headers=auth, json={
        "storeId": HALL_STORE, "uuid": p["uuid"], "robotId": R1}).json()
    assert first["code"] == 610000, first
    busy = client.post("/api/open/scene/v3/robot/call/task", headers=auth, json={
        "storeId": HALL_STORE, "uuid": p["uuid"], "robotId": R1}).json()
    assert busy["code"] == 5001, busy

    task_no = first["data"]["taskNo"]
    c = client.delete("/api/open/scene/v1/robot/call/task", params={"taskNo": task_no}, headers=auth).json()
    assert c["code"] == 610000
    d = wait_for(lambda: (lambda x: x if x["taskStatus"] == 5 else None)(_status(client, auth, task_no)["data"]))
    assert d["taskStatus"] == 5


def test_offline_robot_call(client, auth):
    p = _point(client, auth, "2번 테이블")
    r = client.post("/api/open/scene/v3/robot/call/task", headers=auth, json={
        "storeId": HALL_STORE, "uuid": p["uuid"], "robotId": R3}).json()
    assert r["code"] == 615001, r


def test_auto_assign_and_return(client, auth):
    p = _point(client, auth, "3번 테이블")
    r = client.post("/api/open/scene/v3/robot/call/task", headers=auth, json={
        "storeId": HALL_STORE, "uuid": p["uuid"]}).json()
    assert r["code"] == 610000, r
    sn = _status(client, auth, r["data"]["taskNo"])["data"]["taskData"]["robotSn"]
    assert sn in (R1, "AA:BB:CC:00:00:02")
    back = client.post("/api/open/scene/v2/robot/call/back/task", headers=auth,
                       params={"storeId": HALL_STORE, "robotId": sn}).json()
    assert back["code"] == 610000, back


def test_dashboard_endpoints(client):
    assert client.get("/").status_code == 200
    ov = client.get("/admin/api/overview").json()
    assert ov["link"]["link"] == "local" and ov["robots"]
    sc = client.get("/admin/api/scenes").json()
    assert client.get(f"/admin/api/scenes/{sc[0]['sceneCode']}/map.png").headers["content-type"] == "image/png"
    assert client.get("/admin/api/audit").json()
    with client.websocket_connect("/ws/events") as ws:
        msg = ws.receive_json()
        assert "bizType" in msg
