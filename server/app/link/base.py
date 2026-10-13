"""로봇 연결부 인터페이스

실제 Keenon 로봇 통신 규격을 받으면 이 인터페이스를 구현한 새 클래스만 추가하면 된다.
서버의 나머지 부분(작업 관리, API, DB)은 바뀌지 않는다.
"""
from __future__ import annotations

from abc import ABC, abstractmethod
from typing import Any, Callable

# (로봇 SN, 메시지) → None
MessageHandler = Callable[[str, dict[str, Any]], None]


class RobotLink(ABC):
    name = "base"

    @abstractmethod
    def start(self, on_message: MessageHandler) -> None:
        """연결 시작. 로봇에서 올라온 메시지는 on_message 로 전달한다."""

    @abstractmethod
    def send(self, sn: str, msg: dict[str, Any]) -> bool:
        """로봇에 명령 전송. 전송 요청에 성공하면 True."""

    def stop(self) -> None:  # pragma: no cover - 선택
        pass

    def status(self) -> dict[str, Any]:
        return {"link": self.name}
