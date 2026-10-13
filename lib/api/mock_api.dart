import 'dart:math';
import 'dart:typed_data';

import '../util/map_image.dart';
import 'keenon_api.dart';
import 'models.dart';

// ===========================================================================
// 데모 모드용 가상 API + 로봇 이동 시뮬레이터
//
// 월드 좌표(미터)는 실제 Keenon 위치 API 와 같은 형식(x, y, angle[rad])으로 돌려준다.
// 맵 이미지: 400x300 px, 해상도 0.05 m/px, origin(-10, -7.5) → 20m x 15m 공간
// ===========================================================================

const _mapW = 400;
const _mapH = 300;
const _res = 0.05;
const _originX = -10.0;
const _originY = -7.5;
const _speed = 0.9; // m/s

/// 맵 위에 표시할 포인트(테이블·객실·주방·충전 위치)
class DemoMarker {
  final String name;
  final double x;
  final double y;
  final DemoMarkerType type;

  const DemoMarker(this.name, this.x, this.y, this.type);
}

enum DemoMarkerType { target, pickup, dock }

class _Pt {
  final double x;
  final double y;
  const _Pt(this.x, this.y);
  double dist(_Pt o) => sqrt((x - o.x) * (x - o.x) + (y - o.y) * (y - o.y));
}

class _SceneCfg {
  final String code;
  final String name;
  final double aisleY; // 모든 이동이 지나가는 중앙 통로의 y 좌표
  final List<_PointDef> points;
  final Uint8List Function() buildMap;

  const _SceneCfg({
    required this.code,
    required this.name,
    required this.aisleY,
    required this.points,
    required this.buildMap,
  });
}

class _PointDef {
  final TargetPoint point;
  final _Pt pos;
  final DemoMarkerType type;
  const _PointDef(this.point, this.pos, this.type);
}

class _SimRobot {
  final Robot info;
  final String sceneCode;
  final _Pt dock;
  double x;
  double y;
  double heading;
  List<_Pt> path = [];
  String? taskNo;
  DateTime last = DateTime.now();

  _SimRobot(this.info, this.sceneCode, this.dock)
      : x = dock.x,
        y = dock.y,
        heading = pi / 2;

  bool get busy => taskNo != null;

  double remaining() {
    var d = 0.0;
    var cur = _Pt(x, y);
    for (final p in path) {
      d += cur.dist(p);
      cur = p;
    }
    return d;
  }

  /// 경과 시간만큼 경로를 따라 전진
  void step(DateTime now) {
    final dt = now.difference(last).inMilliseconds / 1000.0;
    last = now;
    var move = _speed * max(0.0, dt);
    while (move > 0 && path.isNotEmpty) {
      final t = path.first;
      final dx = t.x - x;
      final dy = t.y - y;
      final d = sqrt(dx * dx + dy * dy);
      if (d < 1e-6) {
        path.removeAt(0);
        continue;
      }
      heading = atan2(dy, dx);
      if (d <= move) {
        x = t.x;
        y = t.y;
        move -= d;
        path.removeAt(0);
      } else {
        x += dx / d * move;
        y += dy / d * move;
        move = 0;
      }
    }
  }
}

class _MockTask {
  final String taskNo;
  final String robotId;
  final DateTime created;
  final _Pt target;
  final bool isBack; // 원점 복귀 작업
  final double startDelay;
  bool started = false;
  bool done = false;
  DateTime? arrivedAt;
  DateTime? canceledAt;
  int status = 1;

  _MockTask({
    required this.taskNo,
    required this.robotId,
    required this.created,
    required this.target,
    required this.isBack,
  }) : startDelay = isBack ? 1.0 : 4.0;
}

/// 실제 로봇·계정 없이 화면 흐름을 확인하기 위한 데모용 API
class MockRobotApi implements RobotApi {
  MockRobotApi() {
    _init();
  }

  static double get demoResolution => _res;

  final Map<String, _SceneCfg> _scenes = {};
  final Map<String, _SimRobot> _sims = {};
  final Map<String, _MockTask> _tasks = {};
  final Map<String, Uint8List> _mapCache = {};
  int _seq = 0;

