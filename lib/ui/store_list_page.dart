import 'package:flutter/material.dart';

import '../api/models.dart';
import '../app_state.dart';
import 'common.dart';
import 'robot_list_page.dart';
import 'settings_page.dart';

class StoreListPage extends StatelessWidget {
  const StoreListPage({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('매장 목록'),
        actions: [
          IconButton(
            tooltip: '설정',
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsPage()),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          if (app.settings.demoMode) const DemoBanner(),
          Expanded(
            child: LoadView<List<Store>>(
              // 설정이 바뀌면(api 인스턴스 교체) 다시 불러온다
              key: ValueKey(app.api),
              load: app.api.getStores,
              builder: (context, stores, reload) => RefreshIndicator(
                onRefresh: reload,
                child: stores.isEmpty
                    ? const EmptyView(message: '연결된 매장이 없습니다.\nKeenon 에 매장 권한을 요청하세요.')
                    : ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
                        itemCount: stores.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, i) {
                          final s = stores[i];
                          final sub = [s.brandName, s.address].where((e) => e.trim().isNotEmpty).join(' · ');
                          return ListTile(
                            leading: const CircleAvatar(child: Icon(Icons.store)),
                            title: Text(s.storeName.isEmpty ? s.storeId : s.storeName),
                            subtitle: Text(sub.isEmpty ? s.storeId : '$sub\n${s.storeId}'),
                            isThreeLine: sub.isNotEmpty,
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => RobotListPage(store: s)),
                            ),
                          );
                        },
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class DemoBanner extends StatelessWidget {
  const DemoBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: Colors.amber.shade100,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: const Text('데모 모드: 가상 데이터입니다. 실제 로봇은 움직이지 않습니다.', style: TextStyle(fontSize: 13)),
    );
  }
}
