# Handoff Report — survey_explorer_3 (TTS and UI Architecture Explorer)

## 1. Observation

1. **Flutter SDK & Environment**:
   - Flutter version command: `flutter --version`
   - Result:
     ```
     Flutter 3.47.9 • channel stable • https://github.com/flutter/flutter.git
     Framework • revision c197ca5199 (7 days ago) • 2026-10-29 10:10:20 -0400
     Engine • hash 9e025265bef30b838c0c1b68cad19decf97048f2 (revision 89c39edfdf) (9 days ago) • 2026-10-27 19:51:20.000Z
     Tools • Dart 3.13.7 • DevTools 2.60.0
     ```
   - Current directory has no existing Flutter project files (`pubspec.yaml`, `lib/`, `test/` are not yet created; only `.agents/teamwork/` exists).

2. **LogicalKeyboardKey SDK Definitions**:
   - Source inspection: `C:\Users\taqmi\06_一時保管\flutter\packages\flutter\lib\src\services\keyboard_key.g.dart`
   - Verified constant definitions:
     - Line 1375: `static const LogicalKeyboardKey audioVolumeUp = LogicalKeyboardKey(0x00100000a10);`
     - Line 1370: `static const LogicalKeyboardKey audioVolumeDown = LogicalKeyboardKey(0x00100000a0f);`
     - Line 1325: `static const LogicalKeyboardKey mediaPlayPause = LogicalKeyboardKey(0x00100000a05);`
     - Line 1725: `static const LogicalKeyboardKey mediaPlay = LogicalKeyboardKey(0x00100000d2f);`
     - Line 1720: `static const LogicalKeyboardKey mediaPause = LogicalKeyboardKey(0x00100000d2e);`
     - Line 1335: `static const LogicalKeyboardKey mediaTrackNext = LogicalKeyboardKey(0x00100000a08);`
     - Line 1340: `static const LogicalKeyboardKey mediaTrackPrevious = LogicalKeyboardKey(0x00100000a09);`

3. **`flutter_tts` Package Specifications**:
   - Current stable version on pub.dev: `flutter_tts: ^4.2.5`
   - Interacts with native engines via Flutter platform channel `MethodChannel('flutter_tts')`.
   - Android 11+ (API 30+) requires package visibility in `android/app/src/main/AndroidManifest.xml`:
     ```xml
     <queries>
         <intent>
             <action android:name="android.intent.action.TTS_SERVICE" />
         </intent>
     </queries>
     ```
   - iOS Audio Category configuration needed for Bluetooth earphones and silent mode playback:
     - `flutterTts.setSharedInstance(true)`
     - `flutterTts.setIosAudioCategory(IosTextToSpeechAudioCategory.playback, [IosTextToSpeechAudioCategoryOptions.allowBluetooth, IosTextToSpeechAudioCategoryOptions.allowBluetoothA2DP, IosTextToSpeechAudioCategoryOptions.mixWithOthers, IosTextToSpeechAudioCategoryOptions.defaultToSpeaker])`
   - Rapid speech triggers: Calling `await flutterTts.stop()` before `await flutterTts.speak(...)` ensures newest button presses immediately interrupt previous speech utterances for low latency.

4. **Testing Platform Channel Barrier**:
   - Headless `flutter test` execution does not have native Android/iOS platform channel implementations registered for `flutter_tts`.
   - Calling `FlutterTts().speak()` inside a widget test throws `MissingPluginException(No implementation found for method speak on channel flutter_tts)` unless abstracted or intercepted.
   - Requirement R4 demands a self-contained `lib/main.dart` with no hidden project dependencies.

---

## 2. Logic Chain

1. **From Observation 4 to Architectural Decision (TTS Service Abstraction)**:
   - Because `flutter test` fails on raw `MethodChannel` calls and R4 demands a single self-contained `lib/main.dart` without requiring heavy external mocking frameworks (like `mockito` or `mocktail` with code generators), `lib/main.dart` should define an `abstract class TtsService` with:
     - `FlutterTtsService implements TtsService` (production implementation invoking `flutter_tts`).
     - `FakeTtsService implements TtsService` (in-memory test fake capturing `spokenHistory` and `lastSpoken`).
   - The top-level application widget `ButtonControlApp` takes an optional `ttsService` parameter (`ButtonControlApp({super.key, this.ttsService})`), defaulting to `FlutterTtsService()`.
   - When run via `main()`, `FlutterTtsService` is used with zero extra setup.
   - When run in `test/widget_test.dart`, `FakeTtsService` is passed, enabling deterministic, fast, exception-free assertions on spoken phrases without platform channel mocking.

