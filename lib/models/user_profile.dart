import 'enums.dart';

/// ユーザープロファイル（誕生年 birthYear のみを保持し、年齢層選択は持たない）
class UserProfile {
  final String id;
  final Gender gender;
  final int birthYear;
  final ExperienceLevel experience;
  final double bodyWeightKg;
  final TrainingPurpose purpose;
  final bool isFirstTime;
  final String? email;

  const UserProfile({
    this.id = 'local_user',
    this.gender = Gender.male,
    this.birthYear = 1995,
    this.experience = ExperienceLevel.beginner,
    this.bodyWeightKg = 65.0,
    this.purpose = TrainingPurpose.bodyMakeMale,
    this.isFirstTime = true,
    this.email,
  });

  UserProfile copyWith({
    String? id,
    Gender? gender,
    int? birthYear,
    ExperienceLevel? experience,
    double? bodyWeightKg,
    TrainingPurpose? purpose,
    bool? isFirstTime,
    String? email,
    bool clearEmail = false,
  }) {
    return UserProfile(
      id: id ?? this.id,
      gender: gender ?? this.gender,
      birthYear: birthYear ?? this.birthYear,
      experience: experience ?? this.experience,
      bodyWeightKg: bodyWeightKg ?? this.bodyWeightKg,
      purpose: purpose ?? this.purpose,
      isFirstTime: isFirstTime ?? this.isFirstTime,
      email: clearEmail ? null : (email ?? this.email),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'gender': gender.id,
      'birth_year': birthYear,
      'experience': experience.id,
      'body_weight_kg': bodyWeightKg,
      'purpose': purpose.id,
      'is_first_time': isFirstTime,
      'email': email,
    };
  }

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    final rawId = json['id'] ?? json['user_id'] ?? 'local_user';
    final rawBirthYear = json['birth_year'] ?? json['birthYear'];
    final rawBodyWeight = json['body_weight_kg'] ?? json['bodyWeightKg'];
    final rawIsFirstTime = json['is_first_time'] ?? json['isFirstTime'];

    return UserProfile(
      id: rawId as String,
      gender: Gender.fromId(json['gender'] as String?),
      birthYear: (rawBirthYear as num?)?.toInt() ?? 1995,
      experience: ExperienceLevel.fromId(json['experience'] as String?),
      bodyWeightKg: (rawBodyWeight as num?)?.toDouble() ?? 65.0,
      purpose: TrainingPurpose.fromId(json['purpose'] as String?),
      isFirstTime: rawIsFirstTime as bool? ?? true,
      email: json['email'] as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UserProfile &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          gender == other.gender &&
          birthYear == other.birthYear &&
          experience == other.experience &&
          bodyWeightKg == other.bodyWeightKg &&
          purpose == other.purpose &&
          isFirstTime == other.isFirstTime &&
          email == other.email;

  @override
  int get hashCode => Object.hash(
    id,
    gender,
    birthYear,
    experience,
    bodyWeightKg,
    purpose,
    isFirstTime,
    email,
  );
}

/// 認証済みユーザー情報（Supabase Auth / ローカルフォールバック共通）
class AuthUser {
  final String id;
  final String? email;
  final String? displayName;
  final bool isLocalFallback;

  const AuthUser({
    required this.id,
    this.email,
    this.displayName,
    this.isLocalFallback = true,
  });

  AuthUser copyWith({
    String? id,
    String? email,
    String? displayName,
    bool? isLocalFallback,
    bool clearEmail = false,
    bool clearDisplayName = false,
  }) {
    return AuthUser(
      id: id ?? this.id,
      email: clearEmail ? null : (email ?? this.email),
      displayName: clearDisplayName ? null : (displayName ?? this.displayName),
      isLocalFallback: isLocalFallback ?? this.isLocalFallback,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'email': email,
      'display_name': displayName,
      'is_local_fallback': isLocalFallback,
    };
  }

  factory AuthUser.fromJson(Map<String, dynamic> json) {
    final rawId = json['id'] ?? json['user_id'] ?? '';
    final rawDisplayName = json['display_name'] ?? json['displayName'];
    final rawIsLocalFallback =
        json['is_local_fallback'] ?? json['isLocalFallback'];

    return AuthUser(
      id: rawId as String,
      email: json['email'] as String?,
      displayName: rawDisplayName as String?,
      isLocalFallback: rawIsLocalFallback as bool? ?? true,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AuthUser &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          email == other.email &&
          displayName == other.displayName &&
          isLocalFallback == other.isLocalFallback;

  @override
  int get hashCode => Object.hash(id, email, displayName, isLocalFallback);
}
