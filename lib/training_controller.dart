import 'package:flutter/foundation.dart';

/// M1 プレースホルダコントローラ（M4 で lib/controllers/training_session_controller.dart に置換）
class TrainingController extends ChangeNotifier {
  String _exerciseName;
  double _weightKg;
  int _reps;
  int _sets;
  bool _isStarted = false;

  TrainingController({
    this._exerciseName = 'ベンチプレス',
    this._weightKg = 60.0,
    this._reps = 10,
    this._sets = 3,
  });

  String get exerciseName => _exerciseName;
  double get weightKg => _weightKg;
  int get reps => _reps;
  int get sets => _sets;
  bool get isStarted => _isStarted;

  void updateExerciseName(String value) {
    _exerciseName = value;
    notifyListeners();
  }

  void adjustWeight(double deltaKg) {
    final next = _weightKg + deltaKg;
    _weightKg = next < 2.5 ? 2.5 : next;
    notifyListeners();
  }

  void adjustReps(int delta) {
    final next = _reps + delta;
    _reps = next < 1 ? 1 : next;
    notifyListeners();
  }

  void adjustSets(int delta) {
    final next = _sets + delta;
    _sets = next < 1 ? 1 : next;
    notifyListeners();
  }

  void toggleStarted() {
    _isStarted = !_isStarted;
    notifyListeners();
  }
}