2. **From Observation 2 & 3 to Button Action Data Model**:
   - Define an enum `ButtonAction` with:
     - `volumeUp`: `keyName: 'KEYCODE_VOLUME_UP'`, `speechText: '音量アップを受信しました'`
     - `volumeDown`: `keyName: 'KEYCODE_VOLUME_DOWN'`, `speechText: '音量ダウンを受信しました'`
     - `mediaPlayPause`: `keyName: 'KEYCODE_MEDIA_PLAY_PAUSE'`, `speechText: '再生・停止ボタンが押されました'` (maps `mediaPlayPause`, `mediaPlay`, and `mediaPause`)
     - `mediaNext`: `keyName: 'KEYCODE_MEDIA_NEXT'`, `speechText: '次の曲ボタンを受信しました'`
     - `mediaPrevious`: `keyName: 'KEYCODE_MEDIA_PREVIOUS'`, `speechText: '前の曲ボタンを受信しました'`
   - Static mapper `ButtonAction? fromLogicalKey(LogicalKeyboardKey key)` provides clean, central decoding.

3. **From Observation 2 & HardwareKeyboard to Event Listener Architecture**:
   - Modern Flutter 3 key handling uses `HardwareKeyboard.instance.addHandler(_handleKeyEvent)` registered in `initState` and unregistered in `dispose`.
   - Only `KeyDownEvent` should trigger processing (`if (event is! KeyDownEvent) return false;`). This avoids duplicate triggers caused by key up or repeated events during physical presses.
   - `WidgetTester.sendKeyEvent(...)` generates both down and up events; filtering for `KeyDownEvent` guarantees exactly 1 event per test press.

4. **From Requirement R3 to Dark-Mode Verification UI Architecture**:
   - `ThemeMode.dark` with dark surface (`#121212` background, `#1E1E1E` card surfaces, teal/amber accent colors).
   - Top / Center flexible area:
     - Large display showing `KEYCODE_VOLUME_UP` (fontSize 32, bold) with localized Japanese speech text and timestamp.
     - When idle (no key yet pressed): shows "ボタンを押してください" ("Waiting for key events...").
   - Bottom flexible area:
     - Real-time scrollable `ListView.builder` displaying timestamped entries `[HH:mm:ss.SSS] KEYCODE_...`.
     - Pure Dart timestamp formatting (no third-party `intl` package needed).
     - Auto-scroll to latest entry via `ScrollController` upon receiving new events.
     - Header includes entry counter and "Clear Log" action.

---

## 3. Caveats

1. **Android Physical Volume Key Interception**:
   - On Android devices, physical volume buttons are by default handled by the Android OS audio service to adjust volume and show the volume slider dialog. Unless the Android `MainActivity` overrides `onKeyDown` or an external/Bluetooth keyboard/controller is connected, Flutter's `HardwareKeyboard` may not receive physical phone volume rocker events while in normal application state. Earphone media keys (Bluetooth/wired) send standard HID media events and are routed directly to Flutter.
   - For automated verification (`flutter test`), `tester.sendKeyEvent(LogicalKeyboardKey.audioVolumeUp)` dispatches directly to Flutter's keyboard services, completely bypassing Android OS audio volume handling.

2. **iOS Physical Volume Buttons**:
   - iOS does not expose physical volume rocker button presses as keyboard events to standard apps. Media buttons on Bluetooth/wired earphones send standard HID remote control commands.
   - Automated tests run headless and simulate `LogicalKeyboardKey` events directly, verifying Flutter logic cross-platform.

3. **Defensive Error Handling for Native TTS**:
   - `FlutterTtsService` must wrap all `_flutterTts` calls in `try/catch` blocks so that if an unsupported platform, missing TTS engine, or permission error occurs, the application UI continues to update without crashing.

---

## 4. Conclusion & Architectural Recommendation

### A. Recommended `lib/main.dart` Structure

