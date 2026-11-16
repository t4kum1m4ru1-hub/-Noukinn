# TutorialScreen ステートマシン＆オーディオ・キーイベント管理設計書

## 1. 概要とアーキテクチャ方針

本ドキュメントは、Flutter製トレーニング支援アプリ「のう筋」の中間発表プレゼン実演に向け、新規画面モジュール `lib/tutorial_screen.dart` におけるステートマシン、キーイベントディスパッチ機構、オーディオ（TTS・電子音・BGMダッキング）制御、および0.7秒デバウンスタイマー管理の完全な実装設計を定義する。

### 1.1 基本設計思想
1. **独立性と安全性の保証**: 既存の `lib/training_screen.dart` は一切変更せず、独立した `lib/tutorial_screen.dart` として実装する。
2. **多重入力経路の単一パイプライン化**:
   - Android 実機 / ADB からの `KeyEventChannelDispatcher` (MethodChannel)
   - PC / エミュレータからの `Focus` キーボード入力 (`KeyDownEvent`)
   - 画面最下部の疑似メディアキーバー（タップ操作）
   これら3つの入力経路をすべて単一の `_handleButtonAction(ButtonAction action)` メソッドに集約する。
3. **音声排他制御とダッキング徹底**:
   新規TTS発話の開始前には必ず `await ttsService?.stop()` を呼び出し、音声の重なりを物理的に防止する。また、発話および電子音再生時には `AudioDuckingController` のリクエスト/リリースを確実に適用する。
4. **テスト容易性と非同期タイマー安全性**:
   0.7秒デバウンスタイマー稼働中は `SchedulerBinding.instance.scheduleFrame()` を周期的に発行し、Widgetテストでの `pumpAndSettle()` がタイマー未消化例外を起こさずに安全に進行できる設計とする。また、ステップ遷移時および画面破棄時には即座に未完了タイマーを破棄する。

---

## 2. 状態モデル定義（Enum & State 変数）

### 2.1 Enum 定義

```dart
/// チュートリアルの全6ステップ
enum TutorialStep {
  /// Step 1: 初期案内画面（チュートリアル趣旨説明・開始/スキップボタン）
  step1Intro,

  /// Step 2: 開始操作体験（暗転＋開始ボタンスポットライト＋イヤホン再生ボタン）
  step2Start,

  /// Step 3: 調整モード突入＆項目選択（Part 1: 突入 / Part 2: 項目送り・決定）
  step3Select,

  /// Step 4: 重量調整とデバウンス体験（重量カードスポットライト＋Vol±で±2.5kg＋0.7sデバウンス）
  step4Adjust,

  /// Step 5: 調整完了の体験（全体暗転＋次曲キーで確定）
  step5Confirm,

  /// Step 6: 完了と本編スタート（暗転解除＋祝福表示＋本編遷移）
  step6Complete,
}

/// Step 3 内のサブフェーズ
enum Step3Phase {
  /// Part 1: 次曲キー（87）による調整モード突入待ち
  enterMode,

  /// Part 2: 音量キー（24/25）による項目巡回と再生キー（85）による決定待ち
  cycleItem,
}

/// Step 3 で選択巡回するトレーニング項目
enum TutorialItem {
  exerciseName('種目名'),
  weight('重量'),
  reps('レップ数'),
  sets('セット数');

  final String label;
  const TutorialItem(this.label);

  /// 次の項目へ巡回（循環）
  TutorialItem get next {
    switch (this) {
      case TutorialItem.exerciseName:
        return TutorialItem.weight;
      case TutorialItem.weight:
        return TutorialItem.reps;
      case TutorialItem.reps:
        return TutorialItem.sets;
      case TutorialItem.sets:
        return TutorialItem.exerciseName;
    }
  }

  /// 前の項目へ巡回（逆循環）
  TutorialItem get previous {
    switch (this) {
      case TutorialItem.exerciseName:
        return TutorialItem.sets;
      case TutorialItem.weight:
        return TutorialItem.exerciseName;
      case TutorialItem.reps:
        return TutorialItem.weight;
      case TutorialItem.sets:
        return TutorialItem.reps;
    }
  }
}
```

### 2.2 TutorialScreen の主要な State 変数

