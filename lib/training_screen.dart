import 'package:flutter/material.dart';

import 'review_screen.dart';
import 'theme/app_colors.dart';
import 'training_controller.dart';

/// M1 プレースホルダ画面（M4 で lib/screens/training_screen.dart に置換）
class TrainingScreen extends StatefulWidget {
  final TrainingController? controller;

  const TrainingScreen({super.key, this.controller});

  @override
  State<TrainingScreen> createState() => _TrainingScreenState();
}

class _TrainingScreenState extends State<TrainingScreen> {
  late final TrainingController _controller;
  late final bool _ownsController;

  @override
  void initState() {
    super.initState();
    if (widget.controller != null) {
      _controller = widget.controller!;
      _ownsController = false;
    } else {
      _controller = TrainingController();
      _ownsController = true;
    }
    _controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onChanged);
    if (_ownsController) {
      _controller.dispose();
    }
    super.dispose();
  }

  void _onChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          key: const Key('training_back_button'),
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          _controller.exerciseName,
          key: const Key('exercise_title'),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Text(
                '${_controller.weightKg.toStringAsFixed(1)} kg / '
                '${_controller.reps} 回 / ${_controller.sets} セット',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppColors.tealAccent,
                ),
              ),
              const Spacer(),
              ElevatedButton(
                key: const Key('btn_next_workout'),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const ReviewScreen(),
                    ),
                  );
                },
                child: const Text('次へ'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
