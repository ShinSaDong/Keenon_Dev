import 'dart:convert';
import 'dart:typed_data';

// ---------------------------------------------------------------------------
// JSON 파싱 헬퍼: Keenon 응답은 숫자/문자열/불리언 타입이 문서와 다르게 올 수 있어
// 모든 필드를 관대하게 해석한다.
// ---------------------------------------------------------------------------

int? asInt(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v.trim()) ?? double.tryParse(v.trim())?.toInt();
  if (v is bool) return v ? 1 : 0;
  return null;
}

double? asDouble(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v.trim());
  return null;
}

String asString(dynamic v) {
  if (v == null) return '';
  return v.toString();
}

bool? asBool(dynamic v) {
  if (v == null) return null;
  if (v is bool) return v;
  if (v is num) return v != 0;
  if (v is String) {
    final s = v.trim().toLowerCase();
    if (s == 'true' || s == '1') return true;
    if (s == 'false' || s == '0') return false;
  }
  return null;
}

/// data 가 배열이거나 {list: [...]} / {records: [...]} 형태인 경우 모두 리스트로 변환
List<Map<String, dynamic>> listFrom(dynamic data) {
  dynamic raw = data;
  if (data is Map) {
    raw = data['list'] ?? data['records'] ?? data['targetList'] ?? const [];
  }
  if (raw is! List) return const [];
  return raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
}

// ---------------------------------------------------------------------------
// 모델
// ---------------------------------------------------------------------------

class Store {
  final String storeId;
  final String storeName;
  final String customerName;
  final String brandName;
  final String address;

  Store({
    required this.storeId,
    required this.storeName,
    this.customerName = '',
    this.brandName = '',
    this.address = '',
  });

  factory Store.fromJson(Map<String, dynamic> j) => Store(
        storeId: asString(j['storeId']),
        storeName: asString(j['storeName']),
        customerName: asString(j['customerName']),
        brandName: asString(j['brandName']),
        address: asString(j['address']),
      );
}

class Robot {
  final String robotId;
  final String robotName;
  final bool online;
  final int? power;
  final String robotModel;
  final String appVersion;
  final int? onlineType;

  Robot({
    required this.robotId,
    required this.robotName,
    required this.online,
    this.power,
    this.robotModel = '',
    this.appVersion = '',
    this.onlineType,
  });

  factory Robot.fromJson(Map<String, dynamic> j) => Robot(
        robotId: asString(j['robotId']),
        robotName: asString(j['robotName']),
        online: asBool(j['onlineStatus']) ?? false,
        power: asInt(j['power']),
        robotModel: asString(j['robotModel']).trim(),
        appVersion: asString(j['appVersion']),
        onlineType: asInt(j['onlineType']),
      );

  String get displayName => robotName.isEmpty ? robotId : robotName;

  /// W 시리즈(호텔) 또는 이름에 '호텔'이 들어가면 호텔 로봇, 그 외는 서빙 로봇으로 표시
  RobotKind get kind => robotKindOf(model: robotModel, name: robotName);
}

enum RobotKind { serving, hotel }

RobotKind robotKindOf({String model = '', String name = ''}) {
  final m = model.trim().toUpperCase();
  if (m.startsWith('W') || name.contains('호텔') || name.toLowerCase().contains('hotel')) {
    return RobotKind.hotel;
  }
  return RobotKind.serving;
}

class RobotStatus {
  final String robotId;
  final String robotName;
  final bool online;
  final bool canBeCalled;
  final bool? charging;
  final int? power;
  final String sceneCode;
  final String sceneName;

  RobotStatus({
    required this.robotId,
    required this.robotName,
    required this.online,
    required this.canBeCalled,
    this.charging,
    this.power,
    this.sceneCode = '',
    this.sceneName = '',
  });

  factory RobotStatus.fromJson(Map<String, dynamic> j) {
    final cs = asInt(j['chargeStatus']);
    return RobotStatus(
      robotId: asString(j['robotId']),
      robotName: asString(j['robotName']),
      online: asBool(j['onlineStatus']) ?? false,
      canBeCalled: asBool(j['canBeCalled']) ?? false,
      charging: cs == null ? null : cs == 1,
      power: asInt(j['power']),
      sceneCode: asString(j['sceneCode']),
      sceneName: asString(j['sceneName']),
    );
  }
}

class Scene {
  final String sceneCode;
  final String sceneName;

  Scene({required this.sceneCode, required this.sceneName});

  factory Scene.fromJson(Map<String, dynamic> j) => Scene(
        sceneCode: asString(j['sceneCode']),
        sceneName: asString(j['sceneName']),
      );

  String get displayName => sceneName.isEmpty ? sceneCode : sceneName;
}

class TargetPoint {
  final String pointName;
  final String area;
  final String uuid;
  final String pointId;

  TargetPoint({
    required this.pointName,
    required this.area,
    required this.uuid,
    required this.pointId,
  });

  factory TargetPoint.fromJson(Map<String, dynamic> j) => TargetPoint(
        pointName: asString(j['pointName']),
        area: asString(j['area']),
        uuid: asString(j['uuid']),
        pointId: asString(j['pointId']),
      );

  String get displayName => pointName.trim().isEmpty ? '포인트 $pointId' : pointName.trim();
}

class CallResult {
  final String taskNo;
  final int? waitQueuing;

  CallResult({required this.taskNo, this.waitQueuing});

