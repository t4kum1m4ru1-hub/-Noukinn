# チュートリアル画面における非同期再入（連打）不具合の根本原因と包括的改修方針

## 1. 概要 (Executive Summary)

本調査では、`lib/tutorial_screen.dart` においてイヤホンボタン等の連続打鍵（ダブルクリックやチャタリングなど）が発生した際に、電子音（ビープ）の重複再生や音声読み上げ（TTS）の多重発話が発生する問題について原因を特定し、包括的な修正戦略を策定しました。

### 主要な発見
1. **根本原因**:
   `lib/tutorial_screen.dart` 内の各ステップ遷移ハンドラ（Step 2、Step 3 Part 1、Step 3 Part 2、Step 4、Step 5）において、`await _playBeep()` および `await _speak(...)` による非同期音声処理の待機中に、画面状態（`_currentStep`）の更新が行われておらず、かつ「遷移中（処理中）」であることを表す排他フラグが存在していません。
   そのため、音声再生の完了を待つわずかな時間（数百ミリ秒）の間に同一キーが再入力されると、同一ハンドラが並行して再実行され、効果音とTTS発話が2回実行されてしまいます。
2. **方針の比較**:
   - **方針A（推奨）: 遷移処理中ロック（`_isStepTransitioning`）＋世代トークン（`_transitionGeneration`）の導入**
     音声処理が完了するまで新たな遷移キーの受付を弾き、かつスキップ操作が発生した際にも過去の非同期処理が新しい画面状態を上書き（先祖返り）しないよう安全に防護します。
   - **方針B（非推奨）: 音声再生前の同期的なステップ状態前進**
     キー入力直後に画面状態を次ステップへ切り替えてしまうと、仕様要件である「発話終了後に自動遷移すること」に反し、音声が鳴っている最中に画面表示だけが先行して切り替わってしまい、実演デモでの視覚・音声の同期体験を損ねます。
3. **検証結果への影響**:
   本改修により、`test/stress_tutorial_keys_test.dart` で失敗している4件のテストがすべて合格（19/19 通過）となるだけでなく、スキップ時のオーディオダッキング残留や画面戻り時のタイマー事後発話も一貫して解決されます。

---

## 2. 現状の観測と失敗の再現 (Empirical Observations)

### 失敗テストの出力
`flutter test --no-test-assets test/stress_tutorial_keys_test.dart` を実行すると、全19テスト中、以下の4テストがビープおよびTTSの重複により失敗します。

```text
Step 2 (Start Experience): キー85の連続連打（ダブルクリック等）で多重発話・重複ビープが発生しないこと（再入防止） [E]
  Expected: <1>
    Actual: <2>
  Step 2 開始キーの連打でビープが重複再生されてはならない

Step 3 Part 1 (Enter Mode): キー87の連続連打で多重発話・重複ビープが発生しないこと（再入防止） [E]
  Expected: <1>
    Actual: <2>
  Step 3 突入キー連打でビープが重複再生されてはならない

Step 4 (Weight Adjustment): 決定キー(85)の連続連打で多重発話・重複ビープが発生しないこと（再入防止） [E]
  Expected: <1>
    Actual: <2>
  Step 4 決定キー連打でビープが重複再生されてはならない

Step 5 (Adjustment Completion): 確定キー(87)の連続連打で多重発話・重複ビープが発生しないこと（再入防止） [E]
  Expected: <1>
    Actual: <2>
  Step 5 確定キー連打でビープが重複再生されてはならない
```

---

## 3. コードレベルの根本原因分析 (Root Cause Analysis)

### (1) Step 2 の実行フロー (`_proceedFromStep2`)
`lib/tutorial_screen.dart` の 328〜338行目：
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
1. 1回目の Key 85（再生/停止キー）が到着すると、`_proceedFromStep2()` が呼び出されます。
2. 内部で `await _playBeep()` が実行され、オーディオダッキングの要求や電子音の再生が開始されます（非同期待機に入ります）。
3. この時点で、`_currentStep` は依然として `TutorialStep.step2Start` のままです。
4. ユーザーがイヤホンのボタンを素早く2回押す（またはボタンのチャタリングが発生する）と、2回目の Key 85 が直ちに到着します。
5. ボタン集約ハンドラ `_handleButtonAction` は `_currentStep` を評価しますが、まだ `TutorialStep.step2Start` であるため、再び `_proceedFromStep2()` を呼び出してしまいます。
6. これにより、2つの非同期実行ラインが同時に走り、`beepCount` が 2、`spokenHistory` も 2 件となってテストが失敗します。

