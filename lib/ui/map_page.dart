import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../api/mock_api.dart';
import '../api/models.dart';
import '../app_state.dart';
import '../util/map_image.dart';
import 'common.dart';
import 'robot_avatar.dart';

/// 맵에 표시할 로봇
class MapRobot {
  final String id;
  final String name;
  final RobotKind kind;

  const MapRobot({required this.id, required this.name, required this.kind});
}

/// 맵 이미지 위에 로봇 위치를 실시간 표시한다.
/// - 실제 모드: 3초 간격 조회 (Keenon 권장)
/// - 데모 모드: 0.3초 간격으로 부드럽게 이동 표시 + 포인트·충전 위치·이동 궤적 표시
/// 지원: Keenon 문서상 W/C 시리즈, 로봇 앱 v1.11.0 / v3.5.3 이상.
class MapPage extends StatefulWidget {
  const MapPage({
    super.key,
    required this.robots,
    required this.sceneCode,
    this.title,
    this.focusRobotId,
  });

  final List<MapRobot> robots;
  final String sceneCode;
  final String? title;
  final String? focusRobotId;

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  static const _trailLength = 60;

  Timer? _timer;
  ui.Image? _image;
  MapData? _map;
  final Map<String, RobotLocation> _locs = {};
  final Map<String, List<Offset>> _trails = {}; // 월드 좌표(m)
  final Map<String, String> _locErrors = {};
  String? _mapError;
  bool _loadingMap = true;
  bool _polling = false;
  String _floor = '';
  late double _res;
  late Duration _interval;
  late bool _demo;
  List<DemoMarker> _markers = const [];
  String? _focus;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final app = AppScope.read(context);
    final api = app.api;
    _demo = api is MockRobotApi;
    _res = _demo ? MockRobotApi.demoResolution : app.settings.mapResolution;
    if (_res <= 0) _res = 0.05;
    _interval = _demo ? const Duration(milliseconds: 300) : const Duration(seconds: 3);
    if (api is MockRobotApi) _markers = api.markersFor(widget.sceneCode);
    _focus = widget.focusRobotId ?? (widget.robots.isNotEmpty ? widget.robots.first.id : null);
    Future.microtask(_init);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _image?.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    await _pollAll(loadMapIfNeeded: false);
    if (!mounted) return;
    await _loadMap(_floor.isEmpty ? '1' : _floor);
    if (!mounted) return;
    _timer = Timer.periodic(_interval, (_) => _pollAll());
  }

  Future<void> _pollAll({bool loadMapIfNeeded = true}) async {
    if (_polling || !mounted) return;
    _polling = true;
    final api = AppScope.read(context).api;
    String? newFloor;
    try {
      for (final r in widget.robots) {
        try {
          final loc = await api.getLocation(r.id);
          _locs[r.id] = loc;
          _locErrors.remove(r.id);
          if (loc.hasPosition) {
            final trail = _trails.putIfAbsent(r.id, () => []);
            final p = Offset(loc.x!, loc.y!);
            if (trail.isEmpty || (trail.last - p).distance > 0.02) {
              trail.add(p);
              if (trail.length > _trailLength) trail.removeAt(0);
            }
          }
          if ((r.id == _focus || newFloor == null) && loc.floor.isNotEmpty) newFloor = loc.floor;
        } catch (e) {
          _locErrors[r.id] = '$e';
        }
        if (!mounted) return;
      }
      final changed = newFloor != null && newFloor != _floor;
      setState(() {
        if (newFloor != null) _floor = newFloor;
      });
      if (changed && loadMapIfNeeded) await _loadMap(_floor);
    } finally {
      _polling = false;
    }
  }

  Future<void> _loadMap(String floor) async {
    if (!mounted) return;
    setState(() {
      _loadingMap = true;
      _mapError = null;
    });
    try {
      final focusLoc = _focus == null ? null : _locs[_focus];
      final map = await AppScope.read(context).api.getMap(
            sceneCode: widget.sceneCode,
            floor: floor,
            building: (focusLoc?.building.isNotEmpty ?? false) ? focusLoc!.building : null,
          );
      final raw = map.bytes;
      if (raw == null) throw Exception('맵 데이터(content)가 비어 있습니다');
      final display = toDisplayableImage(raw, width: map.width, height: map.height);
      if (display == null) {
        throw Exception('맵 이미지 형식을 해석하지 못했습니다 (${raw.length} bytes)');
      }
      final codec = await ui.instantiateImageCodec(display);
      final frame = await codec.getNextFrame();
      if (!mounted) {
        frame.image.dispose();
        return;
      }
      final old = _image;
      setState(() {
        _map = map;
        _image = frame.image;
        _loadingMap = false;
      });
      old?.dispose();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _mapError = '$e';
        _loadingMap = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title ?? '맵 · 실시간 위치'),
        actions: [
          IconButton(
            tooltip: '맵 다시 불러오기',
            icon: const Icon(Icons.refresh),
            onPressed: () => _loadMap(_floor.isEmpty ? '1' : _floor),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: cs.surfaceContainerHighest,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Wrap(
              spacing: 14,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('층: ${_floor.isEmpty ? '-' : _floor}'),
                Text('갱신: ${_demo ? '0.3초 (데모)' : '3초'}', style: const TextStyle(fontSize: 12)),
                if (_markers.isNotEmpty) ...[
                  _legend(_markerColor(DemoMarkerType.target), '목적지'),
                  _legend(_markerColor(DemoMarkerType.pickup), '픽업'),
                  _legend(_markerColor(DemoMarkerType.dock), '충전'),
                ],
                if (_map?.isDynamic == true) const Text('동적 맵(좌표 검증 필요)', style: TextStyle(fontSize: 12)),
              ],
            ),
          ),
          Expanded(child: _buildMap(context)),
          const Divider(height: 1),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 200),
            child: ListView(
              shrinkWrap: true,
              children: [for (final r in widget.robots) _robotRow(r)],
            ),
          ),
        ],
      ),
    );
  }

  Widget _legend(Color c, String label) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      );

  Widget _robotRow(MapRobot r) {
    final loc = _locs[r.id];
    final err = _locErrors[r.id];
    final selected = r.id == _focus;
    String sub;
    if (err != null) {
      sub = '위치 조회 오류: $err';
    } else if (loc == null) {
      sub = '위치 확인 중…';
    } else {
      sub = '좌표 ${loc.rawCoordinate.isEmpty ? '-' : loc.rawCoordinate}${loc.inElevator ? ' · 엘리베이터 탑승 중' : ''}';
    }
    return ListTile(
      dense: true,
      selected: selected,
      leading: RobotAvatar(kind: r.kind, size: 36),
      title: Text('${r.name} · ${robotKindLabel(r.kind)}'),
      subtitle: Text(sub, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(color: robotKindColor(r.kind), shape: BoxShape.circle),
      ),
      onTap: () => setState(() => _focus = r.id),
    );
  }

  Widget _buildMap(BuildContext context) {
    final img = _image;
    final map = _map;
    if (img == null || map == null) {
      if (_loadingMap) return const Center(child: CircularProgressIndicator());
      return ErrorView(
        message: _mapError ?? '맵을 불러오지 못했습니다',
        hint: '맵 API 지원: W/C 시리즈, 로봇 앱 v1.11.0(W) / v3.5.3(C) 이상',
        onRetry: () => _loadMap(_floor.isEmpty ? '1' : _floor),
      );
    }
    return InteractiveViewer(
      maxScale: 10,
      minScale: 0.5,
      child: Center(
        child: FittedBox(
          child: SizedBox(
            width: img.width.toDouble(),
            height: img.height.toDouble(),
            child: CustomPaint(
              painter: _MapPainter(
                image: img,
                originX: map.originX,
                originY: map.originY,
                res: _res,
                markers: _markers,
                robots: [
                  for (final r in widget.robots)
                    if (_locs[r.id]?.hasPosition ?? false)
                      _RobotDraw(
                        name: r.name,
                        color: robotKindColor(r.kind),
                        x: _locs[r.id]!.x!,
                        y: _locs[r.id]!.y!,
                        angle: _locs[r.id]!.angle,
                        trail: List.of(_trails[r.id] ?? const <Offset>[]),
                        selected: r.id == _focus,
                      ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Color _markerColor(DemoMarkerType t) {
  switch (t) {
    case DemoMarkerType.target:
      return const Color(0xFF2A9D8F);
    case DemoMarkerType.pickup:
      return const Color(0xFF7B4FD1);
    case DemoMarkerType.dock:
      return const Color(0xFF2E9E5B);
  }
}

class _RobotDraw {
  final String name;
  final Color color;
  final double x;
  final double y;
  final double? angle;
  final List<Offset> trail;
  final bool selected;

  _RobotDraw({
    required this.name,
    required this.color,
    required this.x,
    required this.y,
    required this.angle,
    required this.trail,
    required this.selected,
  });
}

class _MapPainter extends CustomPainter {
  _MapPainter({
    required this.image,
    required this.originX,
    required this.originY,
    required this.res,
    required this.markers,
    required this.robots,
  });

  final ui.Image image;
  final double originX;
  final double originY;
  final double res;
  final List<DemoMarker> markers;
  final List<_RobotDraw> robots;

  /// 월드 좌표(m) → 이미지 픽셀 (y축 반전)
  Offset _px(double x, double y) => Offset((x - originX) / res, image.height - (y - originY) / res);

  void _label(Canvas canvas, String text, Offset center, {Color color = const Color(0xFF1D2433), double size = 9}) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: TextStyle(fontSize: size, color: color, fontWeight: FontWeight.w600)),
      textDirection: TextDirection.ltr,
    )..layout();
    final box = Rect.fromCenter(center: center, width: tp.width + 6, height: tp.height + 2);
    canvas.drawRRect(
      RRect.fromRectAndRadius(box, const Radius.circular(3)),
      Paint()..color = const Color(0xDDFFFFFF),
    );
    tp.paint(canvas, Offset(box.left + 3, box.top + 1));
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawImage(image, Offset.zero, Paint()..filterQuality = FilterQuality.none);
    final unit = math.max(4.0, image.width / 45); // 로봇 아이콘 반지름

    // 포인트(데모)
    for (final m in markers) {
      final p = _px(m.x, m.y);
      final c = _markerColor(m.type);
      canvas.drawCircle(p, unit * 0.35, Paint()..color = c);
      canvas.drawCircle(
        p,
        unit * 0.35,
        Paint()
          ..color = const Color(0xFFFFFFFF)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
      if (m.type != DemoMarkerType.dock) _label(canvas, m.name, p + Offset(0, -unit * 0.95), color: c);
    }

    // 이동 궤적
    for (final r in robots) {
      if (r.trail.length < 2) continue;
      final path = Path()..moveTo(_px(r.trail.first.dx, r.trail.first.dy).dx, _px(r.trail.first.dx, r.trail.first.dy).dy);
      for (final t in r.trail.skip(1)) {
        final p = _px(t.dx, t.dy);
        path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = r.color.withAlpha(110)
          ..style = PaintingStyle.stroke
          ..strokeWidth = unit * 0.3
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }

    // 로봇
    for (final r in robots) {
      final p = _px(r.x, r.y);
      if (r.selected) canvas.drawCircle(p, unit * 1.8, Paint()..color = r.color.withAlpha(60));
      canvas.drawCircle(p, unit, Paint()..color = r.color);
      canvas.drawCircle(
        p,
        unit,
        Paint()
          ..color = const Color(0xFFFFFFFF)
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.0, unit / 5),
      );
      final a = r.angle;
      if (a != null) {
        // 월드 yaw(반시계) → 이미지 좌표(y 아래)
        final dir = Offset(math.cos(a), -math.sin(a));
        final perp = Offset(-dir.dy, dir.dx);
        final tip = p + dir * (unit * 0.75);
        final b1 = p - dir * (unit * 0.35) + perp * (unit * 0.45);
        final b2 = p - dir * (unit * 0.35) - perp * (unit * 0.45);
        canvas.drawPath(
          Path()
            ..moveTo(tip.dx, tip.dy)
            ..lineTo(b1.dx, b1.dy)
            ..lineTo(b2.dx, b2.dy)
            ..close(),
          Paint()..color = const Color(0xFFFFFFFF),
        );
      }
      _label(canvas, r.name, p + Offset(0, unit * 1.9), color: r.color, size: 9);
    }
  }

  @override
  bool shouldRepaint(covariant _MapPainter old) => true;
}
