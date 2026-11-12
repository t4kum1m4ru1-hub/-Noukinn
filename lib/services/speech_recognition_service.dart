import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

/// 音声認識（Speech-to-Text）サービスの抽象化インターフェース
abstract class SpeechRecognitionService {
  /// 音声認識エンジンの初期化（マイク権限リクエストを含む）
  Future<bool> initialize();

  /// 音声認識（リスニング）の開始
  Future<void> startListening({
    required void Function(String recognizedWords) onResult,
    void Function(String error)? onError,
  });

  /// 音声認識の停止
  Future<void> stopListening();

  /// 現在マイクで音声を聞き取り中かどうか
  bool get isListening;

  /// 音声認識機能が端末で利用可能か
  bool get isAvailable;
}

/// speech_to_text パッケージを用いた本番用音声認識実装
class PlatformSpeechRecognitionService implements SpeechRecognitionService {
  final stt.SpeechToText _speechToText;
  bool _isAvailable = false;

  PlatformSpeechRecognitionService({stt.SpeechToText? speechToText})
      : _speechToText = speechToText ?? stt.SpeechToText();

  @override
  Future<bool> initialize() async {
    try {
      _isAvailable = await _speechToText.initialize(
        onError: (val) => debugPrint('SpeechRecognition onError: ${val.errorMsg}'),
        onStatus: (val) => debugPrint('SpeechRecognition onStatus: $val'),
      );
      return _isAvailable;
    } catch (e) {
      debugPrint('PlatformSpeechRecognitionService.initialize error: $e');
      _isAvailable = false;
      return false;
    }
  }

  @override
  Future<void> startListening({
    required void Function(String recognizedWords) onResult,
    void Function(String error)? onError,
  }) async {
    if (!_isAvailable) {
      final ok = await initialize();
      if (!ok) {
        onError?.call('音声認識を利用できません');
        return;
      }
    }

    try {
      await _speechToText.listen(
        listenOptions: stt.SpeechListenOptions(
          listenMode: stt.ListenMode.confirmation,
          localeId: 'ja_JP',
        ),
        onResult: (result) {
          if (result.recognizedWords.isNotEmpty) {
            onResult(result.recognizedWords);
          }
        },
      );
    } catch (e) {
      debugPrint('PlatformSpeechRecognitionService.startListening error: $e');
      onError?.call(e.toString());
    }
  }

  @override
  Future<void> stopListening() async {
    try {
      await _speechToText.stop();
    } catch (e) {
      debugPrint('PlatformSpeechRecognitionService.stopListening error: $e');
    }
  }

  @override
  bool get isListening => _speechToText.isListening;

  @override
  bool get isAvailable => _isAvailable;
}

/// 自動テスト用のインメモリ音声認識サービス
class FakeSpeechRecognitionService implements SpeechRecognitionService {
  bool _isListening = false;
  final bool _isAvailable = true;
  int startCount = 0;
  int stopCount = 0;
  void Function(String recognizedWords)? _onResultCallback;

  @override
  Future<bool> initialize() async => _isAvailable;

  @override
  Future<void> startListening({
    required void Function(String recognizedWords) onResult,
    void Function(String error)? onError,
  }) async {
    startCount++;
    _isListening = true;
    _onResultCallback = onResult;
  }

  @override
  Future<void> stopListening() async {
    stopCount++;
    _isListening = false;
    _onResultCallback = null;
  }

  /// テスト中にユーザーの発話をシミュレートして注入するメソッド
  void simulateSpeech(String recognizedWords) {
    if (_isListening && _onResultCallback != null) {
      _onResultCallback!(recognizedWords);
    }
  }

  @override
  bool get isListening => _isListening;

  @override
  bool get isAvailable => _isAvailable;
}

