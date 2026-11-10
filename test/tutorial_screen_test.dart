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
    testWidgets('メイン画面にチュートリアルボタンが存在し、タップでTutorialScreenへ遷移できること', (tester) async {
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

      // ボタンの存在確認
      final tutorialBtn = find.byKey(const Key('start_tutorial_button'));
      expect(tutorialBtn, findsOneWidget);
      expect(find.text('操作チュートリアルを体験する'), findsOneWidget);

      // 既存のトレーニング開始ボタンも健在であること
      expect(find.byKey(const Key('start_training_button')), findsOneWidget);

      // タップして TutorialScreen へ遷移
      await tester.tap(tutorialBtn);
      await tester.pumpAndSettle();

      expect(find.byType(TutorialScreen), findsOneWidget);
    });
  });

  group('TutorialScreen Widget Test Suite (Matrix 1 - 9)', () {
    testWidgets('1. Step 1: 表示検証、開始タップでStep 2遷移、スキップでTrainingScreen直行', (tester) async {
      // 1a: 開始ボタンで Step 2 へ
      await tester.pumpWidget(buildTestableApp());
      await tester.pumpAndSettle();

      expect(find.text('のう筋 操作チュートリアル'), findsOneWidget);
      final startBtn = find.byKey(const Key('btn_tutorial_start'));
      expect(startBtn, findsOneWidget);

      await tester.tap(startBtn);
      await tester.pumpAndSettle();

      // Step 2 の案内文が表示されること
      expect(find.textContaining('再生/停止'), findsOneWidget);

      // 1b: スキップボタンで本編 TrainingScreen へ直行
      await tester.pumpWidget(buildTestableApp());
      await tester.pumpAndSettle();

      final skipAllBtn = find.byKey(const Key('btn_tutorial_skip_all'));
      expect(skipAllBtn, findsOneWidget);

      await tester.tap(skipAllBtn);
      await tester.pumpAndSettle();

      expect(find.byType(TrainingScreen), findsOneWidget);
    });

    testWidgets('2. Step 2: 不正キー無視、キー85でビープ＋開始TTS＋Step 3自動遷移', (tester) async {
      await tester.pumpWidget(buildTestableApp());
      await tester.pumpAndSettle();

      // Step 1 -> Step 2
      await tester.tap(find.byKey(const Key('btn_tutorial_start')));
      await tester.pumpAndSettle();

      // 不正キー（24, 25, 87）は無視
      await sendNativeKeyEvent(tester, 24);
      await sendNativeKeyEvent(tester, 25);
      await sendNativeKeyEvent(tester, 87);
      await tester.pumpAndSettle();

      expect(fakeSound.beepCount, 0);
      expect(fakeTts.spokenHistory, isEmpty);

      // 有効キー: 85（再生/停止）
      await sendNativeKeyEvent(tester, 85);
      await tester.pumpAndSettle();

      expect(fakeSound.beepCount, 1);
      expect(fakeTts.lastSpoken, '開始、ベンチプレス、60キロ、10回、3セット');

      // Step 3 への自動遷移完了を確認（次曲ボタン案内の表示）
      expect(find.textContaining('次の曲へ進む'), findsOneWidget);
    });

    testWidgets('3. Step 3: Part 1(87で調整突入・88確認)、Part 2(24/25項目送り・85決定でStep 4遷移)', (tester) async {
      await tester.pumpWidget(buildTestableApp());
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('btn_tutorial_start')));
      await tester.pumpAndSettle();
      await sendNativeKeyEvent(tester, 85); // Step 2 完了
      await tester.pumpAndSettle();

      fakeSound.clear();
      fakeTts.clear();

      // Part 1: キー 88（確認ボタン）
      await sendNativeKeyEvent(tester, 88);
      await tester.pump();
      expect(fakeTts.lastSpoken, 'ベンチプレス、60キロ、10回、3セット');

      // Part 1: キー 87（次曲で調整モード突入）
      await sendNativeKeyEvent(tester, 87);
      await tester.pumpAndSettle();
      expect(fakeSound.beepCount, 1);
      expect(fakeTts.lastSpoken, '調整、種目名');

      // Part 2: キー 24 で項目送り（種目名 -> 重量）
      fakeSound.clear();
      await sendNativeKeyEvent(tester, 24);
      await tester.pump();
      expect(fakeSound.beepCount, 1);
      expect(fakeTts.lastSpoken, '重量');

      // Part 2: キー 88（確認ボタン）
      await sendNativeKeyEvent(tester, 88);
      await tester.pump();
      expect(fakeTts.lastSpoken, 'ベンチプレス、60キロ、10回、3セット');

      // Part 2: キー 85（決定で Step 4 へ遷移）
      fakeSound.clear();
      await sendNativeKeyEvent(tester, 85);
      await tester.pumpAndSettle();
      expect(fakeSound.beepCount, 1);
      expect(fakeTts.lastSpoken, '60キロ');

      // Step 4 の表示確認（重量カード表示）
      expect(find.byKey(const Key('card_weight')), findsOneWidget);
    });

    testWidgets('4. Step 4: 24/25連打で±2.5kg即時更新＋0.7sデバウンスTTS、85でデバウンス破棄＆Step 5遷移', (tester) async {
      await tester.pumpWidget(buildTestableApp());
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('btn_tutorial_start')));
      await tester.pumpAndSettle();
      await sendNativeKeyEvent(tester, 85); // Step 2
      await tester.pumpAndSettle();
      await sendNativeKeyEvent(tester, 87); // Step 3 Part 1
      await tester.pumpAndSettle();
      await sendNativeKeyEvent(tester, 24); // 重量選択
      await tester.pump();
      await sendNativeKeyEvent(tester, 85); // Step 4 突入
      await tester.pumpAndSettle();

      fakeSound.clear();
      fakeTts.clear();

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

      // 連打停止から 0.7秒（550ms + 前の200ms = 750ms）経過: TTSが「65キロ」を1回発話
      await tester.pump(const Duration(milliseconds: 550));
      expect(fakeTts.spokenHistory, ['65キロ']);

      // キー 88（確認ボタン）
      await sendNativeKeyEvent(tester, 88);
      await tester.pump();
      expect(fakeTts.lastSpoken, 'ベンチプレス、65キロ、10回、3セット');

      // 3回目打鍵 (+2.5kg -> 67.5kg) 直後にキー 85（決定）
      fakeSound.clear();
      fakeTts.clear();
      await sendNativeKeyEvent(tester, 24);
      await tester.pump(const Duration(milliseconds: 100));
      expect(fakeTts.spokenHistory, isEmpty);
      expect(fakeSound.beepCount, 1);

      fakeSound.clear();
      // 決定キー押下: 保留中デバウンスが破棄され「調整、重量」を発話して Step 5 へ
      await sendNativeKeyEvent(tester, 85);
      await tester.pumpAndSettle();
      expect(fakeSound.beepCount, 1);
      expect(fakeTts.lastSpoken, '調整、重量');

      // さらに時間が経過しても破棄された「67.5キロ」が発話されないこと
      await tester.pump(const Duration(seconds: 1));
      expect(fakeTts.spokenHistory.contains('67.5キロ'), isFalse);
    });

    testWidgets('5. Step 5: 対象外キーで注意案内、キー87で確定＋全体内容TTS＋Step 6自動遷移', (tester) async {
      await tester.pumpWidget(buildTestableApp());
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('btn_tutorial_start')));
      await tester.pumpAndSettle();
      await sendNativeKeyEvent(tester, 85); // Step 2
      await tester.pumpAndSettle();
      await sendNativeKeyEvent(tester, 87); // Step 3
      await tester.pumpAndSettle();
      await sendNativeKeyEvent(tester, 85); // Step 3 decide
      await tester.pumpAndSettle();
      await sendNativeKeyEvent(tester, 85); // Step 4 decide -> Step 5
      await tester.pumpAndSettle();

      fakeSound.clear();
      fakeTts.clear();

      // 対象外キー（85, 24）押下: 遷移せず注意文言が表示されること
      await sendNativeKeyEvent(tester, 85);
      await tester.pump();
      expect(find.textContaining('［次の曲へ進む］ボタンを押して調整を完了してください'), findsOneWidget);

      // キー 87 で確定
      await sendNativeKeyEvent(tester, 87);
      await tester.pumpAndSettle();

      expect(fakeSound.beepCount, 1);
      expect(fakeTts.lastSpoken, '確定、開始、ベンチプレス、60キロ、10回、3セット');

      // Step 6 への自動遷移確認
      expect(find.textContaining('チュートリアル完了'), findsOneWidget);
    });

    testWidgets('6. Step 6: 完了画面表示、ボタンタップまたはキー85で本編TrainingScreenへ遷移', (tester) async {
      await tester.pumpWidget(buildTestableApp());
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('btn_tutorial_start')));
      await tester.pumpAndSettle();
      await sendNativeKeyEvent(tester, 85); // 2
      await tester.pumpAndSettle();
      await sendNativeKeyEvent(tester, 87); // 3
      await tester.pumpAndSettle();
      await sendNativeKeyEvent(tester, 85); // 3 decide
      await tester.pumpAndSettle();
      await sendNativeKeyEvent(tester, 85); // 4 decide
      await tester.pumpAndSettle();
      await sendNativeKeyEvent(tester, 87); // 5 finish -> 6
      await tester.pumpAndSettle();

      expect(find.textContaining('チュートリアル完了'), findsOneWidget);

      // 「最初のトレーニングを開始する」ボタンタップで TrainingScreen へ
      final startFirstBtn = find.byKey(const Key('btn_start_first_training'));
      expect(startFirstBtn, findsOneWidget);

      await tester.tap(startFirstBtn);
      await tester.pumpAndSettle();

      expect(find.byType(TrainingScreen), findsOneWidget);
    });

    testWidgets('7. 全ステップのスキップボタンが即座に次ステップ/本編へ遷移すること', (tester) async {
      await tester.pumpWidget(buildTestableApp());
      await tester.pumpAndSettle();

      // Step 1 -> Step 2
      await tester.tap(find.byKey(const Key('btn_tutorial_start')));
      await tester.pumpAndSettle();

      // Step 2 でスキップ
      await tester.tap(find.byKey(const Key('btn_tutorial_skip')));
      await tester.pumpAndSettle();
      expect(find.textContaining('次の曲へ進む'), findsOneWidget); // Step 3

      // Step 3 でスキップ
      await tester.tap(find.byKey(const Key('btn_tutorial_skip')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('card_weight')), findsOneWidget); // Step 4

      // Step 4 でスキップ
      await tester.tap(find.byKey(const Key('btn_tutorial_skip')));
      await tester.pumpAndSettle();
      expect(find.textContaining('調整を完了'), findsOneWidget); // Step 5

      // Step 5 でスキップ
      await tester.tap(find.byKey(const Key('btn_tutorial_skip')));
      await tester.pumpAndSettle();
      expect(find.textContaining('チュートリアル完了'), findsOneWidget); // Step 6
    });

    testWidgets('8. 画面最下部の疑似メディアキーバー各ボタンが物理キーと同一に動作すること', (tester) async {
      await tester.pumpWidget(buildTestableApp());
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('btn_tutorial_start')));
      await tester.pumpAndSettle();

      // Step 2 で仮想キーバーの「再生/停止」をタップ
      fakeSound.clear();
      fakeTts.clear();
      await tester.tap(find.byKey(const Key('virtual_key_play_pause')));
      await tester.pumpAndSettle();

      expect(fakeSound.beepCount, 1);
      expect(fakeTts.lastSpoken, '開始、ベンチプレス、60キロ、10回、3セット');

      // Step 3 で仮想キーバーの「次曲」をタップ
      fakeSound.clear();
      fakeTts.clear();
      await tester.tap(find.byKey(const Key('virtual_key_next')));
      await tester.pumpAndSettle();

      expect(fakeSound.beepCount, 1);
      expect(fakeTts.lastSpoken, '調整、種目名');
    });

    testWidgets('9. 音声排他制御（stopCallCount >= 発話回数）およびダッキング要求の整合性', (tester) async {
      await tester.pumpWidget(buildTestableApp());
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('btn_tutorial_start')));
      await tester.pumpAndSettle();

      // Step 2 開始発話
      await sendNativeKeyEvent(tester, 85);
      await tester.pumpAndSettle();

      // Step 3 突入発話
      await sendNativeKeyEvent(tester, 87);
      await tester.pumpAndSettle();

      // 発話の直前に必ず stop() が呼ばれていることの検証
      expect(fakeTts.spokenHistory.length, greaterThanOrEqualTo(2));
      expect(fakeTts.stopCallCount, greaterThanOrEqualTo(fakeTts.spokenHistory.length));

      // ダッキング要求が実行された履歴があること
      expect(fakeDucking.events.contains('requestDucking'), isTrue);
    });
  });

  group('Visual & Glow Animation Unit Test', () {
    testWidgets('animateGlow: true で有限フレーム進めた際にアニメーションが正常に稼働すること', (tester) async {
      await tester.pumpWidget(buildTestableApp(animateGlow: true));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 300));
      // 例外なくフレーム更新が進むことを確認
      expect(find.byType(TutorialScreen), findsOneWidget);
    });
  });
}
