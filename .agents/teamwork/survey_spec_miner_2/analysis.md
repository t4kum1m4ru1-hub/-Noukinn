# TutorialScreen 仕様調査・詳細仕様書 (analysis.md)

## 概要
本ドキュメントは、Flutter製筋トレ支援アプリ「のう筋」における新規モジュール「操作チュートリアル画面（`TutorialScreen`）」のキーイベント処理体系、全6ステップのステートマシン、音声・効果音・ダッキング連携、デバウンス並行処理、およびUI演出の厳密な仕様分析レポートである。

---

## Features Discovered（発見・策定した機能一覧）

| # | Category | Feature | Description | Inputs | Outputs | Error Behavior | Discovered Via |
|---|----------|---------|-------------|--------|---------|----------------|----------------|
| 1 | Entry & Routing | チュートリアル画面エントリー導線 | `lib/main.dart` の「トレーニング開始」ボタン直下に「操作チュートリアルを体験する」ボタンを新設。タップで `TutorialScreen` へ遷移。 | タップイベント（Key: `btn_open_tutorial`） | `TutorialScreen` へのNavigator遷移 | 遷移不能時はdebugPrint出力 | ORIGINAL_REQUEST R1, `lib/main.dart` |
| 2 | Key Mapping | ［再生/停止］キー (85, 79) | 通常時: 開始/進行。調整時: 決定。Step 2開始、Step 3決定(60キロ)、Step 4決定(調整、重量)、Step 6完了 | keyevent 85, 79, `LogicalKeyboardKey.mediaPlayPause` / `space` | 状態遷移、TTS発話、電子音ビープ | 他ステップでの無効打鍵は無視 | ORIGINAL_REQUEST R3/R5, `TrainingController` |
| 3 | Key Mapping | ［次の曲へ進む］キー (87) | 調整モードのトグル。Step 3前半で調整モード突入、Step 5で調整確定復帰 | keyevent 87, `LogicalKeyboardKey.mediaTrackNext` / `arrowRight` | 状態遷移、TTS発話（「調整、種目名」「確定、開始…」） | Step 5以外での誤打鍵は案内表示または無視 | ORIGINAL_REQUEST R3/R5, `TrainingController` |
| 4 | Key Mapping | ［前の曲へ戻る］キー (88) | 安全ボタン・種目内容の確認読み上げ（全ステップ共通で状態遷移を起こさない） | keyevent 88, `LogicalKeyboardKey.mediaTrackPrevious` / `arrowLeft` | TTS発話（「ベンチプレス、XXkg、10回、3セット」） | 状態破壊なし | ORIGINAL_REQUEST R3, `TrainingController` |
| 5 | Key Mapping | ［音量 UP / DOWN］キー (24, 25) | 項目送り（種目名⇄重量⇄レップ数⇄セット数）および数値増減（±2.5kg） | keyevent 24, 25, `LogicalKeyboardKey.audioVolumeUp` / `audioVolumeDown` / `arrowUp` / `arrowDown` | リアルタイムUI更新、ビープ音、TTS発話 | Step 1, 2, 5, 6 では無効化（誤操作防止） | ORIGINAL_REQUEST R3/R5, `TrainingController` |
| 6 | State Machine | Step 1: 初期案内画面 | チュートリアルの趣旨説明と開始/スキップボタン | 「チュートリアルを開始する」タップ / 85キー / 「スキップ」タップ | Step 2へ遷移 / `TrainingScreen` へ直行 | 不正キーは無視 | ORIGINAL_REQUEST R5 |
| 7 | State Machine | Step 2: 開始操作体験 | 全体暗転＋開始ボタンのみスポットライト＆ホタル発光。85キーで開始 | keyevent 85, 79, 「開始」タップ, スキップタップ | ビープ音＋開始アニメ演出＋暗転解除＋TTS「開始、ベンチプレス、60キロ、10回、3セット」→ Step 3へ自動遷移 | 85以外のキーは完全無視 | ORIGINAL_REQUEST R5 |
| 8 | State Machine | Step 3: 調整突入＆項目選択 | Part 1: 87キーで調整モード突入（「調整、種目名」）。Part 2: 24/25キーで項目送り、85キーで重量決定（「60キロ」）→ Step 4へ遷移。88キーで内容確認 | keyevent 87 (Part 1), keyevent 24/25, 85, 88 (Part 2) | ビープ音、枠線移動、各項目名TTS、値TTS | 対象外キーは無視 | ORIGINAL_REQUEST R5 |
| 9 | State Machine | Step 4: 重量調整＆デバウンス | 重量カードのみスポットライト。24/25キーで即時ビープ＋リアルタイム±2.5kg増減、連打停止0.7秒後にTTS発話。85キーで決定（「調整、重量」）→ Step 5へ遷移 | keyevent 24/25, 85, 88 | リアルタイムUI更新、ビープ音、0.7sデバウンスTTS、85で「調整、重量」 | 最小値0.0kg未満への減算防止（クランプ） | ORIGINAL_REQUEST R5, `TrainingController` |
| 10 | State Machine | Step 5: 調整完了体験 | 全体暗転＋「次曲ボタンを押して完了」案内。87キーでビープ＋「確定」＋「開始、ベンチプレス、65キロ、10回、3セット」→ Step 6へ自動遷移 | keyevent 87, 「次曲」タップ, スキップタップ | ビープ音、TTS発話、Step 6遷移 | 87以外のキー押下時は注意案内メッセージ表示 | ORIGINAL_REQUEST R5 |
| 11 | State Machine | Step 6: 完走と本編遷移 | 暗転解除、祝福タイトル「🎉 チュートリアル完了！」、説明文。「最初のトレーニングを開始する」タップまたは85キーで本編 `TrainingScreen` へ遷移 | 「最初のトレーニングを開始する」タップ, keyevent 85, 79 | `TrainingScreen` へのNavigator遷移 | 二重遷移防止ガード | ORIGINAL_REQUEST R5 |
| 12 | UI & Visual | スポットライト＆暗転 | 注目要素以外を半透明ブラック（Black 70% = `Color(0xB3000000)`）で覆う暗転オーバーレイ | ステップ状態 | 注目カード・ボタンのくり抜き表示 | なし | ORIGINAL_REQUEST R4 |
| 13 | UI & Visual | ホタル発光枠線アニメーション | 注目要素の枠線に呼吸するように滑らかに明滅するグロー効果（`AnimationController` + `boxShadow`） | アニメーションTick (周期約1500ms) | 発光パルス描画（ティールまたはオレンジ） | 破棄時のコントローラー漏れ防止 | ORIGINAL_REQUEST R4 |
| 14 | UI & Visual | スキップ機能＆仮想キーバー | 各ステップの「スキップ」ボタン、および画面最下部の疑似メディアキーバー（前曲、再生停止、次曲、Vol-、Vol+） | ボタンタップ | キーイベント発火または次ステップ進行 | 無効状態時の二重押し防止 | ORIGINAL_REQUEST R4 |
| 15 | Audio & Concurrency | 音声排他制御＆ダッキング | 新規発話前に必ず `flutterTts.stop()` を実行。全TTS・電子音再生時に `AudioDuckingController` 連携 | 発話トリガー | 音声重複の防止、BGM音量減衰と復帰 | 例外発生時は即座にダッキング解除 | ORIGINAL_REQUEST R2, `lib/main.dart` |

