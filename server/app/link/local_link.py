"""브로커 없이 서버 안에서 가상 로봇을 직접 돌리는 연결 (개발·테스트용)"""
from __future__ import annotations

from typing import Any

from .base import MessageHandler, RobotLink


class LocalLink(RobotLink):
    name = "local"

    def __init__(self) -> None:
        self.fleet = None

    def start(self, on_message: MessageHandler) -> None:
        from simulator.sim import Fleet  # 순환 import 방지

        self.fleet = Fleet(publish=on_message)
        self.fleet.start()

    def send(self, sn: str, msg: dict[str, Any]) -> bool:
        if self.fleet is None or sn not in self.fleet.robots:
            return False
        self.fleet.deliver(sn, msg)
        return True

    def stop(self) -> None:
        if self.fleet is not None:
            self.fleet.stop()

    def status(self) -> dict[str, Any]:
        return {"link": self.name, "simulatedRobots": len(self.fleet.robots) if self.fleet else 0}
