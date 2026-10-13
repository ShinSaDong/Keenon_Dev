"""서버 설정 (환경변수 또는 .env 로 변경)"""
from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

    # DB: 개발은 SQLite, 운영은 PostgreSQL (postgresql+psycopg://user:pw@host/db)
    database_url: str = "sqlite:///./data/control.db"

    # 로봇 연결 방식
    #   local : 서버 안에서 가상 로봇을 직접 돌림 (브로커 불필요, 가장 간단)
    #   mqtt  : MQTT 브로커를 통해 로봇(가상/실제)과 통신
    robot_link: str = "local"
    mqtt_host: str = "localhost"
    mqtt_port: int = 1883
    mqtt_username: str = ""
    mqtt_password: str = ""
    mqtt_topic_prefix: str = "kr/robot"

    # Keenon Open API 호환 인증용 클라이언트 목록  "id:secret,id2:secret2"
    open_clients: str = "demo-client:demo-secret"
    token_ttl_seconds: int = 7200

    # 상태 변경을 Keenon Webhook 형식으로 보낼 주소들 (쉼표 구분, 비우면 사용 안 함)
    webhook_urls: str = ""

    # 마지막 메시지 후 이 시간(초)이 지나면 오프라인 처리
    offline_timeout_seconds: int = 30

    # 첫 실행 시 데모 매장·맵·로봇 등록
    seed_demo: bool = True

    def clients(self) -> dict[str, str]:
        out: dict[str, str] = {}
        for pair in self.open_clients.split(","):
            if ":" in pair:
                cid, secret = pair.split(":", 1)
                if cid.strip():
                    out[cid.strip()] = secret.strip()
        return out

    def webhooks(self) -> list[str]:
        return [u.strip() for u in self.webhook_urls.split(",") if u.strip()]


@lru_cache
def get_settings() -> Settings:
    return Settings()
