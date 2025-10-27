import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import 'window_locker_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SmartWindowLockerApp());
}

class SmartWindowLockerApp extends StatelessWidget {
  const SmartWindowLockerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Window Locker',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const HomePage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final locker = WindowLockerService();
  String status = '';
  String windowsInfo = '';
  String systemInfo = '';
  Timer? _uiTimer;

  @override
  void initState() {
    super.initState();
    _refreshAll();

    // Periodically refresh status text while running
    _uiTimer = Timer.periodic(const Duration(milliseconds: 500), (_) async {
      if (!mounted) return;
      setState(() {
        systemInfo = locker.statusInfo();
      });
    });
  }

  @override
  void dispose() {
    _uiTimer?.cancel();
    locker.dispose();
    super.dispose();
  }

  Future<void> _autoLockOn() async {
    final count = await locker.autoLockOn();
    setState(() {
      status = count > 0
          ? '🔒 自动锁定已启用 - 已捕获 $count 个窗口 (中心定位)'
          : '❌ 没有找到可捕获的窗口';
    });
    await _refreshAll();
  }

  Future<void> _autoLockOff() async {
    locker.autoLockOff();
    setState(() {
      status = '🔓 自动锁定已关闭 - 窗口可自由移动';
    });
    await _refreshAll();
  }

  Future<void> _refreshAll() async {
    setState(() {
      windowsInfo = locker.lockedWindowsInfo();
      systemInfo = locker.statusInfo();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('🧠 Smart Window Locker'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _refreshAll,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: !Platform.isWindows
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'This app only runs on Windows (uses Win32 APIs).',
                  style: TextStyle(fontSize: 16),
                ),
              ),
            )
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '鼠标控制自动锁定 + 中心定位 (可为负值)',
                    style: TextStyle(fontSize: 16, color: Colors.black54),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      FilledButton.icon(
                        icon: const Icon(Icons.lock),
                        label: const Text('自动锁定 ON'),
                        onPressed: _autoLockOn,
                      ),
                      FilledButton.tonalIcon(
                        icon: const Icon(Icons.lock_open),
                        label: const Text('自动锁定 OFF'),
                        onPressed: _autoLockOff,
                      ),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.info_outline),
                        label: const Text('刷新信息'),
                        onPressed: _refreshAll,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(status, style: const TextStyle(fontSize: 16)),
                  const SizedBox(height: 12),
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(
                          child: _InfoCard(
                            title: '当前窗口信息',
                            content: windowsInfo,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _InfoCard(
                            title: '系统状态',
                            content: systemInfo,
                          ),
                        ),
                      ],
                    ),
                  )
                ],
              ),
            ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final String title;
  final String content;

  const _InfoCard({required this.title, required this.content});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surface,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const Divider(height: 20),
            Expanded(
              child: SingleChildScrollView(
                child: SelectableText(
                  content.isEmpty ? '—' : content,
                  style: const TextStyle(fontFamily: 'Consolas', fontSize: 13),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
