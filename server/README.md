# 한국 관제 서버 (1차 테스트)

Keenon 로봇을 국내 서버로 관제하기 위한 **테스트 서버**입니다.

- 앱 쪽: **Keenon Open API와 같은 주소·형식**으로 응답합니다. 앱은 서버 주소만 바꾸면 그대로 동작합니다.
- 로봇 쪽: **RobotLink 어댑터**로 분리되어 있습니다. 지금은 가상 로봇으로 동작하고, Keenon이 실제 통신 규격을 주면 어댑터만 교체합니다.
- 데이터: 모든 상태·작업 이력·감사 로그가 이 서버의 DB(국내)에만 저장됩니다.

```
[Flutter 앱] ──HTTPS(Open API 호환)──▶ [관제 서버 FastAPI] ──MQTT──▶ [로봇(가상/실제)]
                                          │  DB: SQLite(개발) / PostgreSQL(운영)
[웹 대시보드 /] ◀──────────────────────────┘  Webhook(선택)
```

## 1. 가장 빠른 실행 (브로커 없이, 가상 로봇 내장)

```bash
cd server
pip install -r requirements.txt
uvicorn app.main:app --host 0.0.0.0 --port 8000
```

- 대시보드: http://localhost:8000/
  - 맵의 초록 점을 클릭하면 호출됩니다.
  - 로봇 표의 [복귀], 작업 표의 [취소] 버튼을 쓸 수 있습니다.
- API 문서(Swagger): http://localhost:8000/docs
- 데모 매장
  - 데모 레스토랑 1호점: 서빙 로봇 3대 (1대는 오프라인)
  - 데모 호텔: 배송 로봇 2대
- 테스트 계정: `client_id = demo-client`, `client_secret = demo-secret`

## 2. GitHub Codespaces에서 실행 + 에뮬레이터 앱 연결

1. GitHub 저장소에서 **Code ▸ Codespaces ▸ Create codespace on main** 을 누릅니다.
2. 터미널에서 다음을 실행합니다.
   ```bash
   cd server
   pip install -r requirements.txt
   uvicorn app.main:app --host 0.0.0.0 --port 8000
   ```
3. 아래 **PORTS** 탭에서 8000번 포트를 설정합니다.
   - 오른쪽 클릭 ▸ **Port Visibility ▸ Public** 으로 바꿉니다.
   - Public이 아니면 앱이 GitHub 로그인 페이지에 막힙니다.
4. 표시된 주소를 복사합니다. 예: `https://xxxx-8000.app.github.dev`
5. 앱에서 **설정 ▸ 서버 지역: 직접 입력** 을 고릅니다.
   - 위 주소를 넣습니다. 끝에 `/`는 넣지 않습니다.
   - Client ID에 `demo-client`, Secret에 `demo-secret` 을 넣습니다.
   - **데모 모드는 끕니다.**
6. 매장 목록에 "데모 레스토랑 1호점 / 데모 호텔" 이 보이면 연결된 것입니다.
   - 앱에서 호출하면 대시보드 맵에서도 로봇이 움직입니다.

> 안드로이드 앱은 기본적으로 `http://` 주소를 막습니다. Codespaces의 `https://` 주소를 쓰세요.

## 3. MQTT 모드 (실제 로봇과 같은 구조)

서버와 로봇이 MQTT 브로커를 사이에 두고 통신합니다. 실제 로봇이 붙을 때와 같은 구조입니다.

```bash
# 터미널 1: 브로커 (mosquitto 가 없으면 pip install amqtt 후 `amqtt`)
mosquitto -c mosquitto/mosquitto.conf
# 터미널 2: 서버
ROBOT_LINK=mqtt uvicorn app.main:app --host 0.0.0.0 --port 8000
# 터미널 3: 가상 로봇 5대
python -m simulator.run_mqtt
```

Docker를 쓰면 서버 + PostgreSQL + Mosquitto + 가상 로봇이 한 번에 뜹니다.

```bash
docker compose up -d --build      # http://localhost:8000
docker compose logs -f server
docker compose down               # 데이터 유지 /  down -v 는 DB 삭제
```

## 4. 설정 (.env)

`cp .env.example .env` 후 수정합니다. 환경변수로 줘도 됩니다.

| 항목 | 기본값 | 설명 |
|---|---|---|
| `DATABASE_URL` | `sqlite:///./data/control.db` | 운영: `postgresql+psycopg://user:pw@host:5432/db` |
| `ROBOT_LINK` | `local` | `local` 은 서버 안 가상 로봇, `mqtt` 는 브로커 경유 |
| `MQTT_HOST` / `MQTT_PORT` | `localhost` / `1883` | 브로커 주소 |
| `MQTT_TOPIC_PREFIX` | `kr/robot` | 토픽 앞부분 |
| `OPEN_CLIENTS` | `demo-client:demo-secret` | 앱·외부 시스템 계정 (`id:secret`, 쉼표로 여러 개) |
| `WEBHOOK_URLS` | (없음) | 상태 변경을 Keenon Webhook 형식으로 POST할 주소 |
| `OFFLINE_TIMEOUT_SECONDS` | `30` | 이 시간 동안 메시지가 없으면 오프라인 처리 |
| `SEED_DEMO` | `true` | 데모 매장·맵·로봇 자동 등록 |

