# Handoff Report — TutorialScreen Key Events & 6-Step State Machine Specification

**Agent**: `survey_spec_miner_2` (Specification Miner)  
**Date**: 2026-11-10T10:14:00Z  
**Target Milestone**: TutorialScreen Specification & Key Event Architecture  
**Integrity Mode**: development  

---

## Features Discovered

| # | Category | Feature | Description | Inputs | Outputs | Error Behavior | Discovered Via |
|---|----------|---------|-------------|--------|---------|----------------|----------------|
| 1 | Entry & Routing | チュートリアル画面エントリー導線 | `lib/main.dart` の「トレーニング開始」ボタン直下に「操作チュートリアルを体験する」ボタンを新設。タップで `TutorialScreen` へ遷移。 | タップイベント（Key: `btn_open_tutorial`） | `TutorialScreen` へのNavigator遷移 | 遷移不能時はdebugPrint出力 | ORIGINAL_REQUEST R1, `lib/main.dart` |
| 2 | Key Mapping | ［再生/停止］キー (85, 79) | 通常時: 開始/進行。調整時: 決定。Step 2開始、Step 3決定(60キロ)、Step 4決定(調整、重量)、Step 6完了 | keyevent 85, 79, `LogicalKeyboardKey.mediaPlayPause` / `space` | 状態遷移、TTS発話、電子音ビープ | 他ステップでの無効打鍵は無視 | ORIGINAL_REQUEST R3/R5, `TrainingController` |
| 3 | Key Mapping | ［次の曲へ進む］キー (87) | 調整モードのトグル。Step 3前半で調整モード突入、Step 5で調整確定復帰 | keyevent 87, `LogicalKeyboardKey.mediaTrackNext` / `arrowRight` | 状態遷移、TTS発話（「調整、種目名」「確定、開始…」） | Step 5以外での誤打鍵は案内表示または無視 | ORIGINAL_REQUEST R3/R5, `TrainingController` |
| 4 | Key Mapping | ［前の曲へ戻る］キー (88) | 安全ボタン・種目内容の確認読み上げ（全ステップ共通で状態遷移を起こさない） | keyevent 88, `LogicalKeyboardKey.mediaTrackPrevious` / `arrowLeft` | TTS発話（「ベンチプレス、60kg、10回、3セット」） | 状態破壊なし | ORIGINAL_REQUEST R3, `TrainingController` |
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

## Edge Cases

| # | Feature | Input / Scenario | Observed / Specified Behavior |
|---|---------|------------------|-------------------------------|
| 1 | Step 2 キー無視 | Step 2 で音量キー (24, 25) や曲送り (87) を押下 | 反応なし（画面・音声ともに変化せず、誤作動を完全に防止）。「［再生/停止］ボタンを押してください」の案内を維持。 |
| 2 | Step 4 デバウンス中の連打 | Step 4 で音量UP (24) を 0.2秒間隔で5回連続打鍵 | 各打鍵ごとに即時ビープ音が鳴り、画面上の重量表示がリアルタイムに +2.5kg ずつ進む (60.0 -> 72.5kg)。先行するデバウンスタイマーは即時破棄され、最後の打鍵から 0.7秒後に1回だけ最新重量「72.5キロ」が読み上げられる。 |
| 3 | Step 4 デバウンス中の決定押下 | 0.7秒のデバウンスタイマー待機中に、ユーザーが決定（85キー）を押下 | 直ちに保留中のデバウンスタイマーをキャンセル。数値確定処理を行い、即時ビープ音＋「調整、重量」を発話し、Step 5へ遷移（遅延した重量読み上げがStep 5に漏れ出ない）。 |
| 4 | Step 4 最小値ガード | 60.0kg から音量DOWNを連打し 0.0kg に到達 | 0.0kg でクランプされ、それ以下の負の重量には移行しない。 |
| 5 | Step 5 対象外キー押下 | Step 5 で再生ボタン (85) や音量キー (24, 25) を押下 | 状態遷移せず、「［次の曲へ進む］ボタンを押して調整を完了してください」という注意案内文（SnackBarまたはインラインテキスト）を表示。 |
| 6 | スキップ連打 | 各ステップの「スキップ」ボタンをミリ秒単位で連打 | トランジション進行中フラグ（`_isTransitioning`）によりガード。最初の1回のみ受け付け、後続の打鍵は無視して二重遷移やクラッシュを防止。 |
| 7 | 音声再生中の画面破棄 | TTS読み上げ中またはアニメーション中に「戻る」ボタン押下 | `dispose()` で `flutterTts.stop()` を呼び出しダッキングを解除、全てのアニメーションコントローラーとタイマーを破棄。 |
| 8 | ウィジェットテストの pumpAndSettle() | 0.7秒のデバウンスタイマーが稼働中のままテストが `pumpAndSettle()` を実行 | `SchedulerBinding.instance.scheduleFrame()` を伴う定期パルスにより、デバウンスタイマー完了までテストクロックが進行し、未完了タイマー例外（`A Timer is still pending`）を防ぐ。 |

