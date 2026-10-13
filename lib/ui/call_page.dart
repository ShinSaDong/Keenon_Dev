import 'package:flutter/material.dart';

import '../api/models.dart';
import '../app_state.dart';
import 'common.dart';
import 'task_track_page.dart';

/// 씬 → 포인트를 골라 로봇을 호출한다. robotId 가 없으면 매장 내 가용 로봇을 서버가 배정.
class CallPage extends StatefulWidget {
  const CallPage({
    super.key,
    required this.store,
    this.robotId,
    this.robotName,
    this.initialSceneCode,
    this.robotKind,
  });

  final Store store;
  final String? robotId;
  final String? robotName;
  final String? initialSceneCode;
  final RobotKind? robotKind;

  @override
  State<CallPage> createState() => _CallPageState();
}

class _CallPageState extends State<CallPage> {
  List<Scene>? _scenes;
  Scene? _scene;
  List<TargetPoint>? _points;
  TargetPoint? _point;
  String? _error;
  bool _loadingScenes = true;
  bool _loadingPoints = false;
  bool _submitting = false;
  String _query = '';
  late String _robotType;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    final k = widget.robotKind;
    _robotType = k == null ? AppScope.read(context).settings.robotType : (k == RobotKind.hotel ? 'hotel' : 'food');
    // 빌드 단계가 끝난 뒤 불러오기 시작
    Future.microtask(_loadScenes);
  }

  Future<void> _loadScenes() async {
    if (!mounted) return;
    setState(() {
      _loadingScenes = true;
      _error = null;
    });
    try {
      final scenes = await AppScope.read(context).api.getScenes(widget.store.storeId);
      if (!mounted) return;
      Scene? initial;
      for (final s in scenes) {
        if (s.sceneCode == widget.initialSceneCode) initial = s;
      }
      initial ??= scenes.isNotEmpty ? scenes.first : null;
      setState(() {
        _scenes = scenes;
        _loadingScenes = false;
      });
      if (initial != null) await _selectScene(initial);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loadingScenes = false;
      });
    }
  }

  Future<void> _selectScene(Scene s) async {
    setState(() {
      _scene = s;
      _points = null;
      _point = null;
      _loadingPoints = true;
      _error = null;
    });
    try {
      final points = await AppScope.read(context).api.getPoints(s.sceneCode);
      if (!mounted || _scene != s) return;
      setState(() {
        _points = points;
        _loadingPoints = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loadingPoints = false;
      });
    }
  }

  Future<void> _submit() async {
    final point = _point;
    if (point == null) return;
    final target = widget.robotName ?? '가용 로봇(자동 배정)';
    final ok = await confirmDialog(
      context,
      title: '로봇 호출',
      message: '$target 을(를) "${point.displayName}" 으로 호출할까요?',
      ok: '호출',
    );
    if (!ok || !mounted) return;
    setState(() => _submitting = true);
    try {
      final r = await AppScope.read(context).api.callRobot(
            storeId: widget.store.storeId,
            point: point,
            sceneCode: _scene?.sceneCode,
            robotId: widget.robotId,
            robotType: _robotType,
          );
      if (!mounted) return;
      if (r.taskNo.isEmpty) {
        showSnack(context, '호출을 보냈지만 작업 번호를 받지 못했습니다');
        setState(() => _submitting = false);
        return;
      }
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => TaskTrackPage(
            taskNo: r.taskNo,
            title: '호출 → ${point.displayName}',
            robotName: widget.robotName,
            robotId: widget.robotId,
            initialQueue: r.waitQueuing,
            sceneCode: _scene?.sceneCode,
            robotKind: widget.robotKind ?? (_robotType == 'hotel' ? RobotKind.hotel : RobotKind.serving),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      showSnack(context, '호출 실패: $e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.robotName == null ? '로봇 호출' : '${widget.robotName} 호출')),
      body: _buildBody(context),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton.icon(
            onPressed: (_point == null || _submitting) ? null : _submit,
            icon: _submitting
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.send),
            label: Text(_point == null ? '목적지를 선택하세요' : '"${_point!.displayName}" 으로 호출'),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loadingScenes) return const Center(child: CircularProgressIndicator());
    final scenes = _scenes ?? const <Scene>[];
    if (_error != null && scenes.isEmpty) {
      return ErrorView(message: _error!, onRetry: _loadScenes);
    }
    if (scenes.isEmpty) {
      return const Center(child: Text('이 매장에 등록된 씬이 없습니다.'));
    }

    final points = (_points ?? const <TargetPoint>[])
        .where((p) => _query.isEmpty ||
            p.displayName.toLowerCase().contains(_query.toLowerCase()) ||
            p.area.toLowerCase().contains(_query.toLowerCase()))
        .toList();
    // 구역(area)별 묶음
    final groups = <String, List<TargetPoint>>{};
    for (final p in points) {
      groups.putIfAbsent(p.area.trim().isEmpty ? '구역 없음' : p.area.trim(), () => []).add(p);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text('씬'),
              for (final s in scenes)
                ChoiceChip(
                  label: Text(s.displayName),
                  selected: _scene?.sceneCode == s.sceneCode,
                  onSelected: (_) => _selectScene(s),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text('로봇 유형'),
              ChoiceChip(
                label: const Text('배송'),
                selected: _robotType == 'food',
                onSelected: (_) => setState(() => _robotType = 'food'),
              ),
              ChoiceChip(
                label: const Text('호텔'),
                selected: _robotType == 'hotel',
                onSelected: (_) => setState(() => _robotType = 'hotel'),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: '포인트·구역 검색',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (v) => setState(() => _query = v.trim()),
          ),
        ),
        if (_error != null && _points == null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        Expanded(
          child: _loadingPoints
              ? const Center(child: CircularProgressIndicator())
              : points.isEmpty
                  ? const Center(child: Text('포인트가 없습니다.'))
                  : ListView(
                      children: [
                        for (final entry in groups.entries) ...[
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                            child: Text(entry.key, style: Theme.of(context).textTheme.titleSmall),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final p in entry.value)
                                  ChoiceChip(
                                    label: Text(p.displayName),
                                    selected: identical(_point, p),
                                    onSelected: (_) => setState(() => _point = p),
                                  ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                      ],
                    ),
        ),
      ],
    );
  }
}
