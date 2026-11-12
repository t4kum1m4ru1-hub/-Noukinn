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

  /// 年齢区分（5歳刻み: "20〜24歳" 等）
  final String ageGroup;

  /// 性別 ("男性", "女性", "その他・回答しない")
  final String gender;

  /// 目的のカテゴリ（体型 または スポーツ）
  final AimCategory aimCategory;

  /// 目的の具体的内容（例: "細マッチョ", "サッカー" 等）
  final String targetGoal;

  const UserProfile({
    required this.heightCm,
    required this.weightKg,
    required this.ageGroup,
    required this.gender,
    required this.aimCategory,
    required this.targetGoal,
  });

  /// Map（JSON形式）への変換
  Map<String, dynamic> toJson() {
    return {
      'heightCm': heightCm,
      'weightKg': weightKg,
      'ageGroup': ageGroup,
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
      ageGroup: json['ageGroup'] as String? ?? '20〜24歳',
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
    String? ageGroup,
    String? gender,
    AimCategory? aimCategory,
    String? targetGoal,
  }) {
    return UserProfile(
      heightCm: heightCm ?? this.heightCm,
      weightKg: weightKg ?? this.weightKg,
      ageGroup: ageGroup ?? this.ageGroup,
      gender: gender ?? this.gender,
      aimCategory: aimCategory ?? this.aimCategory,
      targetGoal: targetGoal ?? this.targetGoal,
    );
  }
}
