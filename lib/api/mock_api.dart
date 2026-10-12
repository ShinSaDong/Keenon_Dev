import 'dart:math';
import 'dart:typed_data';

import '../util/map_image.dart';
import 'keenon_api.dart';
import 'models.dart';

/// 실제 로봇·계정 없이 화면 흐름을 확인하기 위한 데모용 API
class MockRobotApi implements RobotApi {
  final DateTime _t0 = DateTime.now();
  final Map<String, _MockTask> _tasks = {};
  int _seq = 0;
  Uint8List? _mapCache;

  static const _mapW = 400;
  static const _mapH = 300;
  static const _res = 0.05; // m/px
  static const _originX = -10.0;
  static const _originY = -7.5;

  Future<void> _delay([int ms = 300]) => Future.delayed(Duration(milliseconds: ms));

  final _stores = [
    Store(storeId: 'DEMO-S001', storeName: '데모 레스토랑 1호점', brandName: '데모 외식', address: '서울특별시 강남구 (데모)'),
    Store(storeId: 'DEMO-S002', storeName: '데모 호텔', brandName: '데모 호텔', address: '부산광역시 해운대구 (데모)'),
  ];

  final _robots = <String, List<Robot>>{
    'DEMO-S001': [
      Robot(robotId: 'AA:BB:CC:00:00:01', robotName: '서빙 1호', online: true, power: 82, robotModel: 'T8', appVersion: 'v2.3.0', onlineType: 2),
      Robot(robotId: 'AA:BB:CC:00:00:02', robotName: '서빙 2호', online: true, power: 15, robotModel: 'T8', appVersion: 'v2.3.0', onlineType: 4),
      Robot(robotId: 'AA:BB:CC:00:00:03', robotName: '서빙 3호', online: false, power: 0, robotModel: 'T9', appVersion: 'v2.1.5', onlineType: 2),
    ],
    'DEMO-S002': [
      Robot(robotId: 'AA:BB:CC:00:01:01', robotName: '호텔 배송 1호', online: true, power: 64, robotModel: 'W3', appVersion: 'v1.12.0', onlineType: 2),
    ],
  };

  @override
  Future<List<Store>> getStores() async {
    await _delay();
    return _stores;
  }

  @override
  Future<List<Robot>> getRobots(String storeId) async {
    await _delay();
    return _robots[storeId] ?? const [];
  }

  Robot? _findRobot(String robotId) {
    for (final list in _robots.values) {
      for (final r in list) {
        if (r.robotId == robotId) return r;
      }
    }
    return null;
  }

  @override
  Future<RobotStatus?> getRobotStatus(String robotId) async {
    await _delay();
    final r = _findRobot(robotId);
    if (r == null) return null;
    final busy = _tasks.values.any((t) => t.robotId == robotId && !t.statusAt(DateTime.now()).isFinal);
    return RobotStatus(
      robotId: r.robotId,
      robotName: r.robotName,
      online: r.online,
      canBeCalled: r.online && (r.power ?? 0) > 20 && !busy,
      charging: (r.power ?? 0) < 20,
      power: r.power,
      sceneCode: robotId.endsWith('01:01') ? 'DEMO-HOTEL' : 'DEMO-HALL',
      sceneName: robotId.endsWith('01:01') ? '호텔 1층' : '홀 기본 씬',
    );
  }

  @override
  Future<List<Scene>> getScenes(String storeId) async {
    await _delay();
    if (storeId == 'DEMO-S002') return [Scene(sceneCode: 'DEMO-HOTEL', sceneName: '호텔 1층')];
    return [
      Scene(sceneCode: 'DEMO-HALL', sceneName: '홀 기본 씬'),
      Scene(sceneCode: 'DEMO-TERRACE', sceneName: '테라스 씬'),
    ];
  }

