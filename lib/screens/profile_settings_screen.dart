import 'package:flutter/material.dart';

import '../models/models.dart';
import '../state/app_state.dart';
import '../theme/app_colors.dart';

/// 画面 C: ユーザープロファイル設定（性別・誕生年のみ・経験レベル・体重）および認証連携
class ProfileSettingsScreen extends StatefulWidget {
  final AppState appState;

  const ProfileSettingsScreen({super.key, required this.appState});

  @override
  State<ProfileSettingsScreen> createState() => _ProfileSettingsScreenState();
}

class _ProfileSettingsScreenState extends State<ProfileSettingsScreen> {
  late Gender _selectedGender;
  late ExperienceLevel _selectedExperience;
  late final TextEditingController _birthYearController;
  late final TextEditingController _bodyWeightController;

  int _lastSyncedBirthYear = 1995;
  double _lastSyncedBodyWeight = 65.0;
  bool _isAuthBusy = false;

  @override
  void initState() {
    super.initState();
    final profile = widget.appState.profile;
    _selectedGender = profile.gender;
    _selectedExperience = profile.experience;
    _lastSyncedBirthYear = profile.birthYear;
    _lastSyncedBodyWeight = profile.bodyWeightKg;
    _birthYearController = TextEditingController(
      text: profile.birthYear.toString(),
    );
    _bodyWeightController = TextEditingController(
      text: _formatBodyWeight(profile.bodyWeightKg),
    );
    widget.appState.addListener(_onAppStateChanged);
  }

