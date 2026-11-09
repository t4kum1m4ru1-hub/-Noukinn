import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:button_controll_test/main.dart';
import 'package:button_controll_test/review_screen.dart';

/// Android ネイティブ層（MainActivity.kt）からの MethodChannel 呼び出しをシミュレートするヘルパー
Future<dynamic> sendNativeKeyEvent(
  WidgetTester tester,
  dynamic arguments, {
  String method = 'onKeyEvent',
}) async {
  const codec = StandardMethodCodec();
  final ByteData callData = codec.encodeMethodCall(
    MethodCall(method, arguments),
  );
  final completer = Completer<ByteData?>();
  tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    kKeyEventsChannelName,
    callData,
    (ByteData? reply) {
      completer.complete(reply);
    },
  );
  final reply = await completer.future;
  if (reply == null) {
    return null;
  }
  return codec.decodeEnvelope(reply);
}

/// FlutterTts のネイティブ側イベント（speak.onComplete / speak.onCancel / speak.onError）を送信するヘルパー
Future<void> emitTtsPlatformCallback(
  String method, [
  dynamic arguments = true,
]) async {
  const codec = StandardMethodCodec();
  final ByteData callData = codec.encodeMethodCall(
    MethodCall(method, arguments),
  );
  final completer = Completer<ByteData?>();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage('flutter_tts', callData, (ByteData? reply) {
        completer.complete(reply);
      });
  await completer.future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Unit Tests: ButtonAction & Helpers', () {
    test('指定された6種類のキーコードのみ正しくマッピングされること', () {
      expect(ButtonAction.fromKeyCode(85), ButtonAction.mediaPlayPause);
      expect(ButtonAction.fromKeyCode(79), ButtonAction.headsetHook);
      expect(ButtonAction.fromKeyCode(24), ButtonAction.volumeUp);
      expect(ButtonAction.fromKeyCode(25), ButtonAction.volumeDown);
      expect(ButtonAction.fromKeyCode(87), ButtonAction.mediaNext);
      expect(ButtonAction.fromKeyCode(88), ButtonAction.mediaPrevious);
    });

    test('指定外のキーコード（126, 127, 4 等）は厳密に null を返すこと', () {
      expect(ButtonAction.fromKeyCode(126), isNull); // KEYCODE_MEDIA_PLAY
      expect(ButtonAction.fromKeyCode(127), isNull); // KEYCODE_MEDIA_PAUSE
      expect(ButtonAction.fromKeyCode(4), isNull);   // KEYCODE_BACK
      expect(ButtonAction.fromKeyCode(164), isNull); // KEYCODE_VOLUME_MUTE
      expect(ButtonAction.fromKeyCode(0), isNull);
    });

    test('タイムスタンプが HH:mm:ss.SSS 形式でフォーマットされること', () {
      final log = KeyEventLog(
        timestamp: DateTime(2026, 11, 6, 9, 5, 3, 42),
        action: ButtonAction.volumeUp,
      );
      expect(log.formattedTime, '09:05:03.042');
    });
  });

  group('Audio Ducking Tests: FlutterTtsService & AudioFocus 制御', () {
    const ttsChannel = MethodChannel('flutter_tts');
    late List<String> timeline;
    late FakeAudioDuckingController fakeDucking;
    late FlutterTtsService ttsService;
    late bool autoEmitCancelOnStop;

    setUp(() {
      timeline = [];
      autoEmitCancelOnStop = true;

      fakeDucking = _TimelineDuckingController(timeline);

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(ttsChannel, (MethodCall call) async {
            if (call.method == 'speak') {
              final text = call.arguments is Map
                  ? call.arguments['text']
                  : call.arguments;
              timeline.add('tts.speak:$text');
              return 1;
            }
            if (call.method == 'stop') {
              timeline.add('tts.stop');
              if (autoEmitCancelOnStop) {
                unawaited(emitTtsPlatformCallback('speak.onCancel'));
              }
              return 1;
            }
            return 1;
          });

      ttsService = FlutterTtsService(
        tts: FlutterTts(),
        duckingController: fakeDucking,
      );
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(ttsChannel, null);
    });

    test('speak() 直前にダッキングを有効化し、発話完了（onComplete）で解除すること', () async {
      await ttsService.initialize();
      timeline.clear();

      await ttsService.speak('音量アップを検知しました');
      expect(fakeDucking.isCurrentlyDucked, isTrue);
      expect(timeline, [
        'ducking.request',
        'tts.speak:音量アップを検知しました',
      ]);

      await emitTtsPlatformCallback('speak.onComplete');
      await Future<void>.delayed(Duration.zero);

      expect(fakeDucking.isCurrentlyDucked, isFalse);
      expect(timeline, [
        'ducking.request',
        'tts.speak:音量アップを検知しました',
        'ducking.release',
      ]);
    });

    test('発話エラー時（onError）にオーディオフォーカスを確実に解除すること', () async {
      await ttsService.initialize();
      timeline.clear();

      await ttsService.speak('再生・停止ボタンを検知しました');
      expect(fakeDucking.isCurrentlyDucked, isTrue);

      await emitTtsPlatformCallback('speak.onError', 'TTS engine error');
      await Future<void>.delayed(Duration.zero);

      expect(fakeDucking.isCurrentlyDucked, isFalse);
      expect(timeline.last, 'ducking.release');
    });

    test('発話途中に次のボタンが押された際、一度BGM音量を戻してから再度ダッキングすること', () async {
      await ttsService.initialize();
      timeline.clear();

      // 1回目の発話開始（まだ完了していない状態）
      await ttsService.speak('音量アップを検知しました');
      expect(fakeDucking.isCurrentlyDucked, isTrue);

      // 1回目の発話途中に2回目の発話を要求
      await ttsService.speak('曲送りを検知しました');
      expect(fakeDucking.isCurrentlyDucked, isTrue);

      // 順序検証: 1回目要求 -> 1回目発話 -> 停止 -> 一度解除 -> 2回目要求 -> 2回目発話
      expect(timeline, [
        'ducking.request',
        'tts.speak:音量アップを検知しました',
        'tts.stop',
        'ducking.release',
        'ducking.request',
        'tts.speak:曲送りを検知しました',
      ]);

      // 2回目の発話完了で解除
      await emitTtsPlatformCallback('speak.onComplete');
      await Future<void>.delayed(Duration.zero);
      expect(fakeDucking.isCurrentlyDucked, isFalse);
      expect(timeline.last, 'ducking.release');
    });
  });

  group('Widget Tests: MethodChannel("com.example.noukin/key_events") 連携', () {
    late FakeTtsService fakeTts;

    setUp(() {
      fakeTts = FakeTtsService();
    });

    testWidgets('初期状態: 待機メッセージ・空ログ・クリアボタン無効が表示されること', (tester) async {
      await tester.pumpWidget(ButtonControlApp(ttsService: fakeTts));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('waiting_prompt')), findsOneWidget);
      expect(find.text('まだ受信ログはありません'), findsOneWidget);
      expect(find.text('受信ログ一覧 (0件)'), findsOneWidget);

      final clearBtn = tester.widget<IconButton>(
        find.byKey(const Key('clear_logs_button')),
      );
      expect(clearBtn.onPressed, isNull);
      expect(fakeTts.spokenHistory, isEmpty);
    });

    testWidgets('全6種類の対象キーコードで画面中央表示・TTS読み上げ・ログ追記が正しく動作すること', (tester) async {
      await tester.pumpWidget(ButtonControlApp(ttsService: fakeTts));
      await tester.pumpAndSettle();

      final cases = [
        (85, 'KEYCODE_MEDIA_PLAY_PAUSE', '再生・停止ボタンを検知しました'),
        (79, 'KEYCODE_HEADSETHOOK', '再生・停止ボタンを検知しました'),
        (24, 'KEYCODE_VOLUME_UP', '音量アップを検知しました'),
        (25, 'KEYCODE_VOLUME_DOWN', '音量ダウンを検知しました'),
        (87, 'KEYCODE_MEDIA_NEXT', '曲送りを検知しました'),
        (88, 'KEYCODE_MEDIA_PREVIOUS', '曲戻しを検知しました'),
      ];

      for (var i = 0; i < cases.length; i++) {
        final (code, expectedKeyName, expectedSpeech) = cases[i];
        final result = await sendNativeKeyEvent(tester, code);
        await tester.pumpAndSettle();

        expect(result, isTrue);
        expect(find.byKey(const Key('center_key_name')), findsOneWidget);
        expect(
          tester.widget<Text>(find.byKey(const Key('center_key_name'))).data,
          expectedKeyName,
        );
        expect(
          tester.widget<Text>(find.byKey(const Key('center_key_code'))).data,
          'KeyCode: $code',
        );
        expect(fakeTts.lastSpoken, expectedSpeech);
        expect(find.text('受信ログ一覧 (${i + 1}件)'), findsOneWidget);
      }

      expect(fakeTts.spokenHistory.length, 6);
    });

    testWidgets('対象外のキーコード（126, 127 等）は無視され UI・TTS が変化しないこと', (tester) async {
      await tester.pumpWidget(ButtonControlApp(ttsService: fakeTts));
      await tester.pumpAndSettle();

      expect(await sendNativeKeyEvent(tester, 126), isFalse);
      expect(await sendNativeKeyEvent(tester, 127), isFalse);
      expect(await sendNativeKeyEvent(tester, 'invalid_arg'), isFalse);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('waiting_prompt')), findsOneWidget);
      expect(fakeTts.spokenHistory, isEmpty);
      expect(find.text('受信ログ一覧 (0件)'), findsOneWidget);
    });

    testWidgets('連続受信時のスクロールとログクリアが動作すること', (tester) async {
      await tester.pumpWidget(ButtonControlApp(ttsService: fakeTts));
      await tester.pumpAndSettle();

      for (var i = 0; i < 20; i++) {
        await sendNativeKeyEvent(tester, i.isEven ? 24 : 25);
        await tester.pump();
      }
      await tester.pumpAndSettle();

      expect(find.text('受信ログ一覧 (20件)'), findsOneWidget);
      expect(fakeTts.spokenHistory.length, 20);

      await tester.tap(find.byKey(const Key('clear_logs_button')));
      await tester.pumpAndSettle();

      expect(find.text('受信ログ一覧 (0件)'), findsOneWidget);
      expect(find.text('まだ受信ログはありません'), findsOneWidget);
    });
  });

  group('Widget Tests: TrainingScreen UI & Navigation', () {
    late FakeTtsService fakeTts;

    setUp(() {
      fakeTts = FakeTtsService();
    });

    testWidgets('メイン画面から「トレーニング開始」をタップしてトレーニング画面に遷移し、戻るボタンでメインに戻れること', (tester) async {
      await tester.pumpWidget(ButtonControlApp(ttsService: fakeTts));
      await tester.pumpAndSettle();

      final startButton = find.byKey(const Key('start_training_button'));
      expect(startButton, findsOneWidget);
      expect(find.text('トレーニング開始'), findsOneWidget);

      await tester.tap(startButton);
      await tester.pumpAndSettle();

      // トレーニング画面の要素確認
      expect(find.byType(TrainingScreen), findsOneWidget);
      expect(find.text('ベンチプレス'), findsOneWidget);
      expect(find.byKey(const Key('training_back_button')), findsOneWidget);
      expect(find.byKey(const Key('exercise_image')), findsOneWidget);

      // 戻るボタンをタップ
      await tester.tap(find.byKey(const Key('training_back_button')));
      await tester.pumpAndSettle();

      // メイン画面に戻ったことを確認
      expect(find.byType(TrainingScreen), findsNothing);
      expect(find.byKey(const Key('waiting_prompt')), findsOneWidget);
    });

    testWidgets('3つのカード（重量・レップ数・セット数）と音量バーの表示および左右ボタンによる増減が正しく動作すること', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: TrainingScreen(ttsService: fakeTts),
        ),
      );
      await tester.pumpAndSettle();

      // カードと初期値の検証
      expect(find.text('重量'), findsOneWidget);
      expect(find.text('60 kg'), findsOneWidget);

      expect(find.text('レップ数'), findsOneWidget);
      expect(find.text('10 回'), findsOneWidget);

      expect(find.text('セット数'), findsOneWidget);
      expect(find.text('1 セット'), findsOneWidget);

      expect(find.text('音声ガイドの音量'), findsOneWidget);
      expect(find.text('80%'), findsOneWidget);

      // 重量ボタンのテスト (+2.5kg / -2.5kg)
      await tester.tap(find.byKey(const Key('btn_weight_up')));
      await tester.pumpAndSettle();
      expect(find.text('62.5 kg'), findsOneWidget);

      await tester.tap(find.byKey(const Key('btn_weight_down')));
      await tester.pumpAndSettle();
      expect(find.text('60 kg'), findsOneWidget);

      // レップ数ボタンのテスト (+1 / -1)
      await tester.tap(find.byKey(const Key('btn_reps_up')));
      await tester.pumpAndSettle();
      expect(find.text('11 回'), findsOneWidget);

      await tester.tap(find.byKey(const Key('btn_reps_down')));
      await tester.pumpAndSettle();
      expect(find.text('10 回'), findsOneWidget);

      // セット数ボタンのテスト (+1 / -1)
      await tester.tap(find.byKey(const Key('btn_sets_up')));
      await tester.pumpAndSettle();
      expect(find.text('2 セット'), findsOneWidget);

      await tester.tap(find.byKey(const Key('btn_sets_down')));
      await tester.pumpAndSettle();
      expect(find.text('1 セット'), findsOneWidget);
    });

    testWidgets('「次へ」ボタンでワークアウトが切り替わり、値がリセットされ、最後にレビューページへ遷移してホームに戻れること', (tester) async {
      await tester.pumpWidget(ButtonControlApp(ttsService: fakeTts));
      await tester.pumpAndSettle();

      // メイン画面からトレーニング画面へ遷移
      await tester.tap(find.byKey(const Key('start_training_button')));
      await tester.pumpAndSettle();

      // 1. ベンチプレスの初期値確認
      expect(find.text('ベンチプレス'), findsOneWidget);
      expect(find.text('60 kg'), findsOneWidget);
      expect(find.text('10 回'), findsOneWidget);
      expect(find.text('1 セット'), findsOneWidget);

      // 値を変更してみる
      await tester.ensureVisible(find.byKey(const Key('btn_weight_up')));
      await tester.tap(find.byKey(const Key('btn_weight_up')));
      await tester.pumpAndSettle();
      expect(find.text('62.5 kg'), findsOneWidget);

      // 「次へ」ボタンを押下 -> 2. デッドリフトへ遷移し、デフォルト値にリセットされる
      final nextButton = find.byKey(const Key('btn_next_workout'));
      expect(nextButton, findsOneWidget);
      expect(find.text('次へ'), findsOneWidget);

      await tester.ensureVisible(nextButton);
      await tester.tap(nextButton);
      await tester.pumpAndSettle();

      expect(find.text('デッドリフト'), findsOneWidget);
      expect(find.text('80 kg'), findsOneWidget);
      expect(find.text('8 回'), findsOneWidget);
      expect(find.text('1 セット'), findsOneWidget);

      // 「次へ」ボタンを押下 -> 3. レッグプレスへ遷移
      await tester.ensureVisible(nextButton);
      await tester.tap(nextButton);
      await tester.pumpAndSettle();

      expect(find.text('レッグプレス'), findsOneWidget);
      expect(find.text('100 kg'), findsOneWidget);
      expect(find.text('12 回'), findsOneWidget);
      expect(find.text('1 セット'), findsOneWidget);

      // 「次へ」ボタンを押下 -> レビューページへ遷移
      await tester.ensureVisible(nextButton);
      await tester.tap(nextButton);
      await tester.pumpAndSettle();

      expect(find.byType(ReviewScreen), findsOneWidget);
      expect(find.text('レビューページ'), findsNWidgets(2));
      expect(find.byKey(const Key('btn_finish_workout')), findsOneWidget);

      // 「ワークアウトを終了」を押下 -> ホーム画面に戻る
      await tester.ensureVisible(find.byKey(const Key('btn_finish_workout')));
      await tester.tap(find.byKey(const Key('btn_finish_workout')));
      await tester.pumpAndSettle();

      expect(find.byType(ReviewScreen), findsNothing);
      expect(find.byType(TrainingScreen), findsNothing);
      expect(find.byKey(const Key('waiting_prompt')), findsOneWidget);
    });
  });
}

class _TimelineDuckingController extends FakeAudioDuckingController {
  final List<String> timeline;
  _TimelineDuckingController(this.timeline);

  @override
  Future<void> configure() async {
    await super.configure();
    timeline.add('ducking.configure');
  }

  @override
  Future<void> requestDucking() async {
    await super.requestDucking();
    timeline.add('ducking.request');
  }

  @override
  Future<void> releaseDucking() async {
    await super.releaseDucking();
    timeline.add('ducking.release');
  }
}