---

## Edge Cases（境界値・異常系動作一覧）

| # | Feature | Input / Scenario | Observed / Specified Behavior |
|---|---------|------------------|-------------------------------|
| 1 | Step 2 キー無視 | Step 2 で音量キー (24, 25) や曲送り (87) を押下 | 反応なし（画面・音声ともに変化せず、誤作動を完全に防止）。「［再生/停止］ボタンを押してください」の控えめな補助テキストを維持。 |
| 2 | Step 4 デバウンス中の連打 | Step 4 で音量UP (24) を 0.2秒間隔で5回連続打鍵 | 各打鍵ごとに即時ビープ音が鳴り、画面上の重量表示がリアルタイムに +2.5kg ずつ進む (60.0 -> 72.5kg)。先行するデバウンスタイマーは即時破棄され、最後の打鍵から 0.7秒後に1回だけ最新重量「72.5キロ」が読み上げられる。 |
| 3 | Step 4 デバウンス中の決定押下 | 0.7秒のデバウンスタイマー待機中に、ユーザーが決定（85キー）を押下 | 直ちに保留中のデバウンスタイマーをキャンセル。数値確定処理を行い、即時ビープ音＋「調整、重量」を発話し、Step 5へ遷移（遅延した重量読み上げがStep 5に漏れ出ない）。 |
| 4 | Step 4 最小値ガード | 60.0kg から音量DOWNを連打し 0.0kg に到達 | 0.0kg でクランプされ、それ以下の負の重量には移行しない。 |
| 5 | Step 5 対象外キー押下 | Step 5 で再生ボタン (85) や音量キー (24, 25) を押下 | 状態遷移せず、「［次の曲へ進む］ボタンを押して調整を完了してください」という注意案内文（SnackBarまたはインラインテキスト）を表示。 |
| 6 | スキップ連打 | 各ステップの「スキップ」ボタンをミリ秒単位で連打 | トランジション進行中フラグ（`_isTransitioning`）によりガード。最初の1回のみ受け付け、後続の打鍵は無視して二重遷移やクラッシュを防止。 |
| 7 | 音声再生中の画面破棄 | TTS読み上げ中またはアニメーション中に「戻る」ボタン押下 | `dispose()` で `flutterTts.stop()` を呼び出しダッキングを解除、全てのアニメーションコントローラーとタイマーを破棄。 |
| 8 | ウィジェットテストの pumpAndSettle() | 0.7秒のデバウンスタイマーが稼働中のままテストが `pumpAndSettle()` を実行 | `SchedulerBinding.instance.scheduleFrame()` を伴う定期パルスにより、デバウンスタイマー完了までテストクロックが進行し、未完了タイマー例外（`A Timer is still pending`）を防ぐ。 |

