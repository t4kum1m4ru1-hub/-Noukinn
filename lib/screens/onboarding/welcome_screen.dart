import 'dart:async';
import 'package:flutter/material.dart';
import '../../main.dart'
    show
        ButtonAction,
        KeyEventChannelDispatcher,
        SoundEffectService,
        SpeechRecognitionService,
        TtsService,
        VoiceCommandInterpreter,
        VoiceAction,
        NextStepAction;
import '../../theme/app_colors.dart';

/// 初回起動時に最初に表示されるウェルカム画面
class WelcomeScreen extends StatefulWidget {
  final VoidCallback onStart;
  final TtsService? ttsService;
  final SoundEffectService? soundEffectService;
  final SpeechRecognitionService? speechService;

  const WelcomeScreen({
    super.key,
    required this.onStart,
    this.ttsService,
    this.soundEffectService,
    this.speechService,
  });

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  bool _isListening = false;
  String? _recognizedText;

  @override
  void initState() {
    super.initState();
    KeyEventChannelDispatcher.instance.registerListener(_onKeyEvent);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _startVoicePromptFlow();
    });
  }

  @override
  void dispose() {
    KeyEventChannelDispatcher.instance.unregisterListener(_onKeyEvent);
    widget.speechService?.stopListening();
    super.dispose();
  }

  /// 音声案内読み上げ完了後、効果音を鳴らしてマイク待機を開始する
  Future<void> _startVoicePromptFlow() async {
    const text = '完全ハンズフリートレーニングへようこそ。設定をはじめます。';
    if (widget.ttsService != null) {
      await widget.ttsService!.speakAndWait(text);
    }
    if (!mounted) return;

    // 音声案内終了後、合図の電子音を鳴らして音声聞き取りを開始
    await widget.soundEffectService?.playBeep();
    _startListening();
  }

  Future<void> _startListening() async {
    if (widget.speechService == null) return;
    setState(() {
      _isListening = true;
    });

    await widget.speechService!.startListening(
      onResult: (words) {
        if (!mounted) return;
        setState(() {
          _recognizedText = words;
        });

        final action = VoiceCommandInterpreter.interpret(
          step: 0,
          speech: words,
          currentAimCategory: AimCategory.bodyType,
        );

        if (action is NextStepAction) {
          widget.speechService?.stopListening();
          widget.soundEffectService?.playBeep();
          widget.onStart();
        }
      },
    );
  }

  void _onKeyEvent(ButtonAction action) {
    widget.speechService?.stopListening();
    widget.soundEffectService?.playBeep();
    widget.onStart();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 16),
              // 上部タイトル
              const Column(
                children: [
                  Text(
                    'NOUKIN',
                    key: Key('welcome_title'),
                    style: TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.w900,
                      color: AppColors.tealAccent,
                      letterSpacing: 2.0,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: 8),
                  Text(
                    '完全ハンズフリートレーニングへようこそ',
                    key: Key('welcome_subtitle'),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
              const Spacer(flex: 1),

              // 中央イラスト（プレースホルダー）
              Center(
                child: Container(
                  key: const Key('welcome_image_container'),
                  width: 200,
                  height: 200,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceVariant,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.tealAccent, width: 2.0),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.tealAccent.withValues(alpha: 0.15),
                        blurRadius: 24,
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.fitness_center,
                          size: 64,
                          color: AppColors.tealAccent,
                        ),
                        SizedBox(height: 10),
                        Icon(
                          Icons.headphones,
                          size: 36,
                          color: AppColors.primaryAccent,
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              const Spacer(flex: 1),

              // 音声認識インジケーター（音声ガイド待機・受付中）
              if (_isListening) ...[
                Container(
                  key: const Key('welcome_voice_indicator'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.tealAccent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: AppColors.tealAccent.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.mic,
                        color: AppColors.tealAccent,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _recognizedText != null
                            ? '「$_recognizedText」を認識中...'
                            : '音声待機中:「スタート」「次へ」とお話しください',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.tealAccent,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // 下部説明テキスト
              Container(
                padding: const EdgeInsets.all(16.0),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: const Text(
                  'スマホを触らず、音楽を聴きながら音声とイヤホン操作だけでトレーニングを進行できます。\n\nあなたに合わせた初期設定を行うため、5つの質問にお答えください。',
                  key: Key('welcome_description'),
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.6,
                    color: AppColors.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),

              const SizedBox(height: 20),

              // はじめるボタン
              ElevatedButton(
                key: const Key('welcome_start_button'),
                onPressed: () {
                  widget.speechService?.stopListening();
                  widget.soundEffectService?.playBeep();
                  widget.onStart();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryAccent,
                  foregroundColor: AppColors.onPrimaryAccent,
                  minimumSize: const Size.fromHeight(52),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 2,
                ),
                child: const Text(
                  '設定をはじめる',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}