## 5. 구현된 Open API 호환 엔드포인트

응답은 모두 `{code: 610000, msg, data}` 형식입니다. 오류도 HTTP 200에 code로 전달합니다. 예: 610401 토큰 오류, 615001 로봇 오프라인, 5001 로봇 사용 중.

| 기능 | 메서드·경로 |
|---|---|
| 토큰 발급 | `POST /api/open/oauth/token` (form, client_credentials) |
| 매장 목록 / 매장 로봇 | `GET /api/open/data/v1/store/list`, `GET /api/open/data/v1/store/robot/list` |
| 로봇 상태 / 배터리 | `GET /api/open/scene/v1/robot/status`, `GET /api/open/custom/robot/battery/level` |
| 씬 / 목적지 | `GET /api/open/scene/v1/info/list`, `GET /api/open/scene/v1/target/list` |
| 맵 / 맵 포인트 | `GET /api/open/custom/robot/map`, `GET /api/open/custom/robot/v2/map/position` |
| 로봇 위치 | `GET /api/open/custom/robot/location` |
| 호출 / 복귀 | `POST /api/open/scene/v3/robot/call/task`, `POST /api/open/scene/v2/robot/call/back/task` |
| 작업 상태 / 취소 | `GET`·`DELETE /api/open/scene/v1/robot/call/task` |
| 이력 (서빙 / 호텔) | `GET /api/open/data/v1/store/task/food/list`, `.../hotel/list` |

관리용 경로도 있습니다.

- `/admin/api/*`: 대시보드 데이터, 호출, 복귀, 취소, 감사 로그
- `/ws/events`: 실시간 이벤트 (WebSocket, Webhook과 같은 형식)

## 6. 로봇 ↔ 서버 통신 (임시 규격)

Keenon의 로봇-클라우드 규격이 공개되어 있지 않습니다. 그래서 Keenon 메시지 형식(엘리베이터 API의 envelope)을 본뜬 **임시 규격**을 씁니다.

```
로봇 → 서버  kr/robot/{SN}/up/{Hello|Online|Power|WorkState|Position|TaskState|Ack}
서버 → 로봇  kr/robot/{SN}/down/command      (CreateTask | CancelTask | ReturnOrigin)
메시지      {"action","deviceName","messageId","code","status","taskNo"?,"data":{...}}
```

Keenon에서 실제 규격을 받으면 `app/link/` 에 어댑터를 새로 추가하면 됩니다. 예: `keenon_link.py`.
DB·API·앱·대시보드는 바꿀 필요가 없습니다.

## 7. 폴더 구조

```
app/
  main.py              서버 시작, 라우터 연결
  config.py            설정
  db.py                DB 테이블 (매장·씬·포인트·로봇·작업·작업이벤트·감사로그)
  layouts.py, seed.py  데모 맵/로봇 데이터
  protocol.py          로봇 메시지 형식
  link/                로봇 연결 어댑터 (local / mqtt / 추후 keenon)
  services/core.py     관제 로직 (배정, 작업 상태, 오프라인 감시)
  services/events.py   WebSocket / Webhook 이벤트
  api/openapi_compat.py  Keenon Open API 호환
  api/admin.py         대시보드 API
  static/dashboard.html  웹 대시보드
simulator/             가상 로봇 (local 내장 / MQTT 단독 실행)
tests/                 통합 테스트 (pytest)
```

## 8. 테스트

```bash
pip install -r requirements-dev.txt
pytest -q          # 8개: 토큰·목록·맵·호출 전체 주기·사용중/취소·오프라인·자동배정·대시보드
```

## 9. 다음 단계 (운영 전 필수)

- [ ] Keenon 실제 통신 규격을 확보하고 `keenon_link` 어댑터를 작성합니다.
- [ ] 대시보드·관리 API에 로그인을 붙입니다. 지금은 인증이 없습니다.
- [ ] MQTT 계정·TLS(8883)를 적용하고, 로봇별 인증을 붙입니다.
- [ ] NCP 공공기관용(CSAP) 환경에 배포합니다. Server + Cloud DB for PostgreSQL을 쓰고, HTTPS 인증서를 적용합니다.
- [ ] 개인정보·로그 보관 기간 정책을 정하고 백업을 설정합니다.