---

## 1. アプリ全体のメディアキー＆ボタン処理構造の分析

### 1.1 既存アーキテクチャの2大経路
`noukin_app` は、実機ネイティブ環境・テスト環境・PCエミュレータ環境のすべてに対応するため、以下の2系統のキーイベント受付経路を併設している：

```
[Android実機] 物理キー押下
      │
      ▼ (dispatchKeyEvent: 85, 79, 24, 25, 87, 88 を横取り & block OS HUD)
MainActivity.kt
      │
      ▼ MethodChannel("com.example.noukin/key_events").invokeMethod("onKeyEvent", keyCode)
KeyEventChannelDispatcher (lib/main.dart)
      │
      ▼ 最前面リスナーへ通知 (List<void Function(ButtonAction action)>)
TrainingScreen / TutorialScreen

-------------------------------------------------------------------------

[PC / エミュレータ / テスト環境]
1) HardwareKeyboard (KeyEvent: space, arrow keys)
      │
      ▼ Focus(onKeyEvent: _handleKeyboardEvent)
2) 疑似メディアキーバー (InkWell タップ)
      │
      ▼ 直接アクションハンドラを呼び出し
TrainingScreen / TutorialScreen
```

### 1.2 キーコードおよびLogicalKeyboardKeyマッピング一覧

