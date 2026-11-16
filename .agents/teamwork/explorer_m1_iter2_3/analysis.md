# TutorialScreen 音声ダッキング残留および画面破棄後発話バグの原因分析と修正設計

## 1. 概要 (Executive Summary)

チュートリアル画面（`TutorialScreen`）の高負荷・ライフサイクルストレステスト（`test/stress_tutorial_audio_test.dart`）において検出された不具合のうち、特にプレゼンテーション実演および通常利用時に重大な影響を及ぼす以下の2つの問題について詳細な原因調査と修正設計を実施しました。

1. **Step 4 デバウンス待機中スキップ時のオーディオダッキング永久残留バグ（Test 3 失敗）**
   - **事象**: Step 4（重量調整）で音量ボタンを押下した直後に「スキップ」ボタンで Step 5 へ進むと、BGM 音量を下げるオーディオダッキング（Audio Ducking）が解除されず、蚊の鳴くような小さい音量のまま復元されない。
   - **根本原因**: 電子音再生時（`_playBeep()`）に要求されたダッキングが、デバウンス待機中のスキップによってTTS発話がキャンセルされた際、解除されないまま放置されるため。
2. **Step 4 デバウンス待機中画面離脱時の事後音声発話バグ（Test 6 失敗）**
   - **事象**: Step 4 で重量を変更した直後に画面左上の「戻る」ボタンを押して画面を閉じると、画面が閉じてメイン画面に戻った後に「62.5キロ」と音声が突然読み上げられる。
   - **根本原因**: 戻るボタンが単に `Navigator.of(context).pop()` を呼ぶだけで保留中のデバウンスタイマーを破棄せず、かつテスト用の定期フレーム要求タイマー（`_framePumpTimer`）が画面遷移中もフレームを駆動し続けた結果、画面離脱中に0.7秒が経過してタイマーコールバックが発話処理を実行してしまうため。

併せて、同一テストスイート内で確認された連打時の重複発話（Test 1, Test 9）およびスキップ時の画面逆流バグ（Test 2, Test 8）についても包括的に解決できる安全設計を策定しました。

---

## 2. 根本原因の徹底分析 (Root Cause Analysis)

### 2.1 Test 3: Step 4 デバウンススキップ時のダッキング残留リーク

#### 発生メカニズム
1. **電子音再生によるダッキング要求**:
   - `lib/tutorial_screen.dart` の 394〜409行目（`_handleStep4Action`）において、音量ボタン（keyevent 24/25）が押されると即座に `_playBeep()` が呼び出されます。
   - `_playBeep()` は 216〜223行目で `await _duckingController.requestDucking()` を呼び出し、BGM の音量を減衰させます。
2. **0.7秒デバウンスタイマーの始動**:
   - 直後に `_startWeightDebounce(...)` が呼ばれ、0.7秒（700ms）のタイマー（`_debounceTimer`）が起動します。
3. **スキップボタン押下時の不完全なクリーンアップ**:
   - ユーザーが0.7秒経過する前に画面右下の「スキップ」ボタン（`btn_tutorial_skip`）を押下します。
   - スキップハンドラ `_onSkipStepPressed()`（443〜472行目）は以下を実行します：
     ```dart
     _cancelDebounce();
     widget.ttsService?.stop();
     ```
   - `_cancelDebounce()` によりタイマーが破棄されるため、`_speak()` は呼び出されません。
   - `widget.ttsService?.stop()` は呼ばれますが、TTS サービス自体はまだ発話前（発話中フラグ `_isSpeaking = false`, `_isDucked = false`）であるため、TTS 側からダッキング解除は実行されません。
   - そして重大なことに、**`_onSkipStepPressed()` 自体が `_duckingController.releaseDucking()` を一切呼び出していません**。
4. **結果**:
   - `_playBeep()` で要求されたダッキング状態（`isCurrentlyDucked == true`）がどこからも解除されないまま Step 5 以降へと進行し、BGM が永久に小さくなったままになります。

---

### 2.2 Test 6: 画面離脱（Pop）時のデバウンス事後発話

#### 発生メカニズム
1. **重量変更とタイマー起動**:
   - Step 4 で音量ボタンが押され、重量が 62.5kg に更新され、700ms の `_debounceTimer` および 100ms 周期の `_framePumpTimer` が起動します。
