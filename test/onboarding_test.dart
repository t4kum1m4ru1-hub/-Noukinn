import 'dart:async';
import 'package:flutter/cupertino.dart';
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
  late InMemoryProfileStorageService storageService;

  setUp(() {
    fakeTts = FakeTtsService();
    fakeSound = FakeSoundEffectService();
    storageService = InMemoryProfileStorageService();
  });

  group('Unit Tests: UserProfile & StorageService', () {
    test('UserProfile の toJson / fromJson 変換が正しく相互変換できること', () {
      const original = UserProfile(
        heightCm: 175,
        weightKg: 70.5,
        ageGroup: '30〜34歳',
        gender: '男性',
        aimCategory: AimCategory.bodyType,
        targetGoal: '細マッチョ（引き締め＆筋力）',
      );

      final json = original.toJson();
      final restored = UserProfile.fromJson(json);

      expect(restored.heightCm, original.heightCm);
      expect(restored.weightKg, original.weightKg);
      expect(restored.ageGroup, original.ageGroup);
      expect(restored.gender, original.gender);
      expect(restored.aimCategory, original.aimCategory);
      expect(restored.targetGoal, original.targetGoal);
    });

    test('InMemoryProfileStorageService の保存と取得・クリアが正しく動作すること', () async {
      final storage = InMemoryProfileStorageService();
      expect(await storage.isOnboardingCompleted(), isFalse);
      expect(await storage.getUserProfile(), isNull);

      const profile = UserProfile(
        heightCm: 168,
        weightKg: 62.0,
        ageGroup: '25〜29歳',
        gender: '女性',
        aimCategory: AimCategory.sports,
        targetGoal: 'ランニング・陸上',
      );

      await storage.saveUserProfile(profile);
      expect(await storage.isOnboardingCompleted(), isTrue);

      final retrieved = await storage.getUserProfile();
      expect(retrieved, isNotNull);
      expect(retrieved!.targetGoal, 'ランニング・陸上');

      await storage.clear();
      expect(await storage.isOnboardingCompleted(), isFalse);
      expect(await storage.getUserProfile(), isNull);
    });
  });

  group('Widget Tests: WelcomeScreen UI・TTS・イヤホンキー', () {
    testWidgets('ウェルカム画面の表示、初期音声案内、ボタンタップでの開始', (tester) async {
      var started = false;

      await tester.pumpWidget(
        MaterialApp(
          home: WelcomeScreen(
            ttsService: fakeTts,
            soundEffectService: fakeSound,
            onStart: () {
              started = true;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('welcome_title')), findsOneWidget);
      expect(find.text('NOUKIN'), findsOneWidget);
      expect(find.byKey(const Key('welcome_subtitle')), findsOneWidget);
      expect(find.byKey(const Key('welcome_image_container')), findsOneWidget);
      expect(find.byKey(const Key('welcome_description')), findsOneWidget);
      expect(fakeTts.lastSpoken, '完全ハンズフリートレーニングへようこそ。設定をはじめます。');

      final startButton = find.byKey(const Key('welcome_start_button'));
      expect(startButton, findsOneWidget);

      await tester.tap(startButton);
      await tester.pumpAndSettle();

      expect(started, isTrue);
      expect(fakeSound.beepCount, 1);
    });

    testWidgets('ウェルカム画面でイヤホンボタン（85）を押すと開始できること', (tester) async {
      var started = false;

      await tester.pumpWidget(
        MaterialApp(
          home: WelcomeScreen(
            ttsService: fakeTts,
            soundEffectService: fakeSound,
            onStart: () {
              started = true;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await sendNativeKeyEvent(tester, 85);
      await tester.pumpAndSettle();

      expect(started, isTrue);
      expect(fakeSound.beepCount, 1);
    });
  });

  group('Widget Tests: OnboardingScreen タッチ操作フロー', () {
    testWidgets('Step 0〜5 をタッチ操作で選択し、完了時にプロフィールが正しく保存されること', (tester) async {
      UserProfile? completedProfile;

      await tester.pumpWidget(
        MaterialApp(
          home: OnboardingScreen(
            storageService: storageService,
            ttsService: fakeTts,
            soundEffectService: fakeSound,
            onCompleted: (profile) {
              completedProfile = profile;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Step 0: 身長
      expect(find.text('初期設定 (1 / 6)'), findsOneWidget);
      expect(find.text('身長を教えてください'), findsOneWidget);
      expect(fakeTts.lastSpoken, '身長を教えてください。現在、170センチです');

      // 身長ピッカーを操作（170 -> 172cm へ変更）
      final heightPickerFinder = find.byKey(const Key('height_picker'));
      final heightPicker = tester.widget<CupertinoPicker>(heightPickerFinder);
      heightPicker.scrollController?.jumpToItem(172 - 120);
      await tester.pump(const Duration(milliseconds: 750));
      expect(fakeTts.lastSpoken, '172センチ');

      // 次へタップ
      await tester.tap(find.byKey(const Key('onboarding_next_button')));
      await tester.pumpAndSettle();

      // Step 1: 体重
      expect(find.text('初期設定 (2 / 6)'), findsOneWidget);
      expect(find.text('体重を教えてください'), findsOneWidget);
      expect(fakeTts.lastSpoken, '体重を教えてください。現在、65キロです');

      // 体重ピッカーを操作（65 -> 68kg へ変更）
      final weightPickerFinder = find.byKey(const Key('weight_picker'));
      final weightPicker = tester.widget<CupertinoPicker>(weightPickerFinder);
      weightPicker.scrollController?.jumpToItem(68 - 30);
      await tester.pump(const Duration(milliseconds: 750));
      expect(fakeTts.lastSpoken, '68キロ');

      // 次へタップ
      await tester.tap(find.byKey(const Key('onboarding_next_button')));
      await tester.pumpAndSettle();

      // Step 2: 年齢
      expect(find.text('初期設定 (3 / 6)'), findsOneWidget);
      expect(fakeTts.lastSpoken, '年齢を教えてください。現在、20〜24歳です');

      await tester.tap(find.byKey(const Key('choice_30〜34歳')));
      await tester.pump(const Duration(milliseconds: 750));
      expect(fakeTts.lastSpoken, '30〜34歳');

      await tester.tap(find.byKey(const Key('onboarding_next_button')));
      await tester.pumpAndSettle();

      // Step 3: 性別
      expect(find.text('初期設定 (4 / 6)'), findsOneWidget);
      expect(fakeTts.lastSpoken, '性別を教えてください。現在、男性です');

      await tester.tap(find.byKey(const Key('choice_女性')));
      await tester.pump(const Duration(milliseconds: 750));
      expect(fakeTts.lastSpoken, '女性');

      await tester.tap(find.byKey(const Key('onboarding_next_button')));
      await tester.pumpAndSettle();

      // Step 4: 目的基準
      expect(find.text('初期設定 (5 / 6)'), findsOneWidget);
      expect(fakeTts.lastSpoken, '目標の設定基準を教えてください。現在、目指す体型から選ぶです');

      await tester.tap(find.byKey(const Key('aim_choice_目指す体型から選ぶ')));
      await tester.pump(const Duration(milliseconds: 750));

      await tester.tap(find.byKey(const Key('onboarding_next_button')));
      await tester.pumpAndSettle();

      // Step 5: 体型詳細
      expect(find.text('初期設定 (6 / 6)'), findsOneWidget);
      expect(fakeTts.lastSpoken, '目指す体型を教えてください。現在、細マッチョです');

      await tester.tap(find.byKey(const Key('choice_筋肥大・バルクアップ（たくましい体）')));
      await tester.pump(const Duration(milliseconds: 750));
      expect(fakeTts.lastSpoken, '筋肥大・バルクアップ');

      await tester.tap(find.byKey(const Key('onboarding_next_button')));
      await tester.pumpAndSettle();

      expect(completedProfile, isNotNull);
      expect(completedProfile!.heightCm, 172);
      expect(completedProfile!.weightKg, 68.0);
      expect(completedProfile!.ageGroup, '30〜34歳');
      expect(completedProfile!.gender, '女性');
      expect(completedProfile!.aimCategory, AimCategory.bodyType);
      expect(completedProfile!.targetGoal, '筋肥大・バルクアップ（たくましい体）');
      expect(fakeTts.lastSpoken, '設定が完了しました。チュートリアルを開始します。');
    });
  });

  group('Widget Tests: OnboardingScreen イヤホン物理ボタン操作 ＆ 0.7秒デバウンスTTS検証', () {
    testWidgets('音量キーで数値/選択肢増減・0.7秒デバウンス・前曲(88)で戻る・再生停止(85)で決定次へが動作すること', (
      tester,
    ) async {
      UserProfile? completedProfile;

      await tester.pumpWidget(
        MaterialApp(
          home: OnboardingScreen(
            storageService: storageService,
            ttsService: fakeTts,
            soundEffectService: fakeSound,
            onCompleted: (profile) {
              completedProfile = profile;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Step 0: 身長初期案内
      expect(fakeTts.lastSpoken, '身長を教えてください。現在、170センチです');
      fakeTts.clear();
      fakeSound.clear();

      // 音量アップ (24) を2回ポンポンと押す（170 -> 171 -> 172cm）
      await sendNativeKeyEvent(tester, 24);
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('171 cm'), findsOneWidget);
      expect(fakeSound.beepCount, 1);
      expect(fakeTts.spokenHistory, isEmpty); // まだ発話されない（デバウンス中）

      await sendNativeKeyEvent(tester, 24);
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('172 cm'), findsOneWidget);
      expect(fakeSound.beepCount, 2);
      expect(fakeTts.spokenHistory, isEmpty);

      // 0.7秒経過後にまとめて発話「172センチ」
      await tester.pump(const Duration(milliseconds: 550));
      expect(fakeTts.spokenHistory, ['172センチ']);

      // 音量ダウン (25) で171cmへ
      fakeTts.clear();
      await sendNativeKeyEvent(tester, 25);
      await tester.pump(const Duration(milliseconds: 750));
      expect(find.text('171 cm'), findsOneWidget);
      expect(fakeTts.lastSpoken, '171センチ');

      // 再生/停止 (85) で決定して Step 1 (体重) へ進む
      await sendNativeKeyEvent(tester, 85);
      await tester.pumpAndSettle();
      expect(find.text('初期設定 (2 / 6)'), findsOneWidget);
      expect(fakeTts.lastSpoken, '体重を教えてください。現在、65キロです');

      // 体重で音量アップ (24) ➔ 66kg
      fakeTts.clear();
      await sendNativeKeyEvent(tester, 24);
      await tester.pump(const Duration(milliseconds: 750));
      expect(find.text('66 kg'), findsOneWidget);
      expect(fakeTts.lastSpoken, '66キロ');

      // 曲送り (87) で決定して Step 2 (年齢) へ進む
      await sendNativeKeyEvent(tester, 87);
      await tester.pumpAndSettle();
      expect(find.text('初期設定 (3 / 6)'), findsOneWidget);
      expect(fakeTts.lastSpoken, '年齢を教えてください。現在、20〜24歳です');

      // 年齢で音量アップ (24) ➔ 25〜29歳
      fakeTts.clear();
      await sendNativeKeyEvent(tester, 24);
      await tester.pump(const Duration(milliseconds: 750));
      expect(fakeTts.lastSpoken, '25〜29歳');

      // 前の曲 (88) を押すと、回答を修正するため Step 1 (体重) に戻る（選択肢Aの仕様）
      await sendNativeKeyEvent(tester, 88);
      await tester.pumpAndSettle();
      expect(find.text('初期設定 (2 / 6)'), findsOneWidget);
      expect(fakeTts.lastSpoken, '体重を教えてください。現在、66キロです');

      // 再度次へ進む (Step 1 ➔ Step 2 ➔ Step 3)
      await sendNativeKeyEvent(tester, 85); // ➔ Step 2
      await tester.pumpAndSettle();
      expect(find.text('初期設定 (3 / 6)'), findsOneWidget);

      await sendNativeKeyEvent(tester, 85); // ➔ Step 3 (性別)
      await tester.pumpAndSettle();
      expect(find.text('初期設定 (4 / 6)'), findsOneWidget);
      expect(fakeTts.lastSpoken, '性別を教えてください。現在、男性です');

      // 音量アップ (24) で女性に変更
      fakeTts.clear();
      await sendNativeKeyEvent(tester, 24);
      await tester.pump(const Duration(milliseconds: 750));
      expect(fakeTts.lastSpoken, '女性');

      await sendNativeKeyEvent(tester, 85); // ➔ Step 4 (目的基準)
      await tester.pumpAndSettle();
      expect(find.text('初期設定 (5 / 6)'), findsOneWidget);
      expect(fakeTts.lastSpoken, '目標の設定基準を教えてください。現在、目指す体型から選ぶです');

      // 音量キーでスポーツに切り替え
      fakeTts.clear();
      await sendNativeKeyEvent(tester, 24);
      await tester.pump(const Duration(milliseconds: 750));
      expect(fakeTts.lastSpoken, 'やっているスポーツから選ぶ');

      await sendNativeKeyEvent(tester, 85); // ➔ Step 5 (スポーツ詳細)
      await tester.pumpAndSettle();
      expect(find.text('初期設定 (6 / 6)'), findsOneWidget);
      expect(fakeTts.lastSpoken, '行っているスポーツを教えてください。現在、ランニング・陸上です');

      // 音量アップ (24) でサッカー・フットサルに変更
      fakeTts.clear();
      await sendNativeKeyEvent(tester, 24);
      await tester.pump(const Duration(milliseconds: 750));
      expect(fakeTts.lastSpoken, 'サッカー・フットサル');

      // 最後の決定 (85)
      await sendNativeKeyEvent(tester, 85);
      await tester.pumpAndSettle();

      expect(completedProfile, isNotNull);
      expect(completedProfile!.heightCm, 171);
      expect(completedProfile!.weightKg, 66.0);
      expect(completedProfile!.gender, '女性');
      expect(completedProfile!.aimCategory, AimCategory.sports);
      expect(completedProfile!.targetGoal, 'サッカー・フットサル');
      expect(fakeTts.lastSpoken, '設定が完了しました。チュートリアルを開始します。');
    });
  });

  group('Widget Tests: AppEntryRouter ルーティング統合検証', () {
    testWidgets('初回起動時: WelcomeScreen ➔ OnboardingScreen ➔ TutorialScreen 遷移', (
      tester,
    ) async {
      final storage = InMemoryProfileStorageService(initialCompleted: false);

      await tester.pumpWidget(
        ButtonControlApp(
          ttsService: fakeTts,
          soundEffectService: fakeSound,
          profileStorageService: storage,
        ),
      );
      await tester.pumpAndSettle();

      // WelcomeScreen が表示される
      expect(find.byType(WelcomeScreen), findsOneWidget);
      expect(find.byType(ButtonControlScreen), findsNothing);

      // イヤホン再生停止 (85) でスタート
      await sendNativeKeyEvent(tester, 85);
      await tester.pumpAndSettle();

      // OnboardingScreen に遷移
      expect(find.byType(OnboardingScreen), findsOneWidget);

      // 全6ステップをイヤホンキー (85) で進めて完了する
      for (var i = 0; i < 6; i++) {
        await sendNativeKeyEvent(tester, 85);
        await tester.pumpAndSettle();
      }

      // TutorialScreen へ遷移したことを確認
      expect(find.byType(TutorialScreen), findsOneWidget);
      expect(await storage.isOnboardingCompleted(), isTrue);
    });

    testWidgets('2回目以降起動時: 直接 ButtonControlScreen が表示されること', (tester) async {
      final storage = InMemoryProfileStorageService(initialCompleted: true);

      await tester.pumpWidget(
        ButtonControlApp(
          ttsService: fakeTts,
          soundEffectService: fakeSound,
          profileStorageService: storage,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(WelcomeScreen), findsNothing);
      expect(find.byType(OnboardingScreen), findsNothing);
      expect(find.byType(ButtonControlScreen), findsOneWidget);
      expect(find.byKey(const Key('waiting_prompt')), findsOneWidget);
    });
  });
}
