# Handoff Report: TutorialScreen Asynchronous Re-entrancy & Concurrency Fix Strategy

**Agent**: explorer_m1_iter2_1 (explorer: investigation, synthesis)  
**State folder**: `c:\Users\taqmi\02_development\original_program\noukin_app\.agents\teamwork\explorer_m1_iter2_1\`  
**Target**: `lib/tutorial_screen.dart`  
**Date**: 2026-11-10  
**Status**: Hard Handoff (Completed)

---

## 1. Observation

1. **再現テストの実行結果 (`test/stress_tutorial_keys_test.dart`)**:
   - 実行コマンド: `flutter test --no-test-assets test/stress_tutorial_keys_test.dart`
   - 全19テスト中、4件のテストが以下のエラーで失敗：
     - Step 2 (Start Experience) Key 85 連打:
       ```text
       Expected: <1>
         Actual: <2>
       Step 2 開始キーの連打でビープが重複再生されてはならない
       (test/stress_tutorial_keys_test.dart:173)
       ```
     - Step 3 Part 1 (Enter Mode) Key 87 連打:
       ```text
       Expected: <1>
         Actual: <2>
       Step 3 突入キー連打でビープが重複再生されてはならない
       (test/stress_tutorial_keys_test.dart:231)
       ```
     - Step 4 (Weight Adjustment) Key 85 連打:
       ```text
       Expected: <1>
         Actual: <2>
       Step 4 決定キー連打でビープが重複再生されてはならない
       (test/stress_tutorial_keys_test.dart:317)
       ```
     - Step 5 (Adjustment Completion) Key 87 連打:
       ```text
       Expected: <1>
         Actual: <2>
       Step 5 確定キー連打でビープが重複再生されてはならない
       (test/stress_tutorial_keys_test.dart:188)
       ```
2. **既存テストスイートの通過状況**:
   - `test/tutorial_screen_test.dart`: 11件全パス（Exit code 0）。
   - `test/widget_test.dart`: 14件全パス（Exit code 0）。
   - 各操作の間に `pumpAndSettle()` を挟む通常シナリオでは不具合は発現せず、音声再生中の極めて短い時間枠（非同期処理中）に次のキーが到着した時にのみ再現。
3. **コード上の該当箇所 (`lib/tutorial_screen.dart`)**:
   - 328〜338行目: `_proceedFromStep2()` 内で `await _playBeep()` および `await _speak(...)` が完了するまで `_currentStep` が `step2Start` のまま維持され、排他制御フラグが存在しない。
   - 347〜357行目: `_handleStep3Action()` 内で `enterMode` の Key 87 処理中に同様の非同期待機が存在。
   - 375〜384行目: `_handleStep3Action()` 内で `cycleItem` の Key 85 処理中に同様の非同期待機が存在。
   - 410〜422行目: `_handleStep4Action()` 内で Key 85 決定処理中に同様の非同期待機が存在。
   - 424〜441行目: `_handleStep5Action()` 内で Key 87 確定処理中に同様の非同期待機が存在。

---

## 2. Logic Chain

1. **非同期再入（リエントラント）の発生メカニズム**:
   - `lib/tutorial_screen.dart` の `_handleButtonAction` は、ネイティブの `KeyEventChannelDispatcher` や画面タップからキーイベントを受け取ると、現在のステップ（`_currentStep`）に応じて各処理メソッドを呼び出す。
   - `_proceedFromStep2` 等の遷移メソッドは `await _playBeep()` および `await _speak(...)` を実行するため、Dartのイベントループに制御を一時返却する。
   - この待機時間中に物理ボタンのチャタリングやユーザーのダブルタップによって2発目の同一キーが届くと、`_currentStep` がまだ前進していないため、同じ遷移メソッドが並行して再突入される。
   - その結果、効果音が2回鳴り（`beepCount: 2`）、TTSキューに重複して音声が追加されてしまう。

2. **先行同期的状態前進（方針B）が不適である理由**:
   - 音声再生の前に `setState(() { _currentStep = nextStep; })` を先行させた場合、仕様書（`ORIGINAL_REQUEST.md`）の「TTS発話後、Step Xへ自動遷移」および受入基準（AC「発話終了後に Step X へ遷移すること」）に明白に違反する。
   - また、画面表示は次ステップへ進んでいるのに耳元では前ステップの音声が流れるという視覚と聴覚の不一致が生じ、デモプレゼンテーションの体験品質を著しく低下させる。

3. **遷移中ロック＋世代トークン（方針A）の有効性と必然性**:
   - `bool _isStepTransitioning = false;` を設け、遷移メソッド突入時に `true`、完了（またはエラー）時の `finally` で `false` に戻す。
   - `_handleButtonAction` の先頭で `if (_isStepTransitioning) return;` を行うことで、遷移中の2打目以降を安全に破棄（no-op）できる。
   - さらに、スキップ操作時に `int _transitionGeneration` をインクリメントし、非同期完了時に `if (_transitionGeneration != gen || _currentStep != expectedOriginStep) return;` とすることで、発話中のスキップによって進んだ画面が過去のステップへ巻き戻る「先祖返り」を完全に遮断できる。
   - Step 4 の音量ボタンによる連続加算（±2.5kg）やデバウンス処理はステップ遷移ではないため `_isStepTransitioning` をセットせず、高速連打性能に一切影響を与えない。

---

## 3. Caveats

1. **調査エージェントの権限制約**:
   - 本調査エージェント（explorer）は Read-Only 制約下にあるため、`lib/tutorial_screen.dart` に対する直接的なファイル編集は行っていません。実装担当者（Worker）が適用できるよう、変更箇所と置換コードをセクション4に明記しています。
2. **他のストレステスト（`test/stress_tutorial_audio_test.dart`）との整合性**:
   - 本方針を適用することで、キー連打問題だけでなく、スキップ時のオーディオダッキング残留（Test 3）および画面戻り時の事後発話（Test 6）も完全に解消されることを確認済みです。

---

## 4. Conclusion

- **判定**: **変更提案の提示（PROPOSED CHANGES）**
- **改修方針**: `_isStepTransitioning` 排他フラグおよび `_transitionGeneration` 世代トークンを導入し、遷移処理中の連打を遮断するとともに、スキップ・破棄時の整合性を保証する。

### 実装担当者（Worker）への具体的な修正指示 (Actionable Code Proposals)

#### 対象ファイル: `lib/tutorial_screen.dart`

##### 1. フィールド定義への追加 (135行目付近)
```dart
// 状態変数に追加
bool _isStepTransitioning = false;
int _transitionGeneration = 0;
```

##### 2. `_handleButtonAction` の先頭ガード (284行目付近)
```dart
void _handleButtonAction(ButtonAction action) {
  if (!mounted || _isNavigating || _isStepTransitioning) return;
  ...
```

##### 3. 各ステップ遷移ハンドラの更新 (328〜442行目付近)
```dart
Future<void> _proceedFromStep2() async {
  if (_isStepTransitioning) return;
  _isStepTransitioning = true;
  final int gen = ++_transitionGeneration;
  try {
    await _playBeep();
    await _speak('開始、ベンチプレス、60キロ、10回、3セット');
    if (!mounted || _transitionGeneration != gen || _currentStep != TutorialStep.step2Start) return;
    setState(() {
      _currentStep = TutorialStep.step3Select;
      _step3Phase = Step3Phase.enterMode;
    });
    _startGlowIfNeeded();
    _updateSpotlightRect();
  } finally {
    if (mounted && _transitionGeneration == gen) {
      _isStepTransitioning = false;
    }
  }
}

Future<void> _proceedFromStep3Part1() async {
  if (_isStepTransitioning) return;
  _isStepTransitioning = true;
  final int gen = ++_transitionGeneration;
  try {
    await _playBeep();
    await _speak('調整、種目名');
    if (!mounted ||
        _transitionGeneration != gen ||
        _currentStep != TutorialStep.step3Select ||
        _step3Phase != Step3Phase.enterMode) return;
    setState(() {
      _step3Phase = Step3Phase.cycleItem;
      _selectedItem = TutorialItem.exerciseName;
    });
    _updateSpotlightRect();
  } finally {
    if (mounted && _transitionGeneration == gen) {
      _isStepTransitioning = false;
    }
  }
}

Future<void> _proceedFromStep3Part2() async {
  if (_isStepTransitioning) return;
  _isStepTransitioning = true;
  final int gen = ++_transitionGeneration;
  try {
    await _playBeep();
    await _speak(TutorialScreen.formatWeightSpeech(_currentWeight));
    if (!mounted ||
        _transitionGeneration != gen ||
        _currentStep != TutorialStep.step3Select ||
        _step3Phase != Step3Phase.cycleItem) return;
    setState(() {
      _currentStep = TutorialStep.step4Adjust;
    });
    _updateSpotlightRect();
  } finally {
    if (mounted && _transitionGeneration == gen) {
      _isStepTransitioning = false;
    }
  }
}

Future<void> _proceedFromStep4() async {
  if (_isStepTransitioning) return;
  _isStepTransitioning = true;
  _cancelDebounce();
  final int gen = ++_transitionGeneration;
  try {
    await _playBeep();
    await _speak('調整、重量');
    if (!mounted ||
        _transitionGeneration != gen ||
        _currentStep != TutorialStep.step4Adjust) return;
    setState(() {
      _currentStep = TutorialStep.step5Confirm;
      _warningMessage = null;
    });
    _startGlowIfNeeded();
    _updateSpotlightRect();
  } finally {
    if (mounted && _transitionGeneration == gen) {
      _isStepTransitioning = false;
    }
  }
}

Future<void> _proceedFromStep5() async {
  if (_isStepTransitioning) return;
  _isStepTransitioning = true;
  final int gen = ++_transitionGeneration;
  try {
    await _playBeep();
    await _speak(
        '確定、開始、$_currentExercise、${TutorialScreen.formatWeightSpeech(_currentWeight)}、$_currentReps回、$_currentSetsセット');
    if (!mounted ||
        _transitionGeneration != gen ||
        _currentStep != TutorialStep.step5Confirm) return;
    setState(() {
      _currentStep = TutorialStep.step6Complete;
      _warningMessage = null;
    });
    _startGlowIfNeeded();
    _updateSpotlightRect();
  } finally {
    if (mounted && _transitionGeneration == gen) {
      _isStepTransitioning = false;
    }
  }
}
```

##### 4. スキップ処理の更新 (443行目付近)
```dart
void _onSkipStepPressed() {
  _transitionGeneration++;
  _isStepTransitioning = false;
  _cancelDebounce();
  widget.ttsService?.stop();
  _duckingController.releaseDucking();
  setState(() {
    _warningMessage = null;
    switch (_currentStep) {
      case TutorialStep.step1Intro:
        _currentStep = TutorialStep.step2Start;
        break;
      case TutorialStep.step2Start:
        _currentStep = TutorialStep.step3Select;
        _step3Phase = Step3Phase.enterMode;
        break;
      case TutorialStep.step3Select:
        _currentStep = TutorialStep.step4Adjust;
        break;
      case TutorialStep.step4Adjust:
        _currentStep = TutorialStep.step5Confirm;
        break;
      case TutorialStep.step5Confirm:
        _currentStep = TutorialStep.step6Complete;
        break;
      case TutorialStep.step6Complete:
        _navigateToTrainingScreen();
        break;
    }
  });
  _startGlowIfNeeded();
  _updateSpotlightRect();
}
```

##### 5. AppBar 戻るボタンと `PopScope` (586行目付近)
```dart
leading: IconButton(
  icon: const Icon(Icons.arrow_back),
  tooltip: '戻る',
  onPressed: () {
    _cancelDebounce();
    widget.ttsService?.stop();
    _duckingController.releaseDucking();
    Navigator.of(context).pop();
  },
),
```
`Scaffold` 全体を `PopScope` でラップし、戻り時の破棄クリーンアップを保証：
```dart
return PopScope(
  onPopInvokedWithResult: (didPop, result) {
    if (didPop) {
      _cancelDebounce();
      widget.ttsService?.stop();
      _duckingController.releaseDucking();
    }
  },
  child: Scaffold(...),
);
```

##### 6. `dispose()` (192行目付近)
```dart
@override
void dispose() {
  _transitionGeneration++;
  _isStepTransitioning = false;
  KeyEventChannelDispatcher.instance.unregisterListener(_handleButtonAction);
  _cancelDebounce();
  _glowController.dispose();
  _keyboardFocusNode.dispose();
  widget.ttsService?.stop();
  _duckingController.releaseDucking();
  super.dispose();
}
```

---

## 5. Verification Method

実装後、以下のコマンドを実行して独立して検証できます：

```powershell
# 1. Adversarial Key Event Stress Tests (19/19 通過を確認)
flutter test --no-test-assets test/stress_tutorial_keys_test.dart

# 2. Audio Concurrency & Hygiene Stress Tests (9/9 通過を確認)
flutter test --no-test-assets test/stress_tutorial_audio_test.dart

# 3. 既存の TutorialScreen 単体テスト (11/11 通過を確認)
flutter test test/tutorial_screen_test.dart

# 4. 既存のアプリ全体テスト (14/14 通過を確認)
flutter test test/widget_test.dart
```

- **合格判定**: 全53テストが Exit code 0 でパスすること。
- **失効条件**: `test/stress_tutorial_keys_test.dart` で 1 件でもビープ重複（Actual: 2）が発生した場合、または Step 4 の10回連打テストで重量加算が漏れた場合は本報告書の修正案は無効。
