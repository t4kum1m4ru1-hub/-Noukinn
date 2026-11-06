# Handoff Report — explorer_m1_1 (Core Implementation Explorer)

**Agent**: `explorer_m1_1`  
**Milestone**: Milestone 1 (Workspace & Core Implementation)  
**Date**: 2026-11-05T23:46:00Z  
**Target File**: `lib/main.dart` (Specification & Proposed Implementation)  
**Proposed Code Artifact**: `c:\Users\taqmi\02_development\original_program\button_controll_test\.agents\teamwork\explorer_m1_1\proposed_main.dart`

---

## 1. Observation

1. **User Requirements (`ORIGINAL_REQUEST.md`)**:
   - **R1 (Key Detection)**: Capture physical buttons and earphone media keys across Android and iOS via `flutter/services`:
     - Volume Up (`KEYCODE_VOLUME_UP`)
     - Volume Down (`KEYCODE_VOLUME_DOWN`)
     - Play / Pause (`KEYCODE_MEDIA_PLAY_PAUSE` or `KEYCODE_MEDIA_PLAY` / `KEYCODE_MEDIA_PAUSE`)
     - Next Track (`KEYCODE_MEDIA_NEXT`)
     - Previous Track (`KEYCODE_MEDIA_PREVIOUS`)
   - **R2 (Immediate Audio Feedback)**: Immediately speak confirmation phrase in Japanese via `flutter_tts`:
     - Volume Up: `"音量アップを受信しました"`
     - Volume Down: `"音量ダウンを受信しました"`
     - Play / Pause: `"再生・停止ボタンが押されました"`
     - Next Track: `"次の曲ボタンを受信しました"`
     - Previous Track: `"前の曲ボタンを受信しました"`
   - **R3 (Dark-Mode Verification UI)**:
     - Center display: Large key name text (`KEYCODE_VOLUME_UP`, etc.) and speech description.
     - Bottom display: Real-time scrollable log with timestamps (`[HH:mm:ss.SSS] KEYCODE_...`).
   - **R4 (Standalone Deliverable & Documentation)**:
     - Self-contained `lib/main.dart` runnable without external internal modules.
     - Explicit comments at the top documenting `pubspec.yaml` packages (`flutter_tts: ^4.2.5`) and platform configuration.

2. **Flutter Framework SDK Key Constants (`C:\Users\taqmi\06_一時保管\flutter\packages\flutter\lib\src\services\keyboard_key.g.dart`)**:
   - Volume Up:
     - `LogicalKeyboardKey.audioVolumeUp = LogicalKeyboardKey(0x00100000a10);` (line 1375)
     - `PhysicalKeyboardKey.audioVolumeUp = PhysicalKeyboardKey(0x00070080);` (line 4486)
   - Volume Down:
     - `LogicalKeyboardKey.audioVolumeDown = LogicalKeyboardKey(0x00100000a0f);` (line 1370)
     - `PhysicalKeyboardKey.audioVolumeDown = PhysicalKeyboardKey(0x00070081);` (line 4492)
   - Media Play/Pause & Variants:
     - `LogicalKeyboardKey.mediaPlayPause = LogicalKeyboardKey(0x00100000a05);` (line 1325)
     - `LogicalKeyboardKey.mediaPlay = LogicalKeyboardKey(0x00100000d2f);` (line 1725)
     - `LogicalKeyboardKey.mediaPause = LogicalKeyboardKey(0x00100000d2e);` (line 1720)
     - `LogicalKeyboardKey.select = LogicalKeyboardKey(0x0010000050c);` (line 930)
     - `PhysicalKeyboardKey.mediaPlayPause = PhysicalKeyboardKey(0x000c00cd);` (line 4817)
     - `PhysicalKeyboardKey.mediaPlay = PhysicalKeyboardKey(0x000c00b0);` (line 4807)
     - `PhysicalKeyboardKey.mediaPause = PhysicalKeyboardKey(0x000c00b1);` (line 4811)
   - Media Track Next:
     - `LogicalKeyboardKey.mediaTrackNext = LogicalKeyboardKey(0x00100000a08);` (line 1335)
     - `PhysicalKeyboardKey.mediaTrackNext = PhysicalKeyboardKey(0x000c00b5);` (line 4795)
   - Media Track Previous:
     - `LogicalKeyboardKey.mediaTrackPrevious = LogicalKeyboardKey(0x00100000a09);` (line 1340)
     - `PhysicalKeyboardKey.mediaTrackPrevious = PhysicalKeyboardKey(0x000c00b6);` (line 4801)