---

## 1. Observation（直接観察事実）

1. **既存のキーイベントリスナー構造 (`lib/main.dart`, lines 470–524)**:
   - `KeyEventChannelDispatcher` が `MethodChannel("com.example.noukin/key_events")` を購読し、`_listeners` リストの末尾（最前面画面）に `ButtonAction` を配信している。
   - `ButtonAction.fromKeyCode(int keyCode)` は 85 (`mediaPlayPause`), 79 (`headsetHook`), 24 (`volumeUp`), 25 (`volumeDown`), 87 (`mediaNext`), 88 (`mediaPrevious`) の6コードのみをデコードし、その他は厳密に `null` を返す。
2. **Android ネイティブ層 (`android/app/src/main/kotlin/.../MainActivity.kt`, lines 67–78)**:
   - `dispatchKeyEvent` が `TARGET_KEY_CODES`（85, 79, 24, 25, 87, 88）のみを横取りし、`repeatCount == 0 && ACTION_DOWN` 時に `methodChannel?.invokeMethod("onKeyEvent", keyCode)` を送信したうえで `return true` してOS標準HUDを抑止している。
3. **TrainingScreen のキーボード・バー処理 (`lib/training_screen.dart`, lines 91–122, 658–701)**:
   - `Focus` ウィジェットで `onKeyEvent: _handleKeyboardEvent` を持ち、`space` / `mediaPlayPause` ➔ `mediaPlayPause`、`arrowRight` / `mediaTrackNext` ➔ `mediaNext`、`arrowLeft` / `mediaTrackPrevious` ➔ `mediaPrevious`、`arrowUp` / `audioVolumeUp` ➔ `volumeUp`、`arrowDown` / `audioVolumeDown` ➔ `volumeDown` をマッピングしている。
   - 画面最下部に `_buildMediaControlBar()` があり、`btn_media_prev`, `btn_media_play_pause`, `btn_media_next`, `btn_media_vol_down`, `btn_media_vol_up` の疑似ボタンを配置している。
4. **音声・効果音・ダッキング (`lib/main.dart`, lines 60–361)**:
   - `AudioDuckingController`（`AudioSessionDuckingController` / `FakeAudioDuckingController`）
   - `SoundEffectService`（`PlatformSoundEffectService` / `FakeSoundEffectService`）
   - `TtsService`（`FlutterTtsService` / `FakeTtsService`）
   - `FlutterTtsService.speak()` は内部で `_flutterTts.stop()` を実行してから `_requestDucking()` ➔ `_flutterTts.speak()` を呼ぶ設計となっている。
5. **テスト実行結果 (`flutter test`)**:
   - 既存14テストが exit code 0 でパス（所要時間約4秒）。

---

## 2. Logic Chain（推論プロセス）

1. **TutorialScreen の独立モジュール性**:
   - 要件 R1 より、既存の `lib/training_screen.dart` を改変することは厳禁とされている。したがって、新規ファイル `lib/tutorial_screen.dart` を作成し、独立した `StatefulWidget` として実装する必要がある。
2. **二重キー受付機構の継承**:
   - `TrainingScreen` と同様に、実機デモ（イヤホンボタン／ADB input keyevent）では `KeyEventChannelDispatcher` からの `ButtonAction` を受信し、PCエミュレータ・ウィジェットテストでは `Focus(onKeyEvent: ...)` と画面最下部の「疑似メディアキーバー」からアクションを受け付ける構造とする必要がある。
3. **全6ステップの決定論的ステートマシン**:
   - Step 1（案内画面） ➔ Step 2（開始操作） ➔ Step 3（調整突入・項目選択） ➔ Step 4（重量調整・0.7sデバウンス） ➔ Step 5（調整確定） ➔ Step 6（完了・本編へ）。
   - 各ステップで許可されるキー入力のみをディスパッチし、非許可キーは無視または案内表示とすることで、プレゼン時の誤操作による状態破綻を防止する。
