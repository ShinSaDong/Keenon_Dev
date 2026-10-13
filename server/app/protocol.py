"""로봇 ↔ 관제 서버 메시지 규격 (임시)

Keenon 의 실제 로봇 통신 규격을 받기 전까지 쓰는 자체 규격이다.
Keenon Open API 엘리베이터 연동 문서에 나온 메시지 형식
  {action, deviceName, messageId, taskNo, code, status, data}
을 그대로 따라서, 실제 규격을 받았을 때 바꿀 양을 줄인다.

MQTT 토픽
  위로 (로봇 → 서버)  {prefix}/{sn}/up/{action}
  아래로 (서버 → 로봇) {prefix}/{sn}/down/command
"""
from __future__ import annotations

import itertools
import json
import time
from typing import Any

SUCCESS = 610000

# ---- 위로 (로봇 → 서버)
HELLO = "Hello"            # 접속 시 로봇 정보: name, model, appVersion, sceneCode, kind
ONLINE = "Online"          # onlineStatus(bool), onlineType("Wi-Fi"|"4G")
POWER = "Power"            # chargeStatus(1 충전, -1 방전), batteryLevel
WORK_STATE = "WorkState"   # robotState(1 작업 2 대기 3 조작 4 스케줄 5 충전 6 측위), canBeCalled
POSITION = "Position"      # x, y, rotation(rad), floor, building, takeElevatorStatus
TASK_STATE = "TaskState"   # taskState(Keenon 0~7), remainingDistance, errorCode, mileage
ACK = "Ack"                # 명령 결과: result(1 성공/0 실패), errorCode, ackMessageId

UP_ACTIONS = {HELLO, ONLINE, POWER, WORK_STATE, POSITION, TASK_STATE, ACK}

# ---- 아래로 (서버 → 로봇)
CREATE_TASK = "CreateTask"      # data: uuid, pointId, pointName, sceneCode
CANCEL_TASK = "CancelTask"
RETURN_ORIGIN = "ReturnOrigin"

_counter = itertools.count()


def new_message_id() -> int:
    return int(time.time() * 1000) * 100 + next(_counter) % 100


def envelope(action: str, sn: str, data: dict[str, Any] | None = None, task_no: str | None = None,
             code: int = SUCCESS, status: int = 0) -> dict[str, Any]:
    msg: dict[str, Any] = {
        "action": action,
        "deviceName": sn,
        "messageId": new_message_id(),
        "code": code,
        "status": status,
        "data": data or {},
    }
    if task_no:
        msg["taskNo"] = task_no
    return msg


def up_topic(prefix: str, sn: str, action: str) -> str:
    return f"{prefix}/{sn}/up/{action}"


def down_topic(prefix: str, sn: str) -> str:
    return f"{prefix}/{sn}/down/command"


def encode(msg: dict[str, Any]) -> bytes:
    return json.dumps(msg, ensure_ascii=False).encode("utf-8")


def decode(payload: bytes) -> dict[str, Any] | None:
    try:
        obj = json.loads(payload.decode("utf-8"))
        return obj if isinstance(obj, dict) else None
    except (UnicodeDecodeError, json.JSONDecodeError):
        return None
