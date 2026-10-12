import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api/keenon_api.dart';
import 'api/mock_api.dart';

enum KeenonRegion { china, eu, japan, custom }

extension KeenonRegionX on KeenonRegion {
  String get label {
    switch (this) {
      case KeenonRegion.china:
        return '중국 본토';
      case KeenonRegion.eu:
        return 'EU';
      case KeenonRegion.japan:
        return '일본';
      case KeenonRegion.custom:
        return '직접 입력';
    }
  }

  /// Keenon Cloud API 문서(Getting Started)의 운영 도메인
  String get defaultUrl {
    switch (this) {
      case KeenonRegion.china:
        return 'https://console.peanut.keenonrobot.com';
      case KeenonRegion.eu:
        return 'https://es.robotkeenon.com';
      case KeenonRegion.japan:
        return 'https://cloud.robotkeenon.com';
      case KeenonRegion.custom:
        return '';
    }
  }
}

class AppSettings {
  final KeenonRegion region;
  final String customUrl;
  final String clientId;
  final String clientSecret;
  final String robotType; // food | hotel
  final double mapResolution; // m/px
  final bool demoMode;

  const AppSettings({
    this.region = KeenonRegion.china,
    this.customUrl = '',
    this.clientId = '',
    this.clientSecret = '',
    this.robotType = 'food',
    this.mapResolution = 0.05,
    this.demoMode = false,
  });

  String get baseUrl => region == KeenonRegion.custom ? customUrl.trim() : region.defaultUrl;

  bool get isConfigured =>
      demoMode || (clientId.trim().isNotEmpty && clientSecret.trim().isNotEmpty && baseUrl.isNotEmpty);

  AppSettings copyWith({
    KeenonRegion? region,
    String? customUrl,
    String? clientId,
    String? clientSecret,
    String? robotType,
    double? mapResolution,
    bool? demoMode,
  }) =>
      AppSettings(
        region: region ?? this.region,
        customUrl: customUrl ?? this.customUrl,
        clientId: clientId ?? this.clientId,
        clientSecret: clientSecret ?? this.clientSecret,
        robotType: robotType ?? this.robotType,
        mapResolution: mapResolution ?? this.mapResolution,
        demoMode: demoMode ?? this.demoMode,
      );

  static const _kRegion = 'region';
  static const _kCustomUrl = 'customUrl';
  static const _kClientId = 'clientId';
  static const _kClientSecret = 'clientSecret';
  static const _kRobotType = 'robotType';
  static const _kMapRes = 'mapResolution';
  static const _kDemo = 'demoMode';

  static Future<AppSettings> load() async {
    final p = await SharedPreferences.getInstance();
    final regionName = p.getString(_kRegion);
    final region = KeenonRegion.values.firstWhere(
      (r) => r.name == regionName,
      orElse: () => KeenonRegion.china,
    );
    return AppSettings(
      region: region,
      customUrl: p.getString(_kCustomUrl) ?? '',
      clientId: p.getString(_kClientId) ?? '',
      clientSecret: p.getString(_kClientSecret) ?? '',
      robotType: p.getString(_kRobotType) ?? 'food',
      mapResolution: p.getDouble(_kMapRes) ?? 0.05,
      demoMode: p.getBool(_kDemo) ?? false,
    );
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kRegion, region.name);
    await p.setString(_kCustomUrl, customUrl);
    await p.setString(_kClientId, clientId);
    // PoC 전용: secret 을 기기에 평문 저장한다. 운영 버전에서는 서버에서만 보관해야 한다.
    await p.setString(_kClientSecret, clientSecret);
    await p.setString(_kRobotType, robotType);
    await p.setDouble(_kMapRes, mapResolution);
    await p.setBool(_kDemo, demoMode);
  }

  RobotApi buildApi() {
    if (demoMode) return MockRobotApi();
    return KeenonApi(baseUrl: baseUrl, clientId: clientId.trim(), clientSecret: clientSecret.trim());
  }
}

class AppController extends ChangeNotifier {
  AppController(AppSettings settings)
      : _settings = settings,
        _api = settings.buildApi();

  AppSettings _settings;
  RobotApi _api;

  AppSettings get settings => _settings;
  RobotApi get api => _api;

  Future<void> update(AppSettings s) async {
    await s.save();
    _api.dispose();
    _settings = s;
    _api = s.buildApi();
    notifyListeners();
  }

  @override
  void dispose() {
    _api.dispose();
    super.dispose();
  }
}

class AppScope extends InheritedNotifier<AppController> {
  const AppScope({super.key, required AppController controller, required super.child})
      : super(notifier: controller);

  /// 빌드 중 사용 (설정 변경 시 다시 빌드됨)
  static AppController of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;

  /// 이벤트 핸들러 등에서 사용 (의존성 등록 없음)
  static AppController read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AppScope>()!.notifier!;
}