### (2) Step 3 Part 1 (`_handleStep3Action`, Key 87)
`lib/tutorial_screen.dart` の 347〜357行目：
```dart
if (_step3Phase == Step3Phase.enterMode) {
  if (action == ButtonAction.mediaNext) {
    await _playBeep();
    await _speak('調整、種目名');
    if (!mounted) return;
    setState(() {
      _step3Phase = Step3Phase.cycleItem;
      _selectedItem = TutorialItem.exerciseName;
    });
    _updateSpotlightRect();
  }
}
```
Key 87（次曲キー）が連打された場合、`await _playBeep()` および `await _speak('調整、種目名')` の完了前に2回目の打鍵が入り、`_step3Phase` がまだ `enterMode` であるため、重複してビープと発話が走ります。

### (3) Step 4 (`_handleStep4Action`, Key 85)
`lib/tutorial_screen.dart` の 410〜422行目：
```dart
} else if (action == ButtonAction.mediaPlayPause) {
  _cancelDebounce();
  await _playBeep();
  await _speak('調整、重量');
  if (!mounted) return;
  setState(() {
    _currentStep = TutorialStep.step5Confirm;
    _warningMessage = null;
  });
  _startGlowIfNeeded();
  _updateSpotlightRect();
}
```
Key 85（決定キー）連打時に、Step 4 に留まったまま `_playBeep()` と `_speak('調整、重量')` が重複実行されます。

### (4) Step 5 (`_handleStep5Action`, Key 87)
`lib/tutorial_screen.dart` の 424〜441行目：
```dart
void _handleStep5Action(ButtonAction action) async {
  if (action == ButtonAction.mediaNext) {
    await _playBeep();
    await _speak(
        '確定、開始、$_currentExercise、${TutorialScreen.formatWeightSpeech(_currentWeight)}、$_currentReps回、$_currentSetsセット');
    if (!mounted) return;
    setState(() {
      _currentStep = TutorialStep.step6Complete;
      _warningMessage = null;
    });
...
```
Key 87（確定キー）連打時に、同様にビープと確定TTSが多重再生されます。また、確定処理中に不正キーが届いた場合に誤って注意メッセージ（`［次の曲へ進む］ボタンを押して調整を完了してください`）を表示してしまう副作用も抱えています。

---

## 4. 改修方式の比較検討 (Design Strategy Evaluation)

| 比較項目 | 方針A: 遷移中ロック＋世代トークン（推奨） | 方針B: 音声再生前の先行同期ステップ更新（非推奨） |
| :--- | :--- | :--- |
| **仕組み** | `_isStepTransitioning = true` で遷移中の再入を即座に破棄。音声終了後に `setState` でステップを前進。 | キー受信直後に `setState(() { _currentStep = nextStep; })` を実行し、その後に音声処理を `await`。 |
| **仕様書適合性** | **完全適合**<br>仕様書・受入基準に明記された「発話終了後に Step X へ遷移すること」を厳密に遵守。 | **違反**<br>発話開始直後に画面が次へ切り替わってしまい、「発話終了後に遷移」という仕様に矛盾。 |
| **UI・音声の一致** | **良好**<br>現在のステップの案内・スポットライトを維持しながら音声を再生し、完了と同時に次ステップの演出へ移る。 | **不自然**<br>画面はすでに次のステップを表示しているのに、耳元では前のステップの開始音声が流れるチグハグな体験となる。 |
| **連打耐性** | **完全**<br>遷移中の2打目以降は即座に破棄（no-op）されるため、ビープ・TTSともに厳密に1回。 | **条件付き**<br>次ステップのコンテキストで2打目が解釈されるため、Step 4連打時にStep 5の注意警告が誤表示される等の副作用がある。 |
| **スキップ割り込み** | **安全（世代トークンで防護）**<br>発話中にユーザーがスキップボタンを押しても、古い非同期処理が新ステップを巻き戻さない。 | **脆弱**<br>非同期処理が残存している場合の後始末が複雑化しやすい。 |

### 結論
**方針A（遷移処理中ロック `_isStepTransitioning` ＋ 世代トークン `_transitionGeneration`）** を採用します。