3. **Global Event Listener API (`hardware_keyboard.dart`)**:
   - Handler registration: `HardwareKeyboard.instance.addHandler(bool Function(KeyEvent) handler)` (line 570).
   - Handler deregistration: `HardwareKeyboard.instance.removeHandler(handler)` (line 588).
   - Deprecation observation: `RawKeyboardListener` is deprecated after Flutter v3.18. `HardwareKeyboard` is the modern, non-deprecated, binding-level listener.
   - Event types: `KeyDownEvent`, `KeyRepeatEvent`, `KeyUpEvent`. Filtering `event is! KeyDownEvent` prevents double logging and duplicate audio output.

4. **TTS Plugin & Testing Constraints**:
   - `flutter_tts: ^4.2.5` uses native `MethodChannel('flutter_tts')`.
   - Running `flutter test` in headless environments throws `MissingPluginException` if raw `FlutterTts` is invoked.
   - iOS audio session requires category `playback` with Bluetooth options (`allowBluetooth`, `allowBluetoothA2DP`, `mixWithOthers`, `defaultToSpeaker`) and `setSharedInstance(true)`.
   - Android 11+ requires `<queries>` declaration for `android.intent.action.TTS_SERVICE`.

---

## 2. Logic Chain

1. **TTS Service Decoupling (Addressing Observation 4 & Requirement R4)**:
   - Defining `abstract class TtsService` in `lib/main.dart` with methods `initialize()`, `speak(String text)`, and `stop()`.
   - `FlutterTtsService implements TtsService` provides the production implementation using `flutter_tts`, configuring Japanese voice (`ja-JP`), speech rate `0.5`, volume `1.0`, and iOS audio category session flags.
   - `FakeTtsService implements TtsService` provides an in-memory test fake capturing `spokenHistory` and `lastSpoken` without calling native platform channels.
   - `ButtonControlApp` takes an optional `TtsService? ttsService` constructor argument, defaulting to `FlutterTtsService()`.
   - Result: Running `main()` operates full native TTS, while headless `flutter test` injects `FakeTtsService` for instant, 100% deterministic testing without external mocking dependencies or code generation.

2. **ButtonAction Mapping Model (Addressing Observations 1 & 2)**:
   - Enum `ButtonAction` models the 5 target actions:
     - `volumeUp`: `KEYCODE_VOLUME_UP`, "音量アップを受信しました", `Icons.volume_up`
     - `volumeDown`: `KEYCODE_VOLUME_DOWN`, "音量ダウンを受信しました", `Icons.volume_down`
     - `mediaPlayPause`: `KEYCODE_MEDIA_PLAY_PAUSE`, "再生・停止ボタンが押されました", `Icons.play_circle_filled`
     - `mediaNext`: `KEYCODE_MEDIA_NEXT`, "次の曲ボタンを受信しました", `Icons.skip_next`
     - `mediaPrevious`: `KEYCODE_MEDIA_PREVIOUS`, "前の曲ボタンを受信しました", `Icons.skip_previous`
   - Resolution function `ButtonAction.fromKeyEvent(KeyEvent event)` checks `fromLogicalKey` first, then falls back to `fromPhysicalKey`.
   - Discrete Play (`LogicalKeyboardKey.mediaPlay`), Pause (`LogicalKeyboardKey.mediaPause`), and headset select (`LogicalKeyboardKey.select` / `LogicalKeyboardKey.mediaSelect`) map to `ButtonAction.mediaPlayPause`, providing robust interoperability across diverse vendor headsets.