| アクション名 (`ButtonAction`) | Android KeyCode | LogicalKeyboardKey | PhysicalKeyboardKey | PCキーボード代替 | チュートリアル内の役割 |
|---|---|---|---|---|---|
| `mediaPlayPause` | 85 (`KEYCODE_MEDIA_PLAY_PAUSE`) | `LogicalKeyboardKey.mediaPlayPause` | `PhysicalKeyboardKey.mediaPlayPause` | `LogicalKeyboardKey.space` | 【開始 / 決定ボタン】Step 2開始、Step 3決定、Step 4決定、Step 6完了 |
| `headsetHook` | 79 (`KEYCODE_HEADSETHOOK`) | `LogicalKeyboardKey.headsetHook` | `PhysicalKeyboardKey.headsetHook` | (同上) | `mediaPlayPause` と同等に扱う |
| `mediaNext` | 87 (`KEYCODE_MEDIA_NEXT`) | `LogicalKeyboardKey.mediaTrackNext` | `PhysicalKeyboardKey.mediaTrackNext` | `LogicalKeyboardKey.arrowRight` | 【調整トグルボタン】Step 3突入、Step 5調整完了 |
| `mediaPrevious` | 88 (`KEYCODE_MEDIA_PREVIOUS`) | `LogicalKeyboardKey.mediaTrackPrevious` | `PhysicalKeyboardKey.mediaTrackPrevious` | `LogicalKeyboardKey.arrowLeft` | 【内容確認安全ボタン】どの状態でも種目サマリー発話（遷移なし） |
| `volumeUp` | 24 (`KEYCODE_VOLUME_UP`) | `LogicalKeyboardKey.audioVolumeUp` | `PhysicalKeyboardKey.audioVolumeUp` | `LogicalKeyboardKey.arrowUp` | 【項目送り / 数値増加】Step 3項目送り、Step 4重量+2.5kg |
| `volumeDown` | 25 (`KEYCODE_VOLUME_DOWN`) | `LogicalKeyboardKey.audioVolumeDown` | `PhysicalKeyboardKey.audioVolumeDown` | `LogicalKeyboardKey.arrowDown` | 【項目送り / 数値減少】Step 3項目送り、Step 4重量-2.5kg |

---

## 2. 全6ステップの完全ステートマシン詳細仕様

### Step 1: 初期案内画面（チュートリアル開始）
- **画面状態**: 暗転オーバーレイなし（全面通常表示）。
- **タイトル**: 「のう筋 操作チュートリアル」
- **説明文**:
  「このチュートリアルでは、スマートフォンを見ずにイヤホンのボタン操作だけでトレーニングを開始・調整・完了する流れを体験できます。」
- **UIボタン**:
  1. メインボタン: 「チュートリアルを開始する」（Key: `btn_tutorial_start`）➔ Step 2 へ遷移
  2. サブボタン: 「スキップして直接トレーニングへ」（Key: `btn_tutorial_skip_all`）➔ `TrainingScreen` へ直行
- **キー受付**:
  - `mediaPlayPause` (85/79): メインボタンと同等に Step 2 へ進む。
  - その他キー: 無視。

### Step 2: 開始操作体験（イヤホン再生ボタン）
- **画面状態**: 全体暗転（Black 70%）。中央の「開始」ボタン（Key: `btn_tutorial_action`）のみスポットライト＆ホタル発光枠線。
- **案内文**: 「イヤホンの［再生/停止］ボタンを押してトレーニングを始めてみましょう」
- **受付キー**:
  - `mediaPlayPause` (85/79) または 画面の「開始」タップ、または「スキップ」ボタン押下。
- **トリガー時の一連の動作**:
  1. 即座に電子音を再生（`soundEffectService.playBeep()`）。
  2. ボタン拡大・縮小パルスのアニメーション演出を実行。
  3. 暗転オーバーレイをフェードアウト。
  4. TTSで次の文字列を発話:
     ```text
     「開始、ベンチプレス、60キロ、10回、3セット」
     ```
  5. 発話開始（または完了）後、Step 3 へ自動遷移。
- **排他制御**:
  - 音量キー (24, 25)、次曲 (87)、前曲 (88) は完全無視。

### Step 3: 調整モード突入＆項目選択
本ステップは、2つのサブフェーズ（Part 1 / Part 2）で構成される。

#### Part 1: 調整モード突入
- **案内文**: 「［次の曲へ進む］ボタンを押して、調整モードに入りましょう」
- **スポットライト**: 最上部の種目名エリア（「ベンチプレス」）またはモードインジケーター。
- **受付キー**:
  - `mediaNext` (87) または 疑似メディアキーバーの［次曲］タップ、または「スキップ」タップ。
- **動作**:
  1. 電子音ビープ再生（`soundEffectService.playBeep()`）。
  2. TTS発話: 「調整、種目名」
  3. 種目名カードにハイライト枠線が点灯。
  4. 自動的に **Part 2** へ進む。

