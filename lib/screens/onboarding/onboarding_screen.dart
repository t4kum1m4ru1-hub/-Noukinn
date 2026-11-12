import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../models/user_profile.dart';
import '../../services/profile_storage_service.dart';
import '../../theme/app_colors.dart';
import 'question_placeholder_image.dart';

/// 初回起動時に表示される情報収集（アンケート）画面
class OnboardingScreen extends StatefulWidget {
  final ProfileStorageService storageService;
  final void Function(UserProfile profile) onCompleted;

  const OnboardingScreen({
    super.key,
    required this.storageService,
    required this.onCompleted,
  });

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  // ステップインデックス（0: 身長, 1: 体重, 2: 年齢, 3: 性別, 4: 目的カテゴリ, 5: 目的詳細）
  int _currentStep = 0;
  static const int _totalSteps = 6;

  // 身長ドラムロール定義（120cm 〜 220cm）
  static const int _minHeight = 120;
  static const int _maxHeight = 220;
  late int _selectedHeight;
  late final FixedExtentScrollController _heightController;

  // 体重ドラムロール定義（30kg 〜 150kg）
  static const int _minWeight = 30;
  static const int _maxWeight = 150;
  late double _selectedWeight;
  late final FixedExtentScrollController _weightController;

  // 年齢選択肢（5歳区切り）
  static const List<String> _ageOptions = [
    '〜19歳',
    '20〜24歳',
    '25〜29歳',
    '30〜34歳',
    '35〜39歳',
    '40〜44歳',
    '45〜49歳',
    '50〜54歳',
    '55〜59歳',
    '60歳以上',
  ];
  String _selectedAgeGroup = '20〜24歳';

  // 性別選択肢
  static const List<String> _genderOptions = [
    '男性',
    '女性',
    'その他・回答しない',
  ];
  String _selectedGender = '男性';

  // 目的カテゴリ選択肢
  AimCategory _selectedAimCategory = AimCategory.bodyType;

  // 目指す体型の選択肢
  static const List<String> _bodyTypeOptions = [
    '細マッチョ（引き締め＆筋力）',
    '筋肥大・バルクアップ（たくましい体）',
    '引き締め・ダイエット（脂肪燃焼）',
    '健康維持・体力向上（運動不足解消）',
  ];

  // 行っているスポーツの選択肢
  static const List<String> _sportsOptions = [
    'ランニング・陸上',
    'サッカー・フットサル',
    '野球',
    'バスケットボール',
    '格闘技・ボクシング',
    '水泳',
    'その他・複数のスポーツ',
  ];

  String _selectedGoal = '細マッチョ（引き締め＆筋力）';

  @override
  void initState() {
    super.initState();
    _selectedHeight = 170;
    _selectedWeight = 65.0;
    _heightController = FixedExtentScrollController(
      initialItem: _selectedHeight - _minHeight,
    );
    _weightController = FixedExtentScrollController(
      initialItem: (_selectedWeight - _minWeight).toInt(),
    );
  }

  @override
  void dispose() {
    _heightController.dispose();
    _weightController.dispose();
    super.dispose();
  }

  void _goToNextStep() {
    if (_currentStep < _totalSteps - 1) {
      setState(() {
        _currentStep++;
        // 目的カテゴリを変更した直後の場合、詳細目標の初期値を整合
        if (_currentStep == 5) {
          if (_selectedAimCategory == AimCategory.bodyType) {
            if (!_bodyTypeOptions.contains(_selectedGoal)) {
              _selectedGoal = _bodyTypeOptions.first;
            }
          } else {
            if (!_sportsOptions.contains(_selectedGoal)) {
              _selectedGoal = _sportsOptions.first;
            }
          }
        }
      });
    } else {
      _finishOnboarding();
    }
  }

  void _goToPreviousStep() {
    if (_currentStep > 0) {
      setState(() {
        _currentStep--;
      });
    }
  }

