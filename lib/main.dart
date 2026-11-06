// ============================================================================
// Button Control Verification Application (MethodChannel + Audio Ducking Edition)
// ============================================================================
//
// 【pubspec.yaml への追加パッケージ指定】
// このファイルを動作させるには、pubspec.yaml の dependencies に以下の2つのパッケージが
// 必要です。追記後、`flutter pub get` を実行してください：
//
// dependencies:
//   flutter:
//     sdk: flutter
//   flutter_tts: ^4.2.5
//   audio_session: ^0.2.4
//
// 【Android ネイティブ設定の補足】
// 1. MainActivity.kt 側で MethodChannel("com.example.noukin/key_events") を定義し、
//    dispatchKeyEvent で対象キーコード（85, 79, 24, 25, 87, 88）を invokeMethod("onKeyEvent", keyCode)
//    として送信してください。
// 2. Android 11 (API 30) 以降で音声読み上げ（TTS）を利用するため、
//    android/app/src/main/AndroidManifest.xml の <manifest> 直下に以下を追加してください：
//    <queries>
//        <intent>
//            <action android:name="android.intent.action.TTS_SERVICE" />
//        </intent>
//    </queries>
//
// 【オーディオダッキング（BGM自動減衰・復帰）の仕組み】
// - `audio_session` と `flutter_tts` を連携し、Android では `AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK`、
//   iOS では `AVAudioSessionCategoryOptions.duckOthers` を要求します。
// - `speak()` 実行直前にダッキング（オーディオフォーカス取得）を有効化し、
//   発話完了（setCompletionHandler）・中断（setCancelHandler）・エラー（setErrorHandler）時に
//   オーディオフォーカスを解除してバックグラウンドBGMの音量を元に戻します。
// - 発話途中に次のボタンが押された場合は、前の発話を停止して一度オーディオフォーカスを解除
//   （BGM音量を復帰）したうえで、次の発話の直前に再度ダッキングを要求します。
// ============================================================================

import 'dart:async';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// Android ネイティブ層（MainActivity.kt）と通信する MethodChannel 名
const String kKeyEventsChannelName = 'com.example.noukin/key_events';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ButtonControlApp());
}

// ----------------------------------------------------------------------------
// 1. オーディオダッキング制御レイヤー（audio_session 連携）
// ----------------------------------------------------------------------------

/// BGM の音量を一時的に下げる（ダッキング）制御のインターフェース
abstract class AudioDuckingController {
  Future<void> configure();
  Future<void> requestDucking();
  Future<void> releaseDucking();
}

/// `audio_session` パッケージを用いて OS にオーディオフォーカス（ダッキング）を要求・解除する本番実装
class AudioSessionDuckingController implements AudioDuckingController {
  AudioSession? _session;
  bool _isConfigured = false;

  @override
  Future<void> configure() async {
    if (_isConfigured) return;
    try {
      final session = await AudioSession.instance;
      await session.configure(
        AudioSessionConfiguration(
          // iOS: マナーモードでも再生可能な playback カテゴリ + 純粋なダッキング (duckOthers)
          avAudioSessionCategory: AVAudioSessionCategory.playback,
          avAudioSessionCategoryOptions:
              AVAudioSessionCategoryOptions.duckOthers |
              AVAudioSessionCategoryOptions.allowBluetooth |
              AVAudioSessionCategoryOptions.allowBluetoothA2dp,
          avAudioSessionMode: AVAudioSessionMode.defaultMode,
          avAudioSessionSetActiveOptions:
              AVAudioSessionSetActiveOptions.notifyOthersOnDeactivation,
          // Android: AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK による一時減衰（音楽・ラジオ等を止めずに減衰）
          androidAudioAttributes: const AndroidAudioAttributes(
            contentType: AndroidAudioContentType.music,
            usage: AndroidAudioUsage.assistanceNavigationGuidance,
          ),
          androidAudioFocusGainType:
              AndroidAudioFocusGainType.gainTransientMayDuck,
          androidWillPauseWhenDucked: false,
        ),
      );
      _session = session;
      _isConfigured = true;
    } catch (e) {
      debugPrint('AudioSessionDuckingController.configure error: $e');
    }
  }

