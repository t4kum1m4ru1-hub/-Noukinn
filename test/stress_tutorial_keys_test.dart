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

  /// ヘルパー: 指定されたステップまで迅速に進める
  Future<void> navigateToStep(WidgetTester tester, int targetStep) async {
    await tester.pumpWidget(buildTestableApp());
    await tester.pumpAndSettle();

    if (targetStep >= 2) {
      // Step 1 -> Step 2
      await tester.tap(find.byKey(const Key('btn_tutorial_start')));
      await tester.pumpAndSettle();
    }
    if (targetStep >= 3) {
      // Step 2 -> Step 3
      await sendNativeKeyEvent(tester, 85);
      await tester.pumpAndSettle();
    }
    if (targetStep >= 4) {
      // Step 3 enterMode -> cycleItem -> Step 4
      await sendNativeKeyEvent(tester, 87); // enter mode
      await tester.pumpAndSettle();
      await sendNativeKeyEvent(tester, 24); // cycle to weight
      await tester.pump();
      await sendNativeKeyEvent(tester, 85); // select weight -> Step 4
      await tester.pumpAndSettle();
    }
    if (targetStep >= 5) {
      // Step 4 -> Step 5
      await sendNativeKeyEvent(tester, 85);
      await tester.pumpAndSettle();
    }
    if (targetStep >= 6) {
      // Step 5 -> Step 6
      await sendNativeKeyEvent(tester, 87);
      await tester.pumpAndSettle();
    }

    fakeSound.clear();
    fakeTts.clear();
    fakeDucking.events.clear();
  }

  // ==========================================================================
  // Group 1: 不正・予期せぬキー入力の網羅的敵対的検証 (Step 1〜6)
  // ==========================================================================
  group('1. Adversarial Invalid Key Events Matrix across all Steps', () {
    testWidgets('Step 1 (Intro): 音量キー/次曲/前曲/未知キー(999)は無視され、85または79でStep 2へ遷移すること', (tester) async {
      await tester.pumpWidget(buildTestableApp());
      await tester.pumpAndSettle();

      // 不正キーの連続送信
      for (final code in [24, 25, 87, 88, 999, 4, 126]) {
        await sendNativeKeyEvent(tester, code);
      }
      await tester.pumpAndSettle();

      expect(fakeSound.beepCount, 0);
      expect(fakeTts.spokenHistory, isEmpty);
      expect(find.text('のう筋 操作チュートリアル'), findsOneWidget);

      // 有効キー 79 (HeadsetHook) で Step 2 へ進むこと
      await sendNativeKeyEvent(tester, 79);
      await tester.pumpAndSettle();

      expect(find.textContaining('イヤホンの［再生/停止］ボタンを押して'), findsOneWidget);
    });

    testWidgets('Step 2 (Start Experience): 音量キー(24, 25)/次曲(87)/前曲(88)の連打攻撃を完全に無視すること', (tester) async {
      await navigateToStep(tester, 2);

      // 10回の音量・次曲・前曲スパム
      for (int i = 0; i < 10; i++) {
        await sendNativeKeyEvent(tester, 24);
        await sendNativeKeyEvent(tester, 25);
        await sendNativeKeyEvent(tester, 87);
        await sendNativeKeyEvent(tester, 88);
      }
      await tester.pumpAndSettle();

      // 音声・効果音・画面遷移が一切発火しないこと
      expect(fakeSound.beepCount, 0);
      expect(fakeTts.spokenHistory, isEmpty);
      expect(find.textContaining('STEP 1/5: 開始操作'), findsOneWidget);

      // 有効キー 85 で開始すること
      await sendNativeKeyEvent(tester, 85);
      await tester.pumpAndSettle();

      expect(fakeSound.beepCount, 1);
      expect(fakeTts.lastSpoken, '開始、ベンチプレス、60キロ、10回、3セット');
      expect(find.textContaining('STEP 2/5 (1/2): 調整モード起動'), findsOneWidget);
    });

    testWidgets('Step 2 (Start Experience): キー85の連続連打（ダブルクリック等）で多重発話・重複ビープが発生しないこと（再入防止）', (tester) async {
      await navigateToStep(tester, 2);

      // キー85を連続して送信
      await sendNativeKeyEvent(tester, 85);
      await sendNativeKeyEvent(tester, 85);
      await tester.pumpAndSettle();

      // 1回だけ処理されるべき（再入防止）
      expect(fakeSound.beepCount, 1, reason: 'Step 2 開始キーの連打でビープが重複再生されてはならない');
      expect(fakeTts.spokenHistory.length, 1, reason: 'Step 2 開始キーの連打で多重発話されてはならない');
      expect(fakeTts.lastSpoken, '開始、ベンチプレス、60キロ、10回、3セット');
      expect(find.textContaining('STEP 2/5 (1/2): 調整モード起動'), findsOneWidget);
    });

    testWidgets('Step 5 (Adjustment Completion): 確定キー(87)の連続連打で多重発話・重複ビープが発生しないこと（再入防止）', (tester) async {
      await navigateToStep(tester, 5);

      // 次曲(87)を連続して送信
      await sendNativeKeyEvent(tester, 87);
      await sendNativeKeyEvent(tester, 87);
      await tester.pumpAndSettle();

      // 1回だけ処理されるべき（再入防止）
      expect(fakeSound.beepCount, 1, reason: 'Step 5 確定キー連打でビープが重複再生されてはならない');
      expect(fakeTts.spokenHistory.length, 1, reason: 'Step 5 確定キー連打で多重発話されてはならない');
      expect(find.textContaining('🎉 チュートリアル完了！'), findsOneWidget);
    });

    testWidgets('Step 3 Part 1 (Enter Mode): 音量キー(24, 25)/決定(85)は無視され、88は内容確認、87のみ次へ進むこと', (tester) async {
      await navigateToStep(tester, 3);

      // enterMode 中の音量キーや決定キーは無視
      await sendNativeKeyEvent(tester, 24);
      await sendNativeKeyEvent(tester, 25);
      await sendNativeKeyEvent(tester, 85);
      await tester.pumpAndSettle();

      expect(fakeSound.beepCount, 0);
      expect(fakeTts.spokenHistory, isEmpty);
      expect(find.textContaining('STEP 2/5 (1/2): 調整モード起動'), findsOneWidget);

      // 前曲キー(88)で内容安全確認読み上げ
      await sendNativeKeyEvent(tester, 88);
      await tester.pump();
      expect(fakeTts.lastSpoken, 'ベンチプレス、60キロ、10回、3セット');
      expect(find.textContaining('STEP 2/5 (1/2): 調整モード起動'), findsOneWidget);

      // 次曲キー(87)で Part 2 へ突入
      fakeTts.clear();
      await sendNativeKeyEvent(tester, 87);
      await tester.pumpAndSettle();

      expect(fakeSound.beepCount, 1);
      expect(fakeTts.lastSpoken, '調整、種目名');
      expect(find.textContaining('STEP 2/5 (2/2): 項目選択'), findsOneWidget);
    });

    testWidgets('Step 3 Part 1 (Enter Mode): キー87の連続連打で多重発話・重複ビープが発生しないこと（再入防止）', (tester) async {
      await navigateToStep(tester, 3);

      // 次曲キー(87)を連続して送信
      await sendNativeKeyEvent(tester, 87);
      await sendNativeKeyEvent(tester, 87);
      await tester.pumpAndSettle();

      // 1回だけ処理されるべき（再入防止）
      expect(fakeSound.beepCount, 1, reason: 'Step 3 突入キー連打でビープが重複再生されてはならない');
      expect(fakeTts.spokenHistory.length, 1, reason: 'Step 3 突入キー連打で多重発話されてはならない');
      expect(find.textContaining('STEP 2/5 (2/2): 項目選択'), findsOneWidget);
    });

    testWidgets('Step 3 Part 2 (Item Selection): 次曲(87)は無視され、音量キーによる双方向4項目巡回が正常にループすること', (tester) async {
      await navigateToStep(tester, 3);
      await sendNativeKeyEvent(tester, 87); // Part 2 へ
      await tester.pumpAndSettle();
      fakeSound.clear();
      fakeTts.clear();

      // 次曲キー(87)は Part 2 では無視
      await sendNativeKeyEvent(tester, 87);
      await tester.pump();
      expect(fakeSound.beepCount, 0);
      expect(fakeTts.spokenHistory, isEmpty);

      // 音量UPで4項目を前進巡回: 種目名 -> 重量 -> レップ数 -> セット数 -> 種目名
      await sendNativeKeyEvent(tester, 24); // -> 重量
      await tester.pump();
      expect(fakeTts.lastSpoken, '重量');

      await sendNativeKeyEvent(tester, 24); // -> レップ数
      await tester.pump();
      expect(fakeTts.lastSpoken, 'レップ数');

      await sendNativeKeyEvent(tester, 24); // -> セット数
      await tester.pump();
      expect(fakeTts.lastSpoken, 'セット数');

      await sendNativeKeyEvent(tester, 24); // -> 種目名 (ループラップ)
      await tester.pump();
      expect(fakeTts.lastSpoken, '種目名');

      // 音量DOWNで逆循環: 種目名 -> セット数 -> レップ数 -> 重量 -> 種目名
      await sendNativeKeyEvent(tester, 25); // -> セット数
      await tester.pump();
      expect(fakeTts.lastSpoken, 'セット数');

      await sendNativeKeyEvent(tester, 25); // -> レップ数
      await tester.pump();
      expect(fakeTts.lastSpoken, 'レップ数');

      await sendNativeKeyEvent(tester, 25); // -> 重量
      await tester.pump();
      expect(fakeTts.lastSpoken, '重量');

      // 決定(85)で Step 4 へ遷移
      fakeSound.clear();
      fakeTts.clear();
      await sendNativeKeyEvent(tester, 85);
      await tester.pumpAndSettle();

      expect(fakeSound.beepCount, 1);
      expect(fakeTts.lastSpoken, '60キロ');
      expect(find.textContaining('STEP 3/5: 重量調整と音声'), findsOneWidget);
    });

    testWidgets('Step 4 (Weight Adjustment): 次曲(87)は無視され、前曲(88)は内容安全確認読み上げを行うこと', (tester) async {
      await navigateToStep(tester, 4);

      // 次曲(87)は無視
      await sendNativeKeyEvent(tester, 87);
      await tester.pump();
      expect(fakeSound.beepCount, 0);
      expect(fakeTts.spokenHistory, isEmpty);

      // 前曲(88)で内容安全確認読み上げ
      await sendNativeKeyEvent(tester, 88);
      await tester.pump();
      expect(fakeTts.lastSpoken, 'ベンチプレス、60キロ、10回、3セット');

      // 状態が Step 4 のままであること
      expect(find.textContaining('STEP 3/5: 重量調整と音声'), findsOneWidget);
    });

    testWidgets('Step 4 (Weight Adjustment): 決定キー(85)の連続連打で多重発話・重複ビープが発生しないこと（再入防止）', (tester) async {
      await navigateToStep(tester, 4);

      // 決定キー(85)を連続送信
      await sendNativeKeyEvent(tester, 85);
      await sendNativeKeyEvent(tester, 85);
      await tester.pumpAndSettle();

      // 1回だけ処理されるべき（再入防止）
      expect(fakeSound.beepCount, 1, reason: 'Step 4 決定キー連打でビープが重複再生されてはならない');
      expect(fakeTts.spokenHistory.length, 1, reason: 'Step 4 決定キー連打で多重発話されてはならない');
      expect(find.textContaining('STEP 4/5: 調整の完了'), findsOneWidget);
    });

    testWidgets('Step 5 (Adjustment Completion): 不正キー(85, 79, 24, 25, 88)で注意案内表示＋状態維持され、87で注意解除＆Step 6へ進むこと', (tester) async {
      await navigateToStep(tester, 5);

      // 初期状態では注意文言がないこと
      expect(find.text('［次の曲へ進む］ボタンを押して調整を完了してください'), findsNothing);

      // 再生(85)キーを押下 -> 注意文言が出現し、Step 5 に留まること
      await sendNativeKeyEvent(tester, 85);
      await tester.pump();
      expect(find.text('［次の曲へ進む］ボタンを押して調整を完了してください'), findsOneWidget);
      expect(find.byIcon(Icons.info_outline), findsOneWidget);
      expect(find.textContaining('STEP 4/5: 調整の完了'), findsOneWidget);

      // 音量キー(24, 25)や前曲(88)を押下しても注意表示を維持し、Step 5 に留まること
      await sendNativeKeyEvent(tester, 24);
      await tester.pump();
      expect(find.text('［次の曲へ進む］ボタンを押して調整を完了してください'), findsOneWidget);

      await sendNativeKeyEvent(tester, 25);
      await tester.pump();
      expect(find.text('［次の曲へ進む］ボタンを押して調整を完了してください'), findsOneWidget);

      await sendNativeKeyEvent(tester, 88);
      await tester.pump();
      expect(find.text('［次の曲へ進む］ボタンを押して調整を完了してください'), findsOneWidget);

      // 有効キー 次曲(87) で確定遷移
      fakeSound.clear();
      fakeTts.clear();
      await sendNativeKeyEvent(tester, 87);
      await tester.pumpAndSettle();

      expect(fakeSound.beepCount, 1);
      expect(fakeTts.lastSpoken, '確定、開始、ベンチプレス、60キロ、10回、3セット');
      expect(find.textContaining('🎉 チュートリアル完了！'), findsOneWidget);
      expect(find.text('［次の曲へ進む］ボタンを押して調整を完了してください'), findsNothing);
    });

    testWidgets('Step 6 (Completed): 音量キー/次曲/前曲は無視され、再生(85)で本編TrainingScreenへ遷移すること', (tester) async {
      await navigateToStep(tester, 6);

      // 不正キーは無視
      for (final code in [24, 25, 87, 88]) {
        await sendNativeKeyEvent(tester, code);
      }
      await tester.pumpAndSettle();

      expect(find.textContaining('🎉 チュートリアル完了！'), findsOneWidget);
      expect(find.byType(TrainingScreen), findsNothing);

      // 再生(85)で TrainingScreen へ遷移
      await sendNativeKeyEvent(tester, 85);
      await tester.pumpAndSettle();

      expect(find.byType(TrainingScreen), findsOneWidget);
    });
  });

  // ==========================================================================
  // Group 2: Step 4 重量調整デバウンス＆下限クランプの敵対的ストレステスト
  // ==========================================================================
  group('2. Adversarial Stress-Test: Step 4 Debounce & Boundary Clamping', () {
    testWidgets('10回連続の高速連打(Volume Up): UIが即座に85kgへ加算され、連打停止後に発話が厳密に1回だけ実行されること', (tester) async {
      await navigateToStep(tester, 4);

      // 初期重量は 60.0 kg
      expect(find.text('60 kg'), findsOneWidget);

      // 10回高速連打 (間隔30ms < 700ms)
      for (int i = 0; i < 10; i++) {
        await sendNativeKeyEvent(tester, 24);
        await tester.pump(const Duration(milliseconds: 30));
      }

      // 連打直後の状態検証:
      // UIは即座に 85 kg (60 + 2.5 * 10) に更新されている
      expect(find.text('85 kg'), findsOneWidget);
      // 効果音は10回鳴動
      expect(fakeSound.beepCount, 10);
      // 700ms未満のため、TTS発話はまだ0回
      expect(fakeTts.spokenHistory, isEmpty);

      // 750ms経過させデバウンスタイマーを発火
      await tester.pump(const Duration(milliseconds: 750));

      // 厳密に1回だけ最終重量「85キロ」が読み上げられること
      expect(fakeTts.spokenHistory.length, 1);
      expect(fakeTts.spokenHistory, ['85キロ']);
    });

    testWidgets('交互高速連打(5回Up + 5回Down): タイマーが継続リセットされ、最終値「60キロ」が1回だけ発話されること', (tester) async {
      await navigateToStep(tester, 4);

      // 5回 Up (+12.5kg -> 72.5kg)
      for (int i = 0; i < 5; i++) {
        await sendNativeKeyEvent(tester, 24);
        await tester.pump(const Duration(milliseconds: 25));
      }
      expect(find.text('72.5 kg'), findsOneWidget);
      expect(fakeTts.spokenHistory, isEmpty);

      // 直ちに 5回 Down (-12.5kg -> 60.0kg)
      for (int i = 0; i < 5; i++) {
        await sendNativeKeyEvent(tester, 25);
        await tester.pump(const Duration(milliseconds: 25));
      }
      expect(find.text('60 kg'), findsOneWidget);
      expect(fakeTts.spokenHistory, isEmpty);

      // 連打停止から 750ms 経過
      await tester.pump(const Duration(milliseconds: 750));

      // 1回だけ「60キロ」を発話
      expect(fakeTts.spokenHistory.length, 1);
      expect(fakeTts.spokenHistory, ['60キロ']);
    });

    testWidgets('デバウンス待ち(0.7s)中の決定キー(85)割り込み: デバウンスが即座に破棄され、Step 5へ遷移して残存発話が一切出ないこと', (tester) async {
      await navigateToStep(tester, 4);

      // 2回 Up (+5.0kg -> 65.0kg)
      await sendNativeKeyEvent(tester, 24);
      await tester.pump(const Duration(milliseconds: 25));
      await sendNativeKeyEvent(tester, 24);
      await tester.pump(const Duration(milliseconds: 150)); // デバウンス残り550ms

      expect(find.text('65 kg'), findsOneWidget);
      expect(fakeTts.spokenHistory, isEmpty);

      // 決定キー(85)で割り込み
      fakeSound.clear();
      await sendNativeKeyEvent(tester, 85);
      await tester.pumpAndSettle();

      // 効果音再生＋「調整、重量」の発話＋Step 5遷移を確認
      expect(fakeSound.beepCount, 1);
      expect(fakeTts.lastSpoken, '調整、重量');
      expect(find.textContaining('STEP 4/5: 調整の完了'), findsOneWidget);

      // さらに 1000ms 経過しても、キャンセルされた「65キロ」が発話されないことを検証
      await tester.pump(const Duration(milliseconds: 1000));
      expect(fakeTts.spokenHistory.contains('65キロ'), isFalse);
      expect(fakeTts.spokenHistory, ['調整、重量']);
    });

    testWidgets('下限クランプ検証: Volume Downを30回連打しても0.0kgで確実にクランプされ、マイナス値にならないこと', (tester) async {
      await navigateToStep(tester, 4);

      // 60.0kg から 30回 Down (-75.0kg 相当)
      for (int i = 0; i < 30; i++) {
        await sendNativeKeyEvent(tester, 25);
        await tester.pump(const Duration(milliseconds: 20));
      }

      // UI表示が 0 kg にクランプされていること
      expect(find.text('0 kg'), findsOneWidget);

      // 750ms 経過後の発話が「0キロ」であること
      await tester.pump(const Duration(milliseconds: 750));
      expect(fakeTts.spokenHistory.length, 1);
      expect(fakeTts.spokenHistory, ['0キロ']);

      // さらに 0kg の状態で 5回 Down 連打
      fakeTts.clear();
      for (int i = 0; i < 5; i++) {
        await sendNativeKeyEvent(tester, 25);
        await tester.pump(const Duration(milliseconds: 20));
      }

      // 0 kg を維持
      expect(find.text('0 kg'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 750));
      expect(fakeTts.spokenHistory, ['0キロ']);
    });

    testWidgets('デバウンス待ち中にスキップボタン押下: タイマーが即時破棄され、TTSの漏れなくStep 5へ進むこと', (tester) async {
      await navigateToStep(tester, 4);

      // 1回 Up (+2.5kg -> 62.5kg)
      await sendNativeKeyEvent(tester, 24);
      await tester.pump(const Duration(milliseconds: 100)); // デバウンス待ち状態

      expect(find.text('62.5 kg'), findsOneWidget);
      expect(fakeTts.spokenHistory, isEmpty);

      // スキップボタン押下
      await tester.tap(find.byKey(const Key('btn_tutorial_skip')));
      await tester.pumpAndSettle();

      expect(find.textContaining('STEP 4/5: 調整の完了'), findsOneWidget);

      // 1秒経過後も「62.5キロ」が発話されないこと
      await tester.pump(const Duration(seconds: 1));
      expect(fakeTts.spokenHistory, isEmpty);
    });
  });

  // ==========================================================================
  // Group 3: キーボード入力＆仮想キーバーの耐障害性テスト
  // ==========================================================================
  group('3. Keyboard & Virtual Key Bar Resilience', () {
    testWidgets('未対応キー(アルファベット/数字/Tab/Escape/Enter)の打鍵が無視され、状態を破壊しないこと', (tester) async {
      await navigateToStep(tester, 2);

      // Focus に未定義キーを送信
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();

      expect(fakeSound.beepCount, 0);
      expect(fakeTts.spokenHistory, isEmpty);
      expect(find.textContaining('STEP 1/5: 開始操作'), findsOneWidget);

      // 対応キー Space で Step 2 を進行できること
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();

      expect(fakeSound.beepCount, 1);
      expect(fakeTts.lastSpoken, '開始、ベンチプレス、60キロ、10回、3セット');
      expect(find.textContaining('STEP 2/5 (1/2): 調整モード起動'), findsOneWidget);
    });

    testWidgets('仮想メディアキーバーの高速タップ連打でクラッシュせず安定動作すること', (tester) async {
      await navigateToStep(tester, 4);

      // 仮想 Vol+ を5回タップ
      final volUpBtn = find.byKey(const Key('virtual_key_vol_up'));
      for (int i = 0; i < 5; i++) {
        await tester.tap(volUpBtn);
        await tester.pump(const Duration(milliseconds: 30));
      }

      expect(find.text('72.5 kg'), findsOneWidget);
      expect(fakeSound.beepCount, 5);

      // デバウンス発話
      await tester.pump(const Duration(milliseconds: 750));
      expect(fakeTts.spokenHistory, ['72.5キロ']);

      // 仮想 再生/停止(決定) をタップ
      await tester.tap(find.byKey(const Key('virtual_key_play_pause')));
      await tester.pumpAndSettle();

      expect(find.textContaining('STEP 4/5: 調整の完了'), findsOneWidget);
    });
  });

  // ==========================================================================
  // Group 4: 音声制御（Audio Hygiene）とライフサイクルの厳密検証
  // ==========================================================================
  group('4. Audio Hygiene & Ducking Integrity Under High Stress', () {
    testWidgets('連続したキー操作において発話前stop()呼び出しおよびダッキング解放が厳密に保たれること', (tester) async {
      await navigateToStep(tester, 2);

      // Step 2 開始
      await sendNativeKeyEvent(tester, 85);
      await tester.pumpAndSettle();

      // Step 3 突入
      await sendNativeKeyEvent(tester, 87);
      await tester.pumpAndSettle();

      // 項目送り
      await sendNativeKeyEvent(tester, 24);
      await tester.pumpAndSettle();

      // Step 4 突入
      await sendNativeKeyEvent(tester, 85);
      await tester.pumpAndSettle();

      // 各発話の直前に必ず ttsService.stop() が呼ばれていること
      expect(fakeTts.spokenHistory.length, greaterThanOrEqualTo(4));
      expect(fakeTts.stopCallCount, greaterThanOrEqualTo(fakeTts.spokenHistory.length));

      // 画面破棄（dispose）でダッキングが解放され、TTSが停止されること
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();

      expect(fakeDucking.events.contains('releaseDucking'), isTrue);
    });
  });
}