4. **Step 3 の 2相構造（Part 1 & Part 2）**:
   - Step 3 前半では「次の曲へ進む (87)」で調整モード突入（「調整、種目名」発話＋枠線ハイライト）。
   - Step 3 後半では「音量キー (24/25)」で項目選択（種目名 ⇄ 重量 ⇄ レップ数 ⇄ セット数）＋項目名発話。
   - 「再生/停止 (85)」で「60キロ」発話後に Step 4 へ進行。
5. **Step 4 のデバウンス安全性**:
   - 連打中はタイマーをリセットし UI のみを +2.5kg 刻みで即座に再描画。連打が 0.7秒止まった時点でTTS発話する。
   - 決定キー (85) 押下時やスキップ時は直ちにタイマーをキャンセルし、Step 5 に遅延発話が持ち越されないようにする。
   - テストでの `pumpAndSettle()` 停止を防ぐため、`SchedulerBinding.instance.scheduleFrame()` パルスを連動させる。
6. **発話文字列の厳密性**:
   - `ORIGINAL_REQUEST.md` R5 の指示に基づき、Step 2: `「開始、ベンチプレス、60キロ、10回、3セット」`、Step 3: `「調整、種目名」` ➔ `「60キロ」`、Step 4: `「調整、重量」`、Step 5: `「確定」` ＋ `「開始、ベンチプレス、65キロ、10回、3セット」` を厳密に出力する。

---

## 3. Caveats（制約・留意点）

1. **実機 iOS での音量キー制限**:
   - iOS ではOS標準のセキュリティ仕様により、フォアグラウンドアプリがハードウェア音量ボタンのイベントを直接 `KeyEvent` として横取りすることは制限される。ただし、Bluetoothイヤホンのメディアボタン（再生/停止、次曲、前曲）は `MPRemoteCommandCenter` 経由で動作可能である。また、テスト環境やAndroid端末、PCエミュレータでは完全動作する。
2. **発話の「キロ」表記**:
   - 通常の `TrainingController` では `"${weight}kg"` を使用しているが、要件文面 R5 ではカタカナ表記「60キロ」「65キロ」が明記されている。TTSエンジンによっては「kg」を「キログラム」または「ケージー」と発音する場合があるため、要件指示通りカタカナ表記「キロ」でフォーマットする実装が最適である。
3. **既存コードの不可侵性**:
   - `lib/training_screen.dart` は一切変更してはならない。変更が許可されているのは `lib/main.dart`（チュートリアルボタン追加）と新規作成の `lib/tutorial_screen.dart`、および `test/` 配下のテストファイルのみである。

---

## 4. Conclusion（結論・推奨設計）

`TutorialScreen` の実装に必要となるすべてのキーマッピング、6ステップステートマシン、UI演出、デバウンス並行処理、音声同期、テストシミュレーション手順の仕様策定が完了した。

### 推奨モジュール設計
1. `lib/tutorial_screen.dart`:
   - `enum TutorialStep { step1Intro, step2Start, step3SelectTarget, step4AdjustWeight, step5FinishAdjustment, step6Completed }`
   - `enum TutorialStep3Phase { part1Enter, part2Select }`
   - `AnimationController` を用いた呼吸するホタル発光枠線 (`boxShadow`)
   - `Color(0xB3000000)` による半透明ブラック暗転オーバーレイ
   - 0.7秒デバウンスタイマー (`kDebounceDuration = Duration(milliseconds: 700)`)
   - 疑似メディアキーバー（画面下部）およびスキップボタン（右下）
2. `lib/main.dart`:
   - 「トレーニング開始」ボタン（`start_training_button`）の直下に「操作チュートリアルを体験する」ボタン（`Key('open_tutorial_button')`）を配置。

---

## 5. Verification Method（検証方法）

1. **構文解析および静的チェック**:
   ```powershell
   flutter analyze
   ```
2. **既存テストの後方互換性確認**:
   ```powershell
   flutter test
   ```
3. **新規チュートリアル用 Widget テストの追加検証**:
   - Step 1〜6 の遷移、スキップ機能、仮想キーバー、ADB MethodChannel イベント（85, 79, 24, 25, 87, 88）、デバウンス連打、TTS重複防止の網羅テストを実行し exit code 0 を確認する。