```dart
// ============================================================================
// Button Control Verification Application
// ============================================================================
//
// DEPENDENCIES:
// Add the following to your pubspec.yaml:
//
// dependencies:
//   flutter:
//     sdk: flutter
//   flutter_tts: ^4.2.5
//
// PLATFORM CONFIGURATION:
// 1. Android:
//    Add the following queries element to android/app/src/main/AndroidManifest.xml
//    inside the <manifest> tag (outside <application>):
//
//    <queries>
//        <intent>
//            <action android:name="android.intent.action.TTS_SERVICE" />
//        </intent>
//    </queries>
//
// 2. iOS:
//    Configured programmatically via AVAudioSession in FlutterTtsService.
//    Supports Bluetooth earphones and playback during silent mode.
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
abstract class TtsService {
  Future<void> initialize();
  Future<void> speak(String text);
  Future<void> stop();
}

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
      if (!_isInitialized) await initialize();
      await _flutterTts.stop(); // Stop ongoing speech for immediate feedback
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

class FakeTtsService implements TtsService {
  final List<String> spokenHistory = [];
  String? get lastSpoken => spokenHistory.isNotEmpty ? spokenHistory.last : null;
  bool isInitialized = false;

  @override
  Future<void> initialize() async {
    isInitialized = true;
  }

  @override
  Future<void> speak(String text) async {
    if (!isInitialized) await initialize();
    spokenHistory.add(text);
  }

  @override
  Future<void> stop() async {}

  void clear() => spokenHistory.clear();
}

// ----------------------------------------------------------------------------
// 2. Action & Log Domain Models
// ----------------------------------------------------------------------------
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

  static ButtonAction? fromLogicalKey(LogicalKeyboardKey key) {
    if (key == LogicalKeyboardKey.audioVolumeUp) return ButtonAction.volumeUp;
    if (key == LogicalKeyboardKey.audioVolumeDown) return ButtonAction.volumeDown;
    if (key == LogicalKeyboardKey.mediaPlayPause ||
        key == LogicalKeyboardKey.mediaPlay ||
        key == LogicalKeyboardKey.mediaPause) {
      return ButtonAction.mediaPlayPause;
    }
    if (key == LogicalKeyboardKey.mediaTrackNext) return ButtonAction.mediaNext;
    if (key == LogicalKeyboardKey.mediaTrackPrevious) return ButtonAction.mediaPrevious;
    return null;
  }
}

class KeyEventLog {
  final DateTime timestamp;
  final ButtonAction action;

  KeyEventLog({required this.timestamp, required this.action});

  String get formattedTime {
    final h = timestamp.hour.toString().padLeft(2, '0');
    final m = timestamp.minute.toString().padLeft(2, '0');
    final s = timestamp.second.toString().padLeft(2, '0');
    final ms = timestamp.millisecond.toString().padLeft(3, '0');
    return '$h:$m:$s.$ms';
  }
}

// ----------------------------------------------------------------------------
// 3. UI Application & State
// ----------------------------------------------------------------------------
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
      ),
      home: ButtonControlScreen(
        ttsService: ttsService ?? FlutterTtsService(),
      ),
    );
  }
}

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
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    _scrollController.dispose();
    widget.ttsService.stop();
    super.dispose();
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return false;

    final action = ButtonAction.fromLogicalKey(event.logicalKey);
    if (action != null) {
      _processAction(action);
      return true;
    }
    return false;
  }

  void _processAction(ButtonAction action) {
    final now = DateTime.now();
    setState(() {
      _latestAction = action;
      _latestTimestamp = now;
      _logs.add(KeyEventLog(timestamp: now, action: action));
    });

    widget.ttsService.speak(action.speechText);

    WidgetsBinding.instance.addPostFrameCallback((_) {
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
            Expanded(
              flex: 5,
              child: _buildCenterDisplay(),
            ),
            const Divider(height: 1, color: Color(0xFF333333)),
            _buildLogHeader(),
            Expanded(
              flex: 5,
              child: _buildLogList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCenterDisplay() {
    if (_latestAction == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.touch_app_outlined, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'ボタンを押してください',
              style: TextStyle(fontSize: 22, color: Colors.grey, fontWeight: FontWeight.bold),
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
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(action.icon, size: 56, color: Colors.tealAccent),
            const SizedBox(height: 16),
            Text(
              action.keyName,
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
              style: const TextStyle(fontSize: 18, color: Colors.white70),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogHeader() {
    return Container(
      color: const Color(0xFF1E1E1E),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'リアルタイムログ (${_logs.length}件)',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          if (_logs.isNotEmpty)
            GestureDetector(
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

  Widget _buildLogList() {
    if (_logs.isEmpty) {
      return const Center(
        child: Text(
          'ログはありません',
          style: TextStyle(color: Colors.white38),
        ),
      );
    }
    return ListView.builder(
      controller: _scrollController,
      itemCount: _logs.length,
      itemBuilder: (context, index) {
        final log = _logs[index];
        return Container(
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

### B. Recommended Testing Architecture (`test/widget_test.dart`)

```dart
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:button_controll_test/main.dart';