| 変数名 | 型 | 初期値 | 責務 / 説明 |
|---|---|---|---|
| `_currentStep` | `TutorialStep` | `TutorialStep.step1Intro` | 現在進行中のステップ番号 |
| `_step3Phase` | `Step3Phase` | `Step3Phase.enterMode` | Step 3 におけるサブフェーズ状態 |
| `_selectedItem` | `TutorialItem` | `TutorialItem.exerciseName` | Step 3 で現在フォーカスされている項目 |
| `_currentWeight` | `double` | `60.0` | 画面表示・調整対象の重量（kg） |
| `_currentReps` | `int` | `10` | 画面表示用のレップ数 |
| `_currentSets` | `int` | `3` | 画面表示用のセット数 |
| `_currentExercise` | `String` | `'ベンチプレス'` | 種目名 |
| `_debounceTimer` | `Timer?` | `null` | Step 4 の 0.7 秒デバウンス待機用タイマー |
| `_framePumpTimer` | `Timer?` | `null` | Widget テストの `pumpAndSettle` 同期用タイマー |
| `_warningMessage` | `String?` | `null` | Step 5 等で対象外キー押下時に表示する注意案内文 |
| `_isNavigating` | `bool` | `false` | 本編遷移処理の重複呼び出し防止ガード |

---

## 3. ライフサイクルとリスナー管理

### 3.1 KeyEventChannelDispatcher のライフサイクル
`lib/main.dart` の `KeyEventChannelDispatcher` は、登録されたリスナーリストの末尾（最前面のアクティブ画面）にキーイベントを配信する。

- **`initState()`**:
  1. `widget.ttsService?.initialize()` を実行。
  2. `KeyEventChannelDispatcher.instance.registerListener(_handleButtonAction)` を呼び出して登録。
  3. グローアニメーションコントローラおよび `FocusNode` を初期化。
- **`dispose()`**:
  1. `KeyEventChannelDispatcher.instance.unregisterListener(_handleButtonAction)` で登録解除。
  2. デバウンスタイマーをキャンセル（`_cancelDebounce()`）。
  3. `_glowController.dispose()` と `_focusNode.dispose()` を実行。
  4. `widget.ttsService?.stop()` を呼び出し、進行中の音声を停止するとともにダッキングを解除。

### 3.2 コードパターン

```dart
@override
void initState() {
  super.initState();
  widget.ttsService?.initialize();
  KeyEventChannelDispatcher.instance.registerListener(_handleButtonAction);
  _focusNode.requestFocus();

  _glowController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );
  if (widget.animateGlow) {
    _glowController.repeat(reverse: true);
  } else {
    _glowController.value = 1.0;
  }
}

@override
void dispose() {
  KeyEventChannelDispatcher.instance.unregisterListener(_handleButtonAction);
  _cancelDebounce();
  _glowController.dispose();
  _focusNode.dispose();
  widget.ttsService?.stop();
  widget.duckingController?.releaseDucking();
  super.dispose();
}
```

---

## 4. オーディオ発話・ダッキング制御設計

### 4.1 発話排他制御メソッド `_speak(String text)`
要件 R2 および Acceptance Criteria に従い、新しい発話を開始する直前に必ず `widget.ttsService?.stop()` を実行する。これにより、前の音声との重複を防止し、`FakeTtsService` の `stopCallCount` も適切に更新される。

```dart
Future<void> _speak(String text) async {
  try {
    await widget.duckingController?.requestDucking();
    await widget.ttsService?.stop();
    await widget.ttsService?.speak(text);
  } catch (e) {
    debugPrint('TutorialScreen._speak error: $e');
  }
}
```

### 4.2 効果音再生
電子音再生は `widget.soundEffectService?.playBeep()` を使用する。`PlatformSoundEffectService` は内部で自動的に `duckingController?.requestDucking()` を呼び出し、短時間で復帰する。

---

## 5. ステップ別キーイベント処理と状態遷移マトリクス

全ステップにおけるキー操作体系の一覧表：