  Future<void> _delay([int ms = 250]) => Future.delayed(Duration(milliseconds: ms));

  final _stores = [
    Store(storeId: 'DEMO-S001', storeName: '데모 레스토랑 1호점', brandName: '데모 외식', address: '서울특별시 강남구 (데모)'),
    Store(storeId: 'DEMO-S002', storeName: '데모 호텔', brandName: '데모 호텔', address: '부산광역시 해운대구 (데모)'),
  ];

  static const _storeScene = {'DEMO-S001': 'DEMO-HALL', 'DEMO-S002': 'DEMO-HOTEL'};

  // ------------------------------------------------------------------ 초기화

  void _init() {
    // ---- 레스토랑: 상단·하단 테이블 4개씩, 오른쪽 위 주방, 오른쪽 아래 충전 위치
    final hallPoints = <_PointDef>[
      for (var i = 0; i < 4; i++)
        _PointDef(
          TargetPoint(pointName: '${i + 1}번 테이블', area: 'A 구역(창가)', uuid: 'demo-t-${i + 1}', pointId: '${i + 1}'),
          _Pt(-7.0 + 3 * i, 2.6),
          DemoMarkerType.target,
        ),
      for (var i = 0; i < 4; i++)
        _PointDef(
          TargetPoint(pointName: '${i + 5}번 테이블', area: 'B 구역(안쪽)', uuid: 'demo-t-${i + 5}', pointId: '${i + 5}'),
          _Pt(-7.0 + 3 * i, -2.6),
          DemoMarkerType.target,
        ),
      _PointDef(
        TargetPoint(pointName: '주방 픽업대', area: '주방', uuid: 'demo-kitchen', pointId: '50'),
        const _Pt(7.5, 4.4),
        DemoMarkerType.pickup,
      ),
    ];
    _scenes['DEMO-HALL'] = _SceneCfg(
      code: 'DEMO-HALL',
      name: '홀 기본 씬',
      aisleY: -1.0,
      points: hallPoints,
      buildMap: _buildHallMap,
    );

    // ---- 호텔: 가운데 복도, 위·아래 객실 3개씩, 오른쪽 로비(프런트·충전)
    const roomCx = [-7.25, -1.875, 3.375];
    final hotelPoints = <_PointDef>[
      for (var i = 0; i < 3; i++)
        _PointDef(
          TargetPoint(pointName: '${101 + i}호', area: '1층 북쪽', uuid: 'demo-h-${101 + i}', pointId: '${101 + i}'),
          _Pt(roomCx[i], 1.3),
          DemoMarkerType.target,
        ),
      for (var i = 0; i < 3; i++)
        _PointDef(
          TargetPoint(pointName: '${104 + i}호', area: '1층 남쪽', uuid: 'demo-h-${104 + i}', pointId: '${104 + i}'),
          _Pt(roomCx[i], -1.3),
          DemoMarkerType.target,
        ),
      _PointDef(
        TargetPoint(pointName: '프런트', area: '로비', uuid: 'demo-h-front', pointId: '99'),
        const _Pt(8.8, 3.6),
        DemoMarkerType.pickup,
      ),
    ];
    _scenes['DEMO-HOTEL'] = _SceneCfg(
      code: 'DEMO-HOTEL',
      name: '호텔 1층',
      aisleY: 0.0,
      points: hotelPoints,
      buildMap: _buildHotelMap,
    );

    // ---- 로봇
    void add(Robot r, String scene, _Pt dock) => _sims[r.robotId] = _SimRobot(r, scene, dock);
    add(Robot(robotId: 'AA:BB:CC:00:00:01', robotName: '서빙 1호', online: true, power: 82, robotModel: 'T8', appVersion: 'v2.3.0', onlineType: 2),
        'DEMO-HALL', const _Pt(6.5, -5.8));
    add(Robot(robotId: 'AA:BB:CC:00:00:02', robotName: '서빙 2호', online: true, power: 64, robotModel: 'T8', appVersion: 'v2.3.0', onlineType: 4),
        'DEMO-HALL', const _Pt(7.5, -5.8));
    add(Robot(robotId: 'AA:BB:CC:00:00:03', robotName: '서빙 3호', online: false, power: 12, robotModel: 'T9', appVersion: 'v2.1.5', onlineType: 2),
        'DEMO-HALL', const _Pt(8.5, -5.8));
    add(Robot(robotId: 'AA:BB:CC:00:01:01', robotName: '호텔 배송 1호', online: true, power: 71, robotModel: 'W3', appVersion: 'v1.12.0', onlineType: 2),
        'DEMO-HOTEL', const _Pt(8.0, -5.5));
    add(Robot(robotId: 'AA:BB:CC:00:01:02', robotName: '호텔 배송 2호', online: true, power: 55, robotModel: 'W3', appVersion: 'v1.12.0', onlineType: 2),
        'DEMO-HOTEL', const _Pt(9.0, -5.5));
  }

