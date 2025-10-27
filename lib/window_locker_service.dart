// Smart Window Locker core logic implemented with Win32 FFI.
// Note: This is a best-effort port of the Python logic to Dart.

import 'dart:async';
import 'dart:collection';
import 'dart:ffi';
import 'dart:io' show Platform;

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart' as win;

class WindowInfo {
  final int hwnd;
  final String title;
  final String processName;
  final int left;
  final int top;
  final int right;
  final int bottom;
  final bool isVisible;
  final bool isMinimized;
  final bool isMaximized;

  WindowInfo({
    required this.hwnd,
    required this.title,
    required this.processName,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
    required this.isVisible,
    required this.isMinimized,
    required this.isMaximized,
  });

  int get width => right - left;
  int get height => bottom - top;

  @override
  String toString() =>
      '[$processName] $title @ ($left,$top)-($right,$bottom) v:$isVisible min:$isMinimized max:$isMaximized';
}

class RelativeWindowInfo {
  final int hwnd;
  final String title;
  final String processName;
  final double relCenterX;
  final double relCenterY;
  final double relWidth;
  final double relHeight;
  final int monitorIndex; // Only primary (0) is currently used

  const RelativeWindowInfo({
    required this.hwnd,
    required this.title,
    required this.processName,
    required this.relCenterX,
    required this.relCenterY,
    required this.relWidth,
    required this.relHeight,
    required this.monitorIndex,
  });
}

class WindowLockerService {
  // Config
  final Duration checkInterval = const Duration(milliseconds: 50);

  // State
  final Map<String, RelativeWindowInfo> _locked = HashMap();
  bool _monitoring = false;
  Timer? _timer;
  bool _autoLockEnabled = false;
  bool _isMousePressed = false;
  bool _isCurrentlyLocked = false;

  String _windowKey(WindowInfo w) => '${w.processName}:${w.title}';

  void dispose() {
    _timer?.cancel();
  }

  Future<int> autoLockOn() async {
    final count = captureWindows();
    if (count > 0) {
      _autoLockEnabled = true;
      _startMonitoring();
    }
    return count;
  }

  void autoLockOff() {
    _autoLockEnabled = false;
    _isCurrentlyLocked = false;
    _stopMonitoring();
  }

  int captureWindows() {
    final windows = _getAllWindows();
    _locked.clear();

    for (final w in windows) {
      // Filters similar to Python version
      if (w.isMinimized) continue;
      if (w.width < 50 || w.height < 50) continue;
      if (w.title.trim().isEmpty) continue;

      final rel = _absoluteToRelative(w);
      _locked[_windowKey(w)] = rel;
    }

    return _locked.length;
  }

  String lockedWindowsInfo() {
    if (_locked.isEmpty) return '没有捕获的窗口';

    final screenW = win.GetSystemMetrics(win.SM_CXSCREEN);
    final screenH = win.GetSystemMetrics(win.SM_CYSCREEN);
    final buf = StringBuffer('已捕获 ${_locked.length} 个窗口的相对位置:(屏幕 ${screenW}x$screenH)\n\n');

    var i = 1;
    for (final rel in _locked.values) {
      buf.writeln(
          '${i++}. ${rel.title} (${rel.processName})\n   中心位置: ${(rel.relCenterX * 100).toStringAsFixed(1)}% x ${(rel.relCenterY * 100).toStringAsFixed(1)}% @ 显示器${rel.monitorIndex + 1}\n   相对大小: ${(rel.relWidth * 100).toStringAsFixed(1)}% x ${(rel.relHeight * 100).toStringAsFixed(1)}%');
    }

    return buf.toString();
  }

  String statusInfo() {
    final lockedCount = _locked.length;
    final mouseState = _isMousePressed ? '按下' : '松开';
    final lockState = _isCurrentlyLocked ? '已锁定' : '已解锁';

    return '🧠 智能窗口锁定器状态:\n\n'
        '🔒 锁定模式: ${_autoLockEnabled ? '自动锁定' : '禁用'}\n'
        '📊 捕获窗口数: $lockedCount\n'
        '🖱️ 鼠标状态: $mouseState\n'
        '🎯 当前状态: $lockState\n'
        '⏱️ 监控间隔: ${checkInterval.inMilliseconds}ms\n'
        '📐 定位模式: 相对位置 (百分比)\n\n'
        '🧠 智能功能:\n'
        '- 🖱️ 鼠标按下时自动解锁 (可拖拽)\n'
        '- 🔒 鼠标松开时重新捕获中心位置并锁定\n'
        '- 📐 基于窗口中心的相对定位 (可为负值)\n'
        '- 🎯 拖拽到哪里就锁定在哪里\n'
        '- ⚡ 超快响应 (50ms检测)\n';
  }

  // Monitoring
  void _startMonitoring() {
    if (_monitoring) return;
    _monitoring = true;
    _timer?.cancel();
    _timer = Timer.periodic(checkInterval, (_) {
      try {
        if (!_autoLockEnabled) return;
        final pressed = _isMouseLeftPressed();
        if (pressed != _isMousePressed) {
          _isMousePressed = pressed;
          if (pressed) {
            _isCurrentlyLocked = false; // unlock on press
          } else {
            _recaptureCurrentPositions(); // on release
            _isCurrentlyLocked = true;
          }
        }
        if (_isCurrentlyLocked && _locked.isNotEmpty) {
          _enforcePositions();
        }
      } catch (_) {
        // Swallow to keep timer running
      }
    });
  }

  void _stopMonitoring() {
    _monitoring = false;
    _timer?.cancel();
    _timer = null;
  }

  // Win32 helpers
  static bool get _isWin32Available => Platform.isWindows;

  bool _isMouseLeftPressed() {
    if (!_isWin32Available) return false;
    final state = win.GetKeyState(win.VK_LBUTTON);
    return state < 0; // negative means pressed
    }

  List<WindowInfo> _getAllWindows() {
    if (!_isWin32Available) return const [];
    _enumResults.clear();
    final proc = Pointer.fromFunction<win.EnumWindowsProc>(_enumWindowsProc, 1);
    win.EnumWindows(proc, 0);
    return List<WindowInfo>.from(_enumResults);
  }

  RelativeWindowInfo _absoluteToRelative(WindowInfo w) {
    // Primary monitor only (for simplicity)
    final screenW = win.GetSystemMetrics(win.SM_CXSCREEN).toDouble();
    final screenH = win.GetSystemMetrics(win.SM_CYSCREEN).toDouble();

    final width = w.width.toDouble();
    final height = w.height.toDouble();
    final centerX = w.left + width / 2.0;
    final centerY = w.top + height / 2.0;

    final relCenterX = centerX / screenW;
    final relCenterY = centerY / screenH;
    final relWidth = (width / screenW).clamp(0.01, double.infinity);
    final relHeight = (height / screenH).clamp(0.01, double.infinity);

    return RelativeWindowInfo(
      hwnd: w.hwnd,
      title: w.title,
      processName: w.processName,
      relCenterX: relCenterX,
      relCenterY: relCenterY,
      relWidth: relWidth,
      relHeight: relHeight,
      monitorIndex: 0,
    );
  }

  List<WindowInfo> _currentWindowsMapOut() => _getAllWindows();

  void _recaptureCurrentPositions() {
    final current = _currentWindowsMapOut();
    final map = {for (final w in current) _windowKey(w): w};
    var updated = 0;
    for (final key in List<String>.from(_locked.keys)) {
      final cw = map[key];
      if (cw == null) continue;
      if (cw.isMinimized) continue;
      _locked[key] = _absoluteToRelative(cw);
      updated++;
    }
    if (updated > 0) {
      // no-op: keep quiet to avoid logs
    }
  }

  void _enforcePositions() {
    final current = _currentWindowsMapOut();
    final map = {for (final w in current) _windowKey(w): w};

    for (final entry in _locked.entries) {
      final key = entry.key;
      final rel = entry.value;
      final cw = map[key];
      if (cw == null) continue;

      final target = _relativeToAbsolute(rel);
      final cur = (cw.left, cw.top, cw.right, cw.bottom);

      const tol = 10;
      if ((cur.$1 - target.$1).abs() > tol ||
          (cur.$2 - target.$2).abs() > tol ||
          (cur.$3 - target.$3).abs() > tol ||
          (cur.$4 - target.$4).abs() > tol) {
        final width = target.$3 - target.$1;
        final height = target.$4 - target.$2;
        _setWindowPosition(cw.hwnd, target.$1, target.$2, width, height);

        // Ensure visibility without activation
        win.ShowWindow(cw.hwnd, win.SW_SHOWNA);
      }
    }
  }

