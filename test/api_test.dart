import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:keenon_control/api/keenon_api.dart';
import 'package:keenon_control/api/models.dart';
import 'package:keenon_control/util/map_image.dart';

http.Response _json(Object body, [int status = 200]) => http.Response.bytes(
      utf8.encode(jsonEncode(body)),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

void main() {
  group('KeenonApi', () {
    test('토큰 발급 후 Bearer 헤더로 매장 목록 조회', () async {
      var tokenCalls = 0;
      final client = MockClient((req) async {
        if (req.url.path == '/api/open/oauth/token') {
          tokenCalls++;
          expect(req.method, 'POST');
          expect(req.bodyFields['grant_type'], 'client_credentials');
          expect(req.bodyFields['client_id'], 'cid');
          return _json({'access_token': 'tok-1', 'token_type': 'bearer', 'expires_in': 7200});
        }
        expect(req.headers['Authorization'], 'bearer tok-1');
        expect(req.url.path, '/api/open/data/v1/store/list');
        return _json({
          'code': 610000,
          'msg': 'ok',
          'data': [
            {'storeId': 'S1', 'storeName': '1호점'},
          ],
        });
      });
      final api = KeenonApi(baseUrl: 'https://example.com/', clientId: 'cid', clientSecret: 'sec', client: client);
      final stores = await api.getStores();
      expect(stores.single.storeId, 'S1');
      await api.getStores();
      expect(tokenCalls, 1, reason: '유효한 토큰은 재사용');
    });

    test('610401 응답 시 토큰 재발급 후 1회 재시도', () async {
      var tokenCalls = 0;
      var dataCalls = 0;
      final client = MockClient((req) async {
        if (req.url.path == '/api/open/oauth/token') {
          tokenCalls++;
          return _json({'access_token': 'tok-$tokenCalls', 'expires_in': 7200});
        }
        dataCalls++;
        if (req.headers['Authorization'] == 'bearer tok-1') {
          return _json({'code': 610401, 'msg': 'invalid token'});
        }
        return _json({'code': 610000, 'data': {'list': []}});
      });
      final api = KeenonApi(baseUrl: 'https://example.com', clientId: 'a', clientSecret: 'b', client: client);
      final scenes = await api.getScenes('S1');
      expect(scenes, isEmpty);
      expect(tokenCalls, 2);
      expect(dataCalls, 2);
    });

    test('오류 코드는 KeenonApiException 으로 변환', () async {
      final client = MockClient((req) async {
        if (req.url.path == '/api/open/oauth/token') return _json({'access_token': 't', 'expires_in': 7200});
        return _json({'code': 617000, 'msg': 'ip limited'});
      });
      final api = KeenonApi(baseUrl: 'https://example.com', clientId: 'a', clientSecret: 'b', client: client);
      expect(
        api.getStores(),
        throwsA(isA<KeenonApiException>().having((e) => e.code, 'code', 617000)),
      );
    });

    test('호출 요청 바디와 작업 상태 파싱', () async {
      final client = MockClient((req) async {
        if (req.url.path == '/api/open/oauth/token') return _json({'access_token': 't', 'expires_in': 7200});
        if (req.method == 'POST') {
          final body = jsonDecode(req.body) as Map<String, dynamic>;
          expect(req.url.path, '/api/open/scene/v3/robot/call/task');
          expect(body['uuid'], 'u1');
          expect(body['pointId'], '12');
          expect(body['storeId'], 'S1');
          expect(body['robotId'], 'R1');
          return _json({'code': 610000, 'data': {'taskNo': 'T1', 'waitQueuing': 1}});
        }
        expect(req.url.queryParameters['taskNo'], 'T1');
        return _json({
          'code': 610000,
          'data': {
            'taskNo': 'T1',
            'taskStatus': 3,
            'errorCode': 0,
            'taskData': {'remainingDistance': 4.5, 'robotId': 'R1', 'waitQueuing': 0},
          },
        });
      });
      final api = KeenonApi(baseUrl: 'https://example.com', clientId: 'a', clientSecret: 'b', client: client);
      final r = await api.callRobot(
        storeId: 'S1',
        point: TargetPoint(pointName: '1번', area: 'A', uuid: 'u1', pointId: '12'),
        robotId: 'R1',
      );
      expect(r.taskNo, 'T1');
      final s = await api.getTaskStatus('T1');
      expect(s.status, 3);
      expect(s.remainingDistance, 4.5);
      expect(s.isFinal, isFalse);
    });
  });

  group('models', () {
    test('로봇 위치 좌표 문자열 파싱 (공백 섞인 키 포함)', () {
      final loc = RobotLocation.fromJson({' coordinate ': '-8.22, 12.07, -1.53', 'floor': 1, 'takeElevatorStatus': 1});
      expect(loc.x, -8.22);
      expect(loc.y, 12.07);
      expect(loc.angle, -1.53);
      expect(loc.floor, '1');
      expect(loc.inElevator, isTrue);
    });

    test('맵 content: Java signed byte 배열 보정', () {
      final m = MapData.fromJson({
        'content': [-119, 80, 78, 71],
        'originPosition': {'originX': -1, 'originY': 2, 'isDynamic': true},
      });
      expect(m.bytes, Uint8List.fromList([0x89, 0x50, 0x4E, 0x47]));
      expect(m.isDynamic, isTrue);
    });
  });

  group('map_image', () {
    test('PGM(P5) → BMP 변환', () {
      final header = ascii.encode('P5\n# c\n2 2\n255\n');
      final pgm = Uint8List.fromList([...header, 0, 255, 128, 64]);
      final out = toDisplayableImage(pgm);
      expect(out, isNotNull);
      expect(out![0], 0x42); // 'B'
      expect(out[1], 0x4D); // 'M'
    });

    test('원시 점유격자(width*height) → BMP 변환', () {
      final raw = Uint8List.fromList([0, 100, 255, 50]);
      final out = toDisplayableImage(raw, width: 2, height: 2);
      expect(out, isNotNull);
      expect(out!.length, 54 + 8 * 2); // 행당 6바이트 → 8바이트 패딩
    });
  });
}