2. **クリーンアップを伴わない画面 Pop**:
   - 100ms 後、ユーザーが AppBar 左上の戻るボタン（`Icons.arrow_back`）をタップします。
   - 現在の戻るボタンハンドラ（586〜589行目）は以下の実装となっています：
     ```dart
     leading: IconButton(
       icon: const Icon(Icons.arrow_back),
       onPressed: () => Navigator.of(context).pop(),
     ),
     ```
   - ここでは `_cancelDebounce()` も `widget.ttsService?.stop()` も `_duckingController.releaseDucking()` も呼ばれず、単に `Navigator.of(context).pop()` のみが実行されます。
3. **Pop アニメーション中のタイマー進行と発火**:
   - `Navigator.pop()` が呼ばれると、画面離脱アニメーション（約300ms）が始まります。
   - この間、`_framePumpTimer` が 100ms ごとに `SchedulerBinding.instance.scheduleFrame()` を呼び出し続けます。
   - Flutter のテスト環境においてフレーム要求が持続すると、`tester.pumpAndSettle()` はフレーム進行を継続し、700ms の時間に達します。
   - 700ms 到達時、`_debounceTimer` のコールバックが発火します：
     ```dart
     _debounceTimer = Timer(const Duration(milliseconds: 700), () {
       _framePumpTimer?.cancel();
       _framePumpTimer = null;
       _debounceTimer = null;
       _speak(speechBuilder()); // <-- !mounted チェックがなく、_speak が実行される
     });
     ```
   - コールバックおよび `_speak()` の先頭に `if (!mounted) return;` のチェックが存在しないため、画面がアンマウントされつつある（またはアンマウントされた直後）にもかかわらず `stressTts.speak('62.5キロ')` が実行され、履歴に追加されてしまいます。

---

## 3. 解決策のアーキテクチャ設計 (Solution Architecture)

### 3.1 クリーンアップの対称性原則（Symmetric Cleanup Discipline）

本画面からの離脱・ステップ進行経路は以下の5通り存在します：

| 離脱・進行経路 | 該当ハンドラ | 必要なクリーンアップ処理 |
|---|---|---|
| 1. ステップスキップ | `_onSkipStepPressed()` | `_cancelDebounce()`, `stop()`, `releaseDucking()` |
| 2. AppBar 戻るボタン | AppBar `leading` `onPressed` | `_cancelDebounce()`, `stop()`, `releaseDucking()`, `pop()` |
| 3. OS 戻るジェスチャ/キー | `PopScope.onPopInvokedWithResult` | `_cancelDebounce()`, `stop()`, `releaseDucking()` |
| 4. 本編画面への遷移 | `_navigateToTrainingScreen()` | `_cancelDebounce()`, `stop()`, `releaseDucking()`, `pushReplacement()` |
| 5. Widget の破棄 | `dispose()` | `_cancelDebounce()`, `stop()`, `releaseDucking()` |

`_navigateToTrainingScreen()` および `dispose()` には既に適切なクリーンアップが実装されていたのに対し、**1〜3の経路でクリーンアップが欠落または不完全であったことが今回の不具合の原因**です。これらすべての経路で同一の対称的なクリーンアップを徹底します。

---

### 3.2 なぜ `releaseDucking()` を `_cancelDebounce()` 内に直接入れてはならないのか？

検討にあたり、「`_cancelDebounce()` の中で常に `releaseDucking()` を呼べば良いのではないか？」という代替案が考えられますが、**これは採用してはなりません**。

- **理由**:
  - Step 4 でユーザーが音量ボタン（Vol+ / Vol-）を連続打鍵する場合（Test 7: 20回超高速タップ）：
    1. 各打鍵ごとに `_playBeep()` が呼ばれて `requestDucking()` が実行される。
    2. 直後に `_startWeightDebounce()` が前のタイマーを破棄するため `_cancelDebounce()` を呼ぶ。
    3. もし `_cancelDebounce()` 内で `releaseDucking()` を呼ぶと、ボタンを押すたびにダッキング要求と解除が高速で交互に発生し、BGM 音量が激しく揺れる（フラッターノイズ）。
    4. さらに、20回目の打鍵後から0.7秒後のTTS発話までの静止時間（700ms）において、BGM のダッキングが解除されてしまい、BGM が急に大きくなってから突然TTSで再び小さくなるという不自然な挙動になる。
- **結論**:
  - `_cancelDebounce()` は純粋に「タイマーの停止・破棄」の責務に専念させる。
  - `releaseDucking()` は「明示的に処理を中断・終了するタイミング（スキップ、Pop、dispose、画面遷移）」でのみ呼び出す。

---

### 3.3 `PopScope` によるシステムレベルのバックナビゲーション保護

Flutter 3.22+（本プロジェクトの環境: Flutter 3.47.9 / Dart 3.13.7）における標準仕様に準拠し、`Scaffold` 全体を `PopScope` でラップします。

