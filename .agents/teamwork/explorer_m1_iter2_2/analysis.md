# Analysis Report: State Machine Reversion (先祖返り) & Concurrency Fix Strategy

**Agent**: explorer_m1_iter2_2 (investigator, analyzer, synthesizer)  
**Date**: 2026-11-10  
**Target File**: `lib/tutorial_screen.dart`  
**Test Suite**: `test/stress_tutorial_audio_test.dart` (Focus: Test 2 & Test 8, plus Test 1, 3, 6, 9)  

---

## 1. Executive Summary

Challenger の実証的ストレステスト（`test/stress_tutorial_audio_test.dart`）によって発覚した **ステートマシンの先祖返りバグ（State Machine Reversion / Test 2 & Test 8）** および関連する並行性・ライフサイクル問題の根本原因を特定し、完全な修正戦略を策定した。

### 根本原因の要約
Dart の非同期実行モデルにおいて、`_speak(...)` や `_playBeep()` の `await` 待機中にユーザーがスキップボタンを押下すると、画面状態（`_currentStep`）は即座に後続ステップへと進む。しかし、遅延していた非同期 Future が完了した時点で `if (!mounted) return;` のみをチェックしているため、マウント中である限り無条件に `setState(() { _currentStep = <過去のステップ>; })` が実行され、現在の進んだステップを破壊して過去のステップへと強制巻き戻し（先祖返り）が発生していた。

### 解決策の要約
1. **明示的なステップ整合性ガード (`expectedStep` チェック)**:
   すべての `await _playBeep()` および `await _speak(...)` の直後に、`if (!mounted || _currentStep != expectedStep) return;` を配置。非同期完了時にステップが既に前進していた場合、即座に処理を中断・無効化する。
2. **トランジション世代トークン (`_transitionId`) と再入ロック (`_isTransitioning`)**:
   連打による多重発話（Test 1, Test 9）を防止するための `_isTransitioning` を導入。各操作にユニークな `_transitionId` を付与し、非同期完了時に世代の一致を検証。
3. **スキップ時のトランジションロック即時解除 (`Reset on Skip`)**:
   スキップ操作（`_onSkipStepPressed`）時に `_isTransitioning = false` を設定し、`_transitionId++` で進行中の非同期処理を無効化。これにより、スキップ先の新しいステップでユーザーが即座に入力可能となる。
4. **ダッキングおよびデバウンスの完全破棄**:
   スキップ時および画面 pop 時に `_cancelDebounce()`、`widget.ttsService?.stop()`、`_duckingController.releaseDucking()` を確実に呼ぶことで、ダッキングリーク（Test 3）および事後発話（Test 6）を完全に排除。

---

## 2. Deep Dive: State Machine Reversion Mechanism

### 2.1 Test 2 での先祖返り（Step 4 -> Step 3 逆流）の発生シーケンス

```
[Time]  [User Action / Event]            [Internal State (_currentStep)]   [Execution Context]
---------------------------------------------------------------------------------------------------------
t0      Step 2 で key 85 (再生) 押下      _currentStep = step2Start         _proceedFromStep2() 実行開始
t1      _playBeep() 完了                  _currentStep = step2Start
t2      _speak('開始、ベンチプレス...')    _currentStep = step2Start         await _speak(...) で一時中断
t3      ユーザーがスキップボタン押下      _currentStep = step3Select        _onSkipStepPressed() 実行
t4      ユーザーが再度スキップボタン押下  _currentStep = step4Adjust        UIは Step 4 (重量調整) を描画
t5      遅延していた Step 2 音声が完了    _currentStep = step4Adjust        _proceedFromStep2() が再開
t6      if (!mounted) return; を通過      _currentStep = step4Adjust        (画面はマウントされている)
t7      setState(_currentStep = step3)   _currentStep = step3Select [BUG]  強制的に Step 3 へ巻き戻される！
```

- **障害の現れ**:
  ユーザーは Step 4（重量調整）の画面を見ている最中に、突如画面が Step 3（「次の曲へ進む」）へと引き戻される。
