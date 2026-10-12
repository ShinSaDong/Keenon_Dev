import 'dart:typed_data';

/// Keenon 맵 content(byte[])를 Flutter 가 디코딩할 수 있는 이미지 바이트로 변환한다.
/// - PNG/JPEG/GIF/BMP/WEBP 이면 그대로 사용
/// - PGM(P5, ROS 맵 형식)이면 BMP 로 변환
/// - 헤더 없는 원시 그레이스케일/점유격자(width*height)면 BMP 로 변환
/// 변환할 수 없으면 null.
Uint8List? toDisplayableImage(Uint8List bytes, {double? width, double? height}) {
  if (bytes.isEmpty) return null;
  if (_isKnownImage(bytes)) return bytes;

  if (bytes.length > 2 && bytes[0] == 0x50 && bytes[1] == 0x35) {
    final pgm = _parsePgm(bytes);
    if (pgm != null) return grayToBmp(pgm.$1, pgm.$2, pgm.$3);
  }

  final w = width?.round();
  final h = height?.round();
  if (w != null && h != null && w > 0 && h > 0 && bytes.length >= w * h) {
    final raw = Uint8List.sublistView(bytes, 0, w * h);
    return grayToBmp(_normalizeOccupancy(raw), w, h);
  }
  return null;
}

bool _isKnownImage(Uint8List b) {
  if (b.length < 12) return false;
  final png = b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47;
  final jpg = b[0] == 0xFF && b[1] == 0xD8;
  final gif = b[0] == 0x47 && b[1] == 0x49 && b[2] == 0x46;
  final bmp = b[0] == 0x42 && b[1] == 0x4D;
  final webp = b[0] == 0x52 && b[1] == 0x49 && b[2] == 0x46 && b[3] == 0x46 &&
      b[8] == 0x57 && b[9] == 0x45 && b[10] == 0x42 && b[11] == 0x50;
  return png || jpg || gif || bmp || webp;
}

bool _isWs(int c) => c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D;

(Uint8List, int, int)? _parsePgm(Uint8List b) {
  var i = 2;
  final vals = <int>[];
  while (vals.length < 3 && i < b.length) {
    final c = b[i];
    if (c == 0x23) {
      while (i < b.length && b[i] != 0x0A) {
        i++;
      }
      continue;
    }
    if (_isWs(c)) {
      i++;
      continue;
    }
    var n = 0;
    var digits = 0;
    while (i < b.length && b[i] >= 0x30 && b[i] <= 0x39) {
      n = n * 10 + (b[i] - 0x30);
      i++;
      digits++;
    }
    if (digits == 0) return null;
    vals.add(n);
  }
  if (vals.length < 3) return null;
  i++; // maxval 뒤의 공백 1바이트
  final w = vals[0];
  final h = vals[1];
  final maxv = vals[2];
  if (w <= 0 || h <= 0 || maxv <= 0) return null;
  final bpp = maxv > 255 ? 2 : 1;
  if (b.length < i + w * h * bpp) return null;
  final out = Uint8List(w * h);
  for (var p = 0; p < w * h; p++) {
    final v = bpp == 1 ? b[i + p] : ((b[i + 2 * p] << 8) | b[i + 2 * p + 1]);
    out[p] = maxv == 255 ? v : ((v * 255) ~/ maxv).clamp(0, 255).toInt();
  }
  return (out, w, h);
}

/// 점유격자(0=빈 공간, 100=장애물, 255/-1=미탐색)로 보이면 사람이 보기 좋은 회색조로 바꾼다.
Uint8List _normalizeOccupancy(Uint8List raw) {
  var maxKnown = 0;
  for (final v in raw) {
    if (v != 255 && v > maxKnown) maxKnown = v;
  }
  if (maxKnown > 100) return raw; // 이미 회색조 이미지
  final out = Uint8List(raw.length);
  for (var i = 0; i < raw.length; i++) {
    final v = raw[i];
    if (v == 255) {
      out[i] = 205;
    } else {
      out[i] = (254 - (v * 254 ~/ 100)).clamp(0, 254).toInt();
    }
  }
  return out;
}

/// 회색조 픽셀(위→아래 행 순서)을 24비트 BMP 로 인코딩
Uint8List grayToBmp(Uint8List gray, int w, int h) {
  final rowSize = ((w * 3 + 3) ~/ 4) * 4;
  final dataSize = rowSize * h;
  final fileSize = 54 + dataSize;
  final b = ByteData(fileSize);
  b.setUint8(0, 0x42);
  b.setUint8(1, 0x4D);
  b.setUint32(2, fileSize, Endian.little);
  b.setUint32(10, 54, Endian.little);
  b.setUint32(14, 40, Endian.little);
  b.setInt32(18, w, Endian.little);
  b.setInt32(22, h, Endian.little); // 양수 = 아래→위 저장
  b.setUint16(26, 1, Endian.little);
  b.setUint16(28, 24, Endian.little);
  b.setUint32(34, dataSize, Endian.little);
  for (var y = 0; y < h; y++) {
    final srcRow = h - 1 - y;
    var off = 54 + y * rowSize;
    for (var x = 0; x < w; x++) {
      final v = gray[srcRow * w + x];
      b.setUint8(off, v);
      b.setUint8(off + 1, v);
      b.setUint8(off + 2, v);
      off += 3;
    }
  }
  return b.buffer.asUint8List();
}
