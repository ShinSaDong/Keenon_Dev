# Keenon 관제 PoC 앱 (Flutter / Android)

Keenon Cloud Open API(문서 V2.4.0)를 **앱에서 직접 호출**하는 내부 테스트용 앱입니다.

> ⚠️ PoC 전용: `client_secret` 이 기기에 저장됩니다. 외부 배포 전에는 반드시 한국 중계 서버가 토큰을 발급하도록 바꿔야 합니다.
> `lib/api/keenon_api.dart` 의 `RobotApi` 인터페이스 구현만 서버 호출용으로 교체하면 화면 코드는 그대로 쓸 수 있습니다.

## 기능

| 화면 | 사용 API |
|---|---|
| 설정 (리전·client_id·secret·데모 모드·연결 테스트) | `POST /api/open/oauth/token` |
| 매장 목록 | `GET /api/open/data/v1/store/list` |
| 로봇 목록 (온라인·배터리·모델·앱 버전) | `GET /api/open/data/v1/store/robot/list` |
| 로봇 상세 (호출 가능·충전·현재 씬) | `GET /api/open/scene/v1/robot/status` |
| 호출 (씬 → 포인트 선택, 특정 로봇/자동 배정) | `GET /scene/v1/info/list`, `GET /scene/v1/target/list`, `POST /scene/v3/robot/call/task` |
| 원점 복귀 | `POST /api/open/scene/v2/robot/call/back/task` |
| 작업 추적 (3초 간격 조회) · 취소 | `GET` / `DELETE /api/open/scene/v1/robot/call/task` |
| 작업 이력 (배송/호텔, 기간, 페이지) | `GET /api/open/data/v1/store/task/food|hotel/list` |
| 맵 · 실시간 위치 | `GET /api/open/custom/robot/map`, `GET /api/open/custom/robot/location` |

**데모 모드**를 켜면 계정 없이 가상 매장·로봇·맵으로 모든 화면을 확인할 수 있습니다.

### 데모 모드 시나리오
- 매장 2곳: **데모 레스토랑**(서빙 로봇 3대, 테이블 8개·주방) / **데모 호텔**(호텔 배송 로봇 2대, 객실 6개·프런트)
- 로봇을 호출하면 충전 위치 → 중앙 통로 → 목적지로 **맵 위에서 실제로 이동**하고, 도착 후 8초 뒤 충전 위치로 복귀
- 로봇 목록의 **매장 맵** 버튼: 매장의 모든 로봇을 한 맵에서 확인 (0.3초 간격, 이동 궤적 표시)
- 작업 추적 화면의 **맵에서 이동 보기** 버튼: 호출한 로봇의 이동을 바로 확인

### 로봇 이미지
`assets/robots/serving.png`, `assets/robots/hotel.png` 를 넣으면 내장 일러스트 대신 표시됩니다.
Keenon 에서 받은(사용 허락된) 공식 이미지를 넣으세요.

## 빌드 방법

### A. Windows PC (권장)
1. Flutter SDK 와 Android Studio(Android SDK 포함) 설치 → `flutter doctor` 로 확인
2. 이 폴더에서 `build_apk.bat` 실행
   - `android/` 폴더가 없으면 `flutter create` 로 자동 생성
   - 인터넷 권한 추가 → 테스트 → release APK 빌드
3. 결과물: `build\app\outputs\flutter-apk\app-release.apk`

수동으로 하려면:
```
flutter create --platforms=android --org kr.robotcontrol --project-name keenon_control .
powershell -ExecutionPolicy Bypass -File tool\add_internet_permission.ps1
flutter pub get
flutter run            # 연결된 폰/에뮬레이터에서 실행
flutter build apk --release
```

### B. GitHub Actions (PC에 SDK 설치 없이)
이 폴더를 GitHub 저장소(main 브랜치)에 올리면 `.github/workflows/build-apk.yml` 이 자동으로 APK 를 빌드합니다.
Actions 탭 → 실행 결과 → Artifacts 의 `keenon_control-apk` 에서 내려받습니다.

> release APK 는 기본 debug 키로 서명됩니다(내부 테스트용). 스토어 배포 시 별도 서명 키 설정이 필요합니다.

## 실로봇 테스트 전 확인할 것
- Keenon 에서 발급받은 `client_id` / `client_secret`, 로봇이 등록된 **리전 도메인** (중국 본토 / EU / 일본)
- 원격 호출은 **현장 배포가 끝난 로봇**에서만 동작하며, 로봇 앱에서 원격 호출 설정이 켜져 있어야 함
- API별 지원 기종·최소 로봇 앱 버전이 다름 (상태·호출: 배송 v1.8.0 / 호텔 v1.6.0, 맵: W v1.11.0 / C v3.5.3)
- 조회가 과도하면 IP·client_id 가 차단됨(617000). 작업 상태 조회는 3초 간격으로 구현됨

## 실기 검증이 필요한 부분 (문서가 모호함)
- **원점 복귀**: 파라미터가 `Param` 으로 표기되어 쿼리스트링과 JSON 바디에 모두 실어 보냄
- **POST 바디 형식**: JSON 으로 전송 (문서에 Content-Type 명시 없음)
- **맵 content**: `byte[]` → 숫자 배열/base64 모두 처리. PNG/JPEG/BMP/PGM/원시 점유격자 순으로 해석
- **맵 좌표 변환**: `픽셀 = (좌표 - origin) / 해상도`, y축 반전(ROS 방식) 가정. 해상도는 설정 화면에서 조정 (기본 0.05 m/px). `isDynamic` 맵은 계산 방식이 다를 수 있음

## 폴더 구조
```
lib/
  main.dart                앱 시작, 설정 여부에 따라 첫 화면 결정
  app_state.dart           설정 저장(SharedPreferences), API 인스턴스 관리
  api/keenon_api.dart      RobotApi 인터페이스 + Keenon 클라이언트(토큰 캐시·재시도)
  api/mock_api.dart        데모 모드용 가상 API
  api/models.dart          응답 모델 (타입이 달라도 관대하게 파싱)
  api/labels.dart          상태·오류 코드 한국어 문구
  util/map_image.dart      맵 바이트 → 이미지 변환 (PGM/점유격자 → BMP)
  ui/                      화면들
test/                      API 클라이언트·모델·맵 변환·화면 테스트
```
