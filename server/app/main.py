"""한국 관제 서버 (테스트 1차)

실행:  uvicorn app.main:app --host 0.0.0.0 --port 8000
문서:  http://localhost:8000/docs   대시보드: http://localhost:8000/
"""
from __future__ import annotations

import asyncio
import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from .api import admin, openapi_compat
from .config import get_settings
from .db import init_db
from .link.base import RobotLink
from .seed import seed_demo
from .services.core import ApiError, ControlCore
from .services.events import EventHub

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s [%(name)s] %(message)s")
log = logging.getLogger("main")


def build_link() -> RobotLink:
    st = get_settings()
    if st.robot_link == "mqtt":
        from .link.mqtt_link import MqttLink

        return MqttLink(st.mqtt_host, st.mqtt_port, st.mqtt_topic_prefix, st.mqtt_username, st.mqtt_password)
    from .link.local_link import LocalLink

    return LocalLink()


@asynccontextmanager
async def lifespan(app: FastAPI):
    st = get_settings()
    init_db(st.database_url)
    if st.seed_demo:
        seed_demo()
    hub = EventHub(st.webhooks())
    hub.attach_loop(asyncio.get_running_loop())
    core = ControlCore(build_link(), hub, st.offline_timeout_seconds)
    app.state.core = core
    core.start()
    log.info("관제 서버 시작 (robot_link=%s, db=%s)", st.robot_link, st.database_url.split("@")[-1])
    yield
    core.stop()


app = FastAPI(title="한국 관제 서버 (Keenon Open API 호환, 테스트)", version="0.1.0", lifespan=lifespan)
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])


@app.exception_handler(ApiError)
async def api_error_handler(request: Request, exc: ApiError):
    # Keenon 과 같이 HTTP 200 + code/msg 로 오류 전달
    return JSONResponse({"code": exc.code, "msg": exc.msg})


app.include_router(openapi_compat.router, tags=["Keenon Open API 호환"])
app.include_router(admin.router, tags=["관제 대시보드"])
