import 'package:flutter/material.dart';

import '../api/labels.dart';
import '../api/models.dart';
import '../app_state.dart';
import 'call_page.dart';
import 'common.dart';
import 'history_page.dart';
import 'robot_detail_page.dart';

class RobotListPage extends StatelessWidget {
  const RobotListPage({super.key, required this.store});

  final Store store;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(store.storeName.isEmpty ? store.storeId : store.storeName),
        actions: [
          IconButton(
            tooltip: '작업 이력',
            icon: const Icon(Icons.history),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => HistoryPage(store: store)),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => CallPage(store: store)),
        ),
        icon: const Icon(Icons.place),
        label: const Text('로봇 호출'),
      ),
      body: LoadView<List<Robot>>(
        key: ValueKey(app.api),
        load: () => app.api.getRobots(store.storeId),
        builder: (context, robots, reload) => RefreshIndicator(
          onRefresh: reload,
          child: robots.isEmpty
              ? const EmptyView(message: '이 매장에 등록된 로봇이 없습니다.', icon: Icons.smart_toy_outlined)
              : ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.only(bottom: 96),
                  itemCount: robots.length + 1,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    if (i == 0) {
                      final online = robots.where((r) => r.online).length;
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                        child: Text('로봇 ${robots.length}대 · 온라인 $online대',
                            style: Theme.of(context).textTheme.titleSmall),
                      );
                    }
                    final r = robots[i - 1];
                    return _RobotTile(
                      robot: r,
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => RobotDetailPage(store: store, robot: r)),
                        );
                        await reload();
                      },
                    );
                  },
                ),
        ),
      ),
    );
  }
}

class _RobotTile extends StatelessWidget {
  const _RobotTile({required this.robot, required this.onTap});

  final Robot robot;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final r = robot;
    final details = [
      if (r.robotModel.isNotEmpty) r.robotModel,
      if (r.appVersion.isNotEmpty) r.appVersion,
      if (r.onlineType != null) onlineTypeLabel(r.onlineType),
    ].join(' · ');
    return ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: r.online ? Colors.green.shade100 : Colors.grey.shade300,
        child: Icon(Icons.smart_toy, color: r.online ? Colors.green.shade800 : Colors.grey.shade600),
      ),
      title: Row(
        children: [
          Flexible(child: Text(r.displayName, overflow: TextOverflow.ellipsis)),
          const SizedBox(width: 8),
          StatusChip(
            label: r.online ? '온라인' : '오프라인',
            color: r.online ? Colors.green.shade700 : Colors.grey.shade700,
          ),
        ],
      ),
      subtitle: Text(details.isEmpty ? r.robotId : '${r.robotId}\n$details'),
      isThreeLine: details.isNotEmpty,
      trailing: BatteryText(power: r.power),
    );
  }
}
