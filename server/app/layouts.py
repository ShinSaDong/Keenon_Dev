"""데모 매장 배치도 (서버 시드와 가상 로봇이 함께 사용)

좌표계는 Keenon 위치 API 와 같은 월드 좌표(미터, y 위쪽)이다.
맵 이미지: 400x300 px, 해상도 0.05 m/px, origin(-10, -7.5) → 20m x 15m
"""
from __future__ import annotations

import struct
import zlib
from dataclasses import dataclass, field

MAP_W = 400
MAP_H = 300
RES = 0.05
ORIGIN_X = -10.0
ORIGIN_Y = -7.5


@dataclass(frozen=True)
class PointDef:
    uuid: str
    point_id: str
    name: str
    area: str
    x: float
    y: float
    kind: str = "target"  # target | pickup


@dataclass(frozen=True)
class RobotDef:
    sn: str
    name: str
    model: str
    kind: str  # serving | hotel
    dock: tuple[float, float]
    battery: int
    online: bool = True
    app_version: str = "v2.3.0"


@dataclass
class SceneLayout:
    store_id: str
    store_name: str
    brand: str
    address: str
    scene_code: str
    scene_name: str
    aisle_y: float  # 모든 이동이 지나가는 중앙 통로 y
    points: list[PointDef] = field(default_factory=list)
    robots: list[RobotDef] = field(default_factory=list)
    kind: str = "hall"  # hall | hotel

    def point_by_uuid(self, uuid: str) -> PointDef | None:
        return next((p for p in self.points if p.uuid == uuid), None)


def _hall() -> SceneLayout:
    pts = [
        PointDef(f"demo-t-{i + 1}", f"{i + 1}", f"{i + 1}번 테이블", "A 구역(창가)", -7.0 + 3 * i, 2.6)
        for i in range(4)
    ] + [
        PointDef(f"demo-t-{i + 5}", f"{i + 5}", f"{i + 5}번 테이블", "B 구역(안쪽)", -7.0 + 3 * i, -2.6)
        for i in range(4)
    ] + [PointDef("demo-kitchen", "50", "주방 픽업대", "주방", 7.5, 4.4, "pickup")]
    robots = [
        RobotDef("AA:BB:CC:00:00:01", "서빙 1호", "T8", "serving", (6.5, -5.8), 82),
        RobotDef("AA:BB:CC:00:00:02", "서빙 2호", "T8", "serving", (7.5, -5.8), 64),
        RobotDef("AA:BB:CC:00:00:03", "서빙 3호", "T9", "serving", (8.5, -5.8), 12, online=False, app_version="v2.1.5"),
    ]
    return SceneLayout(
        store_id="DEMO-S001",
        store_name="데모 레스토랑 1호점",
        brand="데모 외식",
        address="서울특별시 강남구 (데모)",
        scene_code="DEMO-HALL",
        scene_name="홀 기본 씬",
        aisle_y=-1.0,
        points=pts,
        robots=robots,
        kind="hall",
    )


ROOM_CX = (-7.25, -1.875, 3.375)


def _hotel() -> SceneLayout:
    pts = [
        PointDef(f"demo-h-{101 + i}", f"{101 + i}", f"{101 + i}호", "1층 북쪽", ROOM_CX[i], 1.3) for i in range(3)
    ] + [
        PointDef(f"demo-h-{104 + i}", f"{104 + i}", f"{104 + i}호", "1층 남쪽", ROOM_CX[i], -1.3) for i in range(3)
    ] + [PointDef("demo-h-front", "99", "프런트", "로비", 8.8, 3.6, "pickup")]
    robots = [
        RobotDef("AA:BB:CC:00:01:01", "호텔 배송 1호", "W3", "hotel", (8.0, -5.5), 71, app_version="v1.12.0"),
        RobotDef("AA:BB:CC:00:01:02", "호텔 배송 2호", "W3", "hotel", (9.0, -5.5), 55, app_version="v1.12.0"),
    ]
    return SceneLayout(
        store_id="DEMO-S002",
        store_name="데모 호텔",
        brand="데모 호텔",
        address="부산광역시 해운대구 (데모)",
        scene_code="DEMO-HOTEL",
        scene_name="호텔 1층",
        aisle_y=0.0,
        points=pts,
        robots=robots,
        kind="hotel",
    )


LAYOUTS: list[SceneLayout] = [_hall(), _hotel()]


def layout_for_scene(scene_code: str) -> SceneLayout | None:
    return next((l for l in LAYOUTS if l.scene_code == scene_code), None)