- **Test 2 での検証コード**:
  ```dart
  stressTts.completePendingSpeak(); // Step 2 の音声完了
  await tester.pumpAndSettle();
  expect(find.textContaining('重量調整と音声'), findsOneWidget); // Step 4 が維持されているか？ -> FAIL (0件)
  expect(find.textContaining('次の曲へ進む'), findsNothing);    // Step 3 に逆流していないか？ -> FAIL (見つかってしまう)
  ```

### 2.2 Test 8 での先祖返り（Step 5 -> Step 4 逆流）の発生シーケンス

- **発生箇所**: `_handleStep3Action()` 内の `ButtonAction.mediaPlayPause` 分岐（行 375〜384）。
- **シーケンス**:
  1. Step 3 Part 2 で key 85 を押下 -> `_speak(TutorialScreen.formatWeightSpeech(_currentWeight))`（「60キロ」）が `await` 中。
  2. ユーザーがスキップを2回押下 -> Step 3 ➔ Step 4 ➔ Step 5（調整の完了）。
  3. 「60キロ」の発話が完了 -> `setState(() { _currentStep = TutorialStep.step4Adjust; })` が無条件に発火。
  4. Step 5 にいた画面が **Step 4（重量調整と音声）へ逆流**。
- **Test 8 での検証コード**:
  ```dart
  stressTts.completePendingSpeak(); // Step 3 の決定発話完了
  await tester.pumpAndSettle();
  expect(find.textContaining('調整の完了'), findsOneWidget);     // Step 5 が維持されているか？ -> FAIL (0件)
  expect(find.textContaining('重量調整と音声'), findsNothing);   // Step 4 に逆流していないか？ -> FAIL (見つかってしまう)
  ```

### 2.3 その他のステップにおける潜在的逆流ポイント

| 対象メソッド | トリガー | 非同期発話内容 | 巻き戻し先ステップ | 影響度 |
|---|---|---|---|---|
| `_proceedFromStep2` | Step 2 key 85 / 開始タップ | 「開始、ベンチプレス...」 | Step 3 (enterMode) | **極大** (Test 2 で実証) |
| `_handleStep3Action` (Part 1) | Step 3 Part 1 key 87 | 「調整、種目名」 | Step 3 (cycleItem) | **中** (Step 4 スキップ後に phase 汚染) |
| `_handleStep3Action` (Part 2) | Step 3 Part 2 key 85 | 「60キロ」 | Step 4 | **極大** (Test 8 で実証) |
| `_handleStep4Action` | Step 4 key 85 (決定) | 「調整、重量」 | Step 5 | **大** (Step 6 スキップ後に Step 5 へ逆流) |
| `_handleStep5Action` | Step 5 key 87 (確定) | 「確定、開始、...」 | Step 6 | **大** (本編遷移開始後に Step 6 描画) |

---

## 3. Concrete Fix Design

### 3.1 状態管理変数の新設

`_TutorialScreenState` に以下の2つの変数を追加する：

```dart
/// 非同期ステップ遷移の実行中フラグ（連打による多重発話防止）
bool _isTransitioning = false;

/// 遷移世代トークン（スキップや画面遷移によって古くなった非同期コールバックを無効化）
int _transitionId = 0;
```

### 3.2 明示的なステップ検証ガード（`expectedStep` チェック）のルール

すべての非同期発話・効果音処理において、以下の原則を厳格に適用する：

1. **発話前チェック**:
   `await _playBeep()` の後、および `await _speak(...)` の直前に、現在のステップおよび世代が一致しているか確認。
2. **発話後チェック**:
   `await _speak(...)` の直後に、`if (!mounted || _currentStep != expectedStep || _transitionId != opId) return;` を実行。
3. **一致しない場合の挙動**:
   `setState` を一切呼ばずに直ちに `return`（早期リターン）。

### 3.3 スキップ操作時のトランジションロック解除 (`Reset on Skip`)

