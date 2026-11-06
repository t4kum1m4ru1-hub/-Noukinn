# Handoff Report: Toolchain & Workspace Configuration (Milestone 1)

**Agent**: `explorer_m1_3` (Toolchain Build Explorer)  
**Date**: 2026-11-06  
**Target Workspace**: `c:\Users\taqmi\02_development\original_program\button_controll_test`  

---

## 1. Observation

### 1.1 Current Workspace State
- Workspace root directory contains exclusively `.agents/`:
  ```powershell
  Get-ChildItem -Force
  # Directory: C:\Users\taqmi\02_development\original_program\button_controll_test
  # Mode: d----- Name: .agents
  ```
- No Flutter scaffolding files exist (`pubspec.yaml`, `lib/`, `test/`, `android/`, `ios/` are absent).

### 1.2 Toolchain & Environment Diagnostics
- Active Flutter SDK:
  ```
  Flutter 3.47.9 • channel stable • https://github.com/flutter/flutter.git
  Tools • Dart 3.13.7 • DevTools 2.60.0
  Path: C:\Users\taqmi\06_一時保管\flutter
  ```
- Active OS / Shell: Windows 11 (26H2), PowerShell, default console code page `932` (Shift-JIS).

### 1.3 Critical Toolchain Finding: Impellerc Multi-byte Include Crash
- When running vanilla `flutter test` without arguments on this host environment, the Flutter test asset builder invokes `impellerc.exe` to compile Material design shaders (`ink_sparkle.frag`, `stretch_effect.frag`).
- Verbatim error observed:
  ```
  impellerc failure: Compilation failed for target: RuntimeStageVulkan
  "C:\Users\taqmi\06_ꎞۊ\flutter\packages\flutter\lib\src\material\shaders\ink_sparkle.frag": GLSL to SPIRV failed; Compilation error. 3 error(s) and 15 warning(s).
  C:\Users\taqmi\06_一時保管\flutter\packages\flutter\lib\src\material\shaders\ink_sparkle.frag:9: error: '#include' : Included file not found. for header name: flutter/runtime_effect.glsl
  ShaderCompilerException: Shader compilation of "C:\Users\taqmi\06_一時保管\flutter\packages\flutter\lib\src\material\shaders\ink_sparkle.frag" failed with exit code 1.
  ```
- **Root Cause**: The Flutter SDK path contains multi-byte characters (`06_一時保管`). Under Windows console code page 932, `impellerc`'s `#include` path resolution corrupts the multi-byte string into `06_ꎞۊ`, causing shader compilation to fail before any test starts.
- **Experimental Verification**:
  1. Running `flutter test --no-test-assets` completely bypasses shader asset compilation and executes tests with exit code 0.
  2. Setting the Flutter theme splash factory to `InkRipple.splashFactory` (e.g. `ThemeData.dark().copyWith(splashFactory: InkRipple.splashFactory)`) ensures widget tests do not attempt to dynamically load `shaders/ink_sparkle.frag` at runtime.

### 1.4 Dependency Compatibility Probe
- Probed `flutter pub get` with `flutter_tts: ^4.2.5`, `sdk: ^3.13.7`, `flutter_test`, and `flutter_lints: ^6.0.0`:
  ```
  + flutter_tts 4.2.5
  + flutter_lints 6.0.0
  + cupertino_icons 1.0.9
  ExitCode: 0
  ```
  Dependencies resolve and install with zero conflicts.

---

## 2. Logic Chain

1. **Scaffold Initialization**:
   - Because the project has no scaffold, running:
     ```powershell
     flutter create . --project-name button_controll_test --platforms android,ios
     ```
     generates standard Flutter metadata (`android/`, `ios/`, `lib/main.dart`, `test/widget_test.dart`, `.gitignore`, `analysis_options.yaml`) directly in place.
   - Flutter's repair/create logic will NOT delete or alter `.agents/` because `.agents/` is an unrecognized path ignored by the tool.

2. **Package Configuration (`pubspec.yaml`)**:
   - The user specification mandates:
     - Project name: `button_controll_test`
     - Dart SDK constraint: `^3.13.7`
     - Dependency: `flutter_tts: ^4.2.5`
     - Dev dependencies: `flutter_test: sdk: flutter`, `flutter_lints: ^6.0.0`
     - Flutter material design enabled: `uses-material-design: true`
   - These settings are standard, fully satisfied by the cached local pub packages, and verified to resolve cleanly.