def layout_for_robot(sn: str) -> SceneLayout | None:
    return next((l for l in LAYOUTS if any(r.sn == sn for r in l.robots)), None)


# --------------------------------------------------------------------------- 맵 이미지


def _px(x: float) -> int:
    return round((x - ORIGIN_X) / RES)


def _py(y: float) -> int:
    return round((ORIGIN_Y + MAP_H * RES - y) / RES)


def _rect(g: bytearray, x0: int, y0: int, x1: int, y1: int, v: int) -> None:
    for y in range(max(0, y0), min(MAP_H, y1)):
        row = y * MAP_W
        for x in range(max(0, x0), min(MAP_W, x1)):
            g[row + x] = v


def _walls(g: bytearray) -> None:
    _rect(g, 0, 0, MAP_W, 6, 40)
    _rect(g, 0, MAP_H - 6, MAP_W, MAP_H, 40)
    _rect(g, 0, 0, 6, MAP_H, 40)
    _rect(g, MAP_W - 6, 0, MAP_W, MAP_H, 40)


def render_gray(layout: SceneLayout) -> bytearray:
    g = bytearray([246]) * (MAP_W * MAP_H)
    _walls(g)
    if layout.kind == "hall":
        _rect(g, _px(5.0), 0, _px(5.0) + 6, _py(0.0), 40)  # 주방 칸막이
        _rect(g, _px(6.0), _py(6.6), _px(9.6), _py(5.4), 150)  # 조리대
        for i in range(4):
            cx = -7.0 + 3 * i
            _rect(g, _px(cx - 1.0), _py(5.5), _px(cx + 1.0), _py(3.5), 160)
            _rect(g, _px(cx - 1.0), _py(-3.5), _px(cx + 1.0), _py(-5.5), 160)
            for dx in (-0.6, 0.6):
                _rect(g, _px(cx + dx - 0.2), _py(6.1), _px(cx + dx + 0.2), _py(5.7), 200)
                _rect(g, _px(cx + dx - 0.2), _py(-5.7), _px(cx + dx + 0.2), _py(-6.1), 200)
        _rect(g, _px(6.0), _py(-5.3), _px(9.0), _py(-6.3), 215)  # 충전 구역
    else:
        edges = (-10.0, -4.5, 0.75, 6.0)
        door = 0.75
        for wall_y in (2.0, -2.0):
            y0 = _py(wall_y) - 4 if wall_y > 0 else _py(wall_y)
            for i in range(3):
                cx = (edges[i] + edges[i + 1]) / 2
                _rect(g, _px(edges[i]), y0, _px(cx - door), y0 + 4, 40)
                _rect(g, _px(cx + door), y0, _px(edges[i + 1]), y0 + 4, 40)
        for x in (-4.5, 0.75, 6.0):
            _rect(g, _px(x) - 2, 0, _px(x) + 2, _py(2.0), 40)
            _rect(g, _px(x) - 2, _py(-2.0), _px(x) + 2, MAP_H, 40)
        for i in range(3):
            cx = (edges[i] + edges[i + 1]) / 2
            _rect(g, _px(cx - 1.2), _py(6.8), _px(cx + 1.2), _py(4.2), 175)
            _rect(g, _px(cx - 1.2), _py(-4.2), _px(cx + 1.2), _py(-6.8), 175)
        _rect(g, _px(8.0), _py(6.0), _px(9.6), _py(4.5), 150)  # 프런트
        _rect(g, _px(7.4), _py(-5.0), _px(9.6), _py(-6.0), 215)  # 충전 구역
    return g


def gray_to_png(gray: bytes, w: int, h: int) -> bytes:
    """8비트 회색조 PNG 인코더 (외부 라이브러리 없이)"""
    raw = b"".join(b"\x00" + bytes(gray[y * w:(y + 1) * w]) for y in range(h))

    def chunk(tag: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    ihdr = struct.pack(">IIBBBBB", w, h, 8, 0, 0, 0, 0)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")


def render_png(layout: SceneLayout) -> bytes:
    return gray_to_png(render_gray(layout), MAP_W, MAP_H)


def plan_path(x: float, y: float, to: tuple[float, float], aisle_y: float) -> list[tuple[float, float]]:
    """A → (A.x, 통로) → (B.x, 통로) → B  (데모 맵은 이 경로에서 막히지 않게 설계됨)"""
    pts: list[tuple[float, float]] = []
    if abs(y - aisle_y) > 0.05:
        pts.append((x, aisle_y))
    if abs(x - to[0]) > 0.05:
        pts.append((to[0], aisle_y))
    pts.append(to)
    return pts
