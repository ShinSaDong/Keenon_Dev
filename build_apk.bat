@echo off
setlocal
cd /d "%~dp0"

echo [1/5] Checking Flutter SDK...
where flutter > nul 2>&1
if errorlevel 1 (
  echo Flutter SDK not found in PATH. Install: https://docs.flutter.dev/get-started/install/windows
  pause
  exit /b 1
)

echo [2/5] Generating android platform files (only if missing)...
if not exist android (
  call flutter create --platforms=android --org kr.robotcontrol --project-name keenon_control .
  if errorlevel 1 goto :fail
)

echo [3/5] Adding INTERNET permission to AndroidManifest.xml...
powershell -NoProfile -ExecutionPolicy Bypass -File tool\add_internet_permission.ps1
if errorlevel 1 goto :fail

echo [4/5] flutter pub get / flutter test...
call flutter pub get
if errorlevel 1 goto :fail
call flutter test
if errorlevel 1 echo (Some tests failed - check the output above. Continuing build.)

echo [5/5] Building release APK...
call flutter build apk --release
if errorlevel 1 goto :fail

echo.
echo DONE: build\app\outputs\flutter-apk\app-release.apk
pause
exit /b 0

:fail
echo Build failed. See the messages above.
pause
exit /b 1
