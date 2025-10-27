## Smart Window Locker (Flutter)

Desktop app for Windows built with Flutter + Material Design. It can capture and auto-lock window positions using Win32 APIs. When you press and hold the left mouse button, windows are unlocked for dragging; on release, positions are re-captured and enforced.

Features:
- Auto lock/unlock based on left mouse button state
- Relative positioning (percentage-based, resolution independent)
- Uses Win32 APIs to enumerate and reposition windows

### Local development

Prerequisites:
- Flutter SDK (stable channel)
- Windows 10/11 with Desktop development tools (VS Build Tools)

Run locally:

```
flutter config --enable-windows-desktop
flutter pub get
flutter create .   # generates missing platform folders if needed
flutter run -d windows
```

### GitHub Actions build (Windows EXE)

This folder includes a workflow at `.github/workflows/build-windows.yml` which:
1) Sets up Flutter
2) Ensures Windows desktop is enabled and platform scaffolding exists
3) Builds a release Windows executable
4) Uploads the entire Windows Release folder as an artifact (portable build)

Download tips:
- Download the artifact `SmartWindowLocker-windows-portable` from the workflow run
- Extract the zip and run the `.exe` inside the extracted folder
- Keep all files together (e.g., `flutter_windows.dll`, `data` folder); do not run the `.exe` alone

### Notes
- Some windows may require elevated permissions to move. If you find that certain apps do not move, try running the built EXE as Administrator.
- This app only runs on Windows (uses Win32 APIs).