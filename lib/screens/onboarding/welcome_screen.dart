import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

/// 初回起動時に最初に表示されるウェルカム画面
class WelcomeScreen extends StatelessWidget {
  final VoidCallback onStart;

  const WelcomeScreen({
    super.key,
    required this.onStart,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 24),
              // 上部タイトル
              const Column(
                children: [
                  Text(
                    'NOUKIN',
                    key: Key('welcome_title'),
                    style: TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.w900,
                      color: AppColors.tealAccent,
                      letterSpacing: 2.0,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: 8),
                  Text(
                    '完全ハンズフリートレーニングへようこそ',
                    key: Key('welcome_subtitle'),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
              const Spacer(flex: 1),

              // 中央イラスト（プレースホルダー）
              Center(
                child: Container(
                  key: const Key('welcome_image_container'),
                  width: 220,
                  height: 220,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceVariant,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.tealAccent, width: 2.0),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.tealAccent.withValues(alpha: 0.15),
                        blurRadius: 24,
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.fitness_center,
                          size: 72,
                          color: AppColors.tealAccent,
                        ),
                        SizedBox(height: 12),
                        Icon(
                          Icons.headphones,
                          size: 40,
                          color: AppColors.primaryAccent,
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              const Spacer(flex: 1),

              // 下部説明テキスト
              Container(
                padding: const EdgeInsets.all(16.0),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: const Text(
                  'スマホを触らず、音楽を聴きながら音声とイヤホン操作だけでトレーニングを進行できます。\n\nあなたに合わせた初期設定を行うため、5つの質問にお答えください。',
                  key: Key('welcome_description'),
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.6,
                    color: AppColors.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),

              const SizedBox(height: 24),

              // はじめるボタン
              ElevatedButton(
                key: const Key('welcome_start_button'),
                onPressed: onStart,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryAccent,
                  foregroundColor: AppColors.onPrimaryAccent,
                  minimumSize: const Size.fromHeight(54),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 2,
                ),
                child: const Text(
                  '設定をはじめる',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}