**なぜスキップ時に `_isTransitioning` をリセットしなければならないのか？**
- ユーザーが音声発話の待機中にスキップボタンを押す行為は、「現在進行中の音声・演出を中断し、直ちに次のステップの操作を開始したい」という明確な意思表示である。
- もしスキップ時に `_isTransitioning` を `false` に戻さず、遅延非同期処理の `finally` まかせにすると、音声完了までの数秒間、**スキップ先のステップにおいてボタン押下やキーイベントがすべてブロックされてしまう（操作不能フリーズ）**。
- 加えて、スキップ時に `_transitionId++` を実行することで、遅延非同期処理が後から完了した際に「自分が開始された世代ではない」ことを検知し、安全に何もしないで終了する。

```dart
void _onSkipStepPressed() {
  _cancelDebounce();
  widget.ttsService?.stop();
  _duckingController.releaseDucking();
  _isTransitioning = false; // ロックを即座に解除して新ステップの操作を可能にする
  _transitionId++;          // 世代を進めて保留中の旧非同期処理を無効化する
  
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

---

## 4. Method-by-Method Implementation Blueprint

### 4.1 Step 2: `_proceedFromStep2()`

```dart
Future<void> _proceedFromStep2() async {
  if (_isTransitioning) return; // 連打防止 (Test 1)
  _isTransitioning = true;
  final opId = ++_transitionId;

  try {
    await _playBeep();
    if (!mounted || _currentStep != TutorialStep.step2Start || _transitionId != opId) return;

    await _speak('開始、ベンチプレス、60キロ、10回、3セット');
    // ステップ整合性検証: スキップ等で step2Start から離脱していたら破棄 (Test 2)
    if (!mounted || _currentStep != TutorialStep.step2Start || _transitionId != opId) return;

    setState(() {
      _currentStep = TutorialStep.step3Select;
      _step3Phase = Step3Phase.enterMode;
    });
    _startGlowIfNeeded();
    _updateSpotlightRect();
  } finally {
    if (_transitionId == opId) {
      _isTransitioning = false;
    }
  }
}
```

### 4.2 Step 3: `_handleStep3Action()`

```dart
void _handleStep3Action(ButtonAction action) async {
  if (action == ButtonAction.mediaPrevious) {
    await _speak(
        '$_currentExercise、${TutorialScreen.formatWeightSpeech(_currentWeight)}、$_currentReps回、$_currentSetsセット');
    return;
  }

  if (_step3Phase == Step3Phase.enterMode) {
    if (action == ButtonAction.mediaNext) {
      if (_isTransitioning) return;
      _isTransitioning = true;
      final opId = ++_transitionId;

      try {
        await _playBeep();
        if (!mounted || _currentStep != TutorialStep.step3Select || _step3Phase != Step3Phase.enterMode || _transitionId != opId) return;

        await _speak('調整、種目名');
        if (!mounted || _currentStep != TutorialStep.step3Select || _step3Phase != Step3Phase.enterMode || _transitionId != opId) return;

        setState(() {
          _step3Phase = Step3Phase.cycleItem;
          _selectedItem = TutorialItem.exerciseName;
        });
        _updateSpotlightRect();
      } finally {
        if (_transitionId == opId) {
          _isTransitioning = false;
        }
      }
    }
  } else {
    // 項目巡回 (volumeUp / volumeDown): 連打を阻害しないよう _isTransitioning はかけない
    if (action == ButtonAction.volumeUp) {
      await _playBeep();
      if (!mounted || _currentStep != TutorialStep.step3Select || _step3Phase != Step3Phase.cycleItem) return;
      setState(() {
        _selectedItem = _selectedItem.next;
      });
      _updateSpotlightRect();
      await _speak(_selectedItem.label);
    } else if (action == ButtonAction.volumeDown) {
      await _playBeep();
      if (!mounted || _currentStep != TutorialStep.step3Select || _step3Phase != Step3Phase.cycleItem) return;
      setState(() {
        _selectedItem = _selectedItem.previous;
      });
      _updateSpotlightRect();
      await _speak(_selectedItem.label);
    } else if (action == ButtonAction.mediaPlayPause) {
      // 決定キー: Step 4 への遷移
      if (_isTransitioning) return;
      _isTransitioning = true;
      final opId = ++_transitionId;

      try {
        await _playBeep();
        if (!mounted || _currentStep != TutorialStep.step3Select || _transitionId != opId) return;

        await _speak(TutorialScreen.formatWeightSpeech(_currentWeight));
        // ステップ整合性検証: スキップ等で step3Select から離脱していたら破棄 (Test 8)
        if (!mounted || _currentStep != TutorialStep.step3Select || _transitionId != opId) return;

        setState(() {
          _currentStep = TutorialStep.step4Adjust;
        });
        _updateSpotlightRect();
      } finally {
        if (_transitionId == opId) {
          _isTransitioning = false;
        }
      }
    }
  }
}
```

### 4.3 Step 4: `_handleStep4Action()`

```dart
void _handleStep4Action(ButtonAction action) async {
  if (action == ButtonAction.mediaPrevious) {
    await _speak(
        '$_currentExercise、${TutorialScreen.formatWeightSpeech(_currentWeight)}、$_currentReps回、$_currentSetsセット');
    return;
  }

  if (action == ButtonAction.volumeUp) {
    await _playBeep();
    if (!mounted || _currentStep != TutorialStep.step4Adjust) return;
    setState(() {
      _currentWeight = (_currentWeight + 2.5).clamp(0.0, 500.0);
    });
    _startWeightDebounce(
        () => TutorialScreen.formatWeightSpeech(_currentWeight));
  } else if (action == ButtonAction.volumeDown) {
    await _playBeep();
    if (!mounted || _currentStep != TutorialStep.step4Adjust) return;
    setState(() {
      _currentWeight = (_currentWeight - 2.5).clamp(0.0, 500.0);
    });
    _startWeightDebounce(
        () => TutorialScreen.formatWeightSpeech(_currentWeight));
  } else if (action == ButtonAction.mediaPlayPause) {
    _cancelDebounce();
    if (_isTransitioning) return;
    _isTransitioning = true;
    final opId = ++_transitionId;

    try {
      await _playBeep();
      if (!mounted || _currentStep != TutorialStep.step4Adjust || _transitionId != opId) return;

      await _speak('調整、重量');
      if (!mounted || _currentStep != TutorialStep.step4Adjust || _transitionId != opId) return;

      setState(() {
        _currentStep = TutorialStep.step5Confirm;
        _warningMessage = null;
      });
      _startGlowIfNeeded();
      _updateSpotlightRect();
    } finally {
      if (_transitionId == opId) {
        _isTransitioning = false;
      }
    }
  }
}
```

### 4.4 Step 5: `_handleStep5Action()`

```dart
void _handleStep5Action(ButtonAction action) async {
  if (action == ButtonAction.mediaNext) {
    if (_isTransitioning) return; // 確定キー連打防止 (Test 9)
    _isTransitioning = true;
    final opId = ++_transitionId;

    try {
      await _playBeep();
      if (!mounted || _currentStep != TutorialStep.step5Confirm || _transitionId != opId) return;

      await _speak(
          '確定、開始、$_currentExercise、${TutorialScreen.formatWeightSpeech(_currentWeight)}、$_currentReps回、$_currentSetsセット');
      if (!mounted || _currentStep != TutorialStep.step5Confirm || _transitionId != opId) return;

      setState(() {
        _currentStep = TutorialStep.step6Complete;
        _warningMessage = null;
      });
      _startGlowIfNeeded();
      _updateSpotlightRect();
    } finally {
      if (_transitionId == opId) {
        _isTransitioning = false;
      }
    }
  } else {
    setState(() {
      _warningMessage = '［次の曲へ進む］ボタンを押して調整を完了してください';
    });
  }
}
```

### 4.5 デバウンス制御および画面離脱クリーンアップ (Test 3 & Test 6 対策)

```dart
void _startWeightDebounce(String Function() speechBuilder) {
  _cancelDebounce();
  _debounceTimer = Timer(const Duration(milliseconds: 700), () async {
    _framePumpTimer?.cancel();
    _framePumpTimer = null;
    _debounceTimer = null;
    // タイマー発火時に画面アンマウントまたは Step 4 以外になっていれば発話しない (Test 6)
    if (!mounted || _currentStep != TutorialStep.step4Adjust) return;
    await _speak(speechBuilder());
  });

  _framePumpTimer =
      Timer.periodic(const Duration(milliseconds: 100), (timer) {
    if (_debounceTimer == null || !_debounceTimer!.isActive) {
      timer.cancel();
      return;
    }
    try {
      SchedulerBinding.instance.scheduleFrame();
    } catch (_) {}
  });
  try {
    SchedulerBinding.instance.scheduleFrame();
  } catch (_) {}
}
```

AppBar の戻るボタン（行 586〜589）:
```dart
leading: IconButton(
  icon: const Icon(Icons.arrow_back),
  onPressed: () {
    _cancelDebounce();
    widget.ttsService?.stop();
    _duckingController.releaseDucking();
    Navigator.of(context).pop();
  },
),
```

---

## 5. Verification Mapping for Test 2 & Test 8

### 5.1 Test 2 検証トレース
1. テストが Step 2 で key 85 を送信。`_proceedFromStep2()` が起動し、`opId = 1`, `_isTransitioning = true`。
2. `stressTts.speak()` で非同期保留中になる。
3. テストがスキップボタンを 2 回タップ。
   - 1 回目: `_onSkipStepPressed()` により `_transitionId` が 2 に増加、`_isTransitioning = false`、`_currentStep = step3Select`。
   - 2 回目: `_onSkipStepPressed()` により `_transitionId` が 3 に増加、`_currentStep = step4Adjust`。
4. UI には Step 4（重量調整と音声）が表示される。
5. `stressTts.completePendingSpeak()` で Step 2 の音声完了が解放される。
6. `_proceedFromStep2()` が再開し、ガード行に到達：
   ```dart
   if (!mounted || _currentStep != TutorialStep.step2Start || _transitionId != opId) return;
   ```
   - `_currentStep` は `step4Adjust`（`!= step2Start`）➔ **条件一致で直ちに return**。
   - `_transitionId` は 3（`!= opId (1)`）➔ **条件一致で直ちに return**。
7. `setState` は一切呼ばれず、画面状態は `step4Adjust` のまま完全に保持される。
8. `expect(find.textContaining('重量調整と音声'), findsOneWidget)` が **PASS** する。

### 5.2 Test 8 検証トレース
1. テストが Step 3 Part 2 で key 85（決定）を送信。`_handleStep3Action()` が起動し、`opId = 10`, `_isTransitioning = true`。
2. `stressTts.speak('60キロ')` で非同期保留中になる。
3. テストがスキップボタンを 2 回タップ。
   - 1 回目: `_currentStep = step4Adjust`, `_transitionId` 増加, `_isTransitioning = false`。
   - 2 回目: `_currentStep = step5Confirm`, `_transitionId` 増加。
4. UI には Step 5（調整の完了）が表示される。
5. `stressTts.completePendingSpeak()` で Step 3 の音声完了が解放される。
6. `_handleStep3Action()` が再開し、ガード行に到達：
   ```dart
   if (!mounted || _currentStep != TutorialStep.step3Select || _transitionId != opId) return;
   ```
   - `_currentStep` は `step5Confirm`（`!= step3Select`）➔ **直ちに return**。
7. `_currentStep` は `step5Confirm` のまま維持され、Step 4 への先祖返りは発生しない。
8. `expect(find.textContaining('調整の完了'), findsOneWidget)` が **PASS** する。

---

## 6. Synthesis and Readiness

本設計により、以下の全障害モードが同時に解決される：
- **Bug 1 (先祖返り / Test 2, Test 8)**: `_currentStep != expectedStep` ガードにより完全解消。
- **Bug 2 (ダッキング残留 / Test 3)**: `_onSkipStepPressed()` での明示的 `releaseDucking()` により完全解消。
- **Bug 3 (連打重複発話 / Test 1, Test 9)**: `_isTransitioning` ロックにより完全解消。
- **Bug 4 (AppBar pop 事後発話 / Test 6)**: 戻るボタンでの `_cancelDebounce()` およびデバウンス内 `mounted` チェックにより完全解消。

Worker は本設計に基づいて `lib/tutorial_screen.dart` を修正することで、既存の 11 テスト（`test/tutorial_screen_test.dart`）および 9 つのストレステスト（`test/stress_tutorial_audio_test.dart`）の全 20 テストを 100% 合格させることが可能である。
