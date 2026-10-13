"""이벤트 전달: 웹소켓(앱·대시보드 실시간) + Keenon 형식 Webhook"""
from __future__ import annotations

import asyncio
import json
import logging
from concurrent.futures import ThreadPoolExecutor
from typing import Any

import httpx

log = logging.getLogger("events")


class EventHub:
    def __init__(self, webhook_urls: list[str], client_id: str = "kr-control") -> None:
        self.webhook_urls = webhook_urls
        self.client_id = client_id
        self.loop: asyncio.AbstractEventLoop | None = None
        self._sockets: set[Any] = set()
        self._pool = ThreadPoolExecutor(max_workers=2, thread_name_prefix="webhook")

    # ---- 웹소켓
    def attach_loop(self, loop: asyncio.AbstractEventLoop) -> None:
        self.loop = loop

    def add_socket(self, ws: Any) -> None:
        self._sockets.add(ws)

    def remove_socket(self, ws: Any) -> None:
        self._sockets.discard(ws)

    async def _broadcast(self, text: str) -> None:
        dead = []
        for ws in list(self._sockets):
            try:
                await ws.send_text(text)
            except Exception:
                dead.append(ws)
        for ws in dead:
            self._sockets.discard(ws)

    # ---- 발행 (어느 스레드에서 불러도 됨)
    def publish(self, biz_type: str, data: dict[str, Any], webhook: bool = True) -> None:
        event = {"bizType": biz_type, "clientId": self.client_id, "data": data}
        if self.loop is not None and self._sockets:
            text = json.dumps(event, ensure_ascii=False, default=str)
            try:
                asyncio.run_coroutine_threadsafe(self._broadcast(text), self.loop)
            except RuntimeError:
                pass
        if webhook and self.webhook_urls:
            self._pool.submit(self._post_webhooks, event)

    def _post_webhooks(self, event: dict[str, Any]) -> None:
        for url in self.webhook_urls:
            try:
                httpx.post(url, json=event, timeout=5)
            except Exception as e:  # pragma: no cover
                log.warning("webhook 전송 실패 %s: %s", url, e)
