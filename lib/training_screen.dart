import 'package:flutter/material.dart';
import 'main.dart' show TtsService;
import 'review_screen.dart';

/// ワークアウト種目のデータモデル
class WorkoutExercise {
  final String name;
  final String imagePath;
  final double defaultWeight;
  final int defaultReps;
  final int defaultSets;

  const WorkoutExercise({
    required this.name,
    required this.imagePath,
    required this.defaultWeight,
    required this.defaultReps,
    required this.defaultSets,
  });
}

/// ワークアウト種目の順番とデフォルト値の定義
const List<WorkoutExercise> kWorkoutExercises = [
  WorkoutExercise(
    name: 'ベンチプレス',
    imagePath: 'assets/images/workout/bench_press.avif',
    defaultWeight: 60.0,
    defaultReps: 10,
    defaultSets: 1,
  ),
  WorkoutExercise(
    name: 'デッドリフト',
    imagePath: 'assets/images/workout/dead_lift.avif',
    defaultWeight: 80.0,
    defaultReps: 8,
    defaultSets: 1,
  ),
  WorkoutExercise(
    name: 'レッグプレス',
    imagePath: 'assets/images/workout/leg_press.avif',
    defaultWeight: 100.0,
    defaultReps: 12,
    defaultSets: 1,
  ),
];

/// トレーニング中に表示する専用画面
class TrainingScreen extends StatefulWidget {
  final TtsService? ttsService;

  const TrainingScreen({super.key, this.ttsService});

  @override
  State<TrainingScreen> createState() => _TrainingScreenState();
}

class _TrainingScreenState extends State<TrainingScreen> {
  int _currentExerciseIndex = 0;

  // トレーニング種目のパラメータ
  late double _weight;
  late int _reps;
  late int _sets;
  double _volume = 0.8; // 音声ガイドの音量 (0.0 - 1.0)

  WorkoutExercise get _currentExercise => kWorkoutExercises[_currentExerciseIndex];

  @override
  void initState() {
    super.initState();
    _resetToCurrentExercise();
  }

  void _resetToCurrentExercise() {
    final exercise = _currentExercise;
    _weight = exercise.defaultWeight;
    _reps = exercise.defaultReps;
    _sets = exercise.defaultSets;
  }

