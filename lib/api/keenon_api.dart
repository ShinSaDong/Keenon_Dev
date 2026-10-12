import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'labels.dart';
import 'models.dart';

class KeenonApiException implements Exception {
  final int? code;
  final String message;

  KeenonApiException(this.message, {this.code});

  @override
  String toString() => code == null ? message : '$message (code $code)';
}

/// 앱이 사용하는 로봇 API. 실제 Keenon 구현과 데모(Mock) 구현이 같은 인터페이스를 쓴다.
/// 나중에 한국 중계 서버를 두면 이 인터페이스의 구현만 바꾸면 된다.
abstract class RobotApi {
  Future<List<Store>> getStores();
  Future<List<Robot>> getRobots(String storeId);
  Future<RobotStatus?> getRobotStatus(String robotId);
  Future<List<Scene>> getScenes(String storeId);
  Future<List<TargetPoint>> getPoints(String sceneCode);
  Future<CallResult> callRobot({
    required String storeId,
    required TargetPoint point,
    String? sceneCode,
    String? robotId,
    String? robotType,
  });
  Future<CallResult> returnToOrigin({required String storeId, String? robotId});
  Future<TaskStatus> getTaskStatus(String taskNo);
  Future<void> cancelTask(String taskNo);
  Future<TaskRecordPage> getTaskRecords({
    required String storeId,
    required bool hotel,
    int page = 1,
    int size = 20,
    int? startTime,
    int? endTime,
  });
  Future<MapData> getMap({required String sceneCode, required String floor, String? building});
  Future<RobotLocation> getLocation(String robotSn);
  void dispose() {}
}

/// Keenon Cloud Open API 클라이언트
/// - 토큰: POST /api/open/oauth/token (client_credentials), 만료 60초 전 재발급
/// - 610401(토큰 무효) 응답 시 토큰을 다시 받아 1회 재시도
class KeenonApi implements RobotApi {
  KeenonApi({
    required this.baseUrl,
    required this.clientId,
    required this.clientSecret,
    http.Client? client,
  }) : _http = client ?? http.Client();

  final String baseUrl;
  final String clientId;
  final String clientSecret;
  final http.Client _http;

  static const _timeout = Duration(seconds: 15);

  String? _token;
  DateTime? _tokenExpiry;
  Future<String>? _tokenFuture;