---

## 5. 詳細設計仕様 (Detailed Technical Specification)

### 5.1 状態変数の追加 (`_TutorialScreenState`)

```dart
/// ステップ遷移（効果音・音声再生から次ステップへの遷移）が進行中かどうか
bool _isStepTransitioning = false;

/// 非同期処理の世代番号（スキップや破棄時の古い非同期コールバックの無効化用）
int _transitionGeneration = 0;
```

### 5.2 ボタン集約ハンドラの先頭ガード

`_handleButtonAction` の先頭で、遷移中フラグをチェックして即時リターンします：

```dart
void _handleButtonAction(ButtonAction action) {
  if (!mounted || _isNavigating || _isStepTransitioning) return;
  ...
```

※ Step 4 の音量増減（±2.5kg）や Step 3 Part 2 の項目巡回など、「ステップ遷移を伴わない操作」は `_isStepTransitioning` をセットしないため、高速連打（10回連続打鍵など）が一切阻害されず軽快に動作します。

### 5.3 各ステップ遷移ハンドラの個別保護

各ステップの遷移処理を独立したメソッドとして整理し、`try ... finally` で排他制御します。

#### (1) Step 2 ➔ Step 3
```dart
Future<void> _proceedFromStep2() async {
  if (_isStepTransitioning) return;
  _isStepTransitioning = true;
  final int gen = ++_transitionGeneration;
  try {
    await _playBeep();
    await _speak('開始、ベンチプレス、60キロ、10回、3セット');
    if (!mounted || _transitionGeneration != gen || _currentStep != TutorialStep.step2Start) {
      return;
    }
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
```

#### (2) Step 3 Part 1 ➔ Step 3 Part 2
```dart
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
        _step3Phase != Step3Phase.enterMode) {
      return;
    }
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
```

#### (3) Step 3 Part 2 ➔ Step 4
```dart
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
        _step3Phase != Step3Phase.cycleItem) {
      return;
    }
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
```

#### (4) Step 4 ➔ Step 5
```dart
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
        _currentStep != TutorialStep.step4Adjust) {
      return;
    }
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
```

#### (5) Step 5 ➔ Step 6
```dart
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
        _currentStep != TutorialStep.step5Confirm) {
      return;
    }
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

### 5.4 スキップ・破棄・画面離脱時のクリーンアップ

#### (1) `_onSkipStepPressed()`
```dart
void _onSkipStepPressed() {
  _transitionGeneration++; // 実行中だった非同期遷移コールバックを無効化
  _isStepTransitioning = false; // 新ステップでの操作入力を直ちに許可
  _cancelDebounce();
  widget.ttsService?.stop();
  _duckingController.releaseDucking(); // ダッキング残留リークを解消
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

#### (2) AppBar 戻るボタンと `PopScope`
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
`Scaffold` 全体を `PopScope` でラップし、端末の戻るジェスチャー等で画面を閉じた場合にも、事後発話のタイマーを即時キャンセルします：
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

#### (3) `dispose()`
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

## 6. 影響範囲とリスク評価 (Blast Radius & Risk Assessment)

1. **既存機能への影響**:
   - `test/tutorial_screen_test.dart`（11テスト）および `test/widget_test.dart`（14テスト）は各キー操作後に `pumpAndSettle()` を呼んでいるため、`_isStepTransitioning` は適切に `false` に戻り、全く影響を受けません。
2. **Step 4 連打デバウンス機能への影響**:
   - 音量UP/DOWNキー（コード24/25）は `_isStepTransitioning` を立てないため、10回高速連打で即座に重量が加算され、停止0.7秒後に1回だけTTSが鳴る機能は完全に保護されます。
3. **発表用緊急スキップ機能への影響**:
   - `_transitionGeneration++` により、音声再生中であってもいつでもスキップボタンで次のステップへ進むことができ、音声完了による巻き戻りも発生しません。

---

## 7. 検証コマンド (Verification Command)

実装完了後は以下のテストを実行し、すべてのテストがパスすることを確認します。

```powershell
flutter test --no-test-assets test/stress_tutorial_keys_test.dart
flutter test --no-test-assets test/stress_tutorial_audio_test.dart
flutter test test/tutorial_screen_test.dart
flutter test test/widget_test.dart
```
全53テストが Exit code 0 で成功することが合格条件です。
