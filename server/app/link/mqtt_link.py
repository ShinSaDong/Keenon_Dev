"""MQTT 브로커를 통한 로봇 연결

토픽: {prefix}/{sn}/up/{action}  (로봇 → 서버)
      {prefix}/{sn}/down/command (서버 → 로봇)
"""
from __future__ import annotations

import logging
import uuid
from typing import Any

import paho.mqtt.client as mqtt

from .. import protocol as P
from .base import MessageHandler, RobotLink

log = logging.getLogger("mqtt-link")


class MqttLink(RobotLink):
    name = "mqtt"

    def __init__(self, host: str, port: int, prefix: str, username: str = "", password: str = ""):
        self.host, self.port, self.prefix = host, port, prefix.rstrip("/")
        self.username, self.password = username, password
        self.connected = False
        self.client: mqtt.Client | None = None
        self._handler: MessageHandler | None = None

    def start(self, on_message: MessageHandler) -> None:
        self._handler = on_message
        c = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2, client_id=f"control-server-{uuid.uuid4().hex[:8]}")
        if self.username:
            c.username_pw_set(self.username, self.password or None)
        c.on_connect = self._on_connect
        c.on_disconnect = self._on_disconnect
        c.on_message = self._on_message
        c.reconnect_delay_set(min_delay=1, max_delay=30)
        c.connect_async(self.host, self.port, keepalive=30)
        c.loop_start()
        self.client = c
        log.info("MQTT 연결 시도 %s:%s", self.host, self.port)

    def _on_connect(self, client, userdata, flags, reason_code, properties=None):  # noqa: ANN001
        if reason_code == 0 or getattr(reason_code, "is_failure", True) is False:
            self.connected = True
            client.subscribe(f"{self.prefix}/+/up/#", qos=1)
            log.info("MQTT 연결됨, 구독: %s/+/up/#", self.prefix)
        else:
            log.warning("MQTT 연결 실패: %s", reason_code)

    def _on_disconnect(self, client, userdata, flags, reason_code, properties=None):  # noqa: ANN001
        self.connected = False
        log.warning("MQTT 연결 끊김: %s", reason_code)

    def _on_message(self, client, userdata, message):  # noqa: ANN001
        parts = message.topic.split("/")
        # {prefix...}/{sn}/up/{action}
        if len(parts) < 3 or parts[-2] != "up":
            return
        sn = parts[-3]
        msg = P.decode(message.payload)
        if msg is None:
            log.warning("해석할 수 없는 메시지: %s", message.topic)
            return
        msg.setdefault("action", parts[-1])
        if self._handler:
            try:
                self._handler(sn, msg)
            except Exception:  # pragma: no cover
                log.exception("메시지 처리 오류 %s", message.topic)

    def send(self, sn: str, msg: dict[str, Any]) -> bool:
        if self.client is None or not self.connected:
            return False
        info = self.client.publish(P.down_topic(self.prefix, sn), P.encode(msg), qos=1)
        return info.rc == mqtt.MQTT_ERR_SUCCESS

    def stop(self) -> None:
        if self.client is not None:
            self.client.loop_stop()
            self.client.disconnect()

    def status(self) -> dict[str, Any]:
        return {"link": self.name, "broker": f"{self.host}:{self.port}", "connected": self.connected}