  Uri _uri(String path, [Map<String, String?>? query]) {
    final q = <String, String>{};
    query?.forEach((k, v) {
      if (v != null && v.isNotEmpty) q[k] = v;
    });
    var base = baseUrl.trim();
    while (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    final uri = Uri.parse('$base$path');
    return q.isEmpty ? uri : uri.replace(queryParameters: q);
  }

  Future<String> _getToken({bool force = false}) {
    final now = DateTime.now();
    if (!force && _token != null && _tokenExpiry != null && now.isBefore(_tokenExpiry!)) {
      return Future.value(_token!);
    }
    // 동시에 여러 요청이 와도 토큰 발급은 한 번만
    return _tokenFuture ??= _fetchToken().whenComplete(() => _tokenFuture = null);
  }

  Future<String> _fetchToken() async {
    final http.Response res;
    try {
      res = await _http.post(
        _uri('/api/open/oauth/token'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'client_id': clientId,
          'client_secret': clientSecret,
          'grant_type': 'client_credentials',
        },
      ).timeout(_timeout);
    } on TimeoutException {
      throw KeenonApiException('토큰 발급 요청 시간 초과 (도메인/네트워크 확인)');
    } catch (e) {
      throw KeenonApiException('토큰 발급 요청 실패: $e');
    }

    final body = _decode(res);
    if (body is Map && body['access_token'] != null) {
      final token = body['access_token'].toString();
      final expiresIn = asInt(body['expires_in']) ?? 7200;
      final safe = expiresIn > 120 ? expiresIn - 60 : (expiresIn > 30 ? expiresIn - 10 : expiresIn);
      _token = token;
      _tokenExpiry = DateTime.now().add(Duration(seconds: safe));
      return token;
    }
    if (body is Map) {
      final code = asInt(body['code']);
      final msg = (body['msg'] ?? body['error_description'] ?? body['error'])?.toString();
      throw KeenonApiException('토큰 발급 실패: ${describeApiCode(code, msg)}', code: code);
    }
    throw KeenonApiException('토큰 발급 실패 (HTTP ${res.statusCode})');
  }

  dynamic _decode(http.Response res) {
    try {
      return jsonDecode(utf8.decode(res.bodyBytes));
    } catch (_) {
      throw KeenonApiException('HTTP ${res.statusCode}: 응답을 해석할 수 없습니다');
    }
  }

  Future<dynamic> _request(
    String method,
    String path, {
    Map<String, String?>? query,
    Map<String, dynamic>? body,
    bool retried = false,
  }) async {
    final token = await _getToken();
    final headers = <String, String>{'Authorization': 'bearer $token'};
    final uri = _uri(path, query);

    http.Response res;
    try {
      if (method == 'GET') {
        res = await _http.get(uri, headers: headers).timeout(_timeout);
      } else if (method == 'DELETE') {
        res = await _http.delete(uri, headers: headers).timeout(_timeout);
      } else {
        headers['Content-Type'] = 'application/json';
        res = await _http.post(uri, headers: headers, body: jsonEncode(body ?? const {})).timeout(_timeout);
      }
    } on TimeoutException {
      throw KeenonApiException('요청 시간 초과: $path');
    } on KeenonApiException {
      rethrow;
    } catch (e) {
      throw KeenonApiException('네트워크 오류: $e');
    }

    final decoded = _decode(res);
    if (decoded is! Map) {
      throw KeenonApiException('HTTP ${res.statusCode}: 예상하지 못한 응답 형식');
    }
    final code = asInt(decoded['code']);
    if ((code == 610401 || res.statusCode == 401) && !retried) {
      _token = null;
      _tokenExpiry = null;
      return _request(method, path, query: query, body: body, retried: true);
    }
    if (code != kSuccessCode) {
      throw KeenonApiException(describeApiCode(code, decoded['msg']?.toString()), code: code);
    }
    return decoded['data'];
  }

  // ------------------------------------------------------------------ 매장/로봇

  @override
  Future<List<Store>> getStores() async {
    final data = await _request('GET', '/api/open/data/v1/store/list');
    return listFrom(data).map(Store.fromJson).toList();
  }

  @override
  Future<List<Robot>> getRobots(String storeId) async {
    final data = await _request('GET', '/api/open/data/v1/store/robot/list', query: {'storeId': storeId});
    return listFrom(data).map(Robot.fromJson).toList();
  }

  @override
  Future<RobotStatus?> getRobotStatus(String robotId) async {
    final data = await _request('GET', '/api/open/scene/v1/robot/status', query: {'robotId': robotId});
    final list = listFrom(data);
    if (list.isNotEmpty) return RobotStatus.fromJson(list.first);
    if (data is Map && data['robotId'] != null) {
      return RobotStatus.fromJson(Map<String, dynamic>.from(data));
    }
    return null;
  }

  // ------------------------------------------------------------------ 씬/포인트/호출

  @override
  Future<List<Scene>> getScenes(String storeId) async {
    final data = await _request('GET', '/api/open/scene/v1/info/list', query: {'storeId': storeId});
    return listFrom(data).map(Scene.fromJson).toList();
  }

  @override
  Future<List<TargetPoint>> getPoints(String sceneCode) async {
    final data = await _request('GET', '/api/open/scene/v1/target/list', query: {'sceneCode': sceneCode});
    return listFrom(data).map(TargetPoint.fromJson).toList();
  }

  @override
  Future<CallResult> callRobot({
    required String storeId,
    required TargetPoint point,
    String? sceneCode,
    String? robotId,
    String? robotType,
  }) async {
    final body = <String, dynamic>{
      'uuid': point.uuid,
      'pointId': point.pointId,
      'storeId': storeId,
      if (sceneCode != null && sceneCode.isNotEmpty) 'sceneCode': sceneCode,
      if (robotType != null && robotType.isNotEmpty) 'robotType': robotType,
      if (robotId != null && robotId.isNotEmpty) 'robotId': robotId,
    };
    final data = await _request('POST', '/api/open/scene/v3/robot/call/task', body: body);
    return CallResult.fromJson(data);
  }

  @override
  Future<CallResult> returnToOrigin({required String storeId, String? robotId}) async {
    // 문서에 Param 으로 표기되어 있어 쿼리와 바디에 모두 실어 보낸다.
    final params = <String, String?>{'storeId': storeId, 'robotId': robotId};
    final body = <String, dynamic>{
      'storeId': storeId,
      if (robotId != null && robotId.isNotEmpty) 'robotId': robotId,
    };
    final data = await _request('POST', '/api/open/scene/v2/robot/call/back/task', query: params, body: body);
    return CallResult.fromJson(data);
  }

  @override
  Future<TaskStatus> getTaskStatus(String taskNo) async {
    final data = await _request('GET', '/api/open/scene/v1/robot/call/task', query: {'taskNo': taskNo});
    final s = TaskStatus.fromJson(data);
    if (s.taskNo.isNotEmpty) return s;
    final m = data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
    m['taskNo'] = taskNo;
    return TaskStatus.fromJson(m);
  }

  @override
  Future<void> cancelTask(String taskNo) async {
    await _request('DELETE', '/api/open/scene/v1/robot/call/task', query: {'taskNo': taskNo});
  }

  // ------------------------------------------------------------------ 이력

  @override
  Future<TaskRecordPage> getTaskRecords({
    required String storeId,
    required bool hotel,
    int page = 1,
    int size = 20,
    int? startTime,
    int? endTime,
  }) async {
    final path = hotel ? '/api/open/data/v1/store/task/hotel/list' : '/api/open/data/v1/store/task/food/list';
    final data = await _request('GET', path, query: {
      'storeId': storeId,
      'page': '$page',
      'size': '$size',
      'startTime': startTime?.toString(),
      'endTime': endTime?.toString(),
    });
    final list = listFrom(data).map((e) => TaskRecord.fromJson(e, hotel: hotel)).toList();
    final total = data is Map ? (asInt(data['total']) ?? list.length) : list.length;
    return TaskRecordPage(total: total, list: list);
  }

  // ------------------------------------------------------------------ 맵/위치

  @override
  Future<MapData> getMap({required String sceneCode, required String floor, String? building}) async {
    final data = await _request('GET', '/api/open/custom/robot/map', query: {
      'sceneCode': sceneCode,
      'floorInfo': floor,
      'buildingInfo': building,
    });
    return MapData.fromJson(data);
  }

  @override
  Future<RobotLocation> getLocation(String robotSn) async {
    final data = await _request('GET', '/api/open/custom/robot/location', query: {'robotSn': robotSn});
    return RobotLocation.fromJson(data);
  }

  @override
  void dispose() => _http.close();
}