  factory CallResult.fromJson(dynamic data) {
    final j = data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
    return CallResult(
      taskNo: asString(j['taskNo']),
      waitQueuing: asInt(j['waitQueuing']),
    );
  }
}

class TaskStatus {
  final String taskNo;
  final int? status;
  final int? errorCode;
  final String remark;
  final double? remainingDistance;
  final String robotId;
  final int? waitQueuing;
  final String lastUpdateTime;

  TaskStatus({
    required this.taskNo,
    this.status,
    this.errorCode,
    this.remark = '',
    this.remainingDistance,
    this.robotId = '',
    this.waitQueuing,
    this.lastUpdateTime = '',
  });

  factory TaskStatus.fromJson(dynamic data) {
    final j = data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
    final td = j['taskData'] is Map ? Map<String, dynamic>.from(j['taskData'] as Map) : <String, dynamic>{};
    return TaskStatus(
      taskNo: asString(j['taskNo']),
      status: asInt(j['taskStatus']),
      errorCode: asInt(j['errorCode']),
      remark: asString(j['remark']),
      remainingDistance: asDouble(td['remainingDistance']),
      robotId: asString(td['robotId'] ?? td['robotSn']),
      waitQueuing: asInt(td['waitQueuing']),
      lastUpdateTime: asString(td['lastUpdateTime']),
    );
  }

  /// 0 실패, 4 완료, 5 취소 → 더 이상 상태가 바뀌지 않음
  bool get isFinal => status == 0 || status == 4 || status == 5;
}

class TaskRecord {
  final String robotId;
  final String startTime;
  final String endTime;
  final String backTime;
  final double? mileage;
  final int? type; // food: taskMode, hotel: bizType
  final bool? completed;

  TaskRecord({
    required this.robotId,
    this.startTime = '',
    this.endTime = '',
    this.backTime = '',
    this.mileage,
    this.type,
    this.completed,
  });

  factory TaskRecord.fromJson(Map<String, dynamic> j, {required bool hotel}) {
    final ts = asInt(j['taskStatus']);
    return TaskRecord(
      robotId: asString(j['robotId']),
      startTime: asString(j['startTime']),
      endTime: asString(j['endTime']),
      backTime: asString(j['backTime']),
      mileage: asDouble(hotel ? j['totalMileage'] : j['taskMileage']),
      type: asInt(hotel ? j['bizType'] : j['taskMode']),
      completed: ts == null ? null : ts == 1,
    );
  }
}

class TaskRecordPage {
  final int total;
  final List<TaskRecord> list;

  TaskRecordPage({required this.total, required this.list});
}

class MapData {
  final Uint8List? bytes;
  final bool isDynamic;
  final double? width;
  final double? height;
  final double originX;
  final double originY;

  MapData({
    required this.bytes,
    required this.isDynamic,
    this.width,
    this.height,
    required this.originX,
    required this.originY,
  });

  factory MapData.fromJson(dynamic data) {
    final j = data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
    final op = j['originPosition'] is Map ? Map<String, dynamic>.from(j['originPosition'] as Map) : <String, dynamic>{};
    return MapData(
      bytes: _decodeContent(j['content']),
      isDynamic: asBool(op['isDynamic']) ?? false,
      width: asDouble(op['width']),
      height: asDouble(op['height']),
      originX: asDouble(op['originX']) ?? 0,
      originY: asDouble(op['originY']) ?? 0,
    );
  }

  /// content 는 문서상 byte[] 이며 JSON 에서는 숫자 배열 또는 base64 문자열로 올 수 있다.
  static Uint8List? _decodeContent(dynamic c) {
    if (c == null) return null;
    if (c is List) {
      if (c.isEmpty) return null;
      // Java byte 는 -128~127 이므로 & 0xFF 로 보정
      return Uint8List.fromList(c.map((e) => (asInt(e) ?? 0) & 0xFF).toList());
    }
    if (c is String && c.isNotEmpty) {
      var s = c.trim();
      final comma = s.indexOf(',');
      if (s.startsWith('data:') && comma > 0) s = s.substring(comma + 1);
      try {
        return base64Decode(s);
      } catch (_) {
        return null;
      }
    }
    return null;
  }
}

class RobotLocation {
  final String building;
  final String floor;
  final double? x;
  final double? y;
  final double? angle;
  final bool inElevator;
  final String rawCoordinate;

  RobotLocation({
    this.building = '',
    this.floor = '',
    this.x,
    this.y,
    this.angle,
    this.inElevator = false,
    this.rawCoordinate = '',
  });

  factory RobotLocation.fromJson(dynamic data) {
    final j = <String, dynamic>{};
    if (data is Map) {
      // 문서 예시에 " coordinate " 처럼 공백이 섞인 키가 있어 trim 처리
      data.forEach((k, v) => j[k.toString().trim()] = v);
    }
    final raw = asString(j['coordinate']);
    final parts = raw.split(',').map((e) => double.tryParse(e.trim())).toList();
    return RobotLocation(
      building: asString(j['building']).trim(),
      floor: asString(j['floor']).trim(),
      x: parts.isNotEmpty ? parts[0] : null,
      y: parts.length > 1 ? parts[1] : null,
      angle: parts.length > 2 ? parts[2] : null,
      inElevator: asInt(j['takeElevatorStatus']) == 1,
      rawCoordinate: raw,
    );
  }

  bool get hasPosition => x != null && y != null;
}