| ステップ | ［再生/停止］ (85, 79) | ［次の曲へ］ (87) | ［前の曲へ］ (88) | ［音量 UP］ (24) | ［音量 DOWN］ (25) | スキップ操作 (画面/ボタン) |
|---|---|---|---|---|---|---|
| **Step 1: 開始画面** | Step 2 へ進む | 無視 | 無視 | 無視 | 無視 | メイン: Step 2 へ<br>サブ: TrainingScreen へ直行 |
| **Step 2: 開始操作** | 電子音 ＋ TTS「開始、ベンチプレス、60キロ、10回、3セット」 ➔ Step 3 へ自動遷移 | 無視 | 無視 | 無視 | 無視 | 85押下と同一の挙動で Step 3 へ遷移 |
| **Step 3 Part 1: 突入** | 無視 | 電子音 ＋ TTS「調整、種目名」 ➔ Part 2 へ遷移 | TTS「ベンチプレス、60キロ、10回、3セット」 | 無視 | 無視 | Part 2（またはStep 4）へ進行 |
| **Step 3 Part 2: 選択** | 電子音 ＋ TTS「60キロ」 ➔ Step 4 へ遷移 | 無視 | TTS「ベンチプレス、60キロ、10回、3セット」 | 電子音 ＋ 項目次へ ＋ 項目名TTS | 電子音 ＋ 項目前へ ＋ 項目名TTS | Step 4 へ進行 |
| **Step 4: 重量調整** | タイマー破棄 ＋ 電子音 ＋ TTS「調整、重量」 ➔ Step 5 へ遷移 | 無視 | TTS「ベンチプレス、XXキロ、10回、3セット」 | 電子音 ＋ 重量+2.5kg ＋ 0.7sデバウンスTTS | 電子音 ＋ 重量-2.5kg ＋ 0.7sデバウンスTTS | タイマー破棄 ➔ Step 5 へ進行 |
| **Step 5: 調整完了** | 注意案内文を表示（遷移なし） | 電子音 ＋ TTS「確定、開始、ベンチプレス、XXキロ、10回、3セット」 ➔ Step 6 へ自動遷移 | 注意案内文を表示（遷移なし） | 注意案内文を表示（遷移なし） | 注意案内文を表示（遷移なし） | Step 6 へ進行 |
| **Step 6: 完了** | 本編 TrainingScreen へ遷移 | 無視 | 無視 | 無視 | 無視 | メインボタンタップで TrainingScreen へ遷移 |

---

## 6. 詳細ステップ遷移ロジック

### 6.1 Step 1 ➔ Step 2
- **トリガー**: 「チュートリアルを開始する」ボタン（`Key('btn_tutorial_start')`）タップ、またはキー 85/79。
- **処理**:
  `setState(() { _currentStep = TutorialStep.step2Start; });`
- **スキップ**: 「スキップして直接トレーニングへ」ボタン（`Key('btn_tutorial_skip_all')`）タップにより、直ちに `_navigateToTrainingScreen()` を呼び出す。

### 6.2 Step 2 ➔ Step 3（自動遷移）
- **トリガー**: キー 85/79、中央「開始」ボタンタップ、または右下「スキップ」ボタンタップ。
- **処理シーケンス**:
  1. `await widget.soundEffectService?.playBeep();`
  2. `await _speak('開始、ベンチプレス、60キロ、10回、3セット');`
  3. `setState(() { _currentStep = TutorialStep.step3Select; _step3Phase = Step3Phase.enterMode; });`
- **他キーの挙動**: キー 87, 88, 24, 25 の入力は完全に無視する。

### 6.3 Step 3 Part 1 ➔ Part 2
- **トリガー**: キー 87（次曲）、または右下スキップボタン。
- **処理シーケンス**:
  1. `await widget.soundEffectService?.playBeep();`
  2. `await _speak('調整、種目名');`
  3. `setState(() { _step3Phase = Step3Phase.cycleItem; _selectedItem = TutorialItem.exerciseName; });`

### 6.4 Step 3 Part 2（項目巡回 ➔ Step 4 遷移）
- **項目送り（キー 24 / 25）**:
  1. `await widget.soundEffectService?.playBeep();`
  2. `_selectedItem` を前後に更新。
  3. `await _speak(_selectedItem.label);`（例: 「重量」「レップ数」「セット数」「種目名」）
  4. `setState(() {});`
- **内容確認（キー 88）**:
  `await _speak('ベンチプレス、${formatWeightNumber(_currentWeight)}キロ、10回、3セット');`
- **決定（キー 85 / 79）**:
  1. `await widget.soundEffectService?.playBeep();`
  2. `await _speak('${formatWeightNumber(_currentWeight)}キロ');`（例: 「60キロ」）
  3. `setState(() { _currentStep = TutorialStep.step4Adjust; });`

