import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:button_controll_test/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

  group('Widget Tests: WelcomeScreen', () {
    testWidgets('ウェルカム画面のタイトル・イラスト・ボタンが正しく表示され、タップでコールバックが発火すること', (
      tester,
    ) async {
      var started = false;

      await tester.pumpWidget(
        MaterialApp(
          home: WelcomeScreen(
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

      final startButton = find.byKey(const Key('welcome_start_button'));
      expect(startButton, findsOneWidget);

      await tester.tap(startButton);
      await tester.pumpAndSettle();

      expect(started, isTrue);
    });
  });

  group('Widget Tests: OnboardingScreen 全ステップ進行・選択・戻る検証', () {
    late InMemoryProfileStorageService storageService;

    setUp(() {
      storageService = InMemoryProfileStorageService();
    });

    testWidgets('Step 0〜5 を順番にタッチ操作で選択し、完了時にプロフィールが正しく保存されること（体型ルート）', (
      tester,
    ) async {
      UserProfile? completedProfile;

      await tester.pumpWidget(
        MaterialApp(
          home: OnboardingScreen(
            storageService: storageService,
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
      expect(find.byKey(const Key('height_picker')), findsOneWidget);
      expect(find.byKey(const Key('onboarding_back_button')), findsNothing);

      // 身長ピッカーを操作（170 -> 172cm へ変更）
      final heightPickerFinder = find.byKey(const Key('height_picker'));
      final heightPicker = tester.widget<CupertinoPicker>(heightPickerFinder);
      heightPicker.scrollController?.jumpToItem(172 - 120);
      await tester.pumpAndSettle();

      // 次へタップ
      await tester.tap(find.byKey(const Key('onboarding_next_button')));
      await tester.pumpAndSettle();

      // Step 1: 体重
      expect(find.text('初期設定 (2 / 6)'), findsOneWidget);
      expect(find.text('体重を教えてください'), findsOneWidget);
      expect(find.byKey(const Key('weight_picker')), findsOneWidget);
      expect(find.byKey(const Key('onboarding_back_button')), findsOneWidget);

      // 体重ピッカーを操作（65 -> 68kg へ変更）
      final weightPickerFinder = find.byKey(const Key('weight_picker'));
      final weightPicker = tester.widget<CupertinoPicker>(weightPickerFinder);
      weightPicker.scrollController?.jumpToItem(68 - 30);
      await tester.pumpAndSettle();

      // 次へタップ
      await tester.tap(find.byKey(const Key('onboarding_next_button')));
      await tester.pumpAndSettle();

      // Step 2: 年齢（5歳刻み）
      expect(find.text('初期設定 (3 / 6)'), findsOneWidget);
      expect(find.text('年齢を教えてください'), findsOneWidget);
      expect(find.byKey(const Key('age_options_grid')), findsOneWidget);

      // 「30〜34歳」をタップ
      await tester.tap(find.byKey(const Key('choice_30〜34歳')));
      await tester.pumpAndSettle();

      // 次へタップ
      await tester.tap(find.byKey(const Key('onboarding_next_button')));
      await tester.pumpAndSettle();

      // Step 3: 性別
      expect(find.text('初期設定 (4 / 6)'), findsOneWidget);
      expect(find.text('性別を教えてください'), findsOneWidget);
      expect(find.byKey(const Key('gender_options_list')), findsOneWidget);

      // 「男性」を選択
      await tester.tap(find.byKey(const Key('choice_男性')));
      await tester.pumpAndSettle();

      // 次へタップ
      await tester.tap(find.byKey(const Key('onboarding_next_button')));
      await tester.pumpAndSettle();

      // Step 4: 目標の設定基準（体型 vs スポーツ）
      expect(find.text('初期設定 (5 / 6)'), findsOneWidget);
      expect(find.text('目標の設定基準'), findsOneWidget);

      // 「目指す体型から選ぶ」を選択
      await tester.tap(find.byKey(const Key('aim_choice_目指す体型から選ぶ')));
      await tester.pumpAndSettle();

      // 次へタップ
      await tester.tap(find.byKey(const Key('onboarding_next_button')));
      await tester.pumpAndSettle();

      // Step 5: 目指す体型一覧
      expect(find.text('初期設定 (6 / 6)'), findsOneWidget);
      expect(find.text('目指す体型を教えてください'), findsOneWidget);
      expect(find.byKey(const Key('goal_options_list')), findsOneWidget);

      // 「筋肥大・バルクアップ（たくましい体）」を選択
      await tester.tap(find.byKey(const Key('choice_筋肥大・バルクアップ（たくましい体）')));
      await tester.pumpAndSettle();

      // 完了ボタン確認とタップ
      final finishButton = find.byKey(const Key('onboarding_next_button'));
      expect(find.text('完了してチュートリアルへ'), findsOneWidget);

      await tester.tap(finishButton);
      await tester.pumpAndSettle();

      // 完了コールバックとストレージ保存の検証
      expect(completedProfile, isNotNull);
      expect(completedProfile!.heightCm, 172);
      expect(completedProfile!.weightKg, 68.0);
      expect(completedProfile!.ageGroup, '30〜34歳');
      expect(completedProfile!.gender, '男性');
      expect(completedProfile!.aimCategory, AimCategory.bodyType);
      expect(completedProfile!.targetGoal, '筋肥大・バルクアップ（たくましい体）');

      expect(await storageService.isOnboardingCompleted(), isTrue);
    });

    testWidgets('スポーツルート選択および「戻る」ボタンによる再選択が正しく動作すること', (tester) async {
      UserProfile? completedProfile;

      await tester.pumpWidget(
        MaterialApp(
          home: OnboardingScreen(
            storageService: storageService,
            onCompleted: (profile) {
              completedProfile = profile;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Step 0 -> Step 1 -> Step 2 -> Step 3 -> Step 4 へ一気に進む
      for (var i = 0; i < 4; i++) {
        await tester.tap(find.byKey(const Key('onboarding_next_button')));
        await tester.pumpAndSettle();
      }

      // Step 4 (目標基準) で「やっているスポーツから選ぶ」を選択
      expect(find.text('初期設定 (5 / 6)'), findsOneWidget);
      await tester.tap(find.byKey(const Key('aim_choice_やっているスポーツから選ぶ')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('onboarding_next_button')));
      await tester.pumpAndSettle();

      // Step 5 (スポーツ詳細)
      expect(find.text('行っているスポーツを教えてください'), findsOneWidget);
      expect(find.text('サッカー・フットサル'), findsOneWidget);

      // 「戻る」ボタンを押して Step 4 へ戻る
      await tester.tap(find.byKey(const Key('onboarding_back_button')));
      await tester.pumpAndSettle();
      expect(find.text('初期設定 (5 / 6)'), findsOneWidget);
      expect(find.text('目標の設定基準'), findsOneWidget);

      // 再度「やっているスポーツから選ぶ」で進む
      await tester.tap(find.byKey(const Key('onboarding_next_button')));
      await tester.pumpAndSettle();

      // 「サッカー・フットサル」を選択して完了
      await tester.tap(find.byKey(const Key('choice_サッカー・フットサル')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('onboarding_next_button')));
      await tester.pumpAndSettle();

      expect(completedProfile, isNotNull);
      expect(completedProfile!.aimCategory, AimCategory.sports);
      expect(completedProfile!.targetGoal, 'サッカー・フットサル');
    });
  });

  group('Widget Tests: AppEntryRouter ルーティング統合検証', () {
    late FakeTtsService fakeTts;
    late FakeSoundEffectService fakeSound;

    setUp(() {
      fakeTts = FakeTtsService();
      fakeSound = FakeSoundEffectService();
    });

    testWidgets('初回起動（未完了）時: WelcomeScreen が表示され、設定完了後に TutorialScreen へ遷移すること', (
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

      // 「設定をはじめる」をタップ
      await tester.tap(find.byKey(const Key('welcome_start_button')));
      await tester.pumpAndSettle();

      // OnboardingScreen に遷移
      expect(find.byType(OnboardingScreen), findsOneWidget);

      // 全6ステップを「次へ」で進めて完了する
      for (var i = 0; i < 6; i++) {
        await tester.tap(find.byKey(const Key('onboarding_next_button')));
        await tester.pumpAndSettle();
      }

      // TutorialScreen へ遷移したことを確認
      expect(find.byType(TutorialScreen), findsOneWidget);
      expect(await storage.isOnboardingCompleted(), isTrue);
    });

    testWidgets('2回目以降起動（完了済み）時: WelcomeScreen はスキップされ直接 ButtonControlScreen が表示されること', (
      tester,
    ) async {
      final storage = InMemoryProfileStorageService(initialCompleted: true);

      await tester.pumpWidget(
        ButtonControlApp(
          ttsService: fakeTts,
          soundEffectService: fakeSound,
          profileStorageService: storage,
        ),
      );
      await tester.pumpAndSettle();

      // WelcomeScreen は表示されず、メイン画面が表示される
      expect(find.byType(WelcomeScreen), findsNothing);
      expect(find.byType(OnboardingScreen), findsNothing);
      expect(find.byType(ButtonControlScreen), findsOneWidget);
      expect(find.byKey(const Key('waiting_prompt')), findsOneWidget);
    });
  });
}
