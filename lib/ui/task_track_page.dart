import 'dart:async';

import 'package:flutter/material.dart';

import '../api/labels.dart';
import '../api/models.dart';
import '../app_state.dart';
import 'common.dart';
import 'map_page.dart';

/// 호출/복귀 작업 상태를 3초 간격으로 조회한다 (Keenon 권장 조회 간격 약 3초).
class TaskTrackPage extends StatefulWidget {
  const TaskTrackPage({
    super.key,
    required this.taskNo,
    required this.title,
    this.robotName,
    this.robotId,
    this.initialQueue,
    this.sceneCode,
    this.robotKind = RobotKind.serving,
  });

  final String taskNo;
  final String title;
  final String? robotName;
  final String? robotId;
  final int? initialQueue;

  /// 지정하면 '맵에서 이동 보기' 버튼을 표시
  final String? sceneCode;
  final RobotKind robotKind;

  @override
  State<TaskTrackPage> createState() => _TaskTrackPageState();
}

class _TaskTrackPageState extends State<TaskTrackPage> {
  static const _interval = Duration(seconds: 3);
  static const _maxConsecutiveErrors = 5;

  Timer? _timer;
  TaskStatus? _status;
  String? _error;
  int _errorCount = 0;
  bool _polling = false;
  bool _canceling = false;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    Future.microtask(_poll);
    _timer = Timer.periodic(_interval, (_) => _poll());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _poll() async {
    if (_polling || !mounted) return;
    _polling = true;
    try {
      final s = await AppScope.read(context).api.getTaskStatus(widget.taskNo);
      if (!mounted) return;
      setState(() {
        _status = s;
        _error = null;
        _errorCount = 0;
      });
      if (s.isFinal) _timer?.cancel();
    } catch (e) {
      if (!mounted) return;
      _errorCount++;
      setState(() => _error = '$e');
      if (_errorCount >= _maxConsecutiveErrors) _timer?.cancel();
    } finally {
      _polling = false;
    }
  }

  Future<void> _cancel() async {
    final ok = await confirmDialog(context, title: '작업 취소', message: '이 작업을 취소할까요?', ok: '작업 취소');
    if (!ok || !mounted) return;
    setState(() => _canceling = true);
    try {
      await AppScope.read(context).api.cancelTask(widget.taskNo);
      if (!mounted) return;
      showSnack(context, '취소를 요청했습니다');
      await _poll();
    } catch (e) {
      if (mounted) showSnack(context, '취소 실패: $e', error: true);
    } finally {
      if (mounted) setState(() => _canceling = false);
    }
  }

  void _resume() {
    _errorCount = 0;
    _timer?.cancel();
    _timer = Timer.periodic(_interval, (_) => _poll());
    _poll();
  }

  @override
  Widget build(BuildContext context) {
    final s = _status;
    final stopped = (_timer == null || !_timer!.isActive);
    final finished = s?.isFinal ?? false;
    final errorText = taskErrorLabel(s?.errorCode);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Icon(_iconFor(s?.status), size: 56, color: _colorFor(s?.status)),
                  const SizedBox(height: 12),
                  Text(taskStatusLabel(s?.status), style: theme.textTheme.headlineSmall),
                  const SizedBox(height: 4),
                  if (!finished && !stopped)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: LinearProgressIndicator(),
                    ),
                  if (errorText != null) ...[
                    const SizedBox(height: 12),
                    Text(errorText, textAlign: TextAlign.center, style: TextStyle(color: theme.colorScheme.error)),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          _StepBar(status: s?.status),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _row('작업 번호', widget.taskNo),
                  _row('로봇', (s?.robotId.isNotEmpty ?? false) ? s!.robotId : (widget.robotName ?? '배정 대기')),
                  _row('남은 거리', s?.remainingDistance == null ? '-' : '${s!.remainingDistance!.toStringAsFixed(1)} m'),
                  _row('대기 순번', '${s?.waitQueuing ?? widget.initialQueue ?? '-'}'),
                  _row('최근 갱신', (s?.lastUpdateTime.isNotEmpty ?? false) ? s!.lastUpdateTime : '-'),
                  if ((s?.remark ?? '').isNotEmpty) _row('비고', s!.remark),
                ],
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text('조회 오류: $_error', style: TextStyle(color: theme.colorScheme.error)),
          ],
          const SizedBox(height: 16),
          if (widget.sceneCode != null && widget.sceneCode!.isNotEmpty && _trackRobotId(s) != null) ...[
            FilledButton.tonalIcon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => MapPage(
                    title: '${widget.robotName ?? _trackRobotId(s)} 이동',
                    sceneCode: widget.sceneCode!,
                    robots: [
                      MapRobot(
                        id: _trackRobotId(s)!,
                        name: widget.robotName ?? _trackRobotId(s)!,
                        kind: widget.robotKind,
                      ),
                    ],
                  ),
                ),
              ),
              icon: const Icon(Icons.map),
              label: const Text('맵에서 이동 보기'),
            ),
            const SizedBox(height: 8),
          ],
          if (!finished)
            OutlinedButton.icon(
              onPressed: _canceling ? null : _cancel,
              icon: const Icon(Icons.cancel),
              label: const Text('작업 취소'),
              style: OutlinedButton.styleFrom(foregroundColor: theme.colorScheme.error),
            ),
          if (!finished && stopped) ...[
            const SizedBox(height: 8),
            FilledButton.tonalIcon(
              onPressed: _resume,
              icon: const Icon(Icons.refresh),
              label: const Text('상태 조회 다시 시작'),
            ),
          ],
          if (finished)
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('닫기'),
            ),
        ],
      ),
    );
  }

  String? _trackRobotId(TaskStatus? s) {
    if (s != null && s.robotId.isNotEmpty) return s.robotId;
    final id = widget.robotId;
    return (id == null || id.isEmpty) ? null : id;
  }

  IconData _iconFor(int? s) {
    switch (s) {
      case 0:
        return Icons.error;
      case 1:
      case 7:
        return Icons.hourglass_top;
      case 2:
      case 3:
        return Icons.directions_run;
      case 4:
        return Icons.check_circle;
      case 5:
        return Icons.cancel;
      case 6:
        return Icons.place;
      default:
        return Icons.sync;
    }
  }

  Color _colorFor(int? s) {
    switch (s) {
      case 0:
        return Colors.red.shade700;
      case 4:
      case 6:
        return Colors.green.shade700;
      case 5:
        return Colors.grey.shade700;
      default:
        return Colors.blue.shade700;
    }
  }

  Widget _row(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 80, child: Text(k, style: const TextStyle(color: Colors.black54))),
            Expanded(child: SelectableText(v)),
          ],
        ),
      );
}

/// 대기 → 호출 → 이동 → 도착 → 완료 진행 표시
class _StepBar extends StatelessWidget {
  const _StepBar({required this.status});

  final int? status;

  static const _steps = ['대기', '호출', '이동', '도착', '완료'];

  int get _index {
    switch (status) {
      case 1:
      case 7:
        return 0;
      case 2:
        return 1;
      case 3:
        return 2;
      case 6:
        return 3;
      case 4:
        return 4;
      default:
        return -1;
    }
  }

  @override
  Widget build(BuildContext context) {
    final idx = _index;
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        for (var i = 0; i < _steps.length; i++)
          Expanded(
            child: Column(
              children: [
                Container(
                  height: 6,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    color: i <= idx ? cs.primary : cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _steps[i],
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: i == idx ? FontWeight.w700 : FontWeight.w400,
                    color: i <= idx ? cs.primary : cs.outline,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