  @override
  Future<List<TargetPoint>> getPoints(String sceneCode) async {
    await _delay();
    if (sceneCode == 'DEMO-HOTEL') {
      return [
        for (var i = 1; i <= 6; i++)
          TargetPoint(pointName: '${100 + i}호', area: '1층', uuid: 'demo-h-$i', pointId: '$i'),
        TargetPoint(pointName: '프런트', area: '로비', uuid: 'demo-h-front', pointId: '99'),
      ];
    }
    return [
      for (var i = 1; i <= 8; i++)
        TargetPoint(pointName: '$i번 테이블', area: i <= 4 ? 'A 구역' : 'B 구역', uuid: 'demo-t-$i', pointId: '$i'),
      TargetPoint(pointName: '주방 픽업대', area: '주방', uuid: 'demo-kitchen', pointId: '50'),
    ];
  }

  String _newTask(String robotId) {
    _seq++;
    final no = 'DEMO${DateTime.now().millisecondsSinceEpoch}$_seq';
    _tasks[no] = _MockTask(taskNo: no, robotId: robotId, created: DateTime.now());
    return no;
  }

  @override
  Future<CallResult> callRobot({
    required String storeId,
    required TargetPoint point,
    String? sceneCode,
    String? robotId,
    String? robotType,
  }) async {
    await _delay(500);
    final candidates = (_robots[storeId] ?? const <Robot>[]).where((r) => r.online && (r.power ?? 0) > 20).toList();
    final rid = (robotId != null && robotId.isNotEmpty)
        ? robotId
        : (candidates.isEmpty ? '' : candidates.first.robotId);
    if (rid.isEmpty) {
      throw KeenonApiException('호출 가능한 로봇이 없습니다 (데모)', code: 610500);
    }
    final r = _findRobot(rid);
    if (r != null && !r.online) throw KeenonApiException('로봇이 오프라인입니다', code: 615001);
    return CallResult(taskNo: _newTask(rid), waitQueuing: 1);
  }

  @override
  Future<CallResult> returnToOrigin({required String storeId, String? robotId}) async {
    await _delay(500);
    final rid = robotId ?? (_robots[storeId]?.first.robotId ?? '');
    return CallResult(taskNo: _newTask(rid), waitQueuing: 0);
  }

  @override
  Future<TaskStatus> getTaskStatus(String taskNo) async {
    await _delay(200);
    final t = _tasks[taskNo];
    if (t == null) throw KeenonApiException('작업을 찾을 수 없습니다 (데모)', code: 610601);
    return t.statusAt(DateTime.now());
  }

  @override
  Future<void> cancelTask(String taskNo) async {
    await _delay(300);
    final t = _tasks[taskNo];
    if (t == null) throw KeenonApiException('작업을 찾을 수 없습니다 (데모)', code: 610601);
    t.canceledAt ??= DateTime.now();
  }

  @override
  Future<TaskRecordPage> getTaskRecords({
    required String storeId,
    required bool hotel,
    int page = 1,
    int size = 20,
    int? startTime,
    int? endTime,
  }) async {
    await _delay();
    const total = 37;
    final robots = _robots[storeId] ?? const <Robot>[];
    final rnd = Random(storeId.hashCode ^ (hotel ? 1 : 0));
    final all = List.generate(total, (i) {
      final start = DateTime.now().subtract(Duration(minutes: 25 * i + 5));
      final end = start.add(Duration(minutes: 2 + rnd.nextInt(6)));
      return TaskRecord(
        robotId: robots.isEmpty ? '-' : robots[i % robots.length].robotId,
        startTime: _fmt(start),
        endTime: _fmt(end),
        backTime: _fmt(end.add(const Duration(minutes: 1))),
        mileage: (10 + rnd.nextInt(60)).toDouble(),
        type: hotel ? rnd.nextInt(5) : const [0, 2, 3, 4][rnd.nextInt(4)],
        completed: rnd.nextInt(10) != 0,
      );
    });
    final from = (page - 1) * size;
    final list = from >= total ? <TaskRecord>[] : all.sublist(from, min(total, from + size));
    return TaskRecordPage(total: total, list: list);
  }

