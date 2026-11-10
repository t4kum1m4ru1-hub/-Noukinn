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
    testWidgets('Test 1: Step 2 におけるキー85連打時の重複発話・電子音スパムの検証', (tester) async {
      await tester.pumpWidget(buildStressApp());
      await tester.pumpAndSettle();

      // Step 1 -> Step 2
      await tester.tap(find.byKey(const Key('btn_tutorial_start')));
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

      // 期待値: 最初の1回のみ受け付けられ、複数回の開始TTSが多重発話されないこと
      // （多重発話される場合は bug: 5回の重複呼び出し）
      expect(
        stressTts.speakCallCount,
        equals(1),
        reason: 'Step 2 開始キーの連打で複数回 TTS が多重発話されてはならない (再入防止)',
      );
      expect(
        fakeSound.beepCount,
        equals(1),
        reason: 'Step 2 開始キーの連打で電子音が重複再生されてはならない',
      );
    });

    testWidgets('Test 2: Step 2 発話処理中のスキップ連打によるステートマシン先祖返り（Step 4 -> Step 3 逆流）の検証', (tester) async {
      stressTts.manualSpeakCompletion = true;
      stressTts.cancelPendingOnStop = false; // stop() で completer を即完了させず遅延を再現

      await tester.pumpWidget(buildStressApp());
      await tester.pumpAndSettle();

      // Step 1 -> Step 2
      await tester.tap(find.byKey(const Key('btn_tutorial_start')));
      await tester.pumpAndSettle();

      // Step 2 開始を発火（TTS は manualSpeakCompletion で非同期保留中）
      await sendNativeKeyEvent(tester, 85);
      await tester.pump(const Duration(milliseconds: 50));

      expect(stressTts.spokenHistory, contains('開始、ベンチプレス、60キロ、10回、3セット'));

      // ユーザーが発話待機中にスキップボタンを2回押して Step 4 まで進行
      final skipBtn = find.byKey(const Key('btn_tutorial_skip'));
      await tester.tap(skipBtn); // Step 2 -> Step 3
      await tester.pump(const Duration(milliseconds: 50));

      await tester.tap(skipBtn); // Step 3 -> Step 4
      await tester.pump(const Duration(milliseconds: 50));

      // 現在 Step 4（重量カード表示）にいることを確認
      expect(find.byKey(const Key('card_weight')), findsOneWidget);
      expect(find.textContaining('重量調整と音声'), findsOneWidget);

      // ここで遅延していた Step 2 の TTS 発話が完了
      stressTts.completePendingSpeak();
      await tester.pumpAndSettle();

      // 検証: Step 2 の非同期完了が Step 4 の状態を破壊して Step 3 へ先祖返りさせていないか？
      expect(
        find.textContaining('重量調整と音声'),
        findsOneWidget,
        reason: 'Step 2 の非同期コールバック完了によって Step 4 から Step 3 へ先祖返りしてはならない',
      );
      expect(
        find.textContaining('次の曲へ進む'),
        findsNothing,
        reason: 'Step 3 への先祖返りが発生してはならない',
      );
    });

    testWidgets('Test 3: Step 4 重量調整後の即時スキップ時にオーディオダッキングがリークしないこと', (tester) async {
      await tester.pumpWidget(buildStressApp());
      await tester.pumpAndSettle();

      // Step 1 -> Step 4 までスキップで一気に遷移
      await tester.tap(find.byKey(const Key('btn_tutorial_start')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('btn_tutorial_skip'))); // to 3
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('btn_tutorial_skip'))); // to 4
      await tester.pumpAndSettle();

      stressDucking.clear();

      // Step 4 で音量UPキー（24）を押下 -> 電子音再生＋ダッキング要求＋0.7sデバウンスタイマー開始
      await sendNativeKeyEvent(tester, 24);
      await tester.pump(const Duration(milliseconds: 50));

      // ダッキングが要求されていることを確認
      expect(stressDucking.requestCount, greaterThanOrEqualTo(1));
      expect(stressDucking.isCurrentlyDucked, isTrue);

      // デバウンス発話（0.7秒）を待たずに、即座にスキップボタンを押下して Step 5 へ遷移
      await tester.tap(find.byKey(const Key('btn_tutorial_skip')));
      await tester.pumpAndSettle();

      // 現在 Step 5 にいることを確認
      expect(find.textContaining('調整の完了'), findsOneWidget);

      // 0.7秒以上経過させ、デバウンスタイマーの完了タイミングを通過させる
      await tester.pump(const Duration(seconds: 1));

      // 検証: デバウンスがキャンセルされた後、ダッキングが有効のまま放置（リーク）されていないこと
      expect(
        stressDucking.isCurrentlyDucked,
        isFalse,
        reason: 'デバウンスTTSがスキップされた場合、オーディオダッキングは解除されなければならない',
      );
    });

    testWidgets('Test 4: 全ての speak() の直前に厳密に stop() が実行されていること（Audio Hygiene 順序検証）', (tester) async {
      await tester.pumpWidget(buildStressApp());
      await tester.pumpAndSettle();

      // Step 1 -> Step 2
      await tester.tap(find.byKey(const Key('btn_tutorial_start')));
      await tester.pumpAndSettle();

      stressTts.clear();

      // 各ステップを正規キーで通過
      await sendNativeKeyEvent(tester, 85); // Step 2 -> 3
      await tester.pumpAndSettle();

      await sendNativeKeyEvent(tester, 87); // Step 3 Part 1 -> Part 2
      await tester.pumpAndSettle();

      await sendNativeKeyEvent(tester, 24); // 項目送り: 重量
      await tester.pumpAndSettle();

      await sendNativeKeyEvent(tester, 88); // 内容確認
      await tester.pumpAndSettle();

      await sendNativeKeyEvent(tester, 85); // Step 3 -> Step 4
      await tester.pumpAndSettle();

      // callLog の全 speak 呼び出しについて、直前のイベントが stop であることを検証
      final log = stressTts.callLog;
      expect(log, isNotEmpty);

      for (int i = 0; i < log.length; i++) {
        if (log[i].startsWith('tts.speak:')) {
          expect(i, greaterThan(0), reason: 'speak は最初のログであってはならず、stop が先行する必要がある');
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
      stressTts.manualSpeakCompletion = true;
      stressTts.cancelPendingOnStop = false;

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

      // チュートリアル画面を開く
      await tester.tap(find.byKey(const Key('open_tutorial')));
      await tester.pumpAndSettle();

      // Step 1 -> Step 2
      await tester.tap(find.byKey(const Key('btn_tutorial_start')));
      await tester.pumpAndSettle();

      // Step 2 開始（TTS 発話開始中）
      await sendNativeKeyEvent(tester, 85);
      await tester.pump(const Duration(milliseconds: 50));

      final initialSpeakCount = stressTts.speakCallCount;

      // TTS が完了していない状態で、画面の戻るボタン（AppBar leading）をタップして pop
      final backBtn = find.byType(BackButton);
      final leadingIcon = find.byIcon(Icons.arrow_back);
      if (backBtn.evaluate().isNotEmpty) {
        await tester.tap(backBtn);
      } else {
        await tester.tap(leadingIcon);
      }
      await tester.pumpAndSettle();

      // TutorialScreen が完全にアンマウントされたことを確認
      expect(find.byType(TutorialScreen), findsNothing);

      // 非同期保留されていた TTS 発話の完了を解放
      stressTts.completePendingSpeak();
      await tester.pumpAndSettle();

      // 検証: アンマウント後に新たな speak() が呼び出されたりクラッシュが発生しないこと
      expect(stressTts.speakCallCount, equals(initialSpeakCount));
    });

    testWidgets('Test 6: Step 4 デバウンスタイマー保留中に画面を pop してもタイマー残存クラッシュや事後setStateが発生しないこと', (tester) async {
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

      // Step 4 までスキップ
      await tester.tap(find.byKey(const Key('btn_tutorial_start')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('btn_tutorial_skip'))); // to 3
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('btn_tutorial_skip'))); // to 4
      await tester.pumpAndSettle();

      // Step 4 で重量変更（0.7秒デバウンスタイマー始動）
      await sendNativeKeyEvent(tester, 24);
      await tester.pump(const Duration(milliseconds: 100));

      stressTts.clear();

      // タイマーが発火する前（300ms後）に画面を pop
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();

      expect(find.byType(TutorialScreen), findsNothing);

      // 0.7秒以上経過させても、dispose 済みのタイマーが TTS 発話を起動しないこと
      await tester.pump(const Duration(seconds: 1));
      expect(stressTts.spokenHistory, isEmpty);
    });

    testWidgets('Test 7: 画面最下部仮想キーバー Vol+ の 20回超高速連打テスト（デバウンスと数値整合性）', (tester) async {
      await tester.pumpWidget(buildStressApp());
      await tester.pumpAndSettle();

      // Step 4 までスキップ
      await tester.tap(find.byKey(const Key('btn_tutorial_start')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('btn_tutorial_skip')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('btn_tutorial_skip')));
      await tester.pumpAndSettle();

      stressTts.clear();
      fakeSound.clear();

      final volUpBtn = find.byKey(const Key('virtual_key_vol_up'));

      // 20回高速タップ（50ms間隔）: 60.0kg + 20 * 2.5kg = 110.0kg
      for (int i = 0; i < 20; i++) {
        await tester.tap(volUpBtn);
        await tester.pump(const Duration(milliseconds: 50));
      }

      // 連打中は TTS はまだ発話されていないこと
      expect(stressTts.spokenHistory, isEmpty);
      expect(fakeSound.beepCount, equals(20));
      expect(find.text('110 kg'), findsOneWidget);

      // 連打停止から 0.7秒経過
      await tester.pump(const Duration(milliseconds: 750));

      // デバウンスにより、最後の「110キロ」のみが 1回だけ発話されること
      expect(stressTts.spokenHistory, equals(['110キロ']));
    });

    testWidgets('Test 8: Step 3 決定発話処理中のスキップ連打によるステートマシン先祖返り（Step 5 -> Step 4 逆流）の検証', (tester) async {
      await tester.pumpWidget(buildStressApp());
      await tester.pumpAndSettle();

      // Step 3 Part 2（決定待ち）まで進める
      await tester.tap(find.byKey(const Key('btn_tutorial_start')));
      await tester.pumpAndSettle();
      await sendNativeKeyEvent(tester, 85); // Step 2 -> 3
      await tester.pumpAndSettle();
      await sendNativeKeyEvent(tester, 87); // Part 1 -> Part 2
      await tester.pumpAndSettle();

      // Step 3 Part 2 の状態で manualSpeakCompletion を有効化
      stressTts.manualSpeakCompletion = true;
      stressTts.cancelPendingOnStop = false;
      stressTts.clear();

      // Step 3 決定（キー 85）を押下 -> 「60キロ」発話が非同期保留中
      await sendNativeKeyEvent(tester, 85);
      await tester.pump(const Duration(milliseconds: 50));

      expect(stressTts.spokenHistory, contains('60キロ'));

      // 発話保留中にスキップボタンを2回押して Step 5 へ進行
      final skipBtn = find.byKey(const Key('btn_tutorial_skip'));
      await tester.tap(skipBtn); // Step 3 -> Step 4
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(skipBtn); // Step 4 -> Step 5
      await tester.pump(const Duration(milliseconds: 50));

      // 現在 Step 5 にいることを確認
      expect(find.textContaining('調整の完了'), findsOneWidget);

      // ここで遅延していた Step 3 の発話完了を解放
      stressTts.completePendingSpeak();
      await tester.pumpAndSettle();

      // 検証: Step 3 の非同期完了が Step 5 の状態を破壊して Step 4 へ先祖返りさせていないか？
      expect(
        find.textContaining('調整の完了'),
        findsOneWidget,
        reason: 'Step 3 の決定発話完了によって Step 5 から Step 4 へ先祖返りしてはならない',
      );
      expect(
        find.textContaining('重量調整と音声'),
        findsNothing,
        reason: 'Step 4 への先祖返りが発生してはならない',
      );
    });

    testWidgets('Test 9: Step 5 確定キー連打時の重複発話・電子音スパムの検証', (tester) async {
      await tester.pumpWidget(buildStressApp());
      await tester.pumpAndSettle();

      // Step 5 までスキップ
      await tester.tap(find.byKey(const Key('btn_tutorial_start')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('btn_tutorial_skip'))); // to 3
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('btn_tutorial_skip'))); // to 4
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('btn_tutorial_skip'))); // to 5
      await tester.pumpAndSettle();

      stressTts.clear();
      fakeSound.clear();

      // キー 87（次曲＝確定）を瞬時に5回連打
      await sendNativeKeyEvent(tester, 87);
      await sendNativeKeyEvent(tester, 87);
      await sendNativeKeyEvent(tester, 87);
      await sendNativeKeyEvent(tester, 87);
      await sendNativeKeyEvent(tester, 87);
      await tester.pumpAndSettle();

      // 期待値: 確定TTS（「確定、開始、...」）は1回のみ発話され、複数回多重発話されないこと
      expect(
        stressTts.speakCallCount,
        equals(1),
        reason: 'Step 5 確定キー連打で複数回 TTS が多重発話されてはならない',
      );
      expect(
        fakeSound.beepCount,
        equals(1),
        reason: 'Step 5 確定キー連打で電子音が重複再生されてはならない',
      );
    });
  });
}
