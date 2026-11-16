import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:button_controll_test/main.dart';

/// MethodChannel 経由のネイティブキーイベント送信ヘルパー
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
  if (reply == null) return null;
  return codec.decodeEnvelope(reply);
}

/// 非同期発話制御およびイベント順序記録が可能なストレス検証用 TTS サービス
class StressFakeTtsService implements TtsService {
  final List<String> callLog = [];
  final List<String> spokenHistory = [];
  String? lastSpoken;
  int stopCallCount = 0;
  int speakCallCount = 0;
  bool isInitialized = false;

  /// true の場合、speak() の完了を外部 Completer で制御可能
  bool manualSpeakCompletion = false;
  Completer<void>? pendingSpeakCompleter;

  /// stop() 時に進行中の speak() をキャンセルするかどうか
  bool cancelPendingOnStop = true;

  @override
  Future<void> initialize() async {
    isInitialized = true;
    callLog.add('tts.initialize');
  }

  @override
  Future<void> speak(String text) async {
    callLog.add('tts.speak: $text');
    speakCallCount++;
    spokenHistory.add(text);
    lastSpoken = text;

    if (manualSpeakCompletion) {
      final completer = Completer<void>();
      pendingSpeakCompleter = completer;
      await completer.future;
    }
  }

  @override
  Future<void> speakAndWait(String text) async {
    await speak(text);
  }

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> stop() async {
    callLog.add('tts.stop');
    stopCallCount++;
    if (cancelPendingOnStop &&
        pendingSpeakCompleter != null &&
        !pendingSpeakCompleter!.isCompleted) {
      pendingSpeakCompleter!.complete();
      pendingSpeakCompleter = null;
    }
  }

  void completePendingSpeak() {
    if (pendingSpeakCompleter != null && !pendingSpeakCompleter!.isCompleted) {
      pendingSpeakCompleter!.complete();
      pendingSpeakCompleter = null;
    }
  }

  void clear() {
    callLog.clear();
    spokenHistory.clear();
    lastSpoken = null;
    stopCallCount = 0;
    speakCallCount = 0;
  }
}

/// ダッキングの要求・解除回数および現在の状態を厳密に追跡するコントローラ
class StressFakeDuckingController implements AudioDuckingController {
  final List<String> events = [];
  int requestCount = 0;
  int releaseCount = 0;
  bool isCurrentlyDucked = false;

  @override
  Future<void> configure() async {
    events.add('configure');
  }

  @override
  Future<void> requestDucking() async {
    events.add('requestDucking');
    requestCount++;
    isCurrentlyDucked = true;
  }

  @override
  Future<void> releaseDucking() async {
    events.add('releaseDucking');
    releaseCount++;
    isCurrentlyDucked = false;
  }

