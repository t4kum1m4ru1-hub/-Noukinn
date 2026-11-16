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
      expect(ButtonAction.fromKeyCode(4), isNull); // KEYCODE_BACK
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

      await ttsService.speak('音量アップを検知しました');
      expect(fakeDucking.isCurrentlyDucked, isTrue);

      await ttsService.speak('曲送りを検知しました');
      expect(fakeDucking.isCurrentlyDucked, isTrue);

      expect(timeline, [
        'ducking.request',
        'tts.speak:音量アップを検知しました',
        'tts.stop',
        'ducking.release',
        'ducking.request',
        'tts.speak:曲送りを検知しました',
      ]);

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
      await tester.pumpWidget(
        ButtonControlApp(ttsService: fakeTts, skipOnboarding: true),
      );
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
      await tester.pumpWidget(
        ButtonControlApp(ttsService: fakeTts, skipOnboarding: true),
      );
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
      await tester.pumpWidget(
        ButtonControlApp(ttsService: fakeTts, skipOnboarding: true),
      );
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
      await tester.pumpWidget(
        ButtonControlApp(ttsService: fakeTts, skipOnboarding: true),
      );
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

  group('Widget Tests: TrainingScreen UI & ステートマシン・メディアキー新仕様検証', () {
    late FakeTtsService fakeTts;
    late FakeSoundEffectService fakeSound;

    setUp(() {
      fakeTts = FakeTtsService();
      fakeSound = FakeSoundEffectService();
    });

    testWidgets('メイン画面から「トレーニング開始」をタップしてトレーニング画面に遷移し、戻るボタンでメインに戻れること', (
      tester,
    ) async {
      await tester.pumpWidget(
        ButtonControlApp(
          ttsService: fakeTts,
          soundEffectService: fakeSound,
          skipOnboarding: true,
        ),
      );
      await tester.pumpAndSettle();

      final startButton = find.byKey(const Key('start_training_button'));
      expect(startButton, findsOneWidget);

      await tester.tap(startButton);
      await tester.pumpAndSettle();

      expect(find.byType(TrainingScreen), findsOneWidget);
      expect(find.text('ベンチプレス'), findsOneWidget);
      expect(find.byKey(const Key('training_back_button')), findsOneWidget);
      expect(find.byKey(const Key('exercise_image')), findsOneWidget);

      // 疑似メディアキーバーの新ラベル確認
      expect(find.text('前曲 (内容確認)'), findsOneWidget);
      expect(find.text('再生/停止 (決定/次へ)'), findsOneWidget);
      expect(find.text('次曲 (調整/完了)'), findsOneWidget);
      expect(find.text('Vol-'), findsOneWidget);
      expect(find.text('Vol+'), findsOneWidget);

      await tester.tap(find.byKey(const Key('training_back_button')));
      await tester.pumpAndSettle();

      expect(find.byType(TrainingScreen), findsNothing);
      expect(find.byKey(const Key('waiting_prompt')), findsOneWidget);
    });

    testWidgets('3つのカード（重量・レップ数・セット数）の＋/−タップで電子音再生＋0.7秒デバウンスTTSが動作すること', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: TrainingScreen(
            ttsService: fakeTts,
            soundEffectService: fakeSound,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('重量'), findsOneWidget);
      expect(find.text('60 kg'), findsOneWidget);
      expect(find.text('レップ数'), findsOneWidget);
      expect(find.text('10 回'), findsOneWidget);
      expect(find.text('セット数'), findsOneWidget);
      expect(find.text('3 セット'), findsOneWidget);

      // 重量ボタンのテスト (+2.5kg): タップ直後は電子音のみ鳴り、0.7秒後にTTS発話
      await tester.ensureVisible(find.byKey(const Key('btn_weight_up')));
      await tester.tap(find.byKey(const Key('btn_weight_up')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('62.5 kg'), findsOneWidget);
      expect(fakeSound.beepCount, 1);
      expect(fakeTts.spokenHistory, isEmpty);

      await tester.pump(const Duration(milliseconds: 450));
      expect(fakeTts.lastSpoken, '62.5kg');

      await tester.tap(find.byKey(const Key('btn_weight_down')));
      await tester.pumpAndSettle();
      expect(find.text('60 kg'), findsOneWidget);
      expect(fakeTts.lastSpoken, '60kg');

      // レップ数ボタンのテスト (+1 / -1)
      await tester.ensureVisible(find.byKey(const Key('btn_reps_up')));
      await tester.tap(find.byKey(const Key('btn_reps_up')));
      await tester.pumpAndSettle();
      expect(find.text('11 回'), findsOneWidget);
      expect(fakeTts.lastSpoken, '11回');

      await tester.tap(find.byKey(const Key('btn_reps_down')));
      await tester.pumpAndSettle();
      expect(find.text('10 回'), findsOneWidget);
      expect(fakeTts.lastSpoken, '10回');

      // セット数ボタンのテスト (+1 / -1)
      await tester.ensureVisible(find.byKey(const Key('btn_sets_up')));
      await tester.tap(find.byKey(const Key('btn_sets_up')));
      await tester.pumpAndSettle();
      expect(find.text('4 セット'), findsOneWidget);
      expect(fakeTts.lastSpoken, '4セット');

      await tester.tap(find.byKey(const Key('btn_sets_down')));
      await tester.pumpAndSettle();
      expect(find.text('3 セット'), findsOneWidget);
      expect(fakeTts.lastSpoken, '3セット');
    });

    testWidgets(
      '状態A：開始前➔「開始」発話、進行中➔「次へ」遷移＆発話、最終種目➔「完了、お疲れ様でした」＆レビュー画面遷移',
      (tester) async {
        await tester.pumpWidget(
          ButtonControlApp(
            ttsService: fakeTts,
            soundEffectService: fakeSound,
            skipOnboarding: true,
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('start_training_button')));
        await tester.pumpAndSettle();

        final nextButton = find.byKey(const Key('btn_next_workout'));
        expect(find.text('ベンチプレス'), findsOneWidget);
        expect(
          tester
              .widget<Text>(
                find.descendant(
                  of: nextButton,
                  matching: find.byType(Text),
                ),
              )
              .data,
          '開始',
        );

        // 通常モード時の音量キー（24, 25）は無効（重量が変化しないこと）
        await sendNativeKeyEvent(tester, 24);
        await tester.pump();
        expect(find.text('60 kg'), findsOneWidget);
        expect(fakeTts.spokenHistory, isEmpty);

        // 1回目押下（開始前 ➔ 進行中）：「開始、ベンチプレス、60kg、10回、3セット」
        await tester.ensureVisible(nextButton);
        await tester.tap(nextButton);
        await tester.pumpAndSettle();
        expect(fakeTts.lastSpoken, '開始、ベンチプレス、60kg、10回、3セット');
        expect(
          tester
              .widget<Text>(
                find.descendant(
                  of: nextButton,
                  matching: find.byType(Text),
                ),
              )
              .data,
          '次へ',
        );

        // ［前の曲へ (88)］（確認ボタン）：現在状態の読み上げのみ
        await sendNativeKeyEvent(tester, 88);
        await tester.pumpAndSettle();
        expect(fakeTts.lastSpoken, 'ベンチプレス、60kg、10回、3セット');

        // 2回目押下（2種目目：レッグプレスへ遷移）
        await tester.ensureVisible(nextButton);
        await tester.tap(nextButton);
        await tester.pumpAndSettle();
        expect(find.text('レッグプレス'), findsOneWidget);
        expect(find.text('80 kg'), findsOneWidget);
        expect(find.text('10 回'), findsOneWidget);
        expect(find.text('3 セット'), findsOneWidget);
        expect(fakeTts.lastSpoken, '次へ、レッグプレス、80kg、10回、3セット');

        // 3回目押下（3種目目：デッドリフトへ遷移）
        await tester.ensureVisible(nextButton);
        await tester.tap(nextButton);
        await tester.pumpAndSettle();
        expect(find.text('デッドリフト'), findsOneWidget);
        expect(find.text('100 kg'), findsOneWidget);
        expect(find.text('8 回'), findsOneWidget);
        expect(find.text('3 セット'), findsOneWidget);
        expect(fakeTts.lastSpoken, '次へ、デッドリフト、100kg、8回、3セット');

        // 4回目押下（最終種目完了 ➔ レビューページへ遷移）
        await tester.ensureVisible(nextButton);
        await tester.tap(nextButton);
        await tester.pumpAndSettle();
        expect(fakeTts.lastSpoken, '完了、お疲れ様でした');
        expect(find.byType(ReviewScreen), findsOneWidget);

        await tester.ensureVisible(find.byKey(const Key('btn_finish_workout')));
        await tester.tap(find.byKey(const Key('btn_finish_workout')));
        await tester.pumpAndSettle();
        expect(find.byType(ReviewScreen), findsNothing);
        expect(find.byType(TrainingScreen), findsNothing);
      },
    );

    testWidgets(
      '新仕様メディアキー：次曲(87)=調整モードトグル、再生停止(85)=決定、前曲(88)=全モード共通確認ボタンが完全動作すること',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: TrainingScreen(
              ttsService: fakeTts,
              soundEffectService: fakeSound,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // 1. 通常モードで［次の曲へ (87)］➔ 調整モード（階層1：初期選択「種目名」）へ移行
        await sendNativeKeyEvent(tester, 87);
        await tester.pump();
        expect(fakeTts.lastSpoken, '調整、種目名');

        // 2. 階層1で［前の曲へ (88)］➔ 状態遷移せず、現在の種目内容のみを読み上げ確認
        await sendNativeKeyEvent(tester, 88);
        await tester.pump();
        expect(fakeTts.lastSpoken, 'ベンチプレス、60kg、10回、3セット');
        expect(find.text('状態B: 項目選択［種目名］'), findsOneWidget);

        // 3. 階層1で［音量UP (24)］➔「重量」へ項目送り
        await sendNativeKeyEvent(tester, 24);
        await tester.pump();
        expect(fakeTts.lastSpoken, '重量');

        // 4. 階層1で［再生/停止 (85)］（決定）➔ 階層2（重量調整）へ移行し、電子音＋現在値「60kg」を発話
        fakeSound.clear();
        await sendNativeKeyEvent(tester, 85);
        await tester.pump();
        expect(fakeSound.beepCount, 1);
        expect(fakeTts.lastSpoken, '60kg');
        expect(find.text('状態C: 値調整［重量］'), findsOneWidget);

        // 5. 階層2で［音量UP (24)］を0.2秒間隔で3回連続押下（60 -> 62.5 -> 65 -> 67.5kg）
        fakeTts.clear();
        fakeSound.clear();

        await sendNativeKeyEvent(tester, 24);
        await tester.pump(const Duration(milliseconds: 200));
        expect(find.text('62.5 kg'), findsOneWidget);
        expect(fakeTts.spokenHistory, isEmpty);

        await sendNativeKeyEvent(tester, 24);
        await tester.pump(const Duration(milliseconds: 200));
        expect(find.text('65 kg'), findsOneWidget);
        expect(fakeTts.spokenHistory, isEmpty);

        await sendNativeKeyEvent(tester, 24);
        await tester.pump(const Duration(milliseconds: 200));
        expect(find.text('67.5 kg'), findsOneWidget);
        expect(fakeSound.beepCount, 3);
        expect(fakeTts.spokenHistory, isEmpty);

        // 合計0.75秒経過でデバウンス発話「67.5kg」が1回だけ実行される
        await tester.pump(const Duration(milliseconds: 550));
        expect(fakeTts.spokenHistory, ['67.5kg']);

        // 6. 階層2で［前の曲へ (88)］（確認ボタン）➔ 値や階層を変えずに現在内容を読み上げ確認
        await sendNativeKeyEvent(tester, 88);
        await tester.pump();
        expect(find.text('67.5 kg'), findsOneWidget);
        expect(find.text('状態C: 値調整［重量］'), findsOneWidget);
        expect(fakeTts.lastSpoken, 'ベンチプレス、67.5kg、10回、3セット');

        // 7. 階層2で［再生/停止 (85)］（決定）➔ 変更値を確定して階層1へ戻る（電子音＋「調整、重量」）
        fakeSound.clear();
        await sendNativeKeyEvent(tester, 85);
        await tester.pump();
        expect(fakeSound.beepCount, 1);
        expect(find.text('状態B: 項目選択［重量］'), findsOneWidget);
        expect(fakeTts.lastSpoken, '調整、重量');

        // 8. 階層1で［音量DOWN (25)］➔「種目名」に戻し、［再生/停止 (85)］で階層2へ入り種目をレッグプレスへ変更
        await sendNativeKeyEvent(tester, 25); // 種目名
        await tester.pump();
        expect(fakeTts.lastSpoken, '種目名');

        await sendNativeKeyEvent(tester, 85); // 階層2（種目名調整）へ
        await tester.pump();
        expect(fakeTts.lastSpoken, 'ベンチプレス');

        await sendNativeKeyEvent(tester, 24); // 候補をレッグプレスへ
        await tester.pump(const Duration(milliseconds: 750));
        expect(find.text('レッグプレス'), findsOneWidget);
        expect(fakeTts.lastSpoken, 'レッグプレス');

        // 9. 階層2から直接［次の曲へ (87)］（調整モードのトグル完了）を押下 ➔
        //    種目スワップを確定反映して一発で通常モードへ復帰！
        await sendNativeKeyEvent(tester, 87);
        await tester.pump();
        expect(find.text('状態A: 通常（進行中）'), findsOneWidget);
        expect(find.text('レッグプレス'), findsOneWidget);
        expect(find.text('80 kg'), findsOneWidget);
        expect(fakeTts.lastSpoken, '確定、開始、レッグプレス、80kg、10回、3セット');
      },
    );
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
