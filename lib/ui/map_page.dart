import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../api/mock_api.dart';
import '../api/models.dart';
import '../app_state.dart';
import '../util/map_image.dart';
import 'common.dart';

/// 맵 이미지 위에 로봇 실시간 위치를 3초 간격으로 표시한다.
/// 지원: Keenon 문서상 W/C 시리즈, 로봇 앱 v1.11.0 / v3.5.3 이상.
class MapPage extends StatefulWidget {
  const MapPage({
    super.key,
    required this.robotId,
    required this.robotName,
    required this.sceneCode,
  });

  final String robotId;
  final String robotName;
  final String sceneCode;

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  static const _interval = Duration(seconds: 3);

  Timer? _timer;
  ui.Image? _image;
  MapData? _map;
  RobotLocation? _loc;
  String? _locError;
  String? _mapError;
  bool _loadingMap = true;
  bool _polling = false;
  String _floor = '';
  late double _res;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final app = AppScope.read(context);
    _res = app.settings.demoMode ? MockRobotApi.demoResolution : app.settings.mapResolution;
    if (_res <= 0) _res = 0.05;
    Future.microtask(_init);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _image?.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    await _pollLocation(loadMapIfNeeded: false);
    if (!mounted) return;
    await _loadMap(_floor.isEmpty ? '1' : _floor);
    if (!mounted) return;
    _timer = Timer.periodic(_interval, (_) => _pollLocation());
  }

  Future<void> _pollLocation({bool loadMapIfNeeded = true}) async {
    if (_polling || !mounted) return;
    _polling = true;
    try {
      final loc = await AppScope.read(context).api.getLocation(widget.robotId);
      if (!mounted) return;
      final floorChanged = loc.floor.isNotEmpty && loc.floor != _floor;
      setState(() {
        _loc = loc;
        _locError = null;
        if (loc.floor.isNotEmpty) _floor = loc.floor;
      });
      if (floorChanged && loadMapIfNeeded) {
        await _loadMap(loc.floor);
      }
    } catch (e) {
      if (mounted) setState(() => _locError = '$e');
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
      final map = await AppScope.read(context).api.getMap(
            sceneCode: widget.sceneCode,
            floor: floor,
            building: (_loc?.building.isNotEmpty ?? false) ? _loc!.building : null,
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

  Offset? _toPixel(RobotLocation loc) {
    final map = _map;
    final img = _image;
    if (map == null || img == null || !loc.hasPosition) return null;
    final px = (loc.x! - map.originX) / _res;
    final py = img.height - (loc.y! - map.originY) / _res;
    return Offset(px, py);
  }

  @override
  Widget build(BuildContext context) {
    final loc = _loc;
    final img = _image;
    final pixel = loc == null ? null : _toPixel(loc);
    final outOfMap = pixel != null &&
        img != null &&
        (pixel.dx < 0 || pixel.dy < 0 || pixel.dx > img.width || pixel.dy > img.height);

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.robotName} 위치'),
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
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Wrap(
              spacing: 16,
              runSpacing: 4,
              children: [
                Text('층: ${_floor.isEmpty ? '-' : _floor}'),
                Text('좌표: ${loc == null || loc.rawCoordinate.isEmpty ? '-' : loc.rawCoordinate}'),
                if (loc?.inElevator == true) const Text('엘리베이터 탑승 중', style: TextStyle(fontWeight: FontWeight.w700)),
                if (_map?.isDynamic == true) const Text('동적 맵(좌표 계산 검증 필요)', style: TextStyle(fontSize: 12)),
                if (outOfMap) const Text('로봇 위치가 맵 범위를 벗어남 (해상도 설정 확인)', style: TextStyle(fontSize: 12)),
              ],
            ),
          ),
          if (_locError != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text('위치 조회 오류: $_locError', style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          Expanded(child: _buildMap(context, pixel)),
        ],
      ),
    );
  }

  Widget _buildMap(BuildContext context, Offset? pixel) {
    final img = _image;
    if (img == null) {
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
              painter: _MapPainter(image: img, robot: pixel, angle: _loc?.angle),
            ),
          ),
        ),
      ),
    );
  }
}

class _MapPainter extends CustomPainter {
  _MapPainter({required this.image, required this.robot, required this.angle});

  final ui.Image image;
  final Offset? robot;
  final double? angle;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawImage(image, Offset.zero, Paint()..filterQuality = FilterQuality.none);
    final p = robot;
    if (p == null) return;
    final r = math.max(4.0, image.width / 60);
    final fill = Paint()..color = const Color(0xFF1565C0);
    final halo = Paint()..color = const Color(0x551565C0);
    canvas.drawCircle(p, r * 2, halo);
    canvas.drawCircle(p, r, fill);
    canvas.drawCircle(
      p,
      r,
      Paint()
        ..color = const Color(0xFFFFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.0, r / 4),
    );
    final a = angle;
    if (a != null) {
      // 월드 좌표의 yaw(라디안, 반시계) → 이미지 좌표(y 아래 방향)
      final tip = p + Offset(math.cos(a), -math.sin(a)) * (r * 3);
      canvas.drawLine(
        p,
        tip,
        Paint()
          ..color = const Color(0xFF1565C0)
          ..strokeWidth = math.max(1.5, r / 2)
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _MapPainter old) =>
      old.image != image || old.robot != robot || old.angle != angle;
}