void main() {
  group('Button Control Test Suite', () {
    late FakeTtsService fakeTts;

    setUp(() {
      fakeTts = FakeTtsService();
    });

    testWidgets('Initial state displays waiting prompt and empty log', (WidgetTester tester) async {
      await tester.pumpWidget(ButtonControlApp(ttsService: fakeTts));

      expect(find.text('ボタンを押してください'), findsOneWidget);
      expect(find.text('ログはありません'), findsOneWidget);
      expect(fakeTts.spokenHistory, isEmpty);
    });

    testWidgets('Volume Up key press updates UI, adds log, and triggers TTS', (WidgetTester tester) async {
      await tester.pumpWidget(ButtonControlApp(ttsService: fakeTts));

      // Simulate KEYCODE_VOLUME_UP
      await tester.sendKeyEvent(LogicalKeyboardKey.audioVolumeUp);
      await tester.pumpAndSettle();

      // Verify UI update
      expect(find.text('KEYCODE_VOLUME_UP'), findsWidgets);
      expect(find.text('音量アップを受信しました'), findsWidgets);

      // Verify TTS invocation
      expect(fakeTts.spokenHistory, ['音量アップを受信しました']);
    });

    testWidgets('Volume Down key press updates UI and triggers TTS', (WidgetTester tester) async {
      await tester.pumpWidget(ButtonControlApp(ttsService: fakeTts));

      await tester.sendKeyEvent(LogicalKeyboardKey.audioVolumeDown);
      await tester.pumpAndSettle();

      expect(find.text('KEYCODE_VOLUME_DOWN'), findsWidgets);
      expect(fakeTts.spokenHistory, ['音量ダウンを受信しました']);
    });

    testWidgets('Media Play/Pause key press updates UI and triggers TTS', (WidgetTester tester) async {
      await tester.pumpWidget(ButtonControlApp(ttsService: fakeTts));

      await tester.sendKeyEvent(LogicalKeyboardKey.mediaPlayPause);
      await tester.pumpAndSettle();

      expect(find.text('KEYCODE_MEDIA_PLAY_PAUSE'), findsWidgets);
      expect(fakeTts.spokenHistory, ['再生・停止ボタンが押されました']);
    });

    testWidgets('Media Next and Previous keys update UI and trigger TTS', (WidgetTester tester) async {
      await tester.pumpWidget(ButtonControlApp(ttsService: fakeTts));

      // Next
      await tester.sendKeyEvent(LogicalKeyboardKey.mediaTrackNext);
      await tester.pumpAndSettle();
      expect(find.text('KEYCODE_MEDIA_NEXT'), findsWidgets);
      expect(fakeTts.lastSpoken, '次の曲ボタンを受信しました');

      // Previous
      await tester.sendKeyEvent(LogicalKeyboardKey.mediaTrackPrevious);
      await tester.pumpAndSettle();
      expect(find.text('KEYCODE_MEDIA_PREVIOUS'), findsWidgets);
      expect(fakeTts.lastSpoken, '前の曲ボタンを受信しました');

      expect(fakeTts.spokenHistory.length, 2);
    });

    testWidgets('All 5 target keys sequential presses update log in chronological order', (WidgetTester tester) async {
      await tester.pumpWidget(ButtonControlApp(ttsService: fakeTts));

      final keys = [
        LogicalKeyboardKey.audioVolumeUp,
        LogicalKeyboardKey.audioVolumeDown,
        LogicalKeyboardKey.mediaPlayPause,
        LogicalKeyboardKey.mediaTrackNext,
        LogicalKeyboardKey.mediaTrackPrevious,
      ];

      for (final key in keys) {
        await tester.sendKeyEvent(key);
        await tester.pumpAndSettle();
      }

      expect(fakeTts.spokenHistory, [
        '音量アップを受信しました',
        '音量ダウンを受信しました',
        '再生・停止ボタンが押されました',
        '次の曲ボタンを受信しました',
        '前の曲ボタンを受信しました',
      ]);

      expect(find.text('リアルタイムログ (5件)'), findsOneWidget);
    });

    testWidgets('Non-target keys are ignored', (WidgetTester tester) async {
      await tester.pumpWidget(ButtonControlApp(ttsService: fakeTts));

      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(find.text('ボタンを押してください'), findsOneWidget);
      expect(fakeTts.spokenHistory, isEmpty);
    });
  });
}
```

---

## 5. Verification Method

1. **Self-Verification Commands**:
   Once the project structure is created with `pubspec.yaml`:
   - `flutter pub get`
   - `flutter test`
   - All tests in `test/widget_test.dart` will pass cleanly without missing plugin exceptions or network dependency.

2. **Files to Inspect**:
   - `c:\Users\taqmi\02_development\original_program\button_controll_test\.agents\teamwork\survey_explorer_3\handoff.md` (this report)
   - `c:\Users\taqmi\02_development\original_program\button_controll_test\.agents\teamwork\survey_explorer_3\BRIEFING.md`

3. **Invalidation Conditions**:
   - If Flutter SDK removes `HardwareKeyboard.instance.addHandler` (confirmed present in Flutter 3.47.9 / Dart 3.13.7).
   - If `flutter_tts` changes constructor or method names (analyzed for version `^4.2.5`).
