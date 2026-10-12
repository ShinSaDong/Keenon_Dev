import 'package:flutter/material.dart';

import '../api/keenon_api.dart';
import '../app_state.dart';
import 'common.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, this.firstRun = false});

  final bool firstRun;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late KeenonRegion _region;
  late String _robotType;
  late bool _demo;
  final _customUrl = TextEditingController();
  final _clientId = TextEditingController();
  final _clientSecret = TextEditingController();
  final _mapRes = TextEditingController();
  bool _obscure = true;
  bool _testing = false;
  bool _saving = false;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    final s = AppScope.read(context).settings;
    _region = s.region;
    _robotType = s.robotType;
    _demo = s.demoMode;
    _customUrl.text = s.customUrl;
    _clientId.text = s.clientId;
    _clientSecret.text = s.clientSecret;
    _mapRes.text = s.mapResolution.toString();
  }

  @override
  void dispose() {
    _customUrl.dispose();
    _clientId.dispose();
    _clientSecret.dispose();
    _mapRes.dispose();
    super.dispose();
  }

  AppSettings _current() {
    final base = AppScope.read(context).settings;
    return base.copyWith(
      region: _region,
      customUrl: _customUrl.text.trim(),
      clientId: _clientId.text.trim(),
      clientSecret: _clientSecret.text.trim(),
      robotType: _robotType,
      mapResolution: double.tryParse(_mapRes.text.trim()) ?? 0.05,
      demoMode: _demo,
    );
  }

  Future<void> _test() async {
    final s = _current();
    if (s.demoMode) {
      showSnack(context, '데모 모드에서는 연결 테스트가 필요 없습니다');
      return;
    }
    if (!s.isConfigured) {
      showSnack(context, '도메인, client_id, client_secret 을 모두 입력하세요', error: true);
      return;
    }
    setState(() => _testing = true);
    final api = KeenonApi(baseUrl: s.baseUrl, clientId: s.clientId, clientSecret: s.clientSecret);
    try {
      final stores = await api.getStores();
      if (!mounted) return;
      showSnack(context, '연결 성공: 매장 ${stores.length}곳 확인');
    } catch (e) {
      if (!mounted) return;
      showSnack(context, '연결 실패: $e', error: true);
    } finally {
      api.dispose();
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _save() async {
    final s = _current();
    if (!s.isConfigured) {
      showSnack(context, '도메인, client_id, client_secret 을 입력하거나 데모 모드를 켜세요', error: true);
      return;
    }
    setState(() => _saving = true);
    await AppScope.read(context).update(s);
    if (!mounted) return;
    setState(() => _saving = false);
    if (!widget.firstRun && Navigator.canPop(context)) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(widget.firstRun ? 'Keenon 관제 PoC 설정' : '설정')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: SwitchListTile(
              title: const Text('데모 모드'),
              subtitle: const Text('계정 없이 가상 매장·로봇으로 화면 흐름을 확인합니다'),
              value: _demo,
              onChanged: (v) => setState(() => _demo = v),
            ),
          ),
          const SizedBox(height: 16),
          Text('Keenon 클라우드 접속', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final r in KeenonRegion.values)
                ChoiceChip(
                  label: Text(r.label),
                  selected: _region == r,
                  onSelected: _demo ? null : (_) => setState(() => _region = r),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (_region == KeenonRegion.custom)
            TextField(
              controller: _customUrl,
              enabled: !_demo,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'API 도메인',
                hintText: 'https://...',
                border: OutlineInputBorder(),
              ),
            )
          else
            Text('도메인: ${_region.defaultUrl}', style: theme.textTheme.bodySmall),
          const SizedBox(height: 12),
          TextField(
            controller: _clientId,
            enabled: !_demo,
            decoration: const InputDecoration(labelText: 'client_id', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _clientSecret,
            enabled: !_demo,
            obscureText: _obscure,
            decoration: InputDecoration(
              labelText: 'client_secret',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.errorContainer.withAlpha(120),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              'PoC 전용: client_secret 이 이 기기에 저장됩니다. 외부 배포용 앱에서는 반드시 서버에서 토큰을 발급하도록 바꿔야 합니다.',
              style: TextStyle(fontSize: 13),
            ),
          ),
          const SizedBox(height: 20),
          Text('기본 로봇 유형', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: const Text('배송(food)'),
                selected: _robotType == 'food',
                onSelected: (_) => setState(() => _robotType = 'food'),
              ),
              ChoiceChip(
                label: const Text('호텔(hotel)'),
                selected: _robotType == 'hotel',
                onSelected: (_) => setState(() => _robotType = 'hotel'),
              ),
            ],
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _mapRes,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: '맵 해상도 (m/px)',
              helperText: '로봇 위치를 맵 위에 그릴 때 사용. 실제 값은 Keenon 확인 필요 (일반적으로 0.05)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _testing ? null : _test,
                  icon: _testing
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.wifi_tethering),
                  label: const Text('연결 테스트'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: const Icon(Icons.save),
                  label: const Text('저장'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
