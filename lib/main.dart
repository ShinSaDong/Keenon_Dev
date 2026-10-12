import 'package:flutter/material.dart';

import 'app_state.dart';
import 'ui/settings_page.dart';
import 'ui/store_list_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = await AppSettings.load();
  runApp(KeenonControlApp(controller: AppController(settings)));
}

class KeenonControlApp extends StatelessWidget {
  const KeenonControlApp({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      controller: controller,
      child: MaterialApp(
        title: 'Keenon 관제',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorSchemeSeed: const Color(0xFF1F4E99),
          useMaterial3: true,
        ),
        home: const _Home(),
      ),
    );
  }
}

class _Home extends StatelessWidget {
  const _Home();

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return app.settings.isConfigured ? const StoreListPage() : const SettingsPage(firstRun: true);
  }
}
