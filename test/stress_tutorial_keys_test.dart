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

  /// ヘルパー: 指定されたステップ（1〜6）まで迅速に進める
  Future<void> navigateToStep(WidgetTester tester, int targetStep) async {
    await tester.pumpWidget(buildTestableApp());
    await tester.pumpAndSettle();

    if (targetStep >= 2) {
      // Step 1 -> Step 2-1
      await sendNativeKeyEvent(tester, 85);
      await tester.pumpAndSettle();
    }
    if (targetStep >= 3) {
      // Step 2-1 -> Step 2-2 -> 重量選択 -> Step 3
      await sendNativeKeyEvent(tester, 87); // enterMode -> cycleItem
      await tester.pumpAndSettle();
      await sendNativeKeyEvent(tester, 24); // 種目名 -> 重量
      await tester.pump();
      await sendNativeKeyEvent(tester, 85); // 決定 -> Step 3
      await tester.pumpAndSettle();
    }
    if (targetStep >= 4) {
      // Step 3 -> Step 4
      await sendNativeKeyEvent(tester, 85);
      await tester.pumpAndSettle();
    }
    if (targetStep >= 5) {
      // Step 4 -> Step 5
      await sendNativeKeyEvent(tester, 87);
      await tester.pumpAndSettle();
    }
    if (targetStep >= 6) {
      // Step 5 -> Step 6
      await sendNativeKeyEvent(tester, 88);
      await tester.pumpAndSettle();
    }

    fakeSound.clear();
    fakeTts.clear();
    fakeDucking.events.clear();
  }

  // ==========================================================================
  // Group 1: 不正・予期せぬキー入力の網羅的検証 (Step 1〜6)
  // ==========================================================================
  group('1. Adversarial Invalid Key Events Matrix across all Steps', () {
    testWidgets('Step 1 (Start): 音量キー(24, 25)/次曲(87)/前曲(88)の連打を完全に無視し、85または79で進行すること', (tester) async {
      await navigateToStep(tester, 1);

      for (int i = 0; i < 10; i++) {
        await sendNativeKeyEvent(tester, 24);
        await sendNativeKeyEvent(tester, 25);
        await sendNativeKeyEvent(tester, 87);
        await sendNativeKeyEvent(tester, 88);
      }
      await tester.pumpAndSettle();

      expect(fakeSound.beepCount, 0);
      expect(fakeTts.spokenHistory, isEmpty);
      expect(find.text('再生（または停止）操作でトレーニングを開始しましょう'), findsOneWidget);

      // 有効キー 79 (HeadsetHook) で開始すること
      await sendNativeKeyEvent(tester, 79);
      await tester.pumpAndSettle();

      expect(fakeSound.beepCount, 1);
      expect(
        fakeTts.spokenHistory,
        [
          '開始、ベンチプレス、60キロ、10回、3セット',
          'トレーニングの調整をしましょう。曲送り操作で調整をします。',
        ],
      );
      expect(find.text('曲送り（次の曲へ進む）で調整モードに切り替える'), findsOneWidget);
    });

    testWidgets('Step 1: キー85の連続連打で多重発話・重複ビープが発生しないこと（再入防止）', (tester) async {
      await navigateToStep(tester, 1);

      await sendNativeKeyEvent(tester, 85);
      await sendNativeKeyEvent(tester, 85);
      await tester.pumpAndSettle();

      expect(fakeSound.beepCount, 1);
      expect(fakeTts.spokenHistory.length, 2);
      expect(find.text('曲送り（次の曲へ進む）で調整モードに切り替える'), findsOneWidget);
    });

    testWidgets('Step 2-1 (Enter Mode): 音量キー(24, 25)/決定(85)/前曲(88)は無視され、87のみStep 2-2へ進むこと', (tester) async {
      await navigateToStep(tester, 2);

      await sendNativeKeyEvent(tester, 24);
      await sendNativeKeyEvent(tester, 25);
      await sendNativeKeyEvent(tester, 85);
      await sendNativeKeyEvent(tester, 88);
      await tester.pumpAndSettle();

      expect(fakeSound.beepCount, 0);
      expect(fakeTts.spokenHistory, isEmpty);
      expect(find.text('曲送り（次の曲へ進む）で調整モードに切り替える'), findsOneWidget);

      // 次曲キー(87)で Step 2-2 へ突入
      await sendNativeKeyEvent(tester, 87);
      await tester.pumpAndSettle();

      expect(fakeSound.beepCount, 1);
      expect(
        fakeTts.lastSpoken,
        '調整、種目名。音量操作で調整項目を選択し、再生停止操作で決定しましょう',
      );
      expect(find.text('音量(+/-)で調整項目を選択 ➔ 再生停止で決定'), findsOneWidget);
    });

    testWidgets('Step 2-1: キー87の連続連打で多重発話・重複ビープが発生しないこと（再入防止）', (tester) async {
      await navigateToStep(tester, 2);

      await sendNativeKeyEvent(tester, 87);
      await sendNativeKeyEvent(tester, 87);
      await tester.pumpAndSettle();

      expect(fakeSound.beepCount, 1);
      expect(fakeTts.spokenHistory.length, 1);
      expect(find.text('音量(+/-)で調整項目を選択 ➔ 再生停止で決定'), findsOneWidget);
    });

    testWidgets('Step 2-2 (Item Selection): 次曲(87)および前曲(88)は完全に無効化され、音量キーによる双方向4項目巡回が正常にループすること', (tester) async {
      await navigateToStep(tester, 2);
      await sendNativeKeyEvent(tester, 87); // Step 2-2 へ
      await tester.pumpAndSettle();
      fakeSound.clear();
      fakeTts.clear();

      // 次曲(87)および前曲(88)は無視されること
      await sendNativeKeyEvent(tester, 87);
      await sendNativeKeyEvent(tester, 88);
      await tester.pump();
      expect(fakeSound.beepCount, 0);
      expect(fakeTts.spokenHistory, isEmpty);

      // 音量UPで4項目を前進巡回: 種目名 -> 重量 -> レップ数 -> セット数 -> 種目名
      await sendNativeKeyEvent(tester, 24);
      await tester.pump();
      expect(fakeTts.lastSpoken, '重量');

      await sendNativeKeyEvent(tester, 24);
      await tester.pump();
      expect(fakeTts.lastSpoken, 'レップ数');

      await sendNativeKeyEvent(tester, 24);
      await tester.pump();
      expect(fakeTts.lastSpoken, 'セット数');

      await sendNativeKeyEvent(tester, 24);
      await tester.pump();
      expect(fakeTts.lastSpoken, '種目名');

      // 音量DOWNで逆循環: 種目名 -> セット数 -> レップ数 -> 重量
      await sendNativeKeyEvent(tester, 25);
      await tester.pump();
      expect(fakeTts.lastSpoken, 'セット数');

      await sendNativeKeyEvent(tester, 25);
      await tester.pump();
      expect(fakeTts.lastSpoken, 'レップ数');

      await sendNativeKeyEvent(tester, 25);
      await tester.pump();
      expect(fakeTts.lastSpoken, '重量');

      // 決定(85)で Step 3 へ遷移
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
      expect(find.text('音量(+/-)で重量を調整。再生停止で決定。'), findsOneWidget);
    });

    testWidgets('Step 3 (Value Adjustment): 次曲(87)および前曲(88)は完全に無効化されること', (tester) async {
      await navigateToStep(tester, 3);

      await sendNativeKeyEvent(tester, 87);
      await sendNativeKeyEvent(tester, 88);
      await tester.pump();
      expect(fakeSound.beepCount, 0);
      expect(fakeTts.spokenHistory, isEmpty);
      expect(find.text('音量(+/-)で重量を調整。再生停止で決定。'), findsOneWidget);
    });

    testWidgets('Step 3 (Value Adjustment): 決定キー(85)の連続連打で多重発話・重複ビープが発生しないこと（再入防止）', (tester) async {
      await navigateToStep(tester, 3);

      await sendNativeKeyEvent(tester, 85);
      await sendNativeKeyEvent(tester, 85);
      await tester.pumpAndSettle();

      expect(fakeSound.beepCount, 1);
      expect(fakeTts.spokenHistory.length, 1);
      expect(find.text('曲送り（次の曲へ進む）で調整モードを終了する。'), findsOneWidget);
    });

    testWidgets('Step 4 (Finish Adjustment): 不正キー(85, 79, 24, 25, 88)は握りつぶされ、87のみでStep 5へ進むこと', (tester) async {
      await navigateToStep(tester, 4);

      for (final code in [85, 79, 24, 25, 88]) {
        await sendNativeKeyEvent(tester, code);
      }
      await tester.pumpAndSettle();

      expect(fakeSound.beepCount, 0);
      expect(fakeTts.spokenHistory, isEmpty);
      expect(find.text('曲送り（次の曲へ進む）で調整モードを終了する。'), findsOneWidget);

      // 有効キー 次曲(87) で確定遷移
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
      expect(find.text('曲戻し（前の曲へ戻る）でトレーニングの内容を確認。'), findsOneWidget);
    });

    testWidgets('Step 5 (Reconfirm): 不正キー(85, 79, 24, 25, 87)は握りつぶされ、前曲(88)のみで内容確認しStep 6へ進むこと', (tester) async {
      await navigateToStep(tester, 5);

      for (final code in [85, 79, 24, 25, 87]) {
        await sendNativeKeyEvent(tester, code);
      }
      await tester.pumpAndSettle();

      expect(fakeSound.beepCount, 0);
      expect(fakeTts.spokenHistory, isEmpty);
      expect(find.text('曲戻し（前の曲へ戻る）でトレーニングの内容を確認。'), findsOneWidget);

      // 前曲(88)で確認読み上げ＆Step 6へ自動遷移
      await sendNativeKeyEvent(tester, 88);
      await tester.pumpAndSettle();

      expect(
        fakeTts.spokenHistory,
        [
          'ベンチプレス、60キロ、10回、3セット',
          'チュートリアルは以上です。',
        ],
      );
      expect(find.text('チュートリアル完了！'), findsOneWidget);
    });

    testWidgets('Step 6 (Completed): 音量キー/次曲/前曲は無視され、再生(85)で本編TrainingScreenへ遷移すること', (tester) async {
      await navigateToStep(tester, 6);

      for (final code in [24, 25, 87, 88]) {
        await sendNativeKeyEvent(tester, code);
      }
      await tester.pumpAndSettle();

      expect(find.text('チュートリアル完了！'), findsOneWidget);
      expect(find.byType(TrainingScreen), findsNothing);

      await sendNativeKeyEvent(tester, 85);
      await tester.pumpAndSettle();

      expect(find.byType(TrainingScreen), findsOneWidget);
    });
  });

  // ==========================================================================
  // Group 2: Step 3 重量調整デバウンス＆下限クランプのストレステスト
  // ==========================================================================
  group('2. Adversarial Stress-Test: Step 3 Debounce & Boundary Clamping', () {
    testWidgets('10回連続の高速連打(Volume Up): UIが即座に85kgへ加算され、連打停止後に発話が厳密に1回だけ実行されること', (tester) async {
      await navigateToStep(tester, 3);

      expect(find.text('60 kg'), findsOneWidget);

      for (int i = 0; i < 10; i++) {
        await sendNativeKeyEvent(tester, 24);
        await tester.pump(const Duration(milliseconds: 30));
      }

      expect(find.text('85 kg'), findsOneWidget);
      expect(fakeSound.beepCount, 10);
      expect(fakeTts.spokenHistory, isEmpty);

      await tester.pump(const Duration(milliseconds: 750));

      expect(fakeTts.spokenHistory.length, 1);
      expect(fakeTts.spokenHistory, ['85キロ']);
    });

    testWidgets('交互高速連打(5回Up + 5回Down): タイマーが継続リセットされ、最終値「60キロ」が1回だけ発話されること', (tester) async {
      await navigateToStep(tester, 3);

      for (int i = 0; i < 5; i++) {
        await sendNativeKeyEvent(tester, 24);
        await tester.pump(const Duration(milliseconds: 25));
      }
      expect(find.text('72.5 kg'), findsOneWidget);
      expect(fakeTts.spokenHistory, isEmpty);

      for (int i = 0; i < 5; i++) {
        await sendNativeKeyEvent(tester, 25);
        await tester.pump(const Duration(milliseconds: 25));
      }
      expect(find.text('60 kg'), findsOneWidget);
      expect(fakeTts.spokenHistory, isEmpty);

      await tester.pump(const Duration(milliseconds: 750));

      expect(fakeTts.spokenHistory.length, 1);
      expect(fakeTts.spokenHistory, ['60キロ']);
    });

    testWidgets('デバウンス待ち(0.7s)中の決定キー(85)割り込み: デバウンスが即座に破棄され、Step 4へ遷移して残存発話が一切出ないこと', (tester) async {
      await navigateToStep(tester, 3);

      await sendNativeKeyEvent(tester, 24);
      await tester.pump(const Duration(milliseconds: 25));
      await sendNativeKeyEvent(tester, 24);
      await tester.pump(const Duration(milliseconds: 150));

      expect(find.text('65 kg'), findsOneWidget);
      expect(fakeTts.spokenHistory, isEmpty);

      fakeSound.clear();
      await sendNativeKeyEvent(tester, 85);
      await tester.pumpAndSettle();

      expect(fakeSound.beepCount, 1);
      expect(fakeTts.lastSpoken, '曲送り操作で調整を完了します。調整、重量');
      expect(find.text('曲送り（次の曲へ進む）で調整モードを終了する。'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 1000));
      expect(fakeTts.spokenHistory.contains('65キロ'), isFalse);
      expect(fakeTts.spokenHistory, ['曲送り操作で調整を完了します。調整、重量']);
    });

    testWidgets('下限クランプ検証: Volume Downを30回連打しても0.0kgで確実にクランプされ、マイナス値にならないこと', (tester) async {
      await navigateToStep(tester, 3);

      for (int i = 0; i < 30; i++) {
        await sendNativeKeyEvent(tester, 25);
        await tester.pump(const Duration(milliseconds: 20));
      }

      expect(find.text('0 kg'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 750));
      expect(fakeTts.spokenHistory.length, 1);
      expect(fakeTts.spokenHistory, ['0キロ']);

      fakeTts.clear();
      for (int i = 0; i < 5; i++) {
        await sendNativeKeyEvent(tester, 25);
        await tester.pump(const Duration(milliseconds: 20));
      }

      expect(find.text('0 kg'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 750));
      expect(fakeTts.spokenHistory, ['0キロ']);
    });

    testWidgets('デバウンス待ち中にスキップボタン押下: タイマーが即時破棄され、残存重量TTSが出ずにStep 4へ進むこと', (tester) async {
      await navigateToStep(tester, 3);

      await sendNativeKeyEvent(tester, 24);
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('62.5 kg'), findsOneWidget);
      expect(fakeTts.spokenHistory, isEmpty);

      await tester.tap(find.byKey(const Key('btn_tutorial_skip')));
      await tester.pumpAndSettle();

      expect(find.text('曲送り（次の曲へ進む）で調整モードを終了する。'), findsOneWidget);

      await tester.pump(const Duration(seconds: 1));
      expect(fakeTts.spokenHistory.contains('62.5キロ'), isFalse);
    });
  });

  // ==========================================================================
  // Group 3: キーボード入力＆仮想キーバーの耐障害性テスト
  // ==========================================================================
  group('3. Keyboard & Virtual Key Bar Resilience', () {
    testWidgets('未対応キー(アルファベット/数字/Tab/Escape/Enter)の打鍵が無視され、状態を破壊しないこと', (tester) async {
      await navigateToStep(tester, 1);

      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();

      expect(fakeSound.beepCount, 0);
      expect(fakeTts.spokenHistory, isEmpty);
      expect(find.text('再生（または停止）操作でトレーニングを開始しましょう'), findsOneWidget);

      // 対応キー Space で Step 1 を進行できること
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();

      expect(fakeSound.beepCount, 1);
      expect(find.text('曲送り（次の曲へ進む）で調整モードに切り替える'), findsOneWidget);
    });

    testWidgets('仮想メディアキーバーの高速タップ連打でクラッシュせず安定動作すること', (tester) async {
      await navigateToStep(tester, 3);

      final volUpBtn = find.byKey(const Key('virtual_key_vol_up'));
      for (int i = 0; i < 5; i++) {
        await tester.tap(volUpBtn);
        await tester.pump(const Duration(milliseconds: 30));
      }

      expect(find.text('72.5 kg'), findsOneWidget);
      expect(fakeSound.beepCount, 5);

      await tester.pump(const Duration(milliseconds: 750));
      expect(fakeTts.spokenHistory, ['72.5キロ']);

      await tester.tap(find.byKey(const Key('virtual_key_play_pause')));
      await tester.pumpAndSettle();

      expect(find.text('曲送り（次の曲へ進む）で調整モードを終了する。'), findsOneWidget);
    });
  });

  // ==========================================================================
  // Group 4: 音声制御（Audio Hygiene）とライフサイクルの厳密検証
  // ==========================================================================
  group('4. Audio Hygiene & Ducking Integrity Under High Stress', () {
    testWidgets('連続したキー操作において発話前stop()呼び出しおよびダッキング解放が厳密に保たれること', (tester) async {
      await navigateToStep(tester, 1);

      // Step 1 開始 -> Step 2-1
      await sendNativeKeyEvent(tester, 85);
      await tester.pumpAndSettle();

      // Step 2-1 -> Step 2-2
      await sendNativeKeyEvent(tester, 87);
      await tester.pumpAndSettle();

      // 項目送り
      await sendNativeKeyEvent(tester, 24);
      await tester.pumpAndSettle();

      // Step 2-2 -> Step 3
      await sendNativeKeyEvent(tester, 85);
      await tester.pumpAndSettle();

      expect(fakeTts.spokenHistory.length, greaterThanOrEqualTo(5));
      expect(
        fakeTts.stopCallCount,
        greaterThanOrEqualTo(fakeTts.spokenHistory.length),
      );

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();

      expect(fakeDucking.events.contains('releaseDucking'), isTrue);
    });
  });
}