  List<_SimRobot> _robotsOf(String storeId) {
    final scene = _storeScene[storeId];
    return _sims.values.where((r) => r.sceneCode == scene).toList();
  }

  /// 맵 화면에서 포인트·충전 위치를 그리기 위한 데모 전용 정보
  List<DemoMarker> markersFor(String sceneCode) {
    final cfg = _scenes[sceneCode];
    if (cfg == null) return const [];
    return [
      for (final p in cfg.points) DemoMarker(p.point.displayName, p.pos.x, p.pos.y, p.type),
      for (final r in _sims.values.where((r) => r.sceneCode == sceneCode))
        DemoMarker('충전', r.dock.x, r.dock.y, DemoMarkerType.dock),
    ];
  }

  // ------------------------------------------------------------------ 시뮬레이션

  void _tick() {
    final now = DateTime.now();
    for (final r in _sims.values) {
      r.step(now);
    }
    for (final t in _tasks.values) {
      _advance(t, now);
    }
  }

  /// A → (A.x, 통로) → (B.x, 통로) → B 로 이동 (맵이 이 경로에서 막히지 않도록 설계됨)
  List<_Pt> _plan(_SimRobot r, _Pt to) {
    final aisle = _scenes[r.sceneCode]?.aisleY ?? 0;
    final pts = <_Pt>[];
    if ((r.y - aisle).abs() > 0.05) pts.add(_Pt(r.x, aisle));
    if ((r.x - to.x).abs() > 0.05) pts.add(_Pt(to.x, aisle));
    pts.add(to);
    return pts;
  }

  void _goTo(_SimRobot r, _Pt to) => r.path = _plan(r, to);

  void _advance(_MockTask t, DateTime now) {
    if (t.done) return;
    final r = _sims[t.robotId];
    if (r == null) {
      t.status = 0;
      t.done = true;
      return;
    }
    if (t.canceledAt != null) {
      t.status = 5;
      t.done = true;
      r.taskNo = null;
      _goTo(r, r.dock);
      return;
    }
    final age = now.difference(t.created).inMilliseconds / 1000.0;
    if (!t.started) {
      if (age >= t.startDelay) {
        t.started = true;
        t.status = 3;
        _goTo(r, t.target);
      } else {
        t.status = age < t.startDelay / 2 ? 1 : 2;
      }
      return;
    }
    if (t.arrivedAt == null) {
      if (r.path.isEmpty) {
        t.arrivedAt = now;
        if (t.isBack) {
          t.status = 4;
          t.done = true;
          r.taskNo = null;
        } else {
          t.status = 6; // 목적지 도착: 음식/물품 수령 대기
        }
      } else {
        t.status = 3;
      }
      return;
    }
    // 도착 후 8초 대기 → 완료 처리하고 충전 위치로 복귀
    if (now.difference(t.arrivedAt!).inMilliseconds > 8000) {
      t.status = 4;
      t.done = true;
      r.taskNo = null;
      _goTo(r, r.dock);
    }
  }

