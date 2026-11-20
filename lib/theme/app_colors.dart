import 'package:flutter/material.dart';

/// アプリ全体の色定数を一元管理するクラス
abstract final class AppColors {
  // 背景色・サーフェス色
  static const Color background = Color(0xFF121212);
  static const Color surface = Color(0xFF1E1E1E);
  static const Color surfaceVariant = Color(0xFF2C2C2C);
  static const Color border = Color(0xFF2E2E2E);
  static const Color trackInactive = Color(0xFF333333);

  // 状態ハイライト用サーフェス色（noukin_app カード選択・調整状態）
  static const Color highlightEditingSurface = Color(0xFF2D2212);
  static const Color highlightSelectedSurface = Color(0xFF162927);

  // テキスト色
  static const Color textPrimary = Colors.white;
  static const Color textSecondary = Colors.white70;
  static const Color textTertiary = Colors.white38;

  // 基本アクセントカラー（ティール・アンバー）
  static const Color tealAccent = Colors.tealAccent;
  static const Color amberAccent = Colors.amberAccent;

  // 画面内で最も目立たせるアクション用アクセントカラー（「開始 / 次へ」ボタン等）
  static const Color primaryAccent = Color(0xFFFF9100); // 鮮やかなオレンジアクセント
  static const Color onPrimaryAccent = Colors.black;

  // ステータス色（ケガ部位・バリデーションエラー等）
  static const Color error = Color(0xFFCF6679);
  static const Color onError = Colors.black;
}
