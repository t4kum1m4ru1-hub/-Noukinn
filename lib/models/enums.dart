/// トレーニング目的
enum TrainingPurpose {
  bodyMakeMale(id: 'body_make_male', label: 'ボディーメイク（男性向け）'),
  bodyMakeFemale(id: 'body_make_female', label: 'ボディーメイク（女性向け）'),
  health(id: 'health', label: '健康維持'),
  diet(id: 'diet', label: 'ダイエット'),
  tennis(id: 'tennis', label: 'テニス'),
  windsurfing(id: 'windsurfing', label: 'ウィンドサーフィン');

  final String id;
  final String label;

  const TrainingPurpose({required this.id, required this.label});

  static TrainingPurpose fromId(String? value) {
    if (value == 'body_make') return TrainingPurpose.bodyMakeMale;
    for (final v in values) {
      if (v.id == value || v.name == value) return v;
    }
    return TrainingPurpose.bodyMakeMale;
  }
}

/// 所要時間コース
enum WorkoutDurationCourse {
  short20(id: 'short_20', minutes: 20, exerciseCount: 2, label: 'ショート 20分'),
  standard45(
    id: 'standard_45',
    minutes: 45,
    exerciseCount: 4,
    label: 'スタンダード 45分',
  ),
  full60(id: 'full_60', minutes: 60, exerciseCount: 5, label: 'フル 60分');

  final String id;
  final int minutes;
  final int exerciseCount;
  final String label;

  const WorkoutDurationCourse({
    required this.id,
    required this.minutes,
    required this.exerciseCount,
    required this.label,
  });

  static WorkoutDurationCourse fromId(String? value) {
    for (final v in values) {
      if (v.id == value || v.name == value) return v;
    }
    return WorkoutDurationCourse.standard45;
  }
}

/// 直前のコンディション
enum WorkoutCondition {
  great(id: 'great', label: '絶好調', sets: 3, weightMultiplier: 1.0),
  normal(id: 'normal', label: '普通', sets: 3, weightMultiplier: 1.0),
  tired(id: 'tired', label: '疲労気味', sets: 2, weightMultiplier: 0.95);

  final String id;
  final String label;
  final int sets;
  final double weightMultiplier;

  const WorkoutCondition({
    required this.id,
    required this.label,
    required this.sets,
    required this.weightMultiplier,
  });

  static WorkoutCondition fromId(String? value) {
    for (final v in values) {
      if (v.id == value || v.name == value) return v;
    }
    return WorkoutCondition.normal;
  }
}

/// 実施時間帯区分
enum TimeSlot {
  morning(id: 'morning', label: '朝'),
  daytime(id: 'daytime', label: '日中'),
  evening(id: 'evening', label: '夕方'),
  night(id: 'night', label: '就寝前');

  final String id;
  final String label;

  const TimeSlot({required this.id, required this.label});

  static TimeSlot fromId(String? value) {
    for (final v in values) {
      if (v.id == value || v.name == value) return v;
    }
    return TimeSlot.evening;
  }
}

/// システム時計の時刻から実施時間帯区分を自動判定する
TimeSlot resolveTimeSlot(DateTime now) {
  final hour = now.hour;
  if (hour >= 5 && hour <= 11) return TimeSlot.morning;
  if (hour >= 12 && hour <= 14) return TimeSlot.daytime;
  if (hour >= 15 && hour <= 20) return TimeSlot.evening;
  return TimeSlot.night; // 21..23 || 0..4
}

/// トレーニング終了後の難易度フィードバック
enum WorkoutFeedback {
  tooLight(id: 'too_light', label: '軽すぎた（次回+2.5kg）', weightDeltaKg: 2.5),
  justRight(id: 'just_right', label: 'ちょうど良かった（維持）', weightDeltaKg: 0.0),
  tooHard(id: 'too_hard', label: 'キツすぎた（次回-2.5kg）', weightDeltaKg: -2.5);

  final String id;
  final String label;
  final double weightDeltaKg;

  const WorkoutFeedback({
    required this.id,
    required this.label,
    required this.weightDeltaKg,
  });

  static WorkoutFeedback? tryFromId(String? value) {
    if (value == null || value.isEmpty) return null;
    if (value == 'too_easy') return WorkoutFeedback.tooLight;
    for (final v in values) {
      if (v.id == value || v.name == value) return v;
    }
    return null;
  }

  static WorkoutFeedback fromId(String? value) =>
      tryFromId(value) ?? WorkoutFeedback.justRight;
}

/// 性別
enum Gender {
  male(id: 'male', label: '男性', firstTimeWeightFactor: 1.0),
  female(id: 'female', label: '女性', firstTimeWeightFactor: 0.65);

  final String id;
  final String label;
  final double firstTimeWeightFactor;

  const Gender({
    required this.id,
    required this.label,
    required this.firstTimeWeightFactor,
  });

  static Gender fromId(String? value) {
    for (final v in values) {
      if (v.id == value || v.name == value) return v;
    }
    return Gender.male;
  }
}

/// 筋トレ経験レベル
enum ExperienceLevel {
  beginner(id: 'beginner', label: '初級', firstTimeWeightFactor: 1.0),
  intermediate(id: 'intermediate', label: '中級', firstTimeWeightFactor: 1.25);

  final String id;
  final String label;
  final double firstTimeWeightFactor;

  const ExperienceLevel({
    required this.id,
    required this.label,
    required this.firstTimeWeightFactor,
  });

  static ExperienceLevel fromId(String? value) {
    for (final v in values) {
      if (v.id == value || v.name == value) return v;
    }
    return ExperienceLevel.beginner;
  }
}

/// 部位6大グループ
enum MuscleGroup {
  legsGlutes(id: 'legs_glutes', label: '脚・臀部'),
  chest(id: 'chest', label: '胸'),
  back(id: 'back', label: '背中'),
  shoulders(id: 'shoulders', label: '肩'),
  arms(id: 'arms', label: '腕'),
  core(id: 'core', label: '体幹');

  final String id;
  final String label;

  const MuscleGroup({required this.id, required this.label});

  static MuscleGroup fromId(String? value) {
    for (final v in values) {
      if (v.id == value || v.name == value || v.label == value) return v;
    }
    return MuscleGroup.legsGlutes;
  }
}

/// 筋肉の時間帯区分フラグ
enum MuscleTimeCategory {
  nightAvoid(id: 'night_avoid', label: '就寝前NG（交感神経刺激）'),
  eveningRec(id: 'evening_rec', label: '夕方〜夜おすすめ（15–19時）'),
  morningRec(id: 'morning_rec', label: '朝〜午前おすすめ'),
  other(id: 'other', label: 'その他');

  final String id;
  final String label;

  const MuscleTimeCategory({required this.id, required this.label});

  static MuscleTimeCategory fromId(String? value) {
    for (final v in values) {
      if (v.id == value || v.name == value) return v;
    }
    return MuscleTimeCategory.other;
  }
}

/// 筋肉の回復・対象ステータス
enum MuscleScoreStatus {
  active(id: 'active', label: '回復完了'),
  recovering(id: 'recovering', label: '超回復中'),
  untargeted(id: 'untargeted', label: '対象外'),
  injured(id: 'injured', label: 'ケガ除外');

  final String id;
  final String label;

  const MuscleScoreStatus({required this.id, required this.label});

  static MuscleScoreStatus fromId(String? value) {
    for (final v in values) {
      if (v.id == value || v.name == value) return v;
    }
    return MuscleScoreStatus.active;
  }
}