  TaskStatus _statusOf(_MockTask t) {
    final r = _sims[t.robotId];
    double? remaining;
    if (r != null) {
      if (t.arrivedAt != null || t.done) {
        remaining = 0;
      } else if (t.started) {
        remaining = r.remaining();
      } else {
        final probe = _plan(r, t.target);
        var d = 0.0;
        var cur = _Pt(r.x, r.y);
        for (final p in probe) {
          d += cur.dist(p);
          cur = p;
        }
        remaining = d;
      }
    }
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return TaskStatus(
      taskNo: t.taskNo,
      status: t.status,
      errorCode: null,
      remark: t.isBack ? '원점 복귀 (데모)' : '호출 (데모)',
      remainingDistance: remaining == null ? null : double.parse(remaining.toStringAsFixed(1)),
      robotId: t.robotId,
      waitQueuing: t.started ? 0 : 1,
      lastUpdateTime: '${two(now.hour)}:${two(now.minute)}:${two(now.second)}',
    );
  }

  String _createTask(_SimRobot r, _Pt target, {required bool isBack}) {
    _seq++;
    final no = 'DEMO${DateTime.now().millisecondsSinceEpoch}$_seq';
    _tasks[no] = _MockTask(taskNo: no, robotId: r.info.robotId, created: DateTime.now(), target: target, isBack: isBack);
    r.taskNo = no;
    return no;
  }

  // ------------------------------------------------------------------ RobotApi

  @override
  Future<List<Store>> getStores() async {
    await _delay();
    return _stores;
  }

  @override
  Future<List<Robot>> getRobots(String storeId) async {
    await _delay();
    return _robotsOf(storeId).map((r) => r.info).toList();
  }

  @override
  Future<RobotStatus?> getRobotStatus(String robotId) async {
    await _delay(150);
    _tick();
    final r = _sims[robotId];
    if (r == null) return null;
    final cfg = _scenes[r.sceneCode];
    final atDock = r.dock.dist(_Pt(r.x, r.y)) < 0.1 && !r.busy;
    return RobotStatus(
      robotId: r.info.robotId,
      robotName: r.info.robotName,
      online: r.info.online,
      canBeCalled: r.info.online && (r.info.power ?? 0) > 20 && !r.busy,
      charging: atDock && (r.info.power ?? 0) < 100,
      power: r.info.power,
      sceneCode: r.sceneCode,
      sceneName: cfg?.name ?? '',
    );
  }

  @override
  Future<List<Scene>> getScenes(String storeId) async {
    await _delay();
    final code = _storeScene[storeId];
    final cfg = code == null ? null : _scenes[code];
    return cfg == null ? const [] : [Scene(sceneCode: cfg.code, sceneName: cfg.name)];
  }

  @override
  Future<List<TargetPoint>> getPoints(String sceneCode) async {
    await _delay();
    return (_scenes[sceneCode]?.points ?? const <_PointDef>[]).map((p) => p.point).toList();
  }

  _Pt? _posOfPoint(TargetPoint p) {
    for (final cfg in _scenes.values) {
      for (final d in cfg.points) {
        if (d.point.uuid == p.uuid) return d.pos;
      }
    }
    return null;
  }

  @override
  Future<CallResult> callRobot({
    required String storeId,
    required TargetPoint point,
    String? sceneCode,
    String? robotId,
    String? robotType,
  }) async {
    await _delay(400);
    _tick();
    final target = _posOfPoint(point);
    if (target == null) throw KeenonApiException('목적지 포인트를 찾을 수 없습니다 (데모)', code: 610601);

    _SimRobot? robot;
    if (robotId != null && robotId.isNotEmpty) {
      robot = _sims[robotId];
      if (robot == null) throw KeenonApiException('로봇을 찾을 수 없습니다 (데모)', code: 610601);
      if (!robot.info.online) throw KeenonApiException('로봇이 오프라인입니다', code: 615001);
      if (robot.busy) throw KeenonApiException('로봇이 대기 상태가 아닙니다 (다른 작업 수행 중)', code: 5001);
      if ((robot.info.power ?? 0) <= 20) throw KeenonApiException('배터리가 부족해 호출할 수 없습니다 (데모)', code: 5001);
    } else {
      // 가용 로봇 중 목적지에 가장 가까운 로봇 자동 배정
      final cands = _robotsOf(storeId)
          .where((r) => r.info.online && !r.busy && (r.info.power ?? 0) > 20)
          .toList()
        ..sort((a, b) => _Pt(a.x, a.y).dist(target).compareTo(_Pt(b.x, b.y).dist(target)));
      if (cands.isEmpty) throw KeenonApiException('사용 가능한 로봇이 없습니다 (데모)', code: 610500);
      robot = cands.first;
    }
    final waiting = _tasks.values.where((t) => !t.done && !t.started).length;
    return CallResult(taskNo: _createTask(robot, target, isBack: false), waitQueuing: waiting + 1);
  }

