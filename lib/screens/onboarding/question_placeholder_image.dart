import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

/// 質問画面の中央に配置するプレースホルダー画像・イラストコンポーネント
class QuestionPlaceholderImage extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color accentColor;

  const QuestionPlaceholderImage({
    super.key,
    required this.icon,
    required this.label,
    this.accentColor = AppColors.tealAccent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      key: Key('placeholder_image_${label.replaceAll(' ', '_')}'),
      width: 160,
      height: 160,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accentColor.withValues(alpha: 0.6), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: accentColor.withValues(alpha: 0.12),
            blurRadius: 18,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: 68,
            color: accentColor,
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
