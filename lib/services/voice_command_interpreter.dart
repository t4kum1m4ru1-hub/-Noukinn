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

/// 年齢選択アクション
class SelectAgeAction extends VoiceAction {
  final String ageGroup;
  const SelectAgeAction(this.ageGroup);
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
        return _interpretAge(normalized);
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

  /// Step 2: 年齢解析
  static VoiceAction _interpretAge(String text) {
    if (text.contains('10') || text.contains('15') || text.contains('19')) {
      return const SelectAgeAction('〜19歳');
    }
    if (text.contains('20〜24') || text.contains('20代前半') || text.contains('20') || text.contains('21') || text.contains('22') || text.contains('23') || text.contains('24')) {
      return const SelectAgeAction('20〜24歳');
    }
    if (text.contains('25〜29') || text.contains('20代後半') || text.contains('25') || text.contains('26') || text.contains('27') || text.contains('28') || text.contains('29')) {
      return const SelectAgeAction('25〜29歳');
    }
    if (text.contains('30〜34') || text.contains('30代前半') || text.contains('30') || text.contains('31') || text.contains('32') || text.contains('33') || text.contains('34')) {
      return const SelectAgeAction('30〜34歳');
    }
    if (text.contains('35〜39') || text.contains('30代後半') || text.contains('35') || text.contains('36') || text.contains('37') || text.contains('38') || text.contains('39')) {
      return const SelectAgeAction('35〜39歳');
    }
    if (text.contains('40〜44') || text.contains('40代前半') || text.contains('40') || text.contains('41') || text.contains('42') || text.contains('43') || text.contains('44')) {
      return const SelectAgeAction('40〜44歳');
    }
    if (text.contains('45〜49') || text.contains('40代後半') || text.contains('45') || text.contains('46') || text.contains('47') || text.contains('48') || text.contains('49')) {
      return const SelectAgeAction('45〜49歳');
    }
    if (text.contains('50〜54') || text.contains('50代前半') || text.contains('50') || text.contains('51') || text.contains('52') || text.contains('53') || text.contains('54')) {
      return const SelectAgeAction('50〜54歳');
    }
    if (text.contains('55〜59') || text.contains('50代後半') || text.contains('55') || text.contains('56') || text.contains('57') || text.contains('58') || text.contains('59')) {
      return const SelectAgeAction('55〜59歳');
    }
    if (text.contains('60') || text.contains('65') || text.contains('70')) {
      return const SelectAgeAction('60歳以上');
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