  @override
  Future<CallResult> returnToOrigin({required String storeId, String? robotId}) async {
    await _delay(400);
    _tick();
    final r = (robotId != null && robotId.isNotEmpty) ? _sims[robotId] : _robotsOf(storeId).firstOrNull;
    if (r == null) throw KeenonApiException('로봇을 찾을 수 없습니다 (데모)', code: 610601);
    if (!r.info.online) throw KeenonApiException('로봇이 오프라인입니다', code: 615001);
    // 수행 중인 작업이 있으면 취소하고 복귀
    final current = r.taskNo == null ? null : _tasks[r.taskNo!];
    if (current != null && !current.done) {
      current.canceledAt = DateTime.now();
      _advance(current, DateTime.now());
    }
    return CallResult(taskNo: _createTask(r, r.dock, isBack: true), waitQueuing: 0);
  }

  @override
  Future<TaskStatus> getTaskStatus(String taskNo) async {
    await _delay(120);
    _tick();
    final t = _tasks[taskNo];
    if (t == null) throw KeenonApiException('작업을 찾을 수 없습니다 (데모)', code: 610601);
    return _statusOf(t);
  }

  @override
  Future<void> cancelTask(String taskNo) async {
    await _delay(250);
    _tick();
    final t = _tasks[taskNo];
    if (t == null) throw KeenonApiException('작업을 찾을 수 없습니다 (데모)', code: 610601);
    if (t.done) throw KeenonApiException('이미 종료된 작업입니다', code: 5004);
    t.canceledAt ??= DateTime.now();
    _advance(t, DateTime.now());
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
    final robots = _robotsOf(storeId);
    final rnd = Random(storeId.hashCode ^ (hotel ? 1 : 0));
    final all = List.generate(total, (i) {
      final start = DateTime.now().subtract(Duration(minutes: 25 * i + 5));
      final end = start.add(Duration(minutes: 2 + rnd.nextInt(6)));
      return TaskRecord(
        robotId: robots.isEmpty ? '-' : robots[i % robots.length].info.robotId,
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
    await _delay(300);
    final cfg = _scenes[sceneCode] ?? _scenes['DEMO-HALL']!;
    final bytes = _mapCache.putIfAbsent(cfg.code, cfg.buildMap);
    return MapData(
      bytes: bytes,
      isDynamic: false,
      width: _mapW.toDouble(),
      height: _mapH.toDouble(),
      originX: _originX,
      originY: _originY,
    );
  }

  @override
  Future<RobotLocation> getLocation(String robotSn) async {
    await _delay(20);
    _tick();
    final r = _sims[robotSn];
    if (r == null) throw KeenonApiException('로봇을 찾을 수 없습니다 (데모)', code: 610601);
    final x = r.x.toStringAsFixed(2);
    final y = r.y.toStringAsFixed(2);
    final a = r.heading.toStringAsFixed(2);
    return RobotLocation(
      building: '',
      floor: '1',
      x: double.parse(x),
      y: double.parse(y),
      angle: double.parse(a),
      inElevator: false,
      rawCoordinate: '$x,$y,$a',
    );
  }

  @override
  void dispose() {}

  // ------------------------------------------------------------------ 맵 이미지 생성

  static int _px(double x) => ((x - _originX) / _res).round();
  static int _py(double y) => ((_originY + _mapH * _res - y) / _res).round();

  static Uint8List _canvas() => Uint8List(_mapW * _mapH)..fillRange(0, _mapW * _mapH, 246);

  static void _rect(Uint8List g, int x0, int y0, int x1, int y1, int v) {
    for (var y = max(0, y0); y < min(_mapH, y1); y++) {
      for (var x = max(0, x0); x < min(_mapW, x1); x++) {
        g[y * _mapW + x] = v;
      }
    }
  }

  static void _outerWalls(Uint8List g) {
    _rect(g, 0, 0, _mapW, 6, 40);
    _rect(g, 0, _mapH - 6, _mapW, _mapH, 40);
    _rect(g, 0, 0, 6, _mapH, 40);
    _rect(g, _mapW - 6, 0, _mapW, _mapH, 40);
  }

  static Uint8List _buildHallMap() {
    final g = _canvas();
    _outerWalls(g);
    // 주방 칸막이 (x=5.0m, y 7.5~0m)
    _rect(g, _px(5.0), 0, _px(5.0) + 6, _py(0.0), 40);
    // 주방 조리대
    _rect(g, _px(6.0), _py(6.6), _px(9.6), _py(5.4), 150);
    // 테이블 8개 (2m x 2m) + 의자
    for (var i = 0; i < 4; i++) {
      final cx = -7.0 + 3 * i;
      _rect(g, _px(cx - 1.0), _py(5.5), _px(cx + 1.0), _py(3.5), 160);
      _rect(g, _px(cx - 1.0), _py(-3.5), _px(cx + 1.0), _py(-5.5), 160);
      for (final dx in [-0.6, 0.6]) {
        _rect(g, _px(cx + dx - 0.2), _py(6.1), _px(cx + dx + 0.2), _py(5.7), 200);
        _rect(g, _px(cx + dx - 0.2), _py(-5.7), _px(cx + dx + 0.2), _py(-6.1), 200);
      }
    }
    // 충전 구역
    _rect(g, _px(6.0), _py(-5.3), _px(9.0), _py(-6.3), 215);
    return grayToBmp(g, _mapW, _mapH);
  }

  static Uint8List _buildHotelMap() {
    final g = _canvas();
    _outerWalls(g);
    const doorHalf = 0.75;
    const roomEdges = [-10.0, -4.5, 0.75, 6.0];
    // 객실 벽 (복도 경계 y=±2.0) - 문 자리는 비움
    for (final wallY in [2.0, -2.0]) {
      final y0 = wallY > 0 ? _py(wallY) - 4 : _py(wallY);
      for (var i = 0; i < 3; i++) {
        final cx = (roomEdges[i] + roomEdges[i + 1]) / 2;
        _rect(g, _px(roomEdges[i]), y0, _px(cx - doorHalf), y0 + 4, 40);
        _rect(g, _px(cx + doorHalf), y0, _px(roomEdges[i + 1]), y0 + 4, 40);
      }
    }
    // 객실 사이 벽
    for (final x in [-4.5, 0.75, 6.0]) {
      _rect(g, _px(x) - 2, 0, _px(x) + 2, _py(2.0), 40);
      _rect(g, _px(x) - 2, _py(-2.0), _px(x) + 2, _mapH, 40);
    }
    // 객실 침대
    for (var i = 0; i < 3; i++) {
      final cx = (roomEdges[i] + roomEdges[i + 1]) / 2;
      _rect(g, _px(cx - 1.2), _py(6.8), _px(cx + 1.2), _py(4.2), 175);
      _rect(g, _px(cx - 1.2), _py(-4.2), _px(cx + 1.2), _py(-6.8), 175);
    }
    // 로비 프런트 데스크 + 충전 구역
    _rect(g, _px(8.0), _py(6.0), _px(9.6), _py(4.5), 150);
    _rect(g, _px(7.4), _py(-5.0), _px(9.6), _py(-6.0), 215);
    return grayToBmp(g, _mapW, _mapH);
  }
}
