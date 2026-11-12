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
  late FakeSpeechRecognitionService fakeSpeech;
  late InMemoryProfileStorageService storageService;

  setUp(() {
    fakeTts = FakeTtsService();
    fakeSound = FakeSoundEffectService();
    fakeSpeech = FakeSpeechRecognitionService();
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

  group('Unit Tests: VoiceCommandInterpreter 音声コマンド解析', () {
    test('全ステップ共通の進行キーワード（次へ、決定、スタート等）が NextStepAction に解析されること', () {
      for (final kw in ['次へ', '決定', '進む', 'はい', 'オッケー', 'スタート', 'はじめる', '完了']) {
        final action = VoiceCommandInterpreter.interpret(
          step: 0,
          speech: kw,
          currentAimCategory: AimCategory.bodyType,
        );
        expect(action, isA<NextStepAction>());
      }
    });

    test('全ステップ共通の戻るキーワード（前へ、戻る等）が PreviousStepAction に解析されること', () {
      for (final kw in ['前へ', '戻る', '戻って', 'いいえ']) {
        final action = VoiceCommandInterpreter.interpret(
          step: 1,
          speech: kw,
          currentAimCategory: AimCategory.bodyType,
        );
        expect(action, isA<PreviousStepAction>());
      }
    });

    test('身長: 具体的な数値指定および増減キーワードが正しく解析されること', () {
      final act1 = VoiceCommandInterpreter.interpret(
        step: 0,
        speech: '175センチ',
        currentAimCategory: AimCategory.bodyType,
      );
      expect(act1, isA<SetHeightAction>());
      expect((act1 as SetHeightAction).heightCm, 175);

      final actUp = VoiceCommandInterpreter.interpret(
        step: 0,
        speech: 'アップ',
        currentAimCategory: AimCategory.bodyType,
      );
      expect(actUp, isA<AdjustHeightAction>());
      expect((actUp as AdjustHeightAction).delta, 1);

      final actDown = VoiceCommandInterpreter.interpret(
        step: 0,
        speech: '下げて',
        currentAimCategory: AimCategory.bodyType,
      );
      expect(actDown, isA<AdjustHeightAction>());
      expect((actDown as AdjustHeightAction).delta, -1);
    });

    test('体重: 具体的な数値指定および増減キーワードが正しく解析されること', () {
      final act1 = VoiceCommandInterpreter.interpret(
        step: 1,
        speech: '68キロ',
        currentAimCategory: AimCategory.bodyType,
      );
      expect(act1, isA<SetWeightAction>());
      expect((act1 as SetWeightAction).weightKg, 68.0);

      final actUp = VoiceCommandInterpreter.interpret(
        step: 1,
        speech: '増やして',
        currentAimCategory: AimCategory.bodyType,
      );
      expect(actUp, isA<AdjustWeightAction>());
      expect((actUp as AdjustWeightAction).delta, 1.0);
    });

    test('年代・性別・目的の音声が適切に解析されること', () {
      final actAge = VoiceCommandInterpreter.interpret(
        step: 2,
        speech: '30代前半',
        currentAimCategory: AimCategory.bodyType,
      );
      expect(actAge, isA<SelectAgeAction>());
      expect((actAge as SelectAgeAction).ageGroup, '30〜34歳');

      final actGender = VoiceCommandInterpreter.interpret(
        step: 3,
        speech: '女性です',
        currentAimCategory: AimCategory.bodyType,
      );
      expect(actGender, isA<SelectGenderAction>());
      expect((actGender as SelectGenderAction).gender, '女性');

      final actAim = VoiceCommandInterpreter.interpret(
        step: 4,
        speech: 'スポーツから選ぶ',
        currentAimCategory: AimCategory.bodyType,
      );
      expect(actAim, isA<SelectAimCategoryAction>());
      expect((actAim as SelectAimCategoryAction).category, AimCategory.sports);

      final actGoal = VoiceCommandInterpreter.interpret(
        step: 5,
        speech: 'サッカーをやってます',
        currentAimCategory: AimCategory.sports,
      );
      expect(actGoal, isA<SelectGoalAction>());
      expect((actGoal as SelectGoalAction).goal, 'サッカー・フットサル');
    });
  });

  group('Widget Tests: WelcomeScreen UI・TTS・イヤホンキー・音声認識', () {
    testWidgets('ウェルカム画面の表示、初期音声案内、ボタンタップでの開始', (tester) async {
      var started = false;

      await tester.pumpWidget(
        MaterialApp(
          home: WelcomeScreen(
            ttsService: fakeTts,
            soundEffectService: fakeSound,
            speechService: fakeSpeech,
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
      expect(fakeSound.beepCount, greaterThanOrEqualTo(1));
    });

    testWidgets('ウェルカム画面で声で「スタート」と言うと開始できること', (tester) async {
      var started = false;

      await tester.pumpWidget(
        MaterialApp(
          home: WelcomeScreen(
            ttsService: fakeTts,
            soundEffectService: fakeSound,
            speechService: fakeSpeech,
            onStart: () {
              started = true;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(fakeSpeech.isListening, isTrue);

      // ユーザーが「スタート」と発声
      fakeSpeech.simulateSpeech('スタート');
      await tester.pumpAndSettle();

      expect(started, isTrue);
    });

    testWidgets('ウェルカム画面でイヤホンボタン（85）を押すと開始できること', (tester) async {
      var started = false;

      await tester.pumpWidget(
        MaterialApp(
          home: WelcomeScreen(
            ttsService: fakeTts,
            soundEffectService: fakeSound,
            speechService: fakeSpeech,
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
    });
  });

  group('Widget Tests: OnboardingScreen 音声認識（Speech-to-Text）による完全ハンズフリー操作検証', () {
    testWidgets('全ステップを音声指示（「175センチ」「次へ」「女性」等）のみで完了できること', (tester) async {
      UserProfile? completedProfile;

      await tester.pumpWidget(
        MaterialApp(
          home: OnboardingScreen(
            storageService: storageService,
            ttsService: fakeTts,
            soundEffectService: fakeSound,
            speechService: fakeSpeech,
            onCompleted: (profile) {
              completedProfile = profile;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Step 0: 身長
      expect(find.text('初期設定 (1 / 6)'), findsOneWidget);
      expect(find.byKey(const Key('voice_input_indicator')), findsOneWidget);
      expect(fakeSpeech.isListening, isTrue);

      // 「175センチ」と発声
      fakeSpeech.simulateSpeech('175センチ');
      await tester.pump(const Duration(milliseconds: 750));
      expect(find.text('175 cm'), findsOneWidget);
      expect(fakeTts.lastSpoken, '175センチ');

      // 「次へ」と発声
      fakeSpeech.simulateSpeech('次へ');
      await tester.pumpAndSettle();

      // Step 1: 体重
      expect(find.text('初期設定 (2 / 6)'), findsOneWidget);

      // 「68キロ」と発声
      fakeSpeech.simulateSpeech('68キロ');
      await tester.pump(const Duration(milliseconds: 750));
      expect(find.text('68 kg'), findsOneWidget);
      expect(fakeTts.lastSpoken, '68キロ');

      // 「次へ」と発声
      fakeSpeech.simulateSpeech('次へ');
      await tester.pumpAndSettle();

      // Step 2: 年齢
      expect(find.text('初期設定 (3 / 6)'), findsOneWidget);

      // 「30代前半」と発声
      fakeSpeech.simulateSpeech('30代前半');
      await tester.pump(const Duration(milliseconds: 750));
      expect(fakeTts.lastSpoken, '30〜34歳');

      // 「次へ」と発声
      fakeSpeech.simulateSpeech('次へ');
      await tester.pumpAndSettle();

      // Step 3: 性別
      expect(find.text('初期設定 (4 / 6)'), findsOneWidget);

      // 「女性」と発声
      fakeSpeech.simulateSpeech('女性');
      await tester.pump(const Duration(milliseconds: 750));
      expect(fakeTts.lastSpoken, '女性');

      // 「進む」と発声
      fakeSpeech.simulateSpeech('進む');
      await tester.pumpAndSettle();

      // Step 4: 目的基準
      expect(find.text('初期設定 (5 / 6)'), findsOneWidget);

      // 「スポーツ」と発声
      fakeSpeech.simulateSpeech('スポーツから選ぶ');
      await tester.pump(const Duration(milliseconds: 750));
      expect(fakeTts.lastSpoken, 'やっているスポーツから選ぶ');

      // 「決定」と発声
      fakeSpeech.simulateSpeech('決定');
      await tester.pumpAndSettle();

      // Step 5: スポーツ詳細
      expect(find.text('初期設定 (6 / 6)'), findsOneWidget);

      // 「サッカー」と発声
      fakeSpeech.simulateSpeech('サッカーをやってます');
      await tester.pump(const Duration(milliseconds: 750));
      expect(fakeTts.lastSpoken, 'サッカー・フットサル');

      // 「完了」と発声
      fakeSpeech.simulateSpeech('完了');
      await tester.pumpAndSettle();

      // プロフィール検証
      expect(completedProfile, isNotNull);
      expect(completedProfile!.heightCm, 175);
      expect(completedProfile!.weightKg, 68.0);
      expect(completedProfile!.ageGroup, '30〜34歳');
      expect(completedProfile!.gender, '女性');
      expect(completedProfile!.aimCategory, AimCategory.sports);
      expect(completedProfile!.targetGoal, 'サッカー・フットサル');
      expect(fakeTts.lastSpoken, '設定が完了しました。チュートリアルを開始します。');
    });

    testWidgets('音声指示「戻る」で前の質問画面に戻れること', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: OnboardingScreen(
            storageService: storageService,
            ttsService: fakeTts,
            soundEffectService: fakeSound,
            speechService: fakeSpeech,
            onCompleted: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('初期設定 (1 / 6)'), findsOneWidget);

      // 次へ進む
      fakeSpeech.simulateSpeech('次へ');
      await tester.pumpAndSettle();
      expect(find.text('初期設定 (2 / 6)'), findsOneWidget);

      // 「戻る」と発声
      fakeSpeech.simulateSpeech('戻る');
      await tester.pumpAndSettle();
      expect(find.text('初期設定 (1 / 6)'), findsOneWidget);
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
          speechService: fakeSpeech,
          profileStorageService: storage,
        ),
      );
      await tester.pumpAndSettle();

      // WelcomeScreen が表示される
      expect(find.byType(WelcomeScreen), findsOneWidget);
      expect(find.byType(ButtonControlScreen), findsNothing);

      // 音声「スタート」で開始
      fakeSpeech.simulateSpeech('スタート');
      await tester.pumpAndSettle();

      // OnboardingScreen に遷移
      expect(find.byType(OnboardingScreen), findsOneWidget);

      // 全6ステップを音声「次へ」で進めて完了する
      for (var i = 0; i < 6; i++) {
        fakeSpeech.simulateSpeech('次へ');
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
          speechService: fakeSpeech,
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