3. **Event Filtering & Lifecycle Cleanup (Addressing Observation 3)**:
   - In `_ButtonControlScreenState.initState()`, `HardwareKeyboard.instance.addHandler(_handleKeyEvent)` registers the callback.
   - In `dispose()`, `HardwareKeyboard.instance.removeHandler(_handleKeyEvent)`, `_scrollController.dispose()`, and `widget.ttsService.stop()` clean up all resources.
   - In `_handleKeyEvent`:
     ```dart
     if (event is! KeyDownEvent) return false;
     ```
     This strictly ignores `KeyUpEvent` and `KeyRepeatEvent`.
   - Returning `true` signals that the event was handled by Flutter; returning `false` preserves default propagation for unhandled keys (like Back or alphanumeric keys).

4. **Defensive Error Handling (Addressing Observation 4)**:
   - All calls to `_flutterTts` (`setLanguage`, `speak`, `stop`) are wrapped in `try { ... } catch (e) { debugPrint(...) }`.
   - If a device lacks an installed Japanese TTS voice or encounters an audio focus conflict, the application UI continues to update and logs continue to record without crashing.
   - Calling `_flutterTts.stop()` immediately prior to `_flutterTts.speak(text)` cancels any ongoing utterance, ensuring rapid button presses provide immediate low-latency feedback.
   - `WidgetsBinding.instance.addPostFrameCallback` checks `if (!mounted) return;` before calling `_scrollController.animateTo` to prevent unmounted setState or scroll controller errors.

5. **Dark-Mode Verification UI (Addressing Requirement R3)**:
   - `ThemeData.dark()` with background `0xFF121212` and card surface `0xFF1E1E1E`.
   - Upper section (flex: 5):
     - Idle state: Displays `Icons.touch_app_outlined`, "ボタンを押してください", and prompt text.
     - Active state: Displays action icon (teal accent), large bold key name (`fontSize: 32`, `Key('center_key_name')`), Japanese speech readout, and timestamp (`Key('center_timestamp')`).
   - Divider (`0xFF333333`).
   - Bottom header: Displays total log count (`Key('log_header_count')`) and clear log button (`Key('log_header_clear')`).
   - Bottom section (flex: 5):
     - Empty state: "ログはありません" (`Key('empty_log_message')`).
     - Populated state: Auto-scrolling `ListView.builder` (`Key('log_list_view')`) with monospace timestamp `[HH:mm:ss.SSS]` and key name.

---

## 3. Caveats

1. **Android Physical Volume Buttons vs Headset Buttons**:
   - On physical Android devices, side rocker volume buttons are handled by Android's audio system. In headless automated tests (`WidgetTester.sendKeyEvent`), events bypass native drivers and are captured cleanly. For real-device testing, earphone media buttons send standard HID keycodes directly to Flutter, while side volume keys may trigger the Android volume HUD unless explicitly intercepted at the native activity level.
2. **iOS Physical Side Volume Rocker**:
   - On physical iOS hardware, side volume buttons do not emit `UIKey` events to apps (Apple restricts them to CoreAudio/AVAudioSession). Bluetooth and wired earphone remote buttons send remote command events. In automated tests (`flutter test`), `tester.sendKeyEvent` simulates the Flutter framework event pipeline deterministically.
3. **No External Package Mock Generators Needed**:
   - By embedding `FakeTtsService` directly into `lib/main.dart`, the project eliminates any dependency on `mockito`, `mocktail`, or `build_runner`, keeping the application 100% self-contained as specified in R4.

---

## 4. Conclusion & Complete Implementation Specification