### 6.5 Step 4（重量調整と 0.7 秒デバウンス ➔ Step 5 遷移）
- **重量変更（キー 24 / 25）**:
  1. `await widget.soundEffectService?.playBeep();`
  2. `_currentWeight` を ±2.5kg 加減算（0.0kg〜500.0kg にクランプ）。
  3. `setState(() {});` により画面数値を即時更新。
  4. デバウンスタイマーをリセットし、0.7 秒後に発話予約:
     ```dart
     _startWeightDebounce(() => '${formatWeightNumber(_currentWeight)}キロ');
     ```
- **決定（キー 85 / 79）**:
  1. `_cancelDebounce();`（保留中の発話を即座に破棄）
  2. `await widget.soundEffectService?.playBeep();`
  3. `await _speak('調整、重量');`
  4. `setState(() { _currentStep = TutorialStep.step5Confirm; });`

### 6.6 Step 5 ➔ Step 6
- **トリガー**: キー 87（次曲）、または右下スキップボタン。
- **処理シーケンス**:
  1. `await widget.soundEffectService?.playBeep();`
  2. `await _speak('確定、開始、ベンチプレス、${formatWeightNumber(_currentWeight)}キロ、10回、3セット');`
  3. `setState(() { _currentStep = TutorialStep.step6Complete; });`
- **対象外キー押下（キー 85, 88, 24, 25）**:
  状態遷移を行わず、画面上に注意文言「［次の曲へ進む］ボタンを押して調整を完了してください」を表示する。

### 6.7 Step 6 ➔ TrainingScreen 本編遷移
- **トリガー**: キー 85/79、または「最初のトレーニングを開始する」ボタン（`Key('btn_start_first_training')`）タップ。
- **処理**:
  ```dart
  void _navigateToTrainingScreen() {
    if (!mounted || _isNavigating) return;
    _isNavigating = true;
    _cancelDebounce();
    widget.ttsService?.stop();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) => TrainingScreen(
          ttsService: widget.ttsService,
          soundEffectService: widget.soundEffectService,
        ),
      ),
    );
  }
  ```

---

## 7. 0.7 秒デバウンスタイマーの実装詳細

```dart
Timer? _debounceTimer;
Timer? _framePumpTimer;

void _startWeightDebounce(String Function() speechBuilder) {
  _cancelDebounce();
  _debounceTimer = Timer(const Duration(milliseconds: 700), () {
    _cancelDebounce();
    _speak(speechBuilder());
  });

  // Widget テストで pumpAndSettle() を実行した場合でも
  // デバウンス完了までフレームを進行させ、タイマー残存エラーを防ぐ
  _framePumpTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
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

void _cancelDebounce() {
  _debounceTimer?.cancel();
  _debounceTimer = null;
  _framePumpTimer?.cancel();
  _framePumpTimer = null;
}
```

---

## 8. Worker 向け実装チェックリスト＆ガイドライン

1. **クラス定義**:
   `TutorialScreen` のコンストラクタ引数に `TtsService? ttsService`, `SoundEffectService? soundEffectService`, `AudioDuckingController? duckingController`, `bool animateGlow = true` を定義すること。
2. **重量フォーマット関数**:
   整数の場合は小数点なし、端数がある場合は小数第1位で出力する静的ヘルパー `TutorialScreen.formatWeightNumber(double val)` を提供すること。
3. **スポットライト・オーバーレイ描画**:
   `targetRect` が与えられた場合は `Path.combine(PathOperation.difference, ...)` でくり抜き、`null` の場合は全画面を暗転描画する `SpotlightOverlayPainter` を使用すること。
4. **ホタル発光枠線**:
   `widget.animateGlow` が true の場合のみリピート再生し、false の場合は静止状態とすること。
5. **テスト用 Key 命名**:
   - Step 1: `btn_tutorial_start`, `btn_tutorial_skip_all`
   - Step 2: `btn_tutorial_action`
   - Step 6: `btn_start_first_training`
   - 共通スキップ: `btn_tutorial_skip`
   - 疑似キーバー: `virtual_key_prev`, `virtual_key_play_pause`, `virtual_key_next`, `virtual_key_vol_down`, `virtual_key_vol_up`
   - メイン画面のエントリーボタン: `start_tutorial_button`