  (int, int, int, int) _relativeToAbsolute(RelativeWindowInfo rel) {
    final screenW = win.GetSystemMetrics(win.SM_CXSCREEN);
    final screenH = win.GetSystemMetrics(win.SM_CYSCREEN);

    final absW = (rel.relWidth * screenW).toInt();
    final absH = (rel.relHeight * screenH).toInt();

    final centerX = (rel.relCenterX * screenW).toInt();
    final centerY = (rel.relCenterY * screenH).toInt();

    final left = centerX - absW ~/ 2;
    final top = centerY - absH ~/ 2;

    return (left, top, left + absW, top + absH);
  }

  bool _setWindowPosition(int hwnd, int x, int y, int width, int height) {
    if (!_isWin32Available) return false;
    final ok = win.SetWindowPos(
      hwnd,
      win.HWND_TOP,
      x,
      y,
      width,
      height,
      win.SWP_SHOWWINDOW,
    );
    return ok != 0;
  }
}

String _basename(String fullPath) {
  var path = fullPath.replaceAll('\\\\', '\\');
  final idx = path.lastIndexOf('\\');
  if (idx == -1) return path;
  return path.substring(idx + 1);
}

// =============================
// Top-level callback for EnumWindows (must be static/top-level for FFI)
// =============================

final List<WindowInfo> _enumResults = <WindowInfo>[];

int _enumWindowsProc(int hWnd, int lParam) {
  try {
    if (win.IsWindowVisible(hWnd) == 0) return 1; // continue

    // Title
    final length = win.GetWindowTextLength(hWnd);
    final titlePtr = calloc<Uint16>(length + 1).cast<Utf16>();
    win.GetWindowText(hWnd, titlePtr, length + 1);
    final title = titlePtr.toDartString();
    calloc.free(titlePtr);

    if (title.isEmpty) return 1; // skip untitled windows

    // Rect
    final rect = calloc<win.RECT>();
    win.GetWindowRect(hWnd, rect);

    // Placement
    final placement = calloc<win.WINDOWPLACEMENT>();
    placement.ref.length = sizeOf<win.WINDOWPLACEMENT>();
    win.GetWindowPlacement(hWnd, placement);
    final isMin = placement.ref.showCmd == win.SW_SHOWMINIMIZED;
    final isMax = placement.ref.showCmd == win.SW_SHOWMAXIMIZED;

    // Process name
    final pidPtr = calloc<Uint32>();
    win.GetWindowThreadProcessId(hWnd, pidPtr);
    final pid = pidPtr.value;
    calloc.free(pidPtr);

    String processName = 'Unknown';
    final hProcess = win.OpenProcess(
      win.PROCESS_QUERY_LIMITED_INFORMATION,
      0,
      pid,
    );
    if (hProcess != 0) {
      final sizePtr = calloc<Uint32>();
      sizePtr.value = 260;
      final buffer = calloc<Uint16>(sizePtr.value).cast<Utf16>();
      final ok = win.QueryFullProcessImageName(hProcess, 0, buffer, sizePtr);
      if (ok != 0) {
        final fullPath = buffer.toDartString();
        processName = _basename(fullPath);
      }
      calloc.free(buffer);
      calloc.free(sizePtr);
      win.CloseHandle(hProcess);
    }

    _enumResults.add(
      WindowInfo(
        hwnd: hWnd,
        title: title,
        processName: processName,
        left: rect.ref.left,
        top: rect.ref.top,
        right: rect.ref.right,
        bottom: rect.ref.bottom,
        isVisible: win.IsWindowVisible(hWnd) != 0,
        isMinimized: isMin,
        isMaximized: isMax,
      ),
    );

    calloc.free(rect);
    calloc.free(placement);
  } catch (_) {
    // ignore errors for individual windows
  }
  return 1; // continue enumeration
}