  @override
  Future<void> requestDucking() async {
    try {
      if (!_isConfigured) {
        await configure();
      }
      await _session?.setActive(true);
    } catch (e) {
      debugPrint('AudioSessionDuckingController.requestDucking error: $e');
    }
  }

  @override
  Future<void> releaseDucking() async {
    try {
      await _session?.setActive(
        false,
        avAudioSessionSetActiveOptions:
            AVAudioSessionSetActiveOptions.notifyOthersOnDeactivation,
      );
    } catch (e) {
      debugPrint('AudioSessionDuckingController.releaseDucking error: $e');
    }
  }
}

/// 自動テスト検証用のダッキングコントローラ（要求・解除履歴を記録）
class FakeAudioDuckingController implements AudioDuckingController {
  final List<String> events = [];
  bool isConfigured = false;
  bool isCurrentlyDucked = false;

  @override
  Future<void> configure() async {
    isConfigured = true;
    events.add('configure');
  }

  @override
  Future<void> requestDucking() async {
    if (!isConfigured) {
      await configure();
    }
    isCurrentlyDucked = true;
    events.add('requestDucking');
  }

  @override
  Future<void> releaseDucking() async {
    isCurrentlyDucked = false;
    events.add('releaseDucking');
  }
}

// ----------------------------------------------------------------------------
// 2. TTS（音声読み上げ）サービス抽象化レイヤー
// ----------------------------------------------------------------------------

/// 音声読み上げ機能のインターフェース
abstract class TtsService {
  Future<void> initialize();
  Future<void> speak(String text);
  Future<void> stop();
}

/// 実機・エミュレータ動作時に flutter_tts とオーディオダッキングを連携させる本番用クラス
class FlutterTtsService implements TtsService {
  final FlutterTts _flutterTts;
  final AudioDuckingController _duckingController;

  bool _isInitialized = false;
  bool _isSpeaking = false;
  bool _isDucked = false;
  Completer<void>? _cancelCompleter;

  FlutterTtsService({
    FlutterTts? tts,
    AudioDuckingController? duckingController,
  }) : _flutterTts = tts ?? FlutterTts(),
       _duckingController =
           duckingController ?? AudioSessionDuckingController();

  @override
  Future<void> initialize() async {
    if (_isInitialized) return;
    try {
      await _duckingController.configure();

      await _flutterTts.setLanguage('ja-JP');
      await _flutterTts.setSpeechRate(0.5);
      await _flutterTts.setVolume(1.0);
      await _flutterTts.setPitch(1.0);
      await _flutterTts.awaitSpeakCompletion(false);

      if (defaultTargetPlatform == TargetPlatform.android) {
        await _flutterTts.setAudioAttributesForNavigation();
      } else if (defaultTargetPlatform == TargetPlatform.iOS) {
        await _flutterTts.setSharedInstance(true);
        await _flutterTts.autoStopSharedSession(false);
        await _flutterTts.setIosAudioCategory(
          IosTextToSpeechAudioCategory.playback,
          [
            IosTextToSpeechAudioCategoryOptions.duckOthers,
            IosTextToSpeechAudioCategoryOptions.allowBluetooth,
            IosTextToSpeechAudioCategoryOptions.allowBluetoothA2DP,
          ],
        );
      }

      // 発話完了時：オーディオフォーカスを解除し BGM 音量を元に戻す
      _flutterTts.setCompletionHandler(() {
        _isSpeaking = false;
        unawaited(_releaseDuckingIfNeeded());
      });

      // 発話中断時：オーディオフォーカスを解除し BGM 音量を元に戻す
      _flutterTts.setCancelHandler(() {
        _isSpeaking = false;
        final future = _releaseDuckingIfNeeded();
        if (_cancelCompleter != null && !_cancelCompleter!.isCompleted) {
          future.whenComplete(() {
            if (_cancelCompleter != null && !_cancelCompleter!.isCompleted) {
              _cancelCompleter!.complete();
            }
          });
        }
      });

      // エラー発生時：オーディオフォーカスを解除し BGM 音量を元に戻す
      _flutterTts.setErrorHandler((dynamic message) {
        debugPrint('FlutterTts errorHandler: $message');
        _isSpeaking = false;
        final future = _releaseDuckingIfNeeded();
        if (_cancelCompleter != null && !_cancelCompleter!.isCompleted) {
          future.whenComplete(() {
            if (_cancelCompleter != null && !_cancelCompleter!.isCompleted) {
              _cancelCompleter!.complete();
            }
          });
        }
      });

      _isInitialized = true;
    } catch (e) {
      debugPrint('FlutterTtsService.initialize error: $e');
    }
  }