The proposed implementation has been saved to:
`c:\Users\taqmi\02_development\original_program\button_controll_test\.agents\teamwork\explorer_m1_1\proposed_main.dart`

### Complete Code for `lib/main.dart`

```dart
// ============================================================================
// Button Control Verification Application
// ============================================================================
//
// DEPENDENCIES:
// Add the following dependencies to your pubspec.yaml:
//
// dependencies:
//   flutter:
//     sdk: flutter
//   flutter_tts: ^4.2.5
//
// dev_dependencies:
//   flutter_test:
//     sdk: flutter
//   flutter_lints: ^5.0.0
//
// PLATFORM CONFIGURATION:
// 1. Android Configuration (Android 11+ / API 30+ Package Visibility):
//    Add the following <queries> element inside <manifest> (outside <application>)
//    in android/app/src/main/AndroidManifest.xml:
//
//    <queries>
//        <intent>
//            <action android:name="android.intent.action.TTS_SERVICE" />
//        </intent>
//    </queries>
//
// 2. iOS Configuration (Audio Session & Silent Mode Playback):
//    Handled programmatically in FlutterTtsService.initialize() via AVAudioSession:
//    - setSharedInstance(true)
//    - setIosAudioCategory(playback, [allowBluetooth, allowBluetoothA2DP, mixWithOthers, defaultToSpeaker])
//
// 3. Automated Test Dependency Decoupling:
//    The application uses an abstract TtsService interface.
//    In production: FlutterTtsService connects to native TTS engines via flutter_tts.
//    In automated widget tests: FakeTtsService is injected into ButtonControlApp(ttsService: fakeTts)
//    to enable headless testing without MissingPluginException.
// ============================================================================

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ButtonControlApp());
}

// ----------------------------------------------------------------------------
// 1. TTS Abstraction Layer
// ----------------------------------------------------------------------------

/// Abstract interface for Text-To-Speech audio feedback.
abstract class TtsService {
  Future<void> initialize();
  Future<void> speak(String text);
  Future<void> stop();
}

/// Production implementation of [TtsService] utilizing the [FlutterTts] plugin.
/// Includes defensive try/catch error handling around native channel invocations.
class FlutterTtsService implements TtsService {
  final FlutterTts _flutterTts;
  bool _isInitialized = false;

  FlutterTtsService({FlutterTts? tts}) : _flutterTts = tts ?? FlutterTts();

  @override
  Future<void> initialize() async {
    if (_isInitialized) return;
    try {
      await _flutterTts.setLanguage("ja-JP");
      await _flutterTts.setSpeechRate(0.5);
      await _flutterTts.setVolume(1.0);
      await _flutterTts.setPitch(1.0);
      await _flutterTts.awaitSpeakCompletion(true);

      if (defaultTargetPlatform == TargetPlatform.iOS) {
        await _flutterTts.setSharedInstance(true);
        await _flutterTts.setIosAudioCategory(
          IosTextToSpeechAudioCategory.playback,
          [
            IosTextToSpeechAudioCategoryOptions.allowBluetooth,
            IosTextToSpeechAudioCategoryOptions.allowBluetoothA2DP,
            IosTextToSpeechAudioCategoryOptions.mixWithOthers,
            IosTextToSpeechAudioCategoryOptions.defaultToSpeaker,
          ],
        );
      }
      _isInitialized = true;
    } catch (e) {
      debugPrint("FlutterTtsService.initialize error: $e");
    }
  }

  @override
  Future<void> speak(String text) async {
    try {
      if (!_isInitialized) {
        await initialize();
      }
      // Interrupt ongoing utterance immediately for low-latency tactile feedback
      await _flutterTts.stop();
      await _flutterTts.speak(text);
    } catch (e) {
      debugPrint("FlutterTtsService.speak error: $e");
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _flutterTts.stop();
    } catch (e) {
      debugPrint("FlutterTtsService.stop error: $e");
    }
  }
}

/// In-memory test fake implementation of [TtsService] for headless widget tests.
/// Eliminates native platform channel dependencies while recording spoken phrases.
class FakeTtsService implements TtsService {
  final List<String> spokenHistory = [];
  bool isInitialized = false;

  String? get lastSpoken => spokenHistory.isNotEmpty ? spokenHistory.last : null;
  int get speakCount => spokenHistory.length;

  @override
  Future<void> initialize() async {
    isInitialized = true;
  }

  @override
  Future<void> speak(String text) async {
    if (!isInitialized) {
      await initialize();
    }
    spokenHistory.add(text);
  }

  @override
  Future<void> stop() async {
    // No-op for test fake
  }

  void clear() {
    spokenHistory.clear();
  }
}

// ----------------------------------------------------------------------------
// 2. Action & Log Domain Models
// ----------------------------------------------------------------------------

/// Standardized action definitions for target physical and earphone media buttons.
enum ButtonAction {
  volumeUp(
    keyName: 'KEYCODE_VOLUME_UP',
    displayLabel: 'Volume Up',
    speechText: '音量アップを受信しました',
    icon: Icons.volume_up,
  ),
  volumeDown(
    keyName: 'KEYCODE_VOLUME_DOWN',
    displayLabel: 'Volume Down',
    speechText: '音量ダウンを受信しました',
    icon: Icons.volume_down,
  ),
  mediaPlayPause(
    keyName: 'KEYCODE_MEDIA_PLAY_PAUSE',
    displayLabel: 'Play / Pause',
    speechText: '再生・停止ボタンが押されました',
    icon: Icons.play_circle_filled,
  ),
  mediaNext(
    keyName: 'KEYCODE_MEDIA_NEXT',
    displayLabel: 'Next Track',
    speechText: '次の曲ボタンを受信しました',
    icon: Icons.skip_next,
  ),
  mediaPrevious(
    keyName: 'KEYCODE_MEDIA_PREVIOUS',
    displayLabel: 'Previous Track',
    speechText: '前の曲ボタンを受信しました',
    icon: Icons.skip_previous,
  );

  final String keyName;
  final String displayLabel;
  final String speechText;
  final IconData icon;

  const ButtonAction({
    required this.keyName,
    required this.displayLabel,
    required this.speechText,
    required this.icon,
  });

  /// Maps a [KeyEvent] to a corresponding [ButtonAction].
  /// Matches against [LogicalKeyboardKey] first, then falls back to [PhysicalKeyboardKey].
  static ButtonAction? fromKeyEvent(KeyEvent event) {
    return fromLogicalKey(event.logicalKey) ?? fromPhysicalKey(event.physicalKey);
  }

  /// Maps [LogicalKeyboardKey] to corresponding [ButtonAction].
  static ButtonAction? fromLogicalKey(LogicalKeyboardKey key) {
    if (key == LogicalKeyboardKey.audioVolumeUp) {
      return ButtonAction.volumeUp;
    }
    if (key == LogicalKeyboardKey.audioVolumeDown) {
      return ButtonAction.volumeDown;
    }
    if (key == LogicalKeyboardKey.mediaPlayPause ||
        key == LogicalKeyboardKey.mediaPlay ||
        key == LogicalKeyboardKey.mediaPause ||
        key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.mediaSelect) {
      return ButtonAction.mediaPlayPause;
    }
    if (key == LogicalKeyboardKey.mediaTrackNext) {
      return ButtonAction.mediaNext;
    }
    if (key == LogicalKeyboardKey.mediaTrackPrevious) {
      return ButtonAction.mediaPrevious;
    }
    return null;
  }

  /// Maps [PhysicalKeyboardKey] to corresponding [ButtonAction] (hardware fallback).
  static ButtonAction? fromPhysicalKey(PhysicalKeyboardKey key) {
    if (key == PhysicalKeyboardKey.audioVolumeUp) {
      return ButtonAction.volumeUp;
    }
    if (key == PhysicalKeyboardKey.audioVolumeDown) {
      return ButtonAction.volumeDown;
    }
    if (key == PhysicalKeyboardKey.mediaPlayPause ||
        key == PhysicalKeyboardKey.mediaPlay ||
        key == PhysicalKeyboardKey.mediaPause ||
        key == PhysicalKeyboardKey.select ||
        key == PhysicalKeyboardKey.mediaSelect) {
      return ButtonAction.mediaPlayPause;
    }
    if (key == PhysicalKeyboardKey.mediaTrackNext) {
      return ButtonAction.mediaNext;
    }
    if (key == PhysicalKeyboardKey.mediaTrackPrevious) {
      return ButtonAction.mediaPrevious;
    }
    return null;
  }
}

/// Pure Dart timestamp formatter: HH:mm:ss.SSS
String formatTimestamp(DateTime dt) {
  final h = dt.hour.toString().padLeft(2, '0');
  final m = dt.minute.toString().padLeft(2, '0');
  final s = dt.second.toString().padLeft(2, '0');
  final ms = dt.millisecond.toString().padLeft(3, '0');
  return '$h:$m:$s.$ms';
}

/// Represents an individual received key event with high-precision timestamp.
class KeyEventLog {
  final DateTime timestamp;
  final ButtonAction action;

  KeyEventLog({required this.timestamp, required this.action});

  String get formattedTime => formatTimestamp(timestamp);
}

// ----------------------------------------------------------------------------
// 3. UI Application & State
// ----------------------------------------------------------------------------

/// Top-level application widget with dark-mode theme configuration.
class ButtonControlApp extends StatelessWidget {
  final TtsService? ttsService;

  const ButtonControlApp({super.key, this.ttsService});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Button Control Test',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF121212),
        colorScheme: const ColorScheme.dark(
          primary: Colors.tealAccent,
          secondary: Colors.amberAccent,
          surface: Color(0xFF1E1E1E),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1E1E1E),
          elevation: 0,
        ),
      ),
      home: ButtonControlScreen(
        ttsService: ttsService ?? FlutterTtsService(),
      ),
    );
  }
}

/// Alias for compatibility with default test templates.
typedef MyApp = ButtonControlApp;

/// Verification screen hosting key interception, center readout, and real-time log.
class ButtonControlScreen extends StatefulWidget {
  final TtsService ttsService;

  const ButtonControlScreen({super.key, required this.ttsService});

  @override
  State<ButtonControlScreen> createState() => _ButtonControlScreenState();
}

class _ButtonControlScreenState extends State<ButtonControlScreen> {
  final List<KeyEventLog> _logs = [];
  final ScrollController _scrollController = ScrollController();
  ButtonAction? _latestAction;
  DateTime? _latestTimestamp;

  @override
  void initState() {
    super.initState();
    widget.ttsService.initialize();
    // Register global hardware key listener
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
  }

  @override
  void dispose() {
    // Clean up hardware keyboard listener and controllers
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    _scrollController.dispose();
    widget.ttsService.stop();
    super.dispose();
  }

  /// Global KeyEvent handler. Filters strictly for KeyDownEvent to prevent duplicate triggers.
  bool _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) {
      return false;
    }

    final action = ButtonAction.fromKeyEvent(event);
    if (action != null) {
      _processAction(action);
      return true; // Mark as handled
    }
    return false; // Allow unhandled keys to propagate normally
  }

  /// Updates UI state, triggers speech synthesis, and auto-scrolls the log.
  void _processAction(ButtonAction action) {
    final now = DateTime.now();
    setState(() {
      _latestAction = action;
      _latestTimestamp = now;
      _logs.add(KeyEventLog(timestamp: now, action: action));
    });

    widget.ttsService.speak(action.speechText);

    // Auto-scroll to latest log entry
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _clearLogs() {
    setState(() {
      _logs.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Button Control Test'),
        centerTitle: true,
        actions: [
          IconButton(
            key: const Key('clear_logs_button'),
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Clear Logs',
            onPressed: _logs.isEmpty ? null : _clearLogs,
          ),
        ],
      ),
      body: Focus(
        autofocus: true,
        child: Column(
          children: [
            // Center large key readout area (flex: 5)
            Expanded(
              flex: 5,
              child: _buildCenterDisplay(),
            ),
            const Divider(height: 1, color: Color(0xFF333333)),
            // Real-time log header
            _buildLogHeader(),
            // Scrollable real-time log list (flex: 5)
            Expanded(
              flex: 5,
              child: _buildLogList(),
            ),
          ],
        ),
      ),
    );
  }

  /// Builds the large central readout for the most recently detected key.
  Widget _buildCenterDisplay() {
    if (_latestAction == null) {
      return Center(
        child: Column(
          key: const Key('waiting_prompt'),
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.touch_app_outlined, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'ボタンを押してください',
              style: TextStyle(
                fontSize: 22,
                color: Colors.grey,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Volume Up/Down または イヤホンボタン',
              style: TextStyle(fontSize: 14, color: Colors.white54),
            ),
          ],
        ),
      );
    }

    final action = _latestAction!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          key: const Key('detected_action_display'),
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(action.icon, size: 64, color: Colors.tealAccent),
            const SizedBox(height: 16),
            Text(
              action.keyName,
              key: const Key('center_key_name'),
              style: const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: Colors.tealAccent,
                letterSpacing: 1.2,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              action.speechText,
              key: const Key('center_speech_text'),
              style: const TextStyle(fontSize: 18, color: Colors.white70),
              textAlign: TextAlign.center,
            ),
            if (_latestTimestamp != null) ...[
              const SizedBox(height: 8),
              Text(
                '受信時刻: ${formatTimestamp(_latestTimestamp!)}',
                key: const Key('center_timestamp'),
                style: const TextStyle(fontSize: 12, color: Colors.white38),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Builds the header bar above the log list showing total event count and clear action.
  Widget _buildLogHeader() {
    return Container(
      color: const Color(0xFF1E1E1E),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'リアルタイムログ (${_logs.length}件)',
            key: const Key('log_header_count'),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          if (_logs.isNotEmpty)
            GestureDetector(
              key: const Key('log_header_clear'),
              onTap: _clearLogs,
              child: const Text(
                'クリア',
                style: TextStyle(color: Colors.tealAccent, fontSize: 13),
              ),
            ),
        ],
      ),
    );
  }

  /// Builds the scrollable list of key event records with timestamps.
  Widget _buildLogList() {
    if (_logs.isEmpty) {
      return const Center(
        child: Text(
          'ログはありません',
          key: Key('empty_log_message'),
          style: TextStyle(color: Colors.white38),
        ),
      );
    }
    return ListView.builder(
      key: const Key('log_list_view'),
      controller: _scrollController,
      itemCount: _logs.length,
      itemBuilder: (context, index) {
        final log = _logs[index];
        return Container(
          key: Key('log_entry_$index'),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Color(0xFF222222))),
          ),
          child: ListTile(
            dense: true,
            leading: Icon(log.action.icon, color: Colors.tealAccent, size: 20),
            title: Text(
              '[${log.formattedTime}] ${log.action.keyName}',
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: Text(
              log.action.speechText,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ),
        );
      },
    );
  }
}
```

---

## 5. Verification Method

1. **Self-Verification Commands**:
   Once workspace scaffolding (`pubspec.yaml`, `flutter pub get`) is established:
   ```powershell
   flutter analyze lib/main.dart
   flutter test test/widget_test.dart
   ```
2. **Key Invalidation Conditions**:
   - Invalidation occurs if `HardwareKeyboard.instance.addHandler` API signature changes.
   - Invalidation occurs if `flutter_tts` changes constructor parameters or method names.
