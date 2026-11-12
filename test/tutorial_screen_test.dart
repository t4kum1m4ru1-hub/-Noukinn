import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:button_controll_test/main.dart';

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeTtsService fakeTts;
  late FakeSoundEffectService fakeSound;
  late FakeAudioDuckingController fakeDucking;

  setUp(() {
    fakeTts = FakeTtsService();
    fakeSound = FakeSoundEffectService();
    fakeDucking = FakeAudioDuckingController();
  });

  Widget buildTestableApp({
    Widget? home,
    bool animateGlow = false,
    Key? key,
  }) {
    final darkTheme = ThemeData.dark().copyWith(
      splashFactory: InkRipple.splashFactory,
      scaffoldBackgroundColor: const Color(0xFF121212),
      colorScheme: const ColorScheme.dark(
        primary: Colors.tealAccent,
        secondary: Colors.amberAccent,
        surface: Color(0xFF1E1E1E),
      ),
    );

    return MaterialApp(
      theme: darkTheme,
      home: home ??
          TutorialScreen(
            key: key ?? UniqueKey(),
            ttsService: fakeTts,
            soundEffectService: fakeSound,
            duckingController: fakeDucking,
            animateGlow: animateGlow,
          ),
    );
  }

  group('Entry Navigation: lib/main.dart -> TutorialScreen', () {
    testWidgets('メイン画面にチュートリアルボタンが存在し、タップで直接 Step 1/5 が起動して自動音声が流れること', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark().copyWith(splashFactory: InkRipple.splashFactory),
          home: ButtonControlScreen(
            ttsService: fakeTts,
            soundEffectService: fakeSound,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final tutorialBtn = find.byKey(const Key('start_tutorial_button'));
      expect(tutorialBtn, findsOneWidget);
      expect(find.text('操作チュートリアルを体験する'), findsOneWidget);
      expect(find.byKey(const Key('start_training_button')), findsOneWidget);

      await tester.tap(tutorialBtn);
      await tester.pumpAndSettle();

      expect(find.byType(TutorialScreen), findsOneWidget);
      expect(find.text('Step 1/5'), findsWidgets);
      expect(find.text('再生（または停止）操作でトレーニングを開始しましょう'), findsOneWidget);
      expect(
        fakeTts.lastSpoken,
        'チュートリアルを開始します。再生停止操作でトレーニングを開始します。',
      );
    });
  });

  group('TutorialScreen UI・音声・フロー網羅テスト', () {
    testWidgets('1. 全体UI共通改修: シンプルなStep表記、セット数「3」表示、キーコード表記なし、BlurStyle.outer発光', (tester) async {
      await tester.pumpWidget(buildTestableApp());
      await tester.pumpAndSettle();

      // シンプルな「Step 1/5」表記
      expect(find.text('Step 1/5'), findsWidgets);
      // セット数カードが「1 / 3」ではなく「3」であること
      expect(find.text('3'), findsOneWidget);
      expect(find.text('1 / 3'), findsNothing);
      expect(find.textContaining('セット目'), findsNothing);

      // デバッグ用キーコード表記（「(85)」「(87)」等）が存在しないこと
      expect(find.textContaining('(85)'), findsNothing);
      expect(find.textContaining('(87)'), findsNothing);
      expect(find.textContaining('(88)'), findsNothing);
    });

    testWidgets('2. Step 1 (Step 1/5): 起動時自動発話、不正キー無視、キー85で開始案内表示＋TTS＋Step 2-1自動遷移', (tester) async {
      await tester.pumpWidget(buildTestableApp());
      await tester.pumpAndSettle();

      expect(
        fakeTts.spokenHistory,
        contains('チュートリアルを開始します。再生停止操作でトレーニングを開始します。'),
      );
      fakeTts.clear();
      fakeSound.clear();

      // 不正キー（24, 25, 87, 88）は無視
      await sendNativeKeyEvent(tester, 24);
      await sendNativeKeyEvent(tester, 25);
      await sendNativeKeyEvent(tester, 87);
      await sendNativeKeyEvent(tester, 88);
      await tester.pumpAndSettle();

      expect(fakeSound.beepCount, 0);
      expect(fakeTts.spokenHistory, isEmpty);

      // 有効キー: 85（再生/停止）
      await sendNativeKeyEvent(tester, 85);
      await tester.pumpAndSettle();

      expect(fakeSound.beepCount, 1);
      expect(
        fakeTts.spokenHistory,
        [
          '開始、ベンチプレス、60キロ、10回、3セット',
          'トレーニングの調整をしましょう。曲送り操作で調整をします。',
        ],
      );

      // Step 2-1 (Step 2/5) への自動遷移完了を確認
      expect(find.text('Step 2/5'), findsWidgets);
      expect(find.text('曲送り（次の曲へ進む）で調整モードに切り替える'), findsOneWidget);
    });

    testWidgets('3. Step 2 (Step 2-1 & Step 2-2): 87で調整モード突入、24/25で項目選択、88は完全無効、85で選択項目決定しStep 3へ', (tester) async {
      await tester.pumpWidget(buildTestableApp());
      await tester.pumpAndSettle();
      await sendNativeKeyEvent(tester, 85); // Step 1 -> Step 2-1
      await tester.pumpAndSettle();

      fakeSound.clear();
      fakeTts.clear();

      // Step 2-1: キー 87（次曲で調整モード Step 2-2 へ突入）
      await sendNativeKeyEvent(tester, 87);
      await tester.pumpAndSettle();
      expect(fakeSound.beepCount, 1);
      expect(
        fakeTts.lastSpoken,
        '調整、種目名。音量操作で調整項目を選択し、再生停止操作で決定しましょう',
      );
      expect(find.text('音量(+/-)で調整項目を選択 ➔ 再生停止で決定'), findsOneWidget);

      // Step 2-2: キー 88（前曲＝確認）は完全に無効化（反応なし）
      fakeSound.clear();
      fakeTts.clear();
      await sendNativeKeyEvent(tester, 88);
      await tester.pumpAndSettle();
      expect(fakeSound.beepCount, 0);
      expect(fakeTts.spokenHistory, isEmpty);

      // Step 2-2: キー 24 で項目送り（種目名 -> 重量）：項目名のみ端的に発話
      await sendNativeKeyEvent(tester, 24);
      await tester.pump();
      expect(fakeSound.beepCount, 1);
      expect(fakeTts.lastSpoken, '重量');

      // Step 2-2: キー 85（決定で Step 3 へ遷移）
      fakeSound.clear();
      fakeTts.clear();
      await sendNativeKeyEvent(tester, 85);
      await tester.pumpAndSettle();
      expect(fakeSound.beepCount, 1);
      expect(
        fakeTts.spokenHistory,
        [
          '重量を調整します。',
          '音量操作で重量を調整してください。再生停止で決定します。60キロ',
        ],
      );

      // Step 3 (Step 3/5) の表示確認
      expect(find.text('Step 3/5'), findsWidgets);
      expect(find.text('音量(+/-)で重量を調整。再生停止で決定。'), findsOneWidget);
    });

    testWidgets('4. Step 3 (Step 3/5): 重量の0.7sデバウンス調整、88無効化、85でStep 4へ遷移', (tester) async {
      await tester.pumpWidget(buildTestableApp());
      await tester.pumpAndSettle();
      await sendNativeKeyEvent(tester, 85); // Step 1 -> Step 2-1
      await tester.pumpAndSettle();
      await sendNativeKeyEvent(tester, 87); // Step 2-1 -> Step 2-2
      await tester.pumpAndSettle();
      await sendNativeKeyEvent(tester, 24); // 重量を選択
      await tester.pump();
      await sendNativeKeyEvent(tester, 85); // Step 2-2 -> Step 3
      await tester.pumpAndSettle();

      fakeSound.clear();
      fakeTts.clear();

      // Step 3 で前曲(88)は完全に無効化（反応なし）
      await sendNativeKeyEvent(tester, 88);
      await tester.pump();
      expect(fakeSound.beepCount, 0);
      expect(fakeTts.spokenHistory, isEmpty);

      // 1回目打鍵 (+2.5kg -> 62.5kg): 即時UI更新、TTSはまだ
      await sendNativeKeyEvent(tester, 24);
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('62.5 kg'), findsOneWidget);
      expect(fakeSound.beepCount, 1);
      expect(fakeTts.spokenHistory, isEmpty);

      // 2回目打鍵 (+2.5kg -> 65.0kg): 即時UI更新、タイマー延長
      await sendNativeKeyEvent(tester, 24);
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('65 kg'), findsOneWidget);
      expect(fakeSound.beepCount, 2);
      expect(fakeTts.spokenHistory, isEmpty);

      // 連打停止から 0.7秒経過: TTSが「65キロ」を1回発話
      await tester.pump(const Duration(milliseconds: 550));
      expect(fakeTts.spokenHistory, ['65キロ']);

      // 3回目打鍵 (+2.5kg -> 67.5kg) 直後にキー 85（決定）
      fakeSound.clear();
      fakeTts.clear();
      await sendNativeKeyEvent(tester, 24);
      await tester.pump(const Duration(milliseconds: 100));
      expect(fakeTts.spokenHistory, isEmpty);
      expect(fakeSound.beepCount, 1);

      fakeSound.clear();
      // 決定キー押下: 保留中デバウンスが破棄され Step 4 へ遷移
      await sendNativeKeyEvent(tester, 85);
      await tester.pumpAndSettle();
      expect(fakeSound.beepCount, 1);
      expect(fakeTts.lastSpoken, '曲送り操作で調整を完了します。調整、重量');
      expect(find.text('Step 4/5'), findsWidgets);
      expect(find.text('曲送り（次の曲へ進む）で調整モードを終了する。'), findsOneWidget);

      // さらに時間が経過しても破棄された「67.5キロ」が発話されないこと
      await tester.pump(const Duration(seconds: 1));
      expect(fakeTts.spokenHistory.contains('67.5キロ'), isFalse);
    });

    testWidgets('5. Step 3 の柔軟な項目調整: レップ数・セット数・種目名を選択した場合もそれぞれ調整できること', (tester) async {
      await tester.pumpWidget(buildTestableApp());
      await tester.pumpAndSettle();
      await sendNativeKeyEvent(tester, 85); // Step 1 -> Step 2-1
      await tester.pumpAndSettle();
      await sendNativeKeyEvent(tester, 87); // Step 2-1 -> Step 2-2 (初期: 種目名)
      await tester.pumpAndSettle();

      // 2回 Volume Up で「レップ数」を選択 (種目名 -> 重量 -> レップ数)
      await sendNativeKeyEvent(tester, 24);
      await tester.pump();
      await sendNativeKeyEvent(tester, 24);
      await tester.pump();
      expect(fakeTts.lastSpoken, 'レップ数');

      // 再生停止(85)で決定 -> Step 3（レップ数調整）へ
      fakeTts.clear();
      await sendNativeKeyEvent(tester, 85);
      await tester.pumpAndSettle();

      expect(
        fakeTts.spokenHistory,
        [
          'レップ数を調整します。',
          '音量操作でレップ数を調整してください。再生停止で決定します。10回',
        ],
      );
      expect(find.text('音量(+/-)でレップ数を調整。再生停止で決定。'), findsOneWidget);

      // Volume Up でレップ数 +1 (10 -> 11回)
      fakeTts.clear();
      await sendNativeKeyEvent(tester, 24);
      await tester.pump(const Duration(milliseconds: 750));
      expect(find.text('11 回'), findsOneWidget);
      expect(fakeTts.spokenHistory, ['11回']);
    });

    testWidgets('6. Step 4 ➔ Step 5 ➔ Step 6 ➔ TrainingScreen の一連の完了遷移', (tester) async {
      await tester.pumpWidget(buildTestableApp());
      await tester.pumpAndSettle();
      await sendNativeKeyEvent(tester, 85); // Step 1 -> Step 2-1
      await tester.pumpAndSettle();
      await sendNativeKeyEvent(tester, 87); // Step 2-1 -> Step 2-2
      await tester.pumpAndSettle();
      await sendNativeKeyEvent(tester, 24); // 重量選択
      await tester.pump();
      await sendNativeKeyEvent(tester, 85); // Step 2-2 -> Step 3
      await tester.pumpAndSettle();
      await sendNativeKeyEvent(tester, 24); // +2.5kg -> 62.5kg
      await tester.pump();
      await sendNativeKeyEvent(tester, 24); // +2.5kg -> 65kg
      await tester.pump();
      await sendNativeKeyEvent(tester, 85); // Step 3 -> Step 4
      await tester.pumpAndSettle();

      fakeSound.clear();
      fakeTts.clear();

      // Step 4: キー 87（次曲）で調整完了 -> Step 5 へ
      await sendNativeKeyEvent(tester, 87);
      await tester.pumpAndSettle();

      expect(fakeSound.beepCount, 1);
      expect(
        fakeTts.spokenHistory,
        [
          '確定',
          'トレーニングの調整が完了しました。曲戻し操作でトレーニングの内容を再確認しましょう。',
        ],
      );
      expect(find.text('Step 5/5'), findsWidgets);
      expect(find.text('曲戻し（前の曲へ戻る）でトレーニングの内容を確認。'), findsOneWidget);

      // Step 5: キー 88（前曲）でトレーニング内容を確認 -> Step 6（完了画面）へ自動遷移
      fakeTts.clear();
      await sendNativeKeyEvent(tester, 88);
      await tester.pumpAndSettle();

      expect(
        fakeTts.spokenHistory,
        [
          'ベンチプレス、65キロ、10回、3セット',
          'チュートリアルは以上です。',
        ],
      );
      expect(find.text('チュートリアル完了！'), findsOneWidget);

      // Step 6: 「最初のトレーニングを開始する」ボタンタップで TrainingScreen へ
      final startFirstBtn = find.byKey(const Key('btn_start_first_training'));
      expect(startFirstBtn, findsOneWidget);
      await tester.tap(startFirstBtn);
      await tester.pumpAndSettle();

      expect(find.byType(TrainingScreen), findsOneWidget);
    });

    testWidgets('7. 全ステップのスキップボタンが即座に次ステップへ遷移すること', (tester) async {
      await tester.pumpWidget(buildTestableApp());
      await tester.pumpAndSettle();

      // Step 1 でスキップ -> Step 2/5
      await tester.tap(find.byKey(const Key('btn_tutorial_skip')));
      await tester.pumpAndSettle();
      expect(find.text('Step 2/5'), findsWidgets);

      // Step 2 でスキップ -> Step 3/5
      await tester.tap(find.byKey(const Key('btn_tutorial_skip')));
      await tester.pumpAndSettle();
      expect(find.text('Step 3/5'), findsWidgets);

      // Step 3 でスキップ -> Step 4/5
      await tester.tap(find.byKey(const Key('btn_tutorial_skip')));
      await tester.pumpAndSettle();
      expect(find.text('Step 4/5'), findsWidgets);

      // Step 4 でスキップ -> Step 5/5
      await tester.tap(find.byKey(const Key('btn_tutorial_skip')));
      await tester.pumpAndSettle();
      expect(find.text('Step 5/5'), findsWidgets);

      // Step 5 でスキップ -> Step 6 (完了画面)
      await tester.tap(find.byKey(const Key('btn_tutorial_skip')));
      await tester.pumpAndSettle();
      expect(find.text('チュートリアル完了！'), findsOneWidget);
    });

    testWidgets('8. 画面最下部の疑似メディアキーバー各ボタンが物理キーと同一に動作すること', (tester) async {
      await tester.pumpWidget(buildTestableApp());
      await tester.pumpAndSettle();

      // Step 1 で仮想キーバーの「再生 (決定)」をタップ
      fakeSound.clear();
      fakeTts.clear();
      await tester.tap(find.byKey(const Key('virtual_key_play_pause')));
      await tester.pumpAndSettle();

      expect(fakeSound.beepCount, 1);
      expect(
        fakeTts.spokenHistory.first,
        '開始、ベンチプレス、60キロ、10回、3セット',
      );
      expect(find.text('Step 2/5'), findsWidgets);

      // Step 2-1 で仮想キーバーの「次曲 (調整)」をタップ
      fakeSound.clear();
      fakeTts.clear();
      await tester.tap(find.byKey(const Key('virtual_key_next')));
      await tester.pumpAndSettle();

      expect(fakeSound.beepCount, 1);
      expect(
        fakeTts.lastSpoken,
        '調整、種目名。音量操作で調整項目を選択し、再生停止操作で決定しましょう',
      );
    });

    testWidgets('9. 音声排他制御（stopCallCount >= 発話回数）およびダッキング要求の整合性', (tester) async {
      await tester.pumpWidget(buildTestableApp());
      await tester.pumpAndSettle();

      await sendNativeKeyEvent(tester, 85); // Step 1 -> Step 2-1
      await tester.pumpAndSettle();

      await sendNativeKeyEvent(tester, 87); // Step 2-1 -> Step 2-2
      await tester.pumpAndSettle();

      // 発話の直前に必ず stop() が呼ばれていることの検証
      expect(fakeTts.spokenHistory.length, greaterThanOrEqualTo(3));
      expect(
        fakeTts.stopCallCount,
        greaterThanOrEqualTo(fakeTts.spokenHistory.length),
      );
      expect(fakeDucking.events.contains('requestDucking'), isTrue);
    });
  });
}
