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
//   cupertino_icons: ^1.0.8
//
// dev_dependencies:
//   flutter_test:
//     sdk: flutter
//   flutter_lints: ^6.0.0
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
  int stopCallCount = 0;

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
    stopCallCount++;
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
        key == LogicalKeyboardKey.select) {
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
    final darkThemeData = ThemeData.dark().copyWith(
      splashFactory: InkRipple.splashFactory,
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
    );

    return MaterialApp(
      title: 'Button Control Test',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      theme: darkThemeData,
      darkTheme: darkThemeData,
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
      return const Center(
        child: SingleChildScrollView(
          child: Column(
            key: Key('waiting_prompt'),
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.touch_app_outlined, size: 56, color: Colors.grey),
              SizedBox(height: 12),
              Text(
                'ボタンを押してください',
                style: TextStyle(
                  fontSize: 22,
                  color: Colors.grey,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 6),
              Text(
                'Volume Up/Down または イヤホンボタン',
                style: TextStyle(fontSize: 14, color: Colors.white54),
              ),
            ],
          ),
        ),
      );
    }

    final action = _latestAction!;
    return Center(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Column(
            key: const Key('detected_action_display'),
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(action.icon, size: 56, color: Colors.tealAccent),
              const SizedBox(height: 12),
              Text(
                action.keyName,
                key: const Key('center_key_name'),
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.tealAccent,
                  letterSpacing: 1.2,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                action.speechText,
                key: const Key('center_speech_text'),
                style: const TextStyle(fontSize: 16, color: Colors.white70),
                textAlign: TextAlign.center,
              ),
              if (_latestTimestamp != null) ...[
                const SizedBox(height: 6),
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