3. **Android 11+ Package Visibility (`AndroidManifest.xml`)**:
   - Android API Level 30+ enforces package visibility restrictions.
   - The Text-To-Speech engine runs as an external system service (`android.intent.action.TTS_SERVICE`).
   - Without an explicit `<queries>` entry, `flutter_tts` cannot query or bind to the engine on Android 11+ devices.
   - The generated `android/app/src/main/AndroidManifest.xml` already contains a `<queries>` block for text processing:
     ```xml
     <queries>
         <intent>
             <action android:name="android.intent.action.PROCESS_TEXT"/>
             <data android:mimeType="text/plain"/>
         </intent>
     </queries>
     ```
   - Adding the TTS intent to this block satisfies platform security and preserves existing intent declarations.

4. **Test Execution Stability**:
   - Headless unit/widget tests (`flutter test`) do not require compiled Vulkan shader assets for testing hardware key event listeners and UI text rendering.
   - Using `flutter test --no-test-assets` guarantees complete immunity from the host Windows path encoding bug in `impellerc.exe`.
   - In `lib/main.dart`, setting `splashFactory: InkRipple.splashFactory` on the dark theme avoids runtime lookups of `ink_sparkle.frag`.

---

## 3. Caveats

1. **Host Environment Path**:
   - The Flutter SDK installation path `C:\Users\taqmi\06_一時保管\flutter` is fixed on the user's workstation. Do not attempt to move or rename the user's directory.
2. **Headless Execution Only in CI/Automated Tests**:
   - `flutter test` runs in a mock headless environment. Native hardware key events and native TTS audio synthesis are tested through abstractions (`FakeTtsService` and `WidgetTester.sendKeyEvent`).
3. **Android Build Prerequisite**:
   - `flutter doctor` noted that Android Studio command-line tools are unconfigured. This affects native APK packaging (`flutter build apk`), but does NOT affect `flutter pub get`, `flutter test`, or `flutter analyze`.

---

## 4. Conclusion

### 4.1 Step 1: Scaffold Initialization Command
Execute in workspace root `c:\Users\taqmi\02_development\original_program\button_controll_test`:
```powershell
flutter create . --project-name button_controll_test --platforms android,ios
```

### 4.2 Step 2: Exact `pubspec.yaml` Content
Replace the generated `pubspec.yaml` with the following authoritative configuration:
```yaml
name: button_controll_test
description: "A minimal cross-platform Flutter physical button and media key verification app."
publish_to: 'none'
version: 1.0.0+1

environment:
  sdk: ^3.13.7

dependencies:
  flutter:
    sdk: flutter
  flutter_tts: ^4.2.5
  cupertino_icons: ^1.0.8

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^6.0.0

flutter:
  uses-material-design: true
```

### 4.3 Step 3: Exact `android/app/src/main/AndroidManifest.xml` Configuration
Ensure the `<queries>` element inside `android/app/src/main/AndroidManifest.xml` includes the TTS service intent:
```xml
    <queries>
        <intent>
            <action android:name="android.intent.action.PROCESS_TEXT"/>
            <data android:mimeType="text/plain"/>
        </intent>
        <intent>
            <action android:name="android.intent.action.TTS_SERVICE" />
        </intent>
    </queries>
```

### 4.4 Step 4: Theme Configuration Recommendation for `lib/main.dart`
Configure the app theme with `InkRipple.splashFactory` to avoid Material 3 shader asset dependencies:
```dart
MaterialApp(
  theme: ThemeData.dark().copyWith(
    splashFactory: InkRipple.splashFactory,
  ),
  home: const VerificationScreen(),
)
```

---

## 5. Verification Method

Once the implementer executes the steps:

1. **Verify Scaffold & Config**:
   ```powershell
   Test-Path pubspec.yaml, android/app/src/main/AndroidManifest.xml, lib/main.dart, test/widget_test.dart
   # Expected output: True, True, True, True
   ```

2. **Verify Dependencies Resolution**:
   ```powershell
   flutter pub get
   # Expected: Exit code 0, all dependencies resolved
   ```

3. **Verify Static Analysis**:
   ```powershell
   flutter analyze
   # Expected: No issues found!
   ```

4. **Verify Automated Tests**:
   ```powershell
   flutter test --no-test-assets
   # Expected: All tests passed! (Zero shader compilation issues)
   ```

5. **Invalidation Conditions**:
   - If `flutter test` without `--no-test-assets` fails with `impellerc failure: Compilation failed for target: RuntimeStageVulkan`, append `--no-test-assets` to the test command.
   - If `flutter test` throws `Exception: Asset 'shaders/ink_sparkle.frag' not found`, ensure `splashFactory: InkRipple.splashFactory` is configured on the `ThemeData`.
   - If `flutter test` throws `MissingPluginException` for `flutter_tts`, verify that tests use `FakeTtsService` instead of directly calling native channels.