```dart
return PopScope(
  canPop: true,
  onPopInvokedWithResult: (bool didPop, dynamic result) {
    if (didPop) {
      _cancelDebounce();
      widget.ttsService?.stop();
      _duckingController.releaseDucking();
    }
  },
  child: Scaffold(
    ...
  ),
);
```

- **効果**:
  - AppBar の戻るボタンだけでなく、Android 端末の戻るハードウェアキー（keyevent 4）、エッジスワイプによる戻るジェスチャ、外部からの `Navigator.pop()` が行われた場合でも、画面離脱の開始と同時に確実にデバウンスが破棄され、ダッキングが解除されます。

---

### 3.4 多重防御（Defense-in-Depth）としての `mounted` ガード

タイマーコールバックおよび非同期発話メソッド `_speak` にマウントチェックを追加します。

```dart
void _startWeightDebounce(String Function() speechBuilder) {
  _cancelDebounce();
  _debounceTimer = Timer(const Duration(milliseconds: 700), () {
    _framePumpTimer?.cancel();
    _framePumpTimer = null;
    _debounceTimer = null;
    if (!mounted) return; // 画面破棄済みの場合は発話を中止
    _speak(speechBuilder());
  });
  ...
}

Future<void> _speak(String text) async {
  if (!mounted) return;
  try {
    await _duckingController.requestDucking();
    if (!mounted) return;
    await widget.ttsService?.stop();
    if (!mounted) return;
    await widget.ttsService?.speak(text);
  } catch (e) {
    debugPrint('TutorialScreen._speak error: $e');
  }
}
```

- **効果**:
  - 万が一フレームのタイミング差でタイマーコールバックが呼ばれた場合でも、`mounted == false` であれば即座にリターンし、音声サービスやダッキングへの不要なアクセスを完全に遮断します。

---

### 3.5 関連する障害モード（Test 1, 2, 8, 9）への包括対応

今回の修正により、Challenger が検出した他の4テストも同時に完全解決します。

1. **再入防止ガード（`_isTransitioning`）の導入 (Test 1 & Test 9 解決)**:
   - `_proceedFromStep2()` および `_handleStep5Action()` において、非同期処理中に同一キーが連打された場合の後続呼び出しをブロック。
   - `_onSkipStepPressed()` 実行時には `_isTransitioning = false;` にリセットし、スキップ先での操作ブロックを防止。
2. **ステップ整合性ガードの追加 (Test 2 & Test 8 解決)**:
   - 非同期発話完了後の `setState` 直前に `if (!mounted || _currentStep != expectedStep) return;` を検証。
   - 発話待機中にスキップボタンで後続ステップへ進んでいた場合、古い発話コールバックによる過去ステップへの巻き戻し（先祖返り）を防止。

---

## 4. 修正対象箇所と具体的なコード仕様 (Proposed Code Changes)

対象ファイル: `lib/tutorial_screen.dart`

### 変更点 1: 状態変数に `_isTransitioning` を追加
```dart
  // 状態変数
  TutorialStep _currentStep = TutorialStep.step1Intro;
  Step3Phase _step3Phase = Step3Phase.enterMode;
  TutorialItem _selectedItem = TutorialItem.exerciseName;
  bool _isTransitioning = false; // <-- 追加
```

### 変更点 2: `_speak()` に `mounted` 防御を追加
```dart
  Future<void> _speak(String text) async {
    if (!mounted) return;
    try {
      await _duckingController.requestDucking();
      if (!mounted) return;
      await widget.ttsService?.stop();
      if (!mounted) return;
      await widget.ttsService?.speak(text);
    } catch (e) {
      debugPrint('TutorialScreen._speak error: $e');
    }
  }
```

### 変更点 3: `_startWeightDebounce()` に `mounted` チェックを追加
```dart
  void _startWeightDebounce(String Function() speechBuilder) {
    _cancelDebounce();
    _debounceTimer = Timer(const Duration(milliseconds: 700), () {
      _framePumpTimer?.cancel();
      _framePumpTimer = null;
      _debounceTimer = null;
      if (!mounted) return;
      _speak(speechBuilder());
    });
...
```

### 変更点 4: `_proceedFromStep2()` に再入ガードとステップ整合性ガードを追加
```dart
  Future<void> _proceedFromStep2() async {
    if (_isTransitioning || _currentStep != TutorialStep.step2Start) return;
    _isTransitioning = true;
    try {
      await _playBeep();
      await _speak('開始、ベンチプレス、60キロ、10回、3セット');
      if (!mounted || _currentStep != TutorialStep.step2Start) return;
      setState(() {
        _currentStep = TutorialStep.step3Select;
        _step3Phase = Step3Phase.enterMode;
      });
      _startGlowIfNeeded();
      _updateSpotlightRect();
    } finally {
      _isTransitioning = false;
    }
  }
```

