import 'package:flutter/material.dart';

import '../api/models.dart';
import '../app_state.dart';
import 'call_page.dart';
import 'common.dart';
import 'map_page.dart';
import 'task_track_page.dart';

class RobotDetailPage extends StatelessWidget {
  const RobotDetailPage({super.key, required this.store, required this.robot});

  final Store store;
  final Robot robot;

  Future<void> _returnToOrigin(BuildContext context) async {
    final ok = await confirmDialog(
      context,
      title: '원점 복귀',
      message: '${robot.displayName} 을(를) 원점으로 복귀시킬까요?',
      ok: '복귀',
    );
    if (!ok || !context.mounted) return;
    final api = AppScope.read(context).api;
    try {
      final r = await api.returnToOrigin(storeId: store.storeId, robotId: robot.robotId);
      if (!context.mounted) return;
      if (r.taskNo.isEmpty) {
        showSnack(context, '복귀 명령을 보냈습니다');
        return;
      }
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => TaskTrackPage(taskNo: r.taskNo, title: '원점 복귀', robotName: robot.displayName),
        ),
      );
    } catch (e) {
      if (context.mounted) showSnack(context, '복귀 실패: $e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(robot.displayName)),
      body: LoadView<RobotStatus?>(
        key: ValueKey(app.api),
        load: () => app.api.getRobotStatus(robot.robotId),
        builder: (context, status, reload) {
          final online = status?.online ?? robot.online;
          final power = status?.power ?? robot.power;
          return RefreshIndicator(
            onRefresh: reload,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            StatusChip(
                              label: online ? '온라인' : '오프라인',
                              color: online ? Colors.green.shade700 : Colors.grey.shade700,
                              icon: online ? Icons.wifi : Icons.wifi_off,
                            ),
                            if (status != null)
                              StatusChip(
                                label: status.canBeCalled ? '호출 가능' : '호출 불가',
                                color: status.canBeCalled ? Colors.blue.shade700 : Colors.orange.shade800,
                                icon: status.canBeCalled ? Icons.check_circle : Icons.block,
                              ),
                            if (status?.charging == true)
                              StatusChip(label: '충전 중', color: Colors.green.shade700, icon: Icons.bolt),
                            BatteryText(power: power, charging: status?.charging),
                          ],
                        ),
                        const SizedBox(height: 16),
                        _row('로봇 ID', robot.robotId),
                        if (robot.robotModel.isNotEmpty) _row('모델', robot.robotModel),
                        if (robot.appVersion.isNotEmpty) _row('앱 버전', robot.appVersion),
                        _row('현재 씬', status == null ? '-' : (status.sceneName.isEmpty ? status.sceneCode : '${status.sceneName} (${status.sceneCode})')),
                      ],
                    ),
                  ),
                ),
                if (status == null)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text('상태 조회 결과가 없습니다. 로봇 앱 버전이 낮으면 일부 정보가 제공되지 않습니다.'),
                  ),
                if (status != null && !status.canBeCalled)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      '호출 불가 시 확인: 로봇 네트워크 · 로봇 앱의 원격 호출 설정 · 대기(idle) 상태 · 앱 버전 호환성',
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => CallPage(
                        store: store,
                        robotId: robot.robotId,
                        robotName: robot.displayName,
                        initialSceneCode: status?.sceneCode,
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.place),
                  label: const Text('이 로봇 호출'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => _returnToOrigin(context),
                  icon: const Icon(Icons.home),
                  label: const Text('원점 복귀'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: (status == null || status.sceneCode.isEmpty)
                      ? null
                      : () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => MapPage(
                                robotId: robot.robotId,
                                robotName: robot.displayName,
                                sceneCode: status.sceneCode,
                              ),
                            ),
                          ),
                  icon: const Icon(Icons.map),
                  label: const Text('맵 · 실시간 위치'),
                ),
              ],
            ),
          );
        },
      ),
    );
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