#### Part 2: 項目選択サイクル
- **案内文**: 「［音量＋/−］ボタンで項目を切り替え、［再生/停止］ボタンで決定しましょう」
- **選択対象**: `種目名` ⇄ `重量` ⇄ `レップ数` ⇄ `セット数`（循環）
- **受付キー**:
  - `volumeUp` (24) / `volumeDown` (25):
    - 即座にビープ音再生。
    - 選択枠（スポットライト／ホタル発光）が次の項目へ移動。
    - TTSで選択項目名を単語発話（「重量」「レップ数」「セット数」「種目名」）。
  - `mediaPlayPause` (85/79):
    - 選択中の項目が「重量」の場合（またはチュートリアル誘導により「重量」が選択された状態）:
      - 即座にビープ音再生。
      - TTSで現在値を発話: 「60キロ」
      - **Step 4** へ遷移。
  - `mediaPrevious` (88):
    - 全体サマリー発話: 「ベンチプレス、60キロ、10回、3セット」（ステップ遷移なし）。

### Step 4: 重量調整とデバウンス体験
- **画面状態**: 「重量」カード（初期値: 60.0 kg）のみスポットライト表示＆ホタル発光枠線。他のカードは Black 70% 暗転。
- **案内文**: 「［音量＋/−］ボタンで重量を変更してみましょう（連打すると素早く変更できます）」
- **受付キー**:
  - `volumeUp` (24) / `volumeDown` (25):
    - **即時**: ビープ音再生（`soundEffectService.playBeep()`）。
    - **即時**: 画面の重量数値を ±2.5kg リアルタイム更新（例: 60.0kg ➔ 62.5kg ➔ 65.0kg）。
    - **デバウンス**: 連打停止から **0.7秒（700ms）** 経過後に、変更後の重量をTTS発話（例: 「62.5キロ」「65キロ」）。連打中はタイマーがリセットされ発話が保留される。
  - `mediaPlayPause` (85/79):
    - デバウンスタイマーを即座にキャンセル。
    - 即座にビープ音再生。
    - TTS発話: 「調整、重量」
    - **Step 5** へ遷移。
  - `mediaPrevious` (88):
    - 現在の全サマリー発話（例: 「ベンチプレス、65キロ、10回、3セット」）。
  - スキップボタン:
    - デバウンスタイマーをキャンセルし、重量を確定して Step 5 へ遷移。

### Step 5: 調整完了の体験
- **画面状態**: 全体暗転。案内文が強調表示。
- **案内文**: 「［次の曲へ進む］ボタンを押して、調整を完了しましょう」
- **受付キー**:
  - `mediaNext` (87) または 疑似メディアキーバー［次曲］タップ、スキップタップ。
- **動作**:
  1. 即座にビープ音再生。
  2. TTS発話:
     ```text
     「確定、開始、ベンチプレス、65キロ、10回、3セット」
     （または「確定」発話に続き「開始、ベンチプレス、65キロ、10回、3セット」）
     ```
  3. 発話開始（または完了）後、**Step 6** へ自動遷移。
- **排他制御**:
  - 87以外のキー押下時は、状態遷移せず「［次の曲へ進む］ボタンを押して調整を完了してください」と注意喚起を表示。

### Step 6: 完了と本編スタート
- **画面状態**: 暗転解除（全画面クリア）。
- **タイトル**: 「🎉 チュートリアル完了！」
- **説明文**:
  「お疲れ様でした！イヤホンのボタンだけで、スマホを見ずにトレーニングを開始・調整・確定する操作がマスターできました。」
- **UIボタン**:
  - メインボタン: 「最初のトレーニングを開始する」（Key: `btn_tutorial_complete`）➔ `TrainingScreen` へ遷移。
- **受付キー**:
  - `mediaPlayPause` (85/79): メインボタンと同等に本編 `TrainingScreen` へ遷移。
  - 戻るボタン: メイン画面（`ButtonControlScreen`）へ戻る。

---