  Future<void> _requestDucking() async {
    _isDucked = true;
    await _duckingController.requestDucking();
  }

  Future<void> _releaseDuckingIfNeeded() async {
    if (!_isDucked) return;
    _isDucked = false;
    await _duckingController.releaseDucking();
  }

  @override
  Future<void> speak(String text) async {
    try {
      if (!_isInitialized) {
        await initialize();
      }

      // 前の読み上げが進行中の場合は停止し、一度オーディオフォーカスを解除して BGM 音量を戻す
      if (_isSpeaking || _isDucked) {
        final completer = Completer<void>();
        _cancelCompleter = completer;
        _isSpeaking = false;
        await _flutterTts.stop();
        await completer.future.timeout(
          const Duration(milliseconds: 80),
          onTimeout: () {},
        );
        _cancelCompleter = null;
        await _releaseDuckingIfNeeded();
      }

      // speak() 呼び出し直前にダッキングを有効化し、BGM の音量を減衰させる
      await _requestDucking();
      _isSpeaking = true;
      await _flutterTts.speak(text);
    } catch (e) {
      debugPrint('FlutterTtsService.speak error: $e');
      _isSpeaking = false;
      await _releaseDuckingIfNeeded();
    }
  }

  @override
  Future<void> stop() async {
    try {
      _isSpeaking = false;
      await _flutterTts.stop();
    } catch (e) {
      debugPrint('FlutterTtsService.stop error: $e');
    } finally {
      await _releaseDuckingIfNeeded();
    }
  }
}

/// UI ウィジェットテスト用のインメモリ TTS サービス
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
// 3. キーコード定義・ログモデル
// ----------------------------------------------------------------------------

/// 検知対象の6種類の物理ボタン・メディアキー定義
enum ButtonAction {
  volumeUp(
    keyCode: 24,
    keyName: 'KEYCODE_VOLUME_UP',
    speechText: '音量アップを検知しました',
    icon: Icons.volume_up,
  ),
  volumeDown(
    keyCode: 25,
    keyName: 'KEYCODE_VOLUME_DOWN',
    speechText: '音量ダウンを検知しました',
    icon: Icons.volume_down,
  ),
  mediaPlayPause(
    keyCode: 85,
    keyName: 'KEYCODE_MEDIA_PLAY_PAUSE',
    speechText: '再生・停止ボタンを検知しました',
    icon: Icons.play_circle_filled,
  ),
  headsetHook(
    keyCode: 79,
    keyName: 'KEYCODE_HEADSETHOOK',
    speechText: '再生・停止ボタンを検知しました',
    icon: Icons.headset_mic,
  ),
  mediaNext(
    keyCode: 87,
    keyName: 'KEYCODE_MEDIA_NEXT',
    speechText: '曲送りを検知しました',
    icon: Icons.skip_next,
  ),
  mediaPrevious(
    keyCode: 88,
    keyName: 'KEYCODE_MEDIA_PREVIOUS',
    speechText: '曲戻しを検知しました',
    icon: Icons.skip_previous,
  );

  final int keyCode;
  final String keyName;
  final String speechText;
  final IconData icon;

  const ButtonAction({
    required this.keyCode,
    required this.keyName,
    required this.speechText,
    required this.icon,
  });

  /// ボタン名とキーコードを合わせた表示文字列（例: "KEYCODE_VOLUME_UP (24)"）
  String get labelWithCode => '$keyName ($keyCode)';

  /// Android キーコード（数値）から対応する [ButtonAction] を返す（対象外の番号は null）
  static ButtonAction? fromKeyCode(int keyCode) {
    for (final action in ButtonAction.values) {
      if (action.keyCode == keyCode) {
        return action;
      }
    }
    return null;
  }
}

/// 時刻を HH:mm:ss.SSS 形式に整形する関数
String formatTimestamp(DateTime dt) {
  final h = dt.hour.toString().padLeft(2, '0');
  final m = dt.minute.toString().padLeft(2, '0');
  final s = dt.second.toString().padLeft(2, '0');
  final ms = dt.millisecond.toString().padLeft(3, '0');
  return '$h:$m:$s.$ms';
}