  void _goToNextExercise() {
    if (_currentExerciseIndex < kWorkoutExercises.length - 1) {
      setState(() {
        _currentExerciseIndex++;
        _resetToCurrentExercise();
      });
    } else {
      // 最後の種目の次はレビュー画面へ遷移
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => const ReviewScreen(),
        ),
      );
    }
  }

  void _decreaseWeight() {
    setState(() {
      if (_weight >= 2.5) {
        _weight -= 2.5;
      } else {
        _weight = 0.0;
      }
    });
  }

  void _increaseWeight() {
    setState(() {
      _weight += 2.5;
    });
  }

  void _decreaseReps() {
    setState(() {
      if (_reps > 0) {
        _reps -= 1;
      }
    });
  }

  void _increaseReps() {
    setState(() {
      _reps += 1;
    });
  }

  void _decreaseSets() {
    setState(() {
      if (_sets > 1) {
        _sets -= 1;
      }
    });
  }

  void _increaseSets() {
    setState(() {
      _sets += 1;
    });
  }

  void _onVolumeChanged(double val) {
    setState(() {
      _volume = val;
    });
    widget.ttsService?.setVolume(val);
  }

  String _formatWeight(double val) {
    if (val == val.roundToDouble()) {
      return '${val.toInt()} kg';
    }
    return '${val.toStringAsFixed(1)} kg';
  }

  @override
  Widget build(BuildContext context) {
    final currentExercise = _currentExercise;

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1E1E),
        elevation: 0,
        leading: IconButton(
          key: const Key('training_back_button'),
          icon: const Icon(Icons.arrow_back),
          tooltip: 'メイン画面へ戻る',
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          currentExercise.name,
          key: const Key('exercise_title'),
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.1,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight - 16),
                child: IntrinsicHeight(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // 中心：トレーニング種目の画像
                      Expanded(
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12.0),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: Image.asset(
                                currentExercise.imagePath,
                                key: const Key('exercise_image'),
                                fit: BoxFit.contain,
                                errorBuilder: (context, error, stackTrace) {
                                  // AVIF 非対応環境等の場合のフォールバック表示
                                  return Container(
                                    width: double.infinity,
                                    height: 220,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF1E1E1E),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(color: const Color(0xFF2E2E2E)),
                                    ),
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        const Icon(
                                          Icons.fitness_center,
                                          size: 64,
                                          color: Colors.tealAccent,
                                        ),
                                        const SizedBox(height: 10),
                                        Text(
                                          currentExercise.name,
                                          style: const TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          currentExercise.imagePath,
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: Colors.white38,
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        ),
                      ),
                      // 中央画像のすぐ下：横幅いっぱいの「次へ」ボタン
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12.0),
                        child: ElevatedButton(
                          key: const Key('btn_next_workout'),
                          onPressed: _goToNextExercise,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.tealAccent,
                            foregroundColor: Colors.black,
                            minimumSize: const Size.fromHeight(50),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text(
                            '次へ',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      // 下部：縦に並ぶ3つのカード
                      _buildCounterCard(
                        cardKey: const Key('card_weight'),
                        label: '重量',
                        valueText: _formatWeight(_weight),
                        downKey: const Key('btn_weight_down'),
                        upKey: const Key('btn_weight_up'),
                        onDown: _decreaseWeight,
                        onUp: _increaseWeight,
                      ),
                      _buildCounterCard(
                        cardKey: const Key('card_reps'),
                        label: 'レップ数',
                        valueText: '$_reps 回',
                        downKey: const Key('btn_reps_down'),
                        upKey: const Key('btn_reps_up'),
                        onDown: _decreaseReps,
                        onUp: _increaseReps,
                      ),
                      _buildCounterCard(
                        cardKey: const Key('card_sets'),
                        label: 'セット数',
                        valueText: '$_sets セット',
                        downKey: const Key('btn_sets_down'),
                        upKey: const Key('btn_sets_up'),
                        onDown: _decreaseSets,
                        onUp: _increaseSets,
                      ),
                      // 音声ガイドの音量バー
                      _buildVolumeCard(),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  /// 左右に増減ボタンを持つ数値調整カード
  Widget _buildCounterCard({
    required Key cardKey,
    required String label,
    required String valueText,
    required Key downKey,
    required Key upKey,
    required VoidCallback onDown,
    required VoidCallback onUp,
  }) {
    return Card(
      key: cardKey,
      color: const Color(0xFF1E1E1E),
      margin: const EdgeInsets.symmetric(vertical: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Color(0xFF2E2E2E)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton.filledTonal(
              key: downKey,
              icon: const Icon(Icons.remove),
              onPressed: onDown,
              style: IconButton.styleFrom(
                backgroundColor: const Color(0xFF2C2C2C),
                foregroundColor: Colors.tealAccent,
                minimumSize: const Size(44, 44),
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Colors.white70,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  valueText,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.tealAccent,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
            IconButton.filledTonal(
              key: upKey,
              icon: const Icon(Icons.add),
              onPressed: onUp,
              style: IconButton.styleFrom(
                backgroundColor: const Color(0xFF2C2C2C),
                foregroundColor: Colors.tealAccent,
                minimumSize: const Size(44, 44),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 音声ガイドの音量バーカード
  Widget _buildVolumeCard() {
    final percent = (_volume * 100).round();
    return Card(
      key: const Key('card_volume'),
      color: const Color(0xFF1E1E1E),
      margin: const EdgeInsets.only(top: 4, bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Color(0xFF2E2E2E)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.volume_up, size: 18, color: Colors.white70),
                    SizedBox(width: 6),
                    Text(
                      '音声ガイドの音量',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.white70,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                Text(
                  '$percent%',
                  key: const Key('volume_value_text'),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.tealAccent,
                  ),
                ),
              ],
            ),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: Colors.tealAccent,
                inactiveTrackColor: const Color(0xFF333333),
                thumbColor: Colors.tealAccent,
                overlayColor: Colors.tealAccent.withAlpha(50),
                trackHeight: 4,
              ),
              child: Slider(
                key: const Key('volume_slider'),
                value: _volume,
                min: 0.0,
                max: 1.0,
                onChanged: _onVolumeChanged,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