## 3. 並行処理・デバウンスタイマー破棄・高速打鍵の安全性仕様

### 3.1 デバウンス制御アルゴリズム
```dart
Timer? _debounceTimer;
Timer? _framePumpTimer;

void adjustWeight(double delta) {
  _soundEffectService.playBeep();
  _currentWeight = (_currentWeight + delta).clamp(0.0, 500.0);
  notifyListeners(); // 画面は即時再描画

  _cancelDebounce();
  _debounceTimer = Timer(const Duration(milliseconds: 700), () {
    _debounceTimer = null;
    _framePumpTimer?.cancel();
    _framePumpTimer = null;
    _speak('${formatWeightNumber(_currentWeight)}キロ');
  });

  // ウィジェットテストの pumpAndSettle() が止まらないよう定期フレームを要求
  _framePumpTimer = Timer.periodic(const Duration(milliseconds: 100), (t) {
    if (_debounceTimer == null || !_debounceTimer!.isActive) {
      t.cancel();
      return;
    }
    try {
      SchedulerBinding.instance.scheduleFrame();
    } catch (_) {}
  });
}

void _cancelDebounce() {
  _debounceTimer?.cancel();
  _debounceTimer = null;
  _framePumpTimer?.cancel();
  _framePumpTimer = null;
}
```

### 3.2 高速ステップ進行時の安全性（Race Condition防止）
1. **画面破棄（dispose）時のリソース解放**:
   - `_cancelDebounce()` の呼び出し
   - `_glowAnimationController.dispose()` の呼び出し
   - `KeyEventChannelDispatcher.instance.unregisterListener(...)` の解除
   - `widget.ttsService.stop()` の呼び出し（ダッキング解除を含む）
2. **ステップ遷移中のリエントラント防止**:
   - `bool _isTransitioning = false` を設け、ステップ移動中は新規キー入力を短時間無視し、二重画面遷移を抑止する。

---

## 4. UI演出とアクセシビリティ仕様

### 4.1 スポットライト＆暗転オーバーレイの実装指針
- 暗転色: `Color(0xB3000000)`（不透明度70%の黒）。
- 構造:
  - 画面全体をスタック構造（`Stack`）とし、下層にコンテンツ、中層に暗転レイヤー、上層にスポットライト対象またはフローティング案内と疑似キーバーを配置する。
  - もしくは、各カード自身が現在ステップに応じて通常色／暗転ディム／ハイライト枠線を切り替える設計。

### 4.2 ホタル発光枠線（Firefly Glowing Border）
- `AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))..repeat(reverse: true)`
- アニメーション値 `t` (0.0 〜 1.0) に基づき、`boxShadow` のぼかし半径および枠線色を補間:
  ```dart
  BoxDecoration(
    borderRadius: BorderRadius.circular(14),
    border: Border.all(
      color: Color.lerp(AppColors.primaryAccent.withOpacity(0.4), AppColors.primaryAccent, t)!,
      width: 2.0,
    ),
    boxShadow: [
      BoxShadow(
        color: AppColors.primaryAccent.withOpacity(0.3 * t + 0.1),
        blurRadius: 10 * t + 4,
        spreadRadius: 2 * t,
      ),
    ],
  )
  ```

---

## 5. 自動テスト（Widget Test）検証手順

### 5.1 シミュレーション手段
1. **MethodChannel ネイティブキー送信**:
   `sendNativeKeyEvent(tester, keyCode)` を用いて Android 側からの 85, 79, 24, 25, 87, 88 をテスト。
2. **ハードウェアキーボードイベント**:
   `await tester.sendKeyEvent(LogicalKeyboardKey.mediaPlayPause)` または `LogicalKeyboardKey.space` 等を送信。
3. **疑似メディアキーバー / 画面ボタンタップ**:
   `await tester.tap(find.byKey(const Key('btn_media_play_pause')))` によるタップ検証。

---

## 結論
本仕様により、中間発表プレゼンで求められる「イヤホンのボタンだけでトレーニングを完結できる」ユーザー体験が、直感的・堅牢・テスト可能に実現される。
