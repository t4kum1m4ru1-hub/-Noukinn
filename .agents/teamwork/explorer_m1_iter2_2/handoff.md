# Handoff Report: State Machine Reversion (先祖返り) Fix Strategy

**Agent**: explorer_m1_iter2_2 (investigator, analyzer, synthesizer)  
**State folder**: `c:\Users\taqmi\02_development\original_program\noukin_app\.agents\teamwork\explorer_m1_iter2_2\`  
**Date**: 2026-11-10  
**Type**: Hard Handoff (Investigation & Fix Strategy Formulation Complete)  

---

## 1. Observation

1. **Challenger テスト失敗の追認**:
   - 実行コマンド: `flutter test --no-test-assets test/stress_tutorial_audio_test.dart`
   - 結果: `00:05 +3 -6: Some tests failed.`（exit code 1）。
   - 失敗箇所:
     - **Test 1**: line 185 (`Expected: <1>, Actual: <3>` 連打時の重複発話)
     - **Test 2**: line 231 (`Found 0 widgets with text containing 重量調整と音声` Step 2 音声待機中スキップによる Step 4 ➔ Step 3 先祖返り)
     - **Test 3**: line 278 (`Expected: <false>, Actual: <true>` デバウンス待機中スキップによるダッキング残留)
     - **Test 6**: line 444 (`Expected: empty, Actual: ['62.5キロ']` pop 中のデバウンス事後発話)
     - **Test 8**: line 520 (`Found 0 widgets with text containing 調整の完了` Step 3 決定音声待機中スキップによる Step 5 ➔ Step 4 先祖返り)
     - **Test 9**: line 558 (`Expected: <1>, Actual: <3>` 確定キー連打時の重複発話)

2. **`lib/tutorial_screen.dart` の該当コード直接観察**:
   - **Step 2 遷移ハンドラ（328〜338行目）**:
     ```dart
     Future<void> _proceedFromStep2() async {
       await _playBeep();
       await _speak('開始、ベンチプレス、60キロ、10回、3セット');
       if (!mounted) return;
       setState(() {
         _currentStep = TutorialStep.step3Select;
         _step3Phase = Step3Phase.enterMode;
       });
       _startGlowIfNeeded();
       _updateSpotlightRect();
     }
     ```
     `await _speak(...)` の後にステップ検証が存在せず、`if (!mounted) return;` のみ。
   - **Step 3 決定ハンドラ（375〜384行目）**:
     ```dart
     } else if (action == ButtonAction.mediaPlayPause) {
       await _playBeep();
       await _speak(TutorialScreen.formatWeightSpeech(_currentWeight));
       if (!mounted) return;
       setState(() {
         _currentStep = TutorialStep.step4Adjust;
       });
       _updateSpotlightRect();
     }
     ```
     同様にステップ検証なし。
   - **スキップ処理ハンドラ（443〜472行目）**:
     ```dart
     void _onSkipStepPressed() {
       _cancelDebounce();
       widget.ttsService?.stop();
       setState(() {
         _warningMessage = null;
         switch (_currentStep) { ... }
       });
       _startGlowIfNeeded();
       _updateSpotlightRect();
     }
     ```
     進行中トランジションのロック解除機構が存在せず、また `_duckingController.releaseDucking()` を呼んでいない。

---

## 2. Logic Chain

1. **先祖返り（Bug 1）の因果関係**:
   - `_speak(...)` は Future を返す非同期メソッドであり、発話完了まで呼び出し元の実行コンテキストをサスペンド（一時停止）する。
   - サスペンド中、Dart イベントループは UI イベントを受け付けるため、ユーザーがスキップボタンを押下すると同期的に `_onSkipStepPressed()` が走り、`_currentStep` は前進（例: Step 2 ➔ 3 ➔ 4）する。
   - その後、遅延していた発話 Future が完了すると、サスペンドされていたコンテキストが再開する。
   - ここで `if (!mounted) return;` のみをチェックしているため、ウィジェットツリー上に画面が残っている限りガードをすり抜ける。
   - 結果として、`setState(() { _currentStep = TutorialStep.step3Select; })` が無条件に実行され、最新の `_currentStep`（Step 4）を過去のステップ（Step 3）へと上書き・巻き戻す（Test 2 の失敗原因）。
   - Step 3 の決定発話（「60キロ」）でも全く同一の機序により、Step 5 に到達した画面が Step 4 へ巻き戻される（Test 8 の失敗原因）。

2. **明示的ステップチェックによる解決論理**:
   - 非同期処理の完了後に `if (!mounted || _currentStep != expectedStep) return;` を検証する。
   - スキップ操作によって `_currentStep` が既に別のステップに遷移している場合、`_currentStep != expectedStep` が `true` となり即座に `return` する。
   - これにより、遅延していた過去ステップの `setState` 実行が完全に遮断され、最新ステップが保護される。

3. **スキップ時のトランジションロック解除論理**:
   - 連打防止のために導入する `_isTransitioning`（再入防止フラグ）は、通常 `try ... finally { _isTransitioning = false; }` で解除される。
   - しかしユーザーが音声発話中にスキップを押した場合、スキップ操作は「待機を放棄して次へ進む」意思表示である。
   - もしスキップ時に `_isTransitioning = false` を明示的にリセットしないと、スキップ先のステップでも非同期音声が終了するまでの数秒間ロックが保持され、ボタンやキー入力がブロックされてしまう。
   - したがって、`_onSkipStepPressed()` 内で `_isTransitioning = false` をリセットすると同時に、世代トークン `_transitionId++` をインクリメントすることで、旧非同期処理が後から `_isTransitioning` を誤って操作する二重解除レースも完全に防止する。

---

## 3. Caveats

1. **Review-Only / Read-Only 制約**:
   - 本エージェントは Explorer（調査・戦略策定）であるため、`lib/tutorial_screen.dart` 自体のソースコード書き換えは行っていない。具体的な修正差分コード（下記 Conclusion 参照）を Worker エージェントが適用する必要がある。
2. **既存テストスイート（`test/tutorial_screen_test.dart`）の整合性**:
   - 既存テストスイート（11テスト）は `fakeTts`（即時完了モック）を使用しているため、`_isTransitioning` や `_transitionId` を追加しても既存テストの通過に一切悪影響を与えない。
3. **音量キー（Step 4）連打の除外**:
   - Step 4 の音量＋/−キーによるリアルタイム重量増減は、Test 7（20回高速連打）が示す通り、連打を受け付ける仕様である。したがって、音量キーのハンドラには `_isTransitioning` ロックをかけてはならない（0.7秒デバウンスタイマーが自然に発話制御を行う）。

---

## 4. Conclusion

ステートマシン先祖返り（先祖返り / Bug 1）および高負荷並行性不具合を完全解決するための修正戦略が策定された。

### Worker 向け修正差分仕様（Blueprint）

#### A. フィールド定義の追加（`_TutorialScreenState` 内）
```dart
bool _isTransitioning = false;
int _transitionId = 0;
```

#### B. `_proceedFromStep2` の修正（Test 1 & Test 2 解消）
```dart
Future<void> _proceedFromStep2() async {
  if (_isTransitioning) return;
  _isTransitioning = true;
  final opId = ++_transitionId;

  try {
    await _playBeep();
    if (!mounted || _currentStep != TutorialStep.step2Start || _transitionId != opId) return;

    await _speak('開始、ベンチプレス、60キロ、10回、3セット');
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

#### C. `_handleStep3Action` の修正（Test 8 解消）
- Part 1 (mediaNext): `_isTransitioning` ガード + `if (!mounted || _currentStep != TutorialStep.step3Select || _step3Phase != Step3Phase.enterMode || _transitionId != opId) return;`
- Part 2 (mediaPlayPause): `_isTransitioning` ガード + `if (!mounted || _currentStep != TutorialStep.step3Select || _transitionId != opId) return;`

#### D. `_handleStep4Action` の修正
- mediaPlayPause: `_isTransitioning` ガード + `if (!mounted || _currentStep != TutorialStep.step4Adjust || _transitionId != opId) return;`

#### D2. `_startWeightDebounce` の修正（Test 6 解消）
- タイマーコールバック先頭に `if (!mounted || _currentStep != TutorialStep.step4Adjust) return;` を追加。

#### E. `_handleStep5Action` の修正（Test 9 解消）
- mediaNext: `_isTransitioning` ガード + `if (!mounted || _currentStep != TutorialStep.step5Confirm || _transitionId != opId) return;`

#### F. `_onSkipStepPressed` の修正（Test 2, Test 3, Test 8 完全連動）
```dart
void _onSkipStepPressed() {
  _cancelDebounce();
  widget.ttsService?.stop();
  _duckingController.releaseDucking();
  _isTransitioning = false;
  _transitionId++;

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

#### G. AppBar leading の修正（Test 6 完全連動）
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

## 5. Verification Method

Worker は実装完了後、以下のコマンド群を実行して独立検証を行う：

1. **ストレステストスイートの実行（全9テストの完全通過確認）**:
   ```powershell
   flutter test --no-test-assets test/stress_tutorial_audio_test.dart
   ```
   - 期待結果: `00:05 +9: All tests passed!`（exit code 0、Test 1〜9 が 100% 成功）。
   - 特に Test 2（Step 4 ➔ Step 3 先祖返り防止）および Test 8（Step 5 ➔ Step 4 先祖返り防止）が確実にグリーンになることを検証。

2. **既存テストスイートの回帰テスト**:
   ```powershell
   flutter test --no-test-assets test/tutorial_screen_test.dart
   ```
   - 期待結果: `00:04 +11: All tests passed!`（exit code 0）。

3. **静的解析の確認**:
   ```powershell
   flutter analyze
   ```
   - 期待結果: `No issues found!`（exit code 0）。
