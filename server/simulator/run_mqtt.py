"""가상 로봇들을 MQTT 브로커에 접속시킨다 (실제 로봇 대신)

사용:  python -m simulator.run_mqtt
환경변수: MQTT_HOST(기본 localhost), MQTT_PORT(1883), MQTT_TOPIC_PREFIX(kr/robot),
          MQTT_USERNAME, MQTT_PASSWORD
"""
from __future__ import annotations

import logging
import os
import signal
import threading
import uuid

import paho.mqtt.client as mqtt

from app import protocol as P
from simulator.sim import Fleet

logging.basicConfig(level=logging.INFO, format="%(asctime)s [sim] %(message)s")
log = logging.getLogger("simulator")


def main() -> None:
    host = os.getenv("MQTT_HOST", "localhost")
    port = int(os.getenv("MQTT_PORT", "1883"))
    prefix = os.getenv("MQTT_TOPIC_PREFIX", "kr/robot").rstrip("/")
    connected = threading.Event()

    client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2, client_id=f"robot-sim-{uuid.uuid4().hex[:8]}")
    if os.getenv("MQTT_USERNAME"):
        client.username_pw_set(os.getenv("MQTT_USERNAME"), os.getenv("MQTT_PASSWORD") or None)

    def publish(sn: str, msg: dict) -> None:
        client.publish(P.up_topic(prefix, sn, msg.get("action", "Unknown")), P.encode(msg), qos=1)

    fleet = Fleet(publish=publish)

    def on_connect(c, userdata, flags, reason_code, properties=None):  # noqa: ANN001
        c.subscribe(f"{prefix}/+/down/command", qos=1)
        log.info("브로커 연결됨 %s:%s, 가상 로봇 %d대", host, port, len(fleet.robots))
        if not connected.is_set():
            connected.set()
            fleet.start()
        else:
            for r in fleet.robots.values():  # 재접속 시 상태 다시 알림
                r.boot()

    def on_message(c, userdata, message):  # noqa: ANN001
        parts = message.topic.split("/")
        msg = P.decode(message.payload)
        if msg is not None and len(parts) >= 3:
            fleet.deliver(parts[-3], msg)

    client.on_connect = on_connect
    client.on_message = on_message
    client.reconnect_delay_set(1, 30)
    client.connect_async(host, port, keepalive=30)
    client.loop_start()

    stop = threading.Event()
    signal.signal(signal.SIGTERM, lambda *_: stop.set())
    signal.signal(signal.SIGINT, lambda *_: stop.set())
    stop.wait()
    fleet.stop()
    client.loop_stop()


if __name__ == "__main__":
    main()
