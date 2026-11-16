import '../models/user_profile.dart';

/// 音声指示を解釈した結果のアクション種別
sealed class VoiceAction {
  const VoiceAction();
}

/// 「次へ」「決定」アクション
class NextStepAction extends VoiceAction {
  const NextStepAction();
}

/// 「前へ」「戻る」アクション
class PreviousStepAction extends VoiceAction {
  const PreviousStepAction();
}

/// 身長の直接数値指定アクション
class SetHeightAction extends VoiceAction {
  final int heightCm;
  const SetHeightAction(this.heightCm);
}

/// 身長の増減アクション（+1 / -1 等）
class AdjustHeightAction extends VoiceAction {
  final int delta;
  const AdjustHeightAction(this.delta);
}

/// 体重の直接数値指定アクション
class SetWeightAction extends VoiceAction {
  final double weightKg;
  const SetWeightAction(this.weightKg);
}

/// 体重の増減アクション
class AdjustWeightAction extends VoiceAction {
  final double delta;
  const AdjustWeightAction(this.delta);
}

/// 生まれ年の直接数値指定アクション
class SetBirthYearAction extends VoiceAction {
  final int birthYear;
  const SetBirthYearAction(this.birthYear);
}

/// 生まれ年の増減アクション（+1 / -1 等）
class AdjustBirthYearAction extends VoiceAction {
  final int delta;
  const AdjustBirthYearAction(this.delta);
}

/// 性別選択アクション
class SelectGenderAction extends VoiceAction {
  final String gender;
  const SelectGenderAction(this.gender);
}

/// 目的基準選択アクション
class SelectAimCategoryAction extends VoiceAction {
  final AimCategory category;
  const SelectAimCategoryAction(this.category);
}

/// 目的詳細選択アクション
class SelectGoalAction extends VoiceAction {
  final String goal;
  const SelectGoalAction(this.goal);
}

/// 不明・該当なし
class UnknownVoiceAction extends VoiceAction {
  final String spoken;
  const UnknownVoiceAction(this.spoken);
}

/// ユーザーの発話を解析して適切なアクションに変換するインタープリター
abstract final class VoiceCommandInterpreter {
  /// 全ステップ共通の進行キーワード
  static const List<String> _nextKeywords = [
    '次へ',
    'つぎへ',
    '次',
    'つぎ',
    '決定',
    'けってい',
    '進む',
    'すすむ',
    'はい',
    'オッケー',
    'おっけー',
    'ok',
    'スタート',
    'はじめる',
    '完了',
  ];

  /// 全ステップ共通の戻るキーワード
  static const List<String> _prevKeywords = [
    '前へ',
    'まえへ',
    '前',
    'まえ',
    '戻る',
    'もどる',
    '戻って',
    'もどって',
    'いいえ',
  ];

  /// 発話を解析してアクションを返す
  static VoiceAction interpret({
    required int step,
    required String speech,
    required AimCategory currentAimCategory,
  }) {
    final normalized = speech.trim().toLowerCase();

    // 1. 全ステップ共通: 次へ / 決定
    for (final kw in _nextKeywords) {
      if (normalized.contains(kw)) {
        return const NextStepAction();
      }
    }

    // 2. 全ステップ共通: 前へ / 戻る
    for (final kw in _prevKeywords) {
      if (normalized.contains(kw)) {
        return const PreviousStepAction();
      }
    }

    // 3. 各ステップごとの個別解析
    switch (step) {
      case 0:
        return _interpretHeight(normalized);
      case 1:
        return _interpretWeight(normalized);
      case 2:
        return _interpretBirthYear(normalized);
      case 3:
        return _interpretGender(normalized);
      case 4:
        return _interpretAimCategory(normalized);
      case 5:
        return _interpretGoal(normalized, currentAimCategory);
      default:
        return UnknownVoiceAction(speech);
    }
  }

  /// Step 0: 身長解析
  static VoiceAction _interpretHeight(String text) {
    if (_hasPlus(text)) return const AdjustHeightAction(1);
    if (_hasMinus(text)) return const AdjustHeightAction(-1);

    final match = RegExp(r'(\d{2,3})').firstMatch(text);
    if (match != null) {
      final val = int.tryParse(match.group(1)!);
      if (val != null && val >= 120 && val <= 220) {
        return SetHeightAction(val);
      }
    }
    return UnknownVoiceAction(text);
  }

  /// Step 1: 体重解析
  static VoiceAction _interpretWeight(String text) {
    if (_hasPlus(text)) return const AdjustWeightAction(1.0);
    if (_hasMinus(text)) return const AdjustWeightAction(-1.0);

    final match = RegExp(r'(\d{2,3})').firstMatch(text);
    if (match != null) {
      final val = double.tryParse(match.group(1)!);
      if (val != null && val >= 30 && val <= 150) {
        return SetWeightAction(val);
      }
    }
    return UnknownVoiceAction(text);
  }

