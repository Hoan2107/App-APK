import 'package:flutter/material.dart';

import 'pages/history_page.dart';
import 'pages/home_page.dart';
import 'pages/templates_page.dart';
import 'store.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  appState.init();
  runApp(const SmsToolApp());
}

class SmsToolApp extends StatelessWidget {
  const SmsToolApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF00897B);
    return MaterialApp(
      title: 'SMS Tool',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: seed),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme:
            ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark),
        useMaterial3: true,
      ),
      home: const Shell(),
    );
  }
}

/// Khung chính: menu bên trái chuyển giữa 3 trang.
class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  int _page = 0;

  void _openMenu() => _scaffoldKey.currentState?.openDrawer();
  void _goHome() => setState(() => _page = 0);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return PopScope(
      canPop: _page == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _goHome();
      },
      child: Scaffold(
        key: _scaffoldKey,
        drawer: NavigationDrawer(
          selectedIndex: _page,
          onDestinationSelected: (i) {
            Navigator.pop(context);
            setState(() => _page = i);
          },
          children: [
            Container(
              margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF00BFA5), Color(0xFF00695C)],
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Row(
                children: [
                  Icon(Icons.sms_rounded, color: Colors.white, size: 34),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('SMS Tool',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w800)),
                        Text('Gửi tin hàng loạt',
                            style: TextStyle(
                                color: Colors.white70, fontSize: 12.5)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const NavigationDrawerDestination(
              icon: Icon(Icons.dashboard_outlined),
              selectedIcon: Icon(Icons.dashboard_rounded),
              label: Text('Tổng quan & gửi tin'),
            ),
            const NavigationDrawerDestination(
              icon: Icon(Icons.article_outlined),
              selectedIcon: Icon(Icons.article_rounded),
              label: Text('Mẫu tin nhắn'),
            ),
            const NavigationDrawerDestination(
              icon: Icon(Icons.history_outlined),
              selectedIcon: Icon(Icons.history_rounded),
              label: Text('Lịch sử gửi'),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 16, 28, 8),
              child: Text(
                'Danh sách và lịch sử được lưu trong máy, '
                'mở lại app vẫn còn.',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: cs.outline),
              ),
            ),
          ],
        ),
        body: ListenableBuilder(
          listenable: appState,
          builder: (context, _) {
            if (!appState.loaded) {
              return const Center(child: CircularProgressIndicator());
            }
            return IndexedStack(
              index: _page,
              children: [
                HomePage(onMenu: _openMenu),
                TemplatesPage(onMenu: _openMenu, onGoHome: _goHome),
                HistoryPage(onMenu: _openMenu, onGoHome: _goHome),
              ],
            );
          },
        ),
      ),
    );
  }
}