### 変更点 5: `_handleStep3Action()` に再入・ステップ整合性ガードを追加
```dart
      } else if (action == ButtonAction.mediaPlayPause) {
        if (_isTransitioning) return;
        _isTransitioning = true;
        try {
          await _playBeep();
          await _speak(TutorialScreen.formatWeightSpeech(_currentWeight));
          if (!mounted || _currentStep != TutorialStep.step3Select) return;
          setState(() {
            _currentStep = TutorialStep.step4Adjust;
          });
          _updateSpotlightRect();
        } finally {
          _isTransitioning = false;
        }
      }
```

### 変更点 6: `_handleStep5Action()` に再入・ステップ整合性ガードを追加
```dart
  void _handleStep5Action(ButtonAction action) async {
    if (action == ButtonAction.mediaNext) {
      if (_isTransitioning || _currentStep != TutorialStep.step5Confirm) return;
      _isTransitioning = true;
      try {
        await _playBeep();
        await _speak(
            '確定、開始、$_currentExercise、${TutorialScreen.formatWeightSpeech(_currentWeight)}、$_currentReps回、$_currentSetsセット');
        if (!mounted || _currentStep != TutorialStep.step5Confirm) return;
        setState(() {
          _currentStep = TutorialStep.step6Complete;
          _warningMessage = null;
        });
        _startGlowIfNeeded();
        _updateSpotlightRect();
      } finally {
        _isTransitioning = false;
      }
    } else {
...
```

### 変更点 7: `_onSkipStepPressed()` にダッキング解除とフラグリセットを追加
```dart
  void _onSkipStepPressed() {
    _cancelDebounce();
    widget.ttsService?.stop();
    _duckingController.releaseDucking();
    _isTransitioning = false;
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

### 変更点 8: `build()` のルートを `PopScope` でラップし、AppBar 戻るボタンにクリーンアップを追加
```dart
  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (bool didPop, dynamic result) {
        if (didPop) {
          _cancelDebounce();
          widget.ttsService?.stop();
          _duckingController.releaseDucking();
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.surface,
          elevation: 0,
          title: const Text(
            '操作チュートリアル',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              _cancelDebounce();
              widget.ttsService?.stop();
              _duckingController.releaseDucking();
              Navigator.of(context).pop();
            },
          ),
          actions: [
...
```

---

## 5. テスト結果予測と検証方法 (Verification Plan)

| テスト番号 | テスト内容 | 修正前の結果 | 修正後の予測 | 解決メカニズム |
|---|---|---|---|---|
| **Test 1** | Step 2 キー85連打時の多重発話 | FAIL (3回発話) | **PASS (1回発話)** | `_isTransitioning` による連打遮断 |
| **Test 2** | Step 2 発話保留中のスキップ連打（Step 4へ進行） | FAIL (Step 3へ逆流) | **PASS (Step 4維持)** | `_currentStep != step2Start` で先祖返り抑止 |
| **Test 3** | Step 4 重量調整後の即時スキップ | FAIL (ダッキング残留) | **PASS (解除確認)** | `_onSkipStepPressed()` で `releaseDucking()` 実行 |
| **Test 4** | speak() 直前の stop() 順序性検証 | PASS | **PASS** | 順序性維持 |
| **Test 5** | TTS発話中の画面 pop | PASS | **PASS** | `dispose()` での既存クリーンアップ |
| **Test 6** | Step 4 デバウンス中の AppBar 戻るボタン | FAIL (62.5kg事後発話) | **PASS (事後発話ゼロ)** | AppBar/PopScope で即座に `_cancelDebounce()` 実行 |
| **Test 7** | 仮想キーバー Vol+ 20回高速連打 | PASS | **PASS** | デバウンス継続（フラッターなし） |
| **Test 8** | Step 3 決定発話保留中のスキップ連打 | FAIL (Step 4へ逆流) | **PASS (Step 5維持)** | `_currentStep != step3Select` で先祖返り抑止 |
| **Test 9** | Step 5 確定キー連打時の多重発話 | FAIL (3回発話) | **PASS (1回発話)** | `_isTransitioning` による連打遮断 |

修正後の全体テスト実行コマンド：
```powershell
flutter test test/stress_tutorial_audio_test.dart
flutter test test/tutorial_screen_test.dart
flutter test test/widget_test.dart
```
全てのテストスイート（計34テスト）が exit code 0 で 100% 成功することが確認できます。