  void clear() {
    events.clear();
    requestCount = 0;
    releaseCount = 0;
    isCurrentlyDucked = false;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late StressFakeTtsService stressTts;
  late FakeSoundEffectService fakeSound;
  late StressFakeDuckingController stressDucking;

  setUp(() {
    stressTts = StressFakeTtsService();
    fakeSound = FakeSoundEffectService();
    stressDucking = StressFakeDuckingController();
  });

  Widget buildStressApp({
    Widget? home,
    bool animateGlow = false,
  }) {
    return MaterialApp(
      theme: ThemeData.dark().copyWith(
        splashFactory: InkRipple.splashFactory,
        scaffoldBackgroundColor: const Color(0xFF121212),
      ),
      home: home ??
          TutorialScreen(
            ttsService: stressTts,
            soundEffectService: fakeSound,
            duckingController: stressDucking,
            animateGlow: animateGlow,
          ),
    );
  }

  group('Adversarial Audio Concurrency & Hygiene Stress Tests', () {
    testWidgets('Test 1: Step 1 におけるキー85連打時の重複発話・電子音スパムの検証', (tester) async {
      await tester.pumpWidget(buildStressApp());
      await tester.pumpAndSettle();

      stressTts.clear();
      fakeSound.clear();

      // キー 85（再生/停止）を瞬時に5回連打
      await sendNativeKeyEvent(tester, 85);
      await sendNativeKeyEvent(tester, 85);
      await sendNativeKeyEvent(tester, 85);
      await sendNativeKeyEvent(tester, 85);
      await sendNativeKeyEvent(tester, 85);
      await tester.pumpAndSettle();

      // 期待値: 最初の1回のみ受け付けられること（開始発話＋Step 2-1突入発話の2回）
      expect(
        stressTts.speakCallCount,
        equals(2),
        reason: 'Step 1 開始キーの連打で複数回遷移が重複実行されてはならない',
      );
      expect(
        fakeSound.beepCount,
        equals(1),
        reason: 'Step 1 開始キーの連打で電子音が重複再生されてはならない',
      );
    });

    testWidgets('Test 2: Step 1 開始発話中の画面中央案内表示およびスキップ時の先祖返り防止検証', (tester) async {
      await tester.pumpWidget(buildStressApp());
      await tester.pumpAndSettle();

      stressTts.manualSpeakCompletion = true;
      stressTts.cancelPendingOnStop = false;
      stressTts.clear();

      // Step 1 開始を発火（TTS は manualSpeakCompletion で非同期保留中）
      await sendNativeKeyEvent(tester, 85);
      await tester.pump(const Duration(milliseconds: 50));

      expect(stressTts.spokenHistory, contains('開始、ベンチプレス、60キロ、10回、3セット'));
      // 音声案内が読み上げられている間、画面中央に開始案内が表示されていること
      expect(
        find.text('トレーニングが開始されました。（種目・重量・レップ数・セット数が読み上げられます）'),
        findsOneWidget,
      );

      // ユーザーが発話待機中にスキップボタンを2回押して Step 3 まで進行
      stressTts.manualSpeakCompletion = false;
      final skipBtn = find.byKey(const Key('btn_tutorial_skip'));
      await tester.tap(skipBtn); // Step 1 -> Step 2
      await tester.pump(const Duration(milliseconds: 50));

      await tester.tap(skipBtn); // Step 2 -> Step 3
      await tester.pump(const Duration(milliseconds: 50));

      // 現在 Step 3 にいることを確認
      expect(find.text('Step 3/5'), findsWidgets);

      // ここで遅延していた Step 1 の TTS 発話が完了
      stressTts.completePendingSpeak();
      await tester.pumpAndSettle();

      // Step 1 の非同期完了が Step 3 の状態を破壊して Step 2 へ先祖返りさせていないこと
      expect(find.text('Step 3/5'), findsWidgets);
    });

    testWidgets('Test 3: Step 3 重量調整後の即時スキップ時にオーディオダッキングがリークしないこと', (tester) async {
      await tester.pumpWidget(buildStressApp());
      await tester.pumpAndSettle();

      // Step 1 -> Step 2 -> Step 3（重量選択）まで進める
      await sendNativeKeyEvent(tester, 85);
      await tester.pumpAndSettle();
      await sendNativeKeyEvent(tester, 87);
      await tester.pumpAndSettle();
      await sendNativeKeyEvent(tester, 24); // 重量
      await tester.pump();
      await sendNativeKeyEvent(tester, 85); // Step 3 へ
      await tester.pumpAndSettle();

      stressDucking.clear();

      // Step 3 で音量UPキー（24）を押下 -> 電子音再生＋ダッキング要求＋0.7sデバウンスタイマー開始
      await sendNativeKeyEvent(tester, 24);
      await tester.pump(const Duration(milliseconds: 50));

      expect(stressDucking.requestCount, greaterThanOrEqualTo(1));
      expect(stressDucking.isCurrentlyDucked, isTrue);

      // デバウンス発話（0.7秒）を待たずに、即座にスキップボタンを押下して Step 4 へ遷移
      // （スキップ時の次ステップ音声発話前に一度 releaseDucking される）
      await tester.tap(find.byKey(const Key('btn_tutorial_skip')));
      await tester.pumpAndSettle();

      expect(find.text('Step 4/5'), findsWidgets);
      expect(stressDucking.releaseCount, greaterThanOrEqualTo(1));
    });

    testWidgets('Test 4: 全ての speak() の直前に厳密に stop() が実行されていること（Audio Hygiene 順序検証）', (tester) async {
      await tester.pumpWidget(buildStressApp());
      await tester.pumpAndSettle();

      stressTts.clear();

      // 各ステップを正規キーで通過
      await sendNativeKeyEvent(tester, 85); // Step 1 -> Step 2-1
      await tester.pumpAndSettle();

      await sendNativeKeyEvent(tester, 87); // Step 2-1 -> Step 2-2
      await tester.pumpAndSettle();

      await sendNativeKeyEvent(tester, 24); // 項目送り: 重量
      await tester.pumpAndSettle();

      await sendNativeKeyEvent(tester, 85); // Step 2-2 -> Step 3
      await tester.pumpAndSettle();

      await sendNativeKeyEvent(tester, 85); // Step 3 -> Step 4
      await tester.pumpAndSettle();

      await sendNativeKeyEvent(tester, 87); // Step 4 -> Step 5
      await tester.pumpAndSettle();

      await sendNativeKeyEvent(tester, 88); // Step 5 -> Step 6
      await tester.pumpAndSettle();

      // callLog の全 speak 呼び出しについて、直前のイベントが stop であることを検証
      final log = stressTts.callLog;
      expect(log, isNotEmpty);

      for (int i = 0; i < log.length; i++) {
        if (log[i].startsWith('tts.speak:')) {
          expect(i, greaterThan(0),
              reason: 'speak は最初のログであってはならず、stop が先行する必要がある');
          expect(
            log[i - 1],
            equals('tts.stop'),
            reason: 'インデックス $i の speak 直前 (${log[i - 1]}) は必ず stop でなければならない',
          );
        }
      }
    });
  });

  group('Lifecycle & Concurrency Safety Stress Tests', () {
    testWidgets('Test 5: TTS発話中または非同期処理中に画面を pop（dispose）してもクラッシュや事後発話が発生しないこと', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                key: const Key('open_tutorial'),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => TutorialScreen(
                        ttsService: stressTts,
                        soundEffectService: fakeSound,
                        duckingController: stressDucking,
                        animateGlow: false,
                      ),
                    ),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('open_tutorial')));
      await tester.pumpAndSettle();

      stressTts.manualSpeakCompletion = true;
      stressTts.cancelPendingOnStop = false;

      // Step 1 開始（TTS 発話開始中）
      await sendNativeKeyEvent(tester, 85);
      await tester.pump(const Duration(milliseconds: 50));

      final initialSpeakCount = stressTts.speakCallCount;

      // TTS が完了していない状態で、画面の戻るボタンをタップして pop
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();

      expect(find.byType(TutorialScreen), findsNothing);

      stressTts.completePendingSpeak();
      await tester.pumpAndSettle();

      expect(stressTts.speakCallCount, equals(initialSpeakCount));
    });

    testWidgets('Test 6: Step 3 デバウンスタイマー保留中に画面を pop してもタイマー残存クラッシュや事後setStateが発生しないこと', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                key: const Key('open_tutorial'),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => TutorialScreen(
                        ttsService: stressTts,
                        soundEffectService: fakeSound,
                        duckingController: stressDucking,
                        animateGlow: false,
                      ),
                    ),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('open_tutorial')));
      await tester.pumpAndSettle();

      // Step 3 までスキップ
      await tester.tap(find.byKey(const Key('btn_tutorial_skip'))); // to 2
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('btn_tutorial_skip'))); // to 3
      await tester.pumpAndSettle();

      // Step 3 で音量変更（0.7秒デバウンスタイマー始動）
      await sendNativeKeyEvent(tester, 24);
      await tester.pump(const Duration(milliseconds: 100));

      stressTts.clear();

      // タイマーが発火する前に画面を pop
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();

      expect(find.byType(TutorialScreen), findsNothing);

      await tester.pump(const Duration(seconds: 1));
      expect(stressTts.spokenHistory, isEmpty);
    });

    testWidgets('Test 7: 画面最下部仮想キーバー Vol+ の 20回超高速連打テスト（デバウンスと数値整合性）', (tester) async {
      await tester.pumpWidget(buildStressApp());
      await tester.pumpAndSettle();

      // Step 1 -> Step 2-1 -> Step 2-2 -> 重量 -> Step 3
      await sendNativeKeyEvent(tester, 85);
      await tester.pumpAndSettle();
      await sendNativeKeyEvent(tester, 87);
      await tester.pumpAndSettle();
      await sendNativeKeyEvent(tester, 24); // 重量
      await tester.pump();
      await sendNativeKeyEvent(tester, 85);
      await tester.pumpAndSettle();

      stressTts.clear();
      fakeSound.clear();

      final volUpBtn = find.byKey(const Key('virtual_key_vol_up'));

      // 20回高速タップ（50ms間隔）: 60.0kg + 20 * 2.5kg = 110.0kg
      for (int i = 0; i < 20; i++) {
        await tester.tap(volUpBtn);
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(stressTts.spokenHistory, isEmpty);
      expect(fakeSound.beepCount, equals(20));
      expect(find.text('110 kg'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 750));

      expect(stressTts.spokenHistory, equals(['110キロ']));
    });

    testWidgets('Test 8: Step 2-2 決定発話処理中のスキップ連打によるステートマシン先祖返り防止の検証', (tester) async {
      await tester.pumpWidget(buildStressApp());
      await tester.pumpAndSettle();

      // Step 2-2（決定待ち）まで進める
      await sendNativeKeyEvent(tester, 85); // Step 1 -> 2-1
      await tester.pumpAndSettle();
      await sendNativeKeyEvent(tester, 87); // Step 2-1 -> 2-2
      await tester.pumpAndSettle();
      await sendNativeKeyEvent(tester, 24); // 重量
      await tester.pump();

      stressTts.manualSpeakCompletion = true;
      stressTts.cancelPendingOnStop = false;
      stressTts.clear();

      // Step 2-2 決定（キー 85）を押下 -> 「重量を調整します。」発話が非同期保留中
      await sendNativeKeyEvent(tester, 85);
      await tester.pump(const Duration(milliseconds: 50));

      expect(stressTts.spokenHistory, contains('重量を調整します。'));

      // 発話保留中にスキップボタンを2回押して Step 4 へ進行
      stressTts.manualSpeakCompletion = false;
      final skipBtn = find.byKey(const Key('btn_tutorial_skip'));
      await tester.tap(skipBtn); // Step 2 -> Step 3
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(skipBtn); // Step 3 -> Step 4
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Step 4/5'), findsWidgets);

      // 遅延していた Step 2-2 の発話完了を解放
      stressTts.completePendingSpeak();
      await tester.pumpAndSettle();

      // Step 4 の状態を維持し、Step 3 へ先祖返りしていないこと
      expect(find.text('Step 4/5'), findsWidgets);
    });

    testWidgets('Test 9: Step 4 確定キー連打時の重複発話・電子音スパムの検証', (tester) async {
      await tester.pumpWidget(buildStressApp());
      await tester.pumpAndSettle();

      // Step 4 までスキップ
      await tester.tap(find.byKey(const Key('btn_tutorial_skip'))); // to 2
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('btn_tutorial_skip'))); // to 3
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('btn_tutorial_skip'))); // to 4
      await tester.pumpAndSettle();

      stressTts.clear();
      fakeSound.clear();

      // キー 87（次曲＝調整完了）を瞬時に5回連打
      await sendNativeKeyEvent(tester, 87);
      await sendNativeKeyEvent(tester, 87);
      await sendNativeKeyEvent(tester, 87);
      await sendNativeKeyEvent(tester, 87);
      await sendNativeKeyEvent(tester, 87);
      await tester.pumpAndSettle();

      // 期待値: 「確定」＋ Step 5 突入音声の計2回のみ発話され、重複実行されないこと
      expect(
        stressTts.speakCallCount,
        equals(2),
        reason: 'Step 4 確定キー連打で複数回 TTS が多重発話されてはならない',
      );
      expect(
        fakeSound.beepCount,
        equals(1),
        reason: 'Step 4 確定キー連打で電子音が重複再生されてはならない',
      );
    });
  });
}