  static String _fmt(DateTime d) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}:${two(d.second)}';
  }

  @override
  Future<MapData> getMap({required String sceneCode, required String floor, String? building}) async {
    await _delay(500);
    _mapCache ??= _buildDemoMap();
    return MapData(
      bytes: _mapCache,
      isDynamic: false,
      width: _mapW.toDouble(),
      height: _mapH.toDouble(),
      originX: _originX,
      originY: _originY,
    );
  }

  Uint8List _buildDemoMap() {
    final g = Uint8List(_mapW * _mapH)..fillRange(0, _mapW * _mapH, 245);
    void rect(int x0, int y0, int x1, int y1, int v) {
      for (var y = max(0, y0); y < min(_mapH, y1); y++) {
        for (var x = max(0, x0); x < min(_mapW, x1); x++) {
          g[y * _mapW + x] = v;
        }
      }
    }

    // 외벽
    rect(0, 0, _mapW, 6, 30);
    rect(0, _mapH - 6, _mapW, _mapH, 30);
    rect(0, 0, 6, _mapH, 30);
    rect(_mapW - 6, 0, _mapW, _mapH, 30);
    // 주방 칸막이
    rect(300, 0, 306, 200, 30);
    // 테이블 8개
    for (var i = 0; i < 4; i++) {
      rect(40 + i * 60, 50, 80 + i * 60, 80, 120);
      rect(40 + i * 60, 210, 80 + i * 60, 240, 120);
    }
    return grayToBmp(g, _mapW, _mapH);
  }

  @override
  Future<RobotLocation> getLocation(String robotSn) async {
    await _delay(200);
    final t = DateTime.now().difference(_t0).inMilliseconds / 1000.0;
    final w = 2 * pi / 40; // 40초에 한 바퀴
    final x = -1.5 + 6.0 * cos(w * t);
    final y = 3.5 * sin(w * t);
    final heading = atan2(3.5 * cos(w * t), -6.0 * sin(w * t));
    return RobotLocation(
      building: '',
      floor: '1',
      x: double.parse(x.toStringAsFixed(2)),
      y: double.parse(y.toStringAsFixed(2)),
      angle: double.parse(heading.toStringAsFixed(2)),
      inElevator: false,
      rawCoordinate: '${x.toStringAsFixed(2)},${y.toStringAsFixed(2)},${heading.toStringAsFixed(2)}',
    );
  }

  /// 데모 맵 해상도 (설정과 무관하게 데모 맵은 0.05 m/px)
  static double get demoResolution => _res;

  @override
  void dispose() {}
}

class _MockTask {
  final String taskNo;
  final String robotId;
  final DateTime created;
  DateTime? canceledAt;

  _MockTask({required this.taskNo, required this.robotId, required this.created});

  TaskStatus statusAt(DateTime now) {
    final end = canceledAt ?? now;
    final s = end.difference(created).inMilliseconds / 1000.0;
    int status;
    double? remaining;
    int? queue;
    if (s < 3) {
      status = 1;
      queue = 1;
    } else if (s < 6) {
      status = 2;
      remaining = 24;
    } else if (s < 18) {
      status = 3;
      remaining = max(0.0, 24 - (s - 6) * 2);
    } else if (s < 21) {
      status = 6;
      remaining = 0;
    } else {
      status = 4;
      remaining = 0;
    }
    if (canceledAt != null) status = 5;
    String two(int v) => v.toString().padLeft(2, '0');
    return TaskStatus(
      taskNo: taskNo,
      status: status,
      errorCode: null,
      remark: '데모 작업',
      remainingDistance: remaining == null ? null : double.parse(remaining.toStringAsFixed(1)),
      robotId: robotId,
      waitQueuing: queue,
      lastUpdateTime: '${two(now.hour)}:${two(now.minute)}:${two(now.second)}',
    );
  }
}