  @override
  void didUpdateWidget(covariant ProfileSettingsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.appState != widget.appState) {
      oldWidget.appState.removeListener(_onAppStateChanged);
      widget.appState.addListener(_onAppStateChanged);
      _syncFromProfile(widget.appState.profile, force: true);
    }
  }

  @override
  void dispose() {
    widget.appState.removeListener(_onAppStateChanged);
    _birthYearController.dispose();
    _bodyWeightController.dispose();
    super.dispose();
  }

  static String _formatBodyWeight(double weight) {
    if (weight == weight.roundToDouble()) {
      return weight.toInt().toString();
    }
    return weight.toStringAsFixed(1);
  }

  void _onAppStateChanged() {
    if (!mounted) return;
    _syncFromProfile(widget.appState.profile);
    setState(() {});
  }

  void _syncFromProfile(UserProfile profile, {bool force = false}) {
    if (force || profile.birthYear != _lastSyncedBirthYear) {
      _lastSyncedBirthYear = profile.birthYear;
      _birthYearController.text = profile.birthYear.toString();
    }
    if (force || profile.bodyWeightKg != _lastSyncedBodyWeight) {
      _lastSyncedBodyWeight = profile.bodyWeightKg;
      _bodyWeightController.text = _formatBodyWeight(profile.bodyWeightKg);
    }
    if (force) {
      _selectedGender = profile.gender;
      _selectedExperience = profile.experience;
    }
  }

  Future<void> _handleSaveProfile() async {
    final rawYear = _birthYearController.text.trim();
    final parsedYear = int.tryParse(rawYear);
    final isValidYear =
        parsedYear != null &&
        parsedYear >= AppState.minValidBirthYear &&
        parsedYear <= AppState.maxValidBirthYear;

    final rawWeight = _bodyWeightController.text.trim();
    final parsedWeight = double.tryParse(rawWeight);
    final isValidWeight =
        parsedWeight != null &&
        parsedWeight.isFinite &&
        parsedWeight >= AppState.minValidBodyWeightKg &&
        parsedWeight <= AppState.maxValidBodyWeightKg;

    final targetYear = isValidYear
        ? parsedYear
        : widget.appState.profile.birthYear;
    final targetWeight = isValidWeight
        ? parsedWeight
        : widget.appState.profile.bodyWeightKg;

    _lastSyncedBirthYear = targetYear;
    _lastSyncedBodyWeight = targetWeight;
    _birthYearController.text = targetYear.toString();
    _bodyWeightController.text = _formatBodyWeight(targetWeight);

    await widget.appState.updateProfile(
      gender: _selectedGender,
      birthYear: targetYear,
      experience: _selectedExperience,
      bodyWeightKg: targetWeight,
    );
  }

  Future<void> _handleGoogleLogin() async {
    if (_isAuthBusy) return;
    setState(() {
      _isAuthBusy = true;
    });
    try {
      await widget.appState.signInWithGoogle();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)
          ?..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              backgroundColor: AppColors.error,
              content: Text(
                'ログインに失敗しました。接続設定をご確認ください。',
                style: TextStyle(color: AppColors.onError),
              ),
            ),
          );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isAuthBusy = false;
        });
      }
    }
  }

  Future<void> _handleLogout() async {
    if (_isAuthBusy) return;
    setState(() {
      _isAuthBusy = true;
    });
    try {
      await widget.appState.signOut();
    } finally {
      if (mounted) {
        setState(() {
          _isAuthBusy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.appState.currentUser;
    final isLocalFallback = widget.appState.isLocalFallbackMode;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'のう筋（Noukin） — 設定',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildProfileCard(),
                  const SizedBox(height: 20),
                  _buildAuthCard(user, isLocalFallback),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProfileCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              Icon(Icons.person_outline, color: AppColors.tealAccent, size: 20),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'ユーザープロファイル',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            '性別',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          _buildGenderSelector(),
          const SizedBox(height: 16),
          const Text(
            '誕生年（西暦4桁）',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            key: const Key('birth_year_input'),
            controller: _birthYearController,
            keyboardType: TextInputType.number,
            style: const TextStyle(color: AppColors.textPrimary),
            decoration: const InputDecoration(
              hintText: '例: 1995',
              suffixText: '年',
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            '経験レベル',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          _buildExperienceSelector(),
          const SizedBox(height: 16),
          const Text(
            '体重（kg・初期推奨重量算出用）',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            key: const Key('body_weight_input'),
            controller: _bodyWeightController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(color: AppColors.textPrimary),
            decoration: const InputDecoration(
              hintText: '例: 65.0',
              suffixText: 'kg',
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            key: const Key('btn_save_profile'),
            onPressed: _handleSaveProfile,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryAccent,
              foregroundColor: AppColors.onPrimaryAccent,
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'プロフィールを保存',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGenderSelector() {
    return Container(
      key: const Key('gender_selector'),
      child: Row(
        children: [
          for (var i = 0; i < Gender.values.length; i++) ...[
            if (i > 0) const SizedBox(width: 10),
            Expanded(
              child: _buildChoiceTile(
                label: Gender.values[i].label,
                selected: _selectedGender == Gender.values[i],
                onTap: () {
                  setState(() {
                    _selectedGender = Gender.values[i];
                  });
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildExperienceSelector() {
    return Container(
      key: const Key('experience_selector'),
      child: Row(
        children: [
          for (var i = 0; i < ExperienceLevel.values.length; i++) ...[
            if (i > 0) const SizedBox(width: 10),
            Expanded(
              child: _buildChoiceTile(
                label: ExperienceLevel.values[i].label,
                selected: _selectedExperience == ExperienceLevel.values[i],
                onTap: () {
                  setState(() {
                    _selectedExperience = ExperienceLevel.values[i];
                  });
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildChoiceTile({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: selected
          ? AppColors.highlightSelectedSurface
          : AppColors.surfaceVariant,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: selected ? AppColors.tealAccent : AppColors.border,
          width: selected ? 2.0 : 1.0,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                selected ? Icons.check_circle : Icons.radio_button_unchecked,
                size: 18,
                color: selected ? AppColors.tealAccent : AppColors.textSecondary,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: selected
                        ? AppColors.tealAccent
                        : AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAuthCard(AuthUser? user, bool isLocalFallback) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(
                Icons.verified_user_outlined,
                color: AppColors.tealAccent,
                size: 20,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'アカウント認証（Google / Supabase Auth）',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.border),
                ),
                child: Text(
                  isLocalFallback ? 'ローカル保存モード' : 'Supabase クラウド連携',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.tealAccent,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (user != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'ログイン中: ${user.displayName ?? user.id}',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  if (user.email != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      user.email!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: const Key('btn_logout'),
              onPressed: _isAuthBusy ? null : _handleLogout,
              icon: const Icon(Icons.logout),
              label: const Text('ログアウト'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.textPrimary,
                side: const BorderSide(color: AppColors.border),
                minimumSize: const Size.fromHeight(46),
              ),
            ),
          ] else ...[
            const Text(
              'Googleアカウントでログインするとデータを連携・保護できます（未設定時はローカル認証にフォールバックします）。',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              key: const Key('btn_google_login'),
              onPressed: _isAuthBusy ? null : _handleGoogleLogin,
              icon: const Icon(Icons.login),
              label: const Text(
                'Googleでログイン',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.tealAccent,
                foregroundColor: Colors.black,
                minimumSize: const Size.fromHeight(48),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