  Future<void> _finishOnboarding() async {
    final profile = UserProfile(
      heightCm: _selectedHeight,
      weightKg: _selectedWeight,
      ageGroup: _selectedAgeGroup,
      gender: _selectedGender,
      aimCategory: _selectedAimCategory,
      targetGoal: _selectedGoal,
    );

    await widget.storageService.saveUserProfile(profile);
    if (!mounted) return;
    widget.onCompleted(profile);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        title: Text(
          '初期設定 (${_currentStep + 1} / $_totalSteps)',
          key: const Key('onboarding_step_indicator'),
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: AppColors.tealAccent,
          ),
        ),
        centerTitle: true,
        leading: _currentStep > 0
            ? IconButton(
                key: const Key('onboarding_appbar_back_button'),
                icon: const Icon(Icons.arrow_back),
                onPressed: _goToPreviousStep,
              )
            : null,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. 画面上部：質問・トピック
              _buildTopHeader(),

              const SizedBox(height: 12),

              // 2. 画面中央：イラスト・画像（プレースホルダー）
              Expanded(
                flex: 4,
                child: Center(
                  child: _buildCenterImage(),
                ),
              ),

              const SizedBox(height: 12),

              // 3. 画面下部：選択肢（ドラムロールまたはボタングループ）
              Expanded(
                flex: 5,
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.border),
                  ),
                  padding: const EdgeInsets.all(12),
                  child: _buildChoicesSection(),
                ),
              ),

              const SizedBox(height: 16),

              // 画面最下部：ナビゲーションボタン（戻る・次へ）
              _buildBottomNavigation(),
            ],
          ),
        ),
      ),
    );
  }

  // --------------------------------------------------------------------------
  // 1. 画面上部（質問・トピック）
  // --------------------------------------------------------------------------
  Widget _buildTopHeader() {
    String title;
    String subtitle;

    switch (_currentStep) {
      case 0:
        title = '身長を教えてください';
        subtitle = 'ドラムロールを上下に回して選択してください';
        break;
      case 1:
        title = '体重を教えてください';
        subtitle = 'ドラムロールを上下に回して選択してください';
        break;
      case 2:
        title = '年齢を教えてください';
        subtitle = '当てはまる年代を選択してください';
        break;
      case 3:
        title = '性別を教えてください';
        subtitle = 'トレーニング案内に活用します';
        break;
      case 4:
        title = '目標の設定基準';
        subtitle = 'どちらの基準で目的を設定しますか？';
        break;
      case 5:
        if (_selectedAimCategory == AimCategory.bodyType) {
          title = '目指す体型を教えてください';
          subtitle = 'あなたの理想のゴールを選択してください';
        } else {
          title = '行っているスポーツを教えてください';
          subtitle = 'トレーニングを活かしたい競技を選択してください';
        }
        break;
      default:
        title = '';
        subtitle = '';
    }

    return Column(
      children: [
        Text(
          title,
          key: const Key('question_title'),
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          key: const Key('question_subtitle'),
          style: const TextStyle(
            fontSize: 13,
            color: AppColors.textSecondary,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  // --------------------------------------------------------------------------
  // 2. 画面中央（イラスト・画像プレースホルダー）
  // --------------------------------------------------------------------------
  Widget _buildCenterImage() {
    switch (_currentStep) {
      case 0:
        return const QuestionPlaceholderImage(
          icon: Icons.height,
          label: '身長',
          accentColor: AppColors.tealAccent,
        );
      case 1:
        return const QuestionPlaceholderImage(
          icon: Icons.monitor_weight_outlined,
          label: '体重',
          accentColor: AppColors.primaryAccent,
        );
      case 2:
        return const QuestionPlaceholderImage(
          icon: Icons.calendar_month_outlined,
          label: '年齢',
          accentColor: AppColors.tealAccent,
        );
      case 3:
        return const QuestionPlaceholderImage(
          icon: Icons.person_outline,
          label: '性別',
          accentColor: AppColors.primaryAccent,
        );
      case 4:
        return const QuestionPlaceholderImage(
          icon: Icons.flag_outlined,
          label: '目的設定',
          accentColor: AppColors.tealAccent,
        );
      case 5:
        return QuestionPlaceholderImage(
          icon: _selectedAimCategory == AimCategory.bodyType
              ? Icons.accessibility_new_outlined
              : Icons.sports_soccer_outlined,
          label: _selectedAimCategory.label,
          accentColor: AppColors.primaryAccent,
        );
      default:
        return const SizedBox.shrink();
    }
  }

  // --------------------------------------------------------------------------
  // 3. 画面下部（選択肢エリア）
  // --------------------------------------------------------------------------
  Widget _buildChoicesSection() {
    switch (_currentStep) {
      case 0:
        return _buildHeightPicker();
      case 1:
        return _buildWeightPicker();
      case 2:
        return _buildAgeChoices();
      case 3:
        return _buildGenderChoices();
      case 4:
        return _buildAimCategoryChoices();
      case 5:
        return _buildGoalChoices();
      default:
        return const SizedBox.shrink();
    }
  }

  /// 身長ドラムロール（CupertinoPicker）
  Widget _buildHeightPicker() {
    return Column(
      children: [
        Expanded(
          child: CupertinoPicker.builder(
            key: const Key('height_picker'),
            scrollController: _heightController,
            itemExtent: 44,
            diameterRatio: 1.2,
            selectionOverlay: Container(
              decoration: BoxDecoration(
                border: Border.symmetric(
                  horizontal: BorderSide(
                    color: AppColors.tealAccent.withValues(alpha: 0.6),
                    width: 1.5,
                  ),
                ),
              ),
            ),
            childCount: _maxHeight - _minHeight + 1,
            onSelectedItemChanged: (index) {
              setState(() {
                _selectedHeight = _minHeight + index;
              });
            },
            itemBuilder: (context, index) {
              final val = _minHeight + index;
              final isSelected = val == _selectedHeight;
              return Center(
                child: Text(
                  '$val cm',
                  style: TextStyle(
                    fontSize: isSelected ? 24 : 18,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    color: isSelected ? AppColors.tealAccent : AppColors.textTertiary,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  /// 体重ドラムロール（CupertinoPicker）
  Widget _buildWeightPicker() {
    return Column(
      children: [
        Expanded(
          child: CupertinoPicker.builder(
            key: const Key('weight_picker'),
            scrollController: _weightController,
            itemExtent: 44,
            diameterRatio: 1.2,
            selectionOverlay: Container(
              decoration: BoxDecoration(
                border: Border.symmetric(
                  horizontal: BorderSide(
                    color: AppColors.primaryAccent.withValues(alpha: 0.6),
                    width: 1.5,
                  ),
                ),
              ),
            ),
            childCount: _maxWeight - _minWeight + 1,
            onSelectedItemChanged: (index) {
              setState(() {
                _selectedWeight = (_minWeight + index).toDouble();
              });
            },
            itemBuilder: (context, index) {
              final val = _minWeight + index;
              final isSelected = val.toDouble() == _selectedWeight;
              return Center(
                child: Text(
                  '$val kg',
                  style: TextStyle(
                    fontSize: isSelected ? 24 : 18,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    color: isSelected ? AppColors.primaryAccent : AppColors.textTertiary,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  /// 年齢選択ボタングリッド（5歳区切り）
  Widget _buildAgeChoices() {
    return GridView.builder(
      key: const Key('age_options_grid'),
      itemCount: _ageOptions.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 2.8,
      ),
      itemBuilder: (context, index) {
        final option = _ageOptions[index];
        final isSelected = option == _selectedAgeGroup;
        return _buildChoiceButton(
          label: option,
          isSelected: isSelected,
          onTap: () {
            setState(() {
              _selectedAgeGroup = option;
            });
          },
        );
      },
    );
  }

  /// 性別選択ボタン一覧
  Widget _buildGenderChoices() {
    return ListView.separated(
      key: const Key('gender_options_list'),
      itemCount: _genderOptions.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final option = _genderOptions[index];
        final isSelected = option == _selectedGender;
        return _buildChoiceButton(
          label: option,
          isSelected: isSelected,
          onTap: () {
            setState(() {
              _selectedGender = option;
            });
          },
        );
      },
    );
  }

  /// 目的カテゴリ選択ボタン（体型 vs スポーツ）
  Widget _buildAimCategoryChoices() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildLargeChoiceCard(
          title: '目指す体型から選ぶ',
          subtitle: '細マッチョ、筋肥大、引き締めなど',
          icon: Icons.accessibility_new_outlined,
          isSelected: _selectedAimCategory == AimCategory.bodyType,
          onTap: () {
            setState(() {
              _selectedAimCategory = AimCategory.bodyType;
              _selectedGoal = _bodyTypeOptions.first;
            });
          },
        ),
        const SizedBox(height: 14),
        _buildLargeChoiceCard(
          title: 'やっているスポーツから選ぶ',
          subtitle: 'ランニング、サッカー、野球など競技に合わせる',
          icon: Icons.sports_soccer_outlined,
          isSelected: _selectedAimCategory == AimCategory.sports,
          onTap: () {
            setState(() {
              _selectedAimCategory = AimCategory.sports;
              _selectedGoal = _sportsOptions.first;
            });
          },
        ),
      ],
    );
  }

  /// 目的詳細選択ボタン一覧（体型またはスポーツ）
  Widget _buildGoalChoices() {
    final options = _selectedAimCategory == AimCategory.bodyType
        ? _bodyTypeOptions
        : _sportsOptions;

    return ListView.separated(
      key: const Key('goal_options_list'),
      itemCount: options.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final option = options[index];
        final isSelected = option == _selectedGoal;
        return _buildChoiceButton(
          label: option,
          isSelected: isSelected,
          onTap: () {
            setState(() {
              _selectedGoal = option;
            });
          },
        );
      },
    );
  }

  /// 選択肢ボタン共通コンポーネント
  Widget _buildChoiceButton({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: Key('choice_$label'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? AppColors.tealAccent.withValues(alpha: 0.18)
                : AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? AppColors.tealAccent : AppColors.border,
              width: isSelected ? 2.0 : 1.0,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              color: isSelected ? AppColors.tealAccent : AppColors.textPrimary,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }

  /// 目的カテゴリ用の大判選択カード
  Widget _buildLargeChoiceCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: Key('aim_choice_$title'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: isSelected
                ? AppColors.tealAccent.withValues(alpha: 0.18)
                : AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? AppColors.tealAccent : AppColors.border,
              width: isSelected ? 2.0 : 1.0,
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 32,
                color: isSelected ? AppColors.tealAccent : AppColors.textSecondary,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: isSelected
                            ? AppColors.tealAccent
                            : AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (isSelected)
                const Icon(
                  Icons.check_circle,
                  color: AppColors.tealAccent,
                  size: 22,
                ),
            ],
          ),
        ),
      ),
    );
  }

  // --------------------------------------------------------------------------
  // 画面最下部：ナビゲーションボタン（戻る・次へ）
  // --------------------------------------------------------------------------
  Widget _buildBottomNavigation() {
    final isLastStep = _currentStep == _totalSteps - 1;

    return Row(
      children: [
        if (_currentStep > 0) ...[
          Expanded(
            flex: 2,
            child: OutlinedButton(
              key: const Key('onboarding_back_button'),
              onPressed: _goToPreviousStep,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.textSecondary,
                side: const BorderSide(color: AppColors.border),
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text('戻る'),
            ),
          ),
          const SizedBox(width: 12),
        ],
        Expanded(
          flex: 3,
          child: ElevatedButton(
            key: const Key('onboarding_next_button'),
            onPressed: _goToNextStep,
            style: ElevatedButton.styleFrom(
              backgroundColor: isLastStep
                  ? AppColors.primaryAccent
                  : AppColors.tealAccent,
              foregroundColor: Colors.black,
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              elevation: 2,
            ),
            child: Text(
              isLastStep ? '完了してチュートリアルへ' : '次へ',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
