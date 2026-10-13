"""DB 연결과 테이블 정의 (SQLAlchemy 2.0)"""
from __future__ import annotations

import os
from contextlib import contextmanager
from datetime import datetime, timezone
from typing import Iterator

from sqlalchemy import (
    Boolean,
    DateTime,
    Float,
    ForeignKey,
    Integer,
    LargeBinary,
    String,
    Text,
    create_engine,
)
from sqlalchemy.orm import DeclarativeBase, Mapped, Session, mapped_column, sessionmaker


def utcnow() -> datetime:
    return datetime.now(timezone.utc).replace(tzinfo=None)


class Base(DeclarativeBase):
    pass


class Store(Base):
    __tablename__ = "stores"
    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    name: Mapped[str] = mapped_column(String(200))
    brand: Mapped[str] = mapped_column(String(200), default="")
    customer: Mapped[str] = mapped_column(String(200), default="")
    address: Mapped[str] = mapped_column(String(400), default="")


class Scene(Base):
    """로봇이 사용하는 맵 단위 (Keenon 의 sceneCode)"""

    __tablename__ = "scenes"
    code: Mapped[str] = mapped_column(String(64), primary_key=True)
    name: Mapped[str] = mapped_column(String(200))
    store_id: Mapped[str] = mapped_column(ForeignKey("stores.id"))
    floor: Mapped[str] = mapped_column(String(32), default="1")
    building: Mapped[str] = mapped_column(String(64), default="")
    origin_x: Mapped[float] = mapped_column(Float, default=0.0)
    origin_y: Mapped[float] = mapped_column(Float, default=0.0)
    resolution: Mapped[float] = mapped_column(Float, default=0.05)
    width: Mapped[int] = mapped_column(Integer, default=0)
    height: Mapped[int] = mapped_column(Integer, default=0)
    map_png: Mapped[bytes | None] = mapped_column(LargeBinary, nullable=True)


class Point(Base):
    """목적지 포인트 (테이블, 객실, 주방 등)"""

    __tablename__ = "points"
    uuid: Mapped[str] = mapped_column(String(64), primary_key=True)
    point_id: Mapped[str] = mapped_column(String(32))
    name: Mapped[str] = mapped_column(String(200))
    area: Mapped[str] = mapped_column(String(200), default="")
    scene_code: Mapped[str] = mapped_column(ForeignKey("scenes.code"))
    kind: Mapped[str] = mapped_column(String(32), default="target")  # target | pickup | dock
    x: Mapped[float | None] = mapped_column(Float, nullable=True)
    y: Mapped[float | None] = mapped_column(Float, nullable=True)


class Robot(Base):
    __tablename__ = "robots"
    sn: Mapped[str] = mapped_column(String(64), primary_key=True)  # Keenon robotId / robotSn
    name: Mapped[str] = mapped_column(String(200), default="")
    model: Mapped[str] = mapped_column(String(32), default="")
    app_version: Mapped[str] = mapped_column(String(64), default="")
    kind: Mapped[str] = mapped_column(String(16), default="serving")  # serving | hotel
    store_id: Mapped[str | None] = mapped_column(ForeignKey("stores.id"), nullable=True)
    scene_code: Mapped[str | None] = mapped_column(String(64), nullable=True)

    # 최신 상태 (로봇이 올린 값)
    online: Mapped[bool] = mapped_column(Boolean, default=False)
    online_type: Mapped[str] = mapped_column(String(16), default="")
    battery: Mapped[int | None] = mapped_column(Integer, nullable=True)
    charging: Mapped[bool] = mapped_column(Boolean, default=False)
    work_state: Mapped[int | None] = mapped_column(Integer, nullable=True)  # 1 작업 2 대기 3 조작 4 스케줄 5 충전 6 측위
    can_be_called: Mapped[bool] = mapped_column(Boolean, default=False)
    x: Mapped[float | None] = mapped_column(Float, nullable=True)
    y: Mapped[float | None] = mapped_column(Float, nullable=True)
    angle: Mapped[float | None] = mapped_column(Float, nullable=True)
    floor: Mapped[str] = mapped_column(String(32), default="")
    in_elevator: Mapped[bool] = mapped_column(Boolean, default=False)
    current_task: Mapped[str | None] = mapped_column(String(64), nullable=True)
    last_seen: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)


class Task(Base):
    __tablename__ = "tasks"
    task_no: Mapped[str] = mapped_column(String(64), primary_key=True)
    store_id: Mapped[str] = mapped_column(String(64), index=True)
    robot_sn: Mapped[str | None] = mapped_column(String(64), nullable=True, index=True)
    task_type: Mapped[str] = mapped_column(String(16))  # call | return
    scene_code: Mapped[str] = mapped_column(String(64), default="")
    point_uuid: Mapped[str] = mapped_column(String(64), default="")
    point_id: Mapped[str] = mapped_column(String(32), default="")
    point_name: Mapped[str] = mapped_column(String(200), default="")
    # Keenon taskStatus: 0 실패 1 대기열 2 호출중 3 이동중 4 완료 5 취소 6 도착 7 대기
    status: Mapped[int] = mapped_column(Integer, default=1)
    error_code: Mapped[int | None] = mapped_column(Integer, nullable=True)
    remaining: Mapped[float | None] = mapped_column(Float, nullable=True)
    mileage: Mapped[float] = mapped_column(Float, default=0.0)
    requested_by: Mapped[str] = mapped_column(String(64), default="")
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow, index=True)
    started_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    arrived_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    finished_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)


class TaskEvent(Base):
    __tablename__ = "task_events"
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    task_no: Mapped[str] = mapped_column(String(64), index=True)
    status: Mapped[int] = mapped_column(Integer)
    error_code: Mapped[int | None] = mapped_column(Integer, nullable=True)
    at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)
    detail: Mapped[str] = mapped_column(Text, default="")


class AuditLog(Base):
    """누가 언제 어떤 조작을 했는지 (공공기관 납품용 감사 기록)"""

    __tablename__ = "audit_logs"
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    at: Mapped[datetime] = mapped_column(DateTime, default=utcnow, index=True)
    actor: Mapped[str] = mapped_column(String(64))
    action: Mapped[str] = mapped_column(String(64))
    target: Mapped[str] = mapped_column(String(200), default="")
    detail: Mapped[str] = mapped_column(Text, default="")


_engine = None
_SessionLocal: sessionmaker[Session] | None = None


def init_db(url: str) -> None:
    global _engine, _SessionLocal
    if url.startswith("sqlite:///"):
        path = url.removeprefix("sqlite:///")
        if path and path != ":memory:":
            os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
        _engine = create_engine(url, connect_args={"check_same_thread": False, "timeout": 15})
    else:
        _engine = create_engine(url, pool_pre_ping=True)
    _SessionLocal = sessionmaker(bind=_engine, expire_on_commit=False)
    Base.metadata.create_all(_engine)


@contextmanager
def session_scope() -> Iterator[Session]:
    assert _SessionLocal is not None, "init_db() 먼저 호출"
    s = _SessionLocal()
    try:
        yield s
        s.commit()
    except Exception:
        s.rollback()
        raise
    finally:
        s.close()
