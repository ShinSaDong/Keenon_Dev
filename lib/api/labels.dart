/// Keenon Open API 코드값의 한국어 표시 문구 (Keenon Cloud API 문서 V2.4.0 기준)

const int kSuccessCode = 610000;

String describeApiCode(int? code, String? msg) {
  const known = <int, String>{
    610001: 'client_id 또는 client_secret 이 올바르지 않습니다',
    610401: '토큰이 유효하지 않거나 만료되었습니다',
    610403: '이 기능 또는 리소스에 대한 권한이 없습니다',
    610500: 'Keenon 서버 오류가 발생했습니다',
    610601: '요청 파라미터가 올바르지 않습니다',
    617000: '호출이 너무 잦아 IP가 제한되었습니다 (잠시 후 다시 시도)',
    615001: '로봇이 오프라인입니다',
    615025: '로봇 응답 시간이 초과되었습니다',
    5000: '로봇이 작업 중입니다',
    5001: '로봇이 대기 상태가 아닙니다',
    5003: '로봇이 현재 작업을 수행 중입니다',
    5004: '로봇이 수행할 작업이 없습니다',
    5007: '로봇이 작업 중입니다',
    5009: '로봇이 엘리베이터 탑승 중입니다',
    5010: '로봇이 일시정지 상태입니다',
    5011: '원격 조작이 너무 잦습니다',
    5014: '로봇 위치 인식(측위)을 잃었습니다',
    290001: '알 수 없는 오류',
  };
  final base = code == null ? null : known[code];
  if (base != null) return base;
  final m = (msg ?? '').trim();
  if (m.isNotEmpty) return m;
  return '알 수 없는 오류 (code: ${code ?? '-'})';
}

String taskStatusLabel(int? s) {
  switch (s) {
    case 0:
      return '작업 실패';
    case 1:
      return '대기열 등록';
    case 2:
      return '호출 중';
    case 3:
      return '이동 중';
    case 4:
      return '작업 완료';
    case 5:
      return '작업 취소됨';
    case 6:
      return '목적지 도착';
    case 7:
      return '대기 중';
    default:
      return '상태 확인 중';
  }
}

String? taskErrorLabel(int? code) {
  if (code == null || code == 0 || code == 1) return null;
  const m = <int, String>{
    300: '로봇에서 원격 호출 기능이 꺼져 있습니다',
    301: '로봇이 설정 화면에 있습니다',
    302: '로봇이 다른 작업 중이라 호출할 수 없습니다',
    303: '로봇이 작업을 거부했습니다',
    304: '로봇에 해당 작업이 없어 조작할 수 없습니다',
    305: '로봇이 목적지 포인트를 인식하지 못했습니다',
    400: '로봇에서 수동으로 작업을 취소했습니다',
    401: '로봇에서 작업 기록을 찾을 수 없습니다',
    402: '로봇에서 알 수 없는 오류로 작업이 종료되었습니다',
    403: '로봇이 작업 시간 초과로 판단했습니다',
    500: '사용 가능한 로봇이 없습니다',
    501: '오랫동안 갱신이 없어 서버에서 작업을 종료했습니다',
    502: '로봇이 오프라인이 되어 작업이 갱신되지 않았습니다',
    503: '로봇이 호출 서비스에 등록되지 않았습니다',
  };
  return m[code] ?? '오류 코드 $code';
}

String foodTaskModeLabel(int? t) {
  switch (t) {
    case 0:
      return '식사 배송';
    case 2:
      return '직접 배송';
    case 3:
      return '다중 주문 배송';
    case 4:
      return '간식';
    default:
      return t == null ? '-' : '유형 $t';
  }
}

String hotelBizTypeLabel(int? t) {
  switch (t) {
    case 0:
      return '객실 배송';
    case 1:
      return '일반 배송';
    case 2:
      return '디스패치';
    case 3:
      return '테이크아웃';
    case 4:
      return '원점 복귀';
    case 5:
      return '컨테이너';
    default:
      return t == null ? '-' : '유형 $t';
  }
}

String onlineTypeLabel(int? t) {
  switch (t) {
    case 2:
      return 'Wi-Fi';
    case 3:
      return '3G';
    case 4:
      return '4G';
    default:
      return '-';
  }
}