/// 受信した1回分のキーイベント履歴データ
class KeyEventLog {
  final DateTime timestamp;
  final ButtonAction action;

  KeyEventLog({required this.timestamp, required this.action});

  String get formattedTime => formatTimestamp(timestamp);
}

// ----------------------------------------------------------------------------
// 4. UI アプリケーション & MethodChannel リスナー画面
// ----------------------------------------------------------------------------

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

typedef MyApp = ButtonControlApp;

class ButtonControlScreen extends StatefulWidget {
  final TtsService ttsService;

  const ButtonControlScreen({super.key, required this.ttsService});

  @override
  State<ButtonControlScreen> createState() => _ButtonControlScreenState();
}

class _ButtonControlScreenState extends State<ButtonControlScreen> {
  static const MethodChannel _keyEventsChannel = MethodChannel(
    kKeyEventsChannelName,
  );

  final List<KeyEventLog> _logs = [];
  final ScrollController _scrollController = ScrollController();
  ButtonAction? _latestAction;
  DateTime? _latestTimestamp;

  @override
  void initState() {
    super.initState();
    widget.ttsService.initialize();
    // Android ネイティブ層からのキーイベント通知を受け取るリスナーを登録
    _keyEventsChannel.setMethodCallHandler(_handleMethodCall);
  }

  @override
  void dispose() {
    _keyEventsChannel.setMethodCallHandler(null);
    _scrollController.dispose();
    widget.ttsService.stop();
    super.dispose();
  }

  /// MethodChannel 経由で届いたキーコードを解析し、対象キーであれば処理する
  Future<dynamic> _handleMethodCall(MethodCall call) async {
    int? keyCode;
    final args = call.arguments;
    if (args is int) {
      keyCode = args;
    } else if (args is Map) {
      final raw = args['keyCode'];
      if (raw is int) {
        keyCode = raw;
      }
    }

    if (keyCode == null) {
      return false;
    }

    final action = ButtonAction.fromKeyCode(keyCode);
    if (action != null) {
      _processAction(action);
      return true;
    }
    return false;
  }

  /// 画面表示・ログ一覧を更新し、即座に音声読み上げを実行する
  void _processAction(ButtonAction action) {
    final now = DateTime.now();
    setState(() {
      _latestAction = action;
      _latestTimestamp = now;
      _logs.add(KeyEventLog(timestamp: now, action: action));
    });

    widget.ttsService.speak(action.speechText);

    // 新しいログが見えるよう最下部へ自動スクロール
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
            tooltip: 'ログをクリア',
            onPressed: _logs.isEmpty ? null : _clearLogs,
          ),
        ],
      ),
      body: Column(
        children: [
          // 画面中央：直前に検知したボタン名とキーコードを巨大表示
          Expanded(
            flex: 5,
            child: _buildCenterDisplay(),
          ),
          const Divider(height: 1, color: Color(0xFF333333)),
          // ログヘッダー
          _buildLogHeader(),
          // 画面下部：タイムスタンプ付き受信ログ一覧（スクロール可能）
          Expanded(
            flex: 5,
            child: _buildLogList(),
          ),
        ],
      ),
    );
  }

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
                'ボタン入力を待機中...',
                style: TextStyle(
                  fontSize: 22,
                  color: Colors.grey,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 6),
              Text(
                '音量ボタン / イヤホンボタン / adb input keyevent',
                style: TextStyle(fontSize: 13, color: Colors.white54),
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
                  fontSize: 30,
                  fontWeight: FontWeight.bold,
                  color: Colors.tealAccent,
                  letterSpacing: 1.1,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                'KeyCode: ${action.keyCode}',
                key: const Key('center_key_code'),
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: Colors.amberAccent,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
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

  Widget _buildLogHeader() {
    return Container(
      color: const Color(0xFF1E1E1E),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '受信ログ一覧 (${_logs.length}件)',
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

  Widget _buildLogList() {
    if (_logs.isEmpty) {
      return const Center(
        child: Text(
          'まだ受信ログはありません',
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
              '[${log.formattedTime}] ${log.action.labelWithCode}',
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
