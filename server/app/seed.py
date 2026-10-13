"""데모 데이터 등록 (매장·씬·맵·포인트·로봇) - 이미 있으면 건너뜀"""
from __future__ import annotations

from .db import Point, Robot, Scene, Store, session_scope
from .layouts import LAYOUTS, MAP_H, MAP_W, ORIGIN_X, ORIGIN_Y, RES, render_png


def seed_demo() -> None:
    with session_scope() as s:
        for lay in LAYOUTS:
            if s.get(Store, lay.store_id) is None:
                s.add(Store(id=lay.store_id, name=lay.store_name, brand=lay.brand, address=lay.address))
            if s.get(Scene, lay.scene_code) is None:
                s.add(Scene(
                    code=lay.scene_code, name=lay.scene_name, store_id=lay.store_id, floor="1",
                    origin_x=ORIGIN_X, origin_y=ORIGIN_Y, resolution=RES, width=MAP_W, height=MAP_H,
                    map_png=render_png(lay),
                ))
            for p in lay.points:
                if s.get(Point, p.uuid) is None:
                    s.add(Point(uuid=p.uuid, point_id=p.point_id, name=p.name, area=p.area,
                                scene_code=lay.scene_code, kind=p.kind, x=p.x, y=p.y))
            for r in lay.robots:
                if s.get(Robot, r.sn) is None:
                    # 로봇은 등록만 해 두고, 실제 상태는 로봇이 접속해서 올린 값으로 채운다
                    s.add(Robot(sn=r.sn, name=r.name, model=r.model, kind=r.kind, app_version=r.app_version,
                                store_id=lay.store_id, scene_code=lay.scene_code, online=False))
