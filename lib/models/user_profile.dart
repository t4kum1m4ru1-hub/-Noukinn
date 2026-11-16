/// ユーザーが目指す目的のカテゴリ（体型またはスポーツ）
enum AimCategory {
  bodyType('目指す体型'),
  sports('やっているスポーツ');

  final String label;
  const AimCategory(this.label);
}

/// 初回オンボーディングで収集するユーザープロフィール情報
class UserProfile {
  /// 身長 (cm)
  final int heightCm;

  /// 体重 (kg)
  final double weightKg;

  /// 生まれ年 (西暦: 例 2000)
  final int birthYear;

  /// 性別 ("男性", "女性", "その他・回答しない")
  final String gender;

  /// 目的のカテゴリ（体型 または スポーツ）
  final AimCategory aimCategory;

  /// 目的の具体的内容（例: "細マッチョ", "サッカー" 等）
  final String targetGoal;

  const UserProfile({
    required this.heightCm,
    required this.weightKg,
    required this.birthYear,
    required this.gender,
    required this.aimCategory,
    required this.targetGoal,
  });

  /// Map（JSON形式）への変換
  Map<String, dynamic> toJson() {
    return {
      'heightCm': heightCm,
      'weightKg': weightKg,
      'birthYear': birthYear,
      'gender': gender,
      'aimCategory': aimCategory.name,
      'targetGoal': targetGoal,
    };
  }

  /// Map（JSON形式）からの復元
  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      heightCm: json['heightCm'] as int? ?? 170,
      weightKg: (json['weightKg'] as num?)?.toDouble() ?? 65.0,
      birthYear: json['birthYear'] as int? ?? 2000,
      gender: json['gender'] as String? ?? '男性',
      aimCategory: json['aimCategory'] == AimCategory.sports.name
          ? AimCategory.sports
          : AimCategory.bodyType,
      targetGoal: json['targetGoal'] as String? ?? '',
    );
  }

  UserProfile copyWith({
    int? heightCm,
    double? weightKg,
    int? birthYear,
    String? gender,
    AimCategory? aimCategory,
    String? targetGoal,
  }) {
    return UserProfile(
      heightCm: heightCm ?? this.heightCm,
      weightKg: weightKg ?? this.weightKg,
      birthYear: birthYear ?? this.birthYear,
      gender: gender ?? this.gender,
      aimCategory: aimCategory ?? this.aimCategory,
      targetGoal: targetGoal ?? this.targetGoal,
    );
  }
}

