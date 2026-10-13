import 'package:flutter/material.dart';

import '../api/models.dart';

/// 로봇 그림.
/// assets/robots/serving.png, assets/robots/hotel.png 가 있으면 그 이미지를 쓰고,
/// 없으면 앱에 내장된 일러스트(직접 그린 범용 디자인)를 그린다.
class RobotAvatar extends StatelessWidget {
  const RobotAvatar({super.key, required this.kind, this.size = 48, this.online = true});

  final RobotKind kind;
  final double size;
  final bool online;

  static String assetPath(RobotKind kind) =>
      kind == RobotKind.hotel ? 'assets/robots/hotel.png' : 'assets/robots/serving.png';

  @override
  Widget build(BuildContext context) {
    final child = Image.asset(
      assetPath(kind),
      width: size,
      height: size,
      fit: BoxFit.contain,
      errorBuilder: (context, error, stack) => CustomPaint(
        size: Size(size, size),
        painter: RobotIllustrationPainter(kind),
      ),
    );
    return SizedBox(
      width: size,
      height: size,
      child: online ? child : Opacity(opacity: 0.4, child: child),
    );
  }
}

const kServingColor = Color(0xFFE07A2E);
const kHotelColor = Color(0xFF2E6BD6);

Color robotKindColor(RobotKind kind) => kind == RobotKind.hotel ? kHotelColor : kServingColor;

String robotKindLabel(RobotKind kind) => kind == RobotKind.hotel ? '호텔 배송' : '서빙';

/// 범용 서빙 로봇(트레이 3단) / 호텔 배송 로봇(수납함) 일러스트
class RobotIllustrationPainter extends CustomPainter {
  RobotIllustrationPainter(this.kind);

  final RobotKind kind;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    canvas.save();
    canvas.translate((size.width - s) / 2, (size.height - s) / 2);
    if (kind == RobotKind.hotel) {
      _hotel(canvas, s);
    } else {
      _serving(canvas, s);
    }
    canvas.restore();
  }

  RRect _rr(double s, double l, double t, double r, double b, double radius) =>
      RRect.fromLTRBR(l * s, t * s, r * s, b * s, Radius.circular(radius * s));

  void _face(Canvas canvas, double s, double l, double t, double r, double b) {
    canvas.drawRRect(_rr(s, l, t, r, b, 0.05), Paint()..color = const Color(0xFF1D2433));
    final eye = Paint()..color = const Color(0xFF5CE1E6);
    final cy = (t + b) / 2 * s;
    final w = (r - l) * s;
    canvas.drawCircle(Offset(l * s + w * 0.32, cy), s * 0.03, eye);
    canvas.drawCircle(Offset(l * s + w * 0.68, cy), s * 0.03, eye);
    final smile = Paint()
      ..color = const Color(0xFF5CE1E6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.012
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCenter(center: Offset(l * s + w / 2, cy + s * 0.025), width: w * 0.28, height: s * 0.05),
      0.3,
      2.5,
      false,
      smile,
    );
  }

  void _serving(Canvas canvas, double s) {
    final body = Paint()..color = const Color(0xFFF2F4F7);
    final edge = Paint()
      ..color = const Color(0xFFB8C0CC)
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.012;
    final tray = Paint()..color = kServingColor;
    final dark = Paint()..color = const Color(0xFF39404D);

    // 바닥 주행부
    canvas.drawRRect(_rr(s, 0.24, 0.84, 0.76, 0.96, 0.05), dark);
    // 기둥
    canvas.drawRRect(_rr(s, 0.43, 0.28, 0.57, 0.86, 0.03), body);
    canvas.drawRRect(_rr(s, 0.43, 0.28, 0.57, 0.86, 0.03), edge);
    // 트레이 3단
    for (final y in [0.40, 0.56, 0.72]) {
      canvas.drawRRect(_rr(s, 0.2, y, 0.8, y + 0.045, 0.02), tray);
    }
    // 머리(화면)
    canvas.drawRRect(_rr(s, 0.3, 0.04, 0.7, 0.3, 0.07), body);
    canvas.drawRRect(_rr(s, 0.3, 0.04, 0.7, 0.3, 0.07), edge);
    _face(canvas, s, 0.34, 0.08, 0.66, 0.26);
  }

  void _hotel(Canvas canvas, double s) {
    final body = Paint()..color = const Color(0xFFF2F4F7);
    final edge = Paint()
      ..color = const Color(0xFFB8C0CC)
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.012;
    final accent = Paint()..color = kHotelColor;
    final dark = Paint()..color = const Color(0xFF39404D);

    // 바퀴부
    canvas.drawRRect(_rr(s, 0.24, 0.88, 0.76, 0.97, 0.04), dark);
    // 몸체(수납함)
    canvas.drawRRect(_rr(s, 0.22, 0.26, 0.78, 0.9, 0.08), body);
    canvas.drawRRect(_rr(s, 0.22, 0.26, 0.78, 0.9, 0.08), edge);
    // 수납함 문
    canvas.drawRRect(_rr(s, 0.28, 0.42, 0.72, 0.82, 0.04), Paint()..color = const Color(0xFFE3E8EF));
    canvas.drawRRect(_rr(s, 0.28, 0.42, 0.72, 0.82, 0.04), edge);
    canvas.drawRRect(_rr(s, 0.62, 0.58, 0.66, 0.68, 0.02), dark);
    // 상단 라인
    canvas.drawRRect(_rr(s, 0.22, 0.34, 0.78, 0.37, 0.0), accent);
    // 머리(화면)
    canvas.drawRRect(_rr(s, 0.3, 0.03, 0.7, 0.25, 0.06), body);
    canvas.drawRRect(_rr(s, 0.3, 0.03, 0.7, 0.25, 0.06), edge);
    _face(canvas, s, 0.34, 0.06, 0.66, 0.22);
  }

  @override
  bool shouldRepaint(covariant RobotIllustrationPainter oldDelegate) => oldDelegate.kind != kind;
}