  /// Step 2: 生まれ年解析
  static VoiceAction _interpretBirthYear(String text) {
    if (_hasPlus(text)) return const AdjustBirthYearAction(1);
    if (_hasMinus(text)) return const AdjustBirthYearAction(-1);

    final match4 = RegExp(r'(\d{4})').firstMatch(text);
    if (match4 != null) {
      final val = int.tryParse(match4.group(1)!);
      if (val != null && val >= 1940 && val <= 2015) {
        return SetBirthYearAction(val);
      }
    }

    final match2 = RegExp(r'(\d{2})年').firstMatch(text);
    if (match2 != null) {
      final shortYear = int.tryParse(match2.group(1)!);
      if (shortYear != null) {
        final fullYear = shortYear <= 15 ? 2000 + shortYear : 1900 + shortYear;
        if (fullYear >= 1940 && fullYear <= 2015) {
          return SetBirthYearAction(fullYear);
        }
      }
    }

    return UnknownVoiceAction(text);
  }

  /// Step 3: 性別解析
  static VoiceAction _interpretGender(String text) {
    if (text.contains('男')) return const SelectGenderAction('男性');
    if (text.contains('女')) return const SelectGenderAction('女性');
    if (text.contains('その他') || text.contains('回答しない') || text.contains('答えない')) {
      return const SelectGenderAction('その他・回答しない');
    }
    return UnknownVoiceAction(text);
  }

  /// Step 4: 目的カテゴリ解析
  static VoiceAction _interpretAimCategory(String text) {
    if (text.contains('体型') || text.contains('たいけい') || text.contains('見た目') || text.contains('からだ')) {
      return const SelectAimCategoryAction(AimCategory.bodyType);
    }
    if (text.contains('スポーツ') || text.contains('競技') || text.contains('きょうぎ') || text.contains('運動')) {
      return const SelectAimCategoryAction(AimCategory.sports);
    }
    return UnknownVoiceAction(text);
  }

  /// Step 5: 目的詳細解析
  static VoiceAction _interpretGoal(String text, AimCategory category) {
    if (category == AimCategory.bodyType) {
      if (text.contains('細マッチョ') || text.contains('ほそまっちょ')) {
        return const SelectGoalAction('細マッチョ（引き締め＆筋力）');
      }
      if (text.contains('筋肥大') || text.contains('バルクアップ') || text.contains('筋肉') || text.contains('大きく')) {
        return const SelectGoalAction('筋肥大・バルクアップ（たくましい体）');
      }
      if (text.contains('引き締め') || text.contains('ダイエット') || text.contains('痩せる') || text.contains('やせたい') || text.contains('脂肪')) {
        return const SelectGoalAction('引き締め・ダイエット（脂肪燃焼）');
      }
      if (text.contains('健康') || text.contains('体力') || text.contains('運動不足')) {
        return const SelectGoalAction('健康維持・体力向上（運動不足解消）');
      }
    } else {
      if (text.contains('ランニング') || text.contains('走る') || text.contains('陸上') || text.contains('マラソン')) {
        return const SelectGoalAction('ランニング・陸上');
      }
      if (text.contains('サッカー') || text.contains('フットサル')) {
        return const SelectGoalAction('サッカー・フットサル');
      }
      if (text.contains('野球') || text.contains('ベースボール')) {
        return const SelectGoalAction('野球');
      }
      if (text.contains('バスケ') || text.contains('バスケット')) {
        return const SelectGoalAction('バスケットボール');
      }
      if (text.contains('格闘技') || text.contains('ボクシング')) {
        return const SelectGoalAction('格闘技・ボクシング');
      }
      if (text.contains('水泳') || text.contains('スイミング') || text.contains('泳ぐ')) {
        return const SelectGoalAction('水泳');
      }
      if (text.contains('その他') || text.contains('複数')) {
        return const SelectGoalAction('その他・複数のスポーツ');
      }
    }
    return UnknownVoiceAction(text);
  }

  static bool _hasPlus(String t) {
    return t.contains('プラス') ||
        t.contains('アップ') ||
        t.contains('上げて') ||
        t.contains('たかく') ||
        t.contains('高く') ||
        t.contains('もっと') ||
        t.contains('ふやして') ||
        t.contains('増やして') ||
        t.contains('+');
  }

  static bool _hasMinus(String t) {
    return t.contains('マイナス') ||
        t.contains('ダウン') ||
        t.contains('下げて') ||
        t.contains('ひくく') ||
        t.contains('低く') ||
        t.contains('へらして') ||
        t.contains('減らして') ||
        t.contains('-');
  }
}

