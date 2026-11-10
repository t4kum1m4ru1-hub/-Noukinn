# Dispatch Messages

## 2026-11-05T23:32:45Z
Create a minimal cross-platform Flutter verification application in `lib/main.dart` that captures physical buttons (Volume Up/Down) and earphone media keys (Play/Pause, Next, Previous) across Android and iOS, immediately reading out detected actions via `flutter_tts`, accompanied by automated tests.

Working directory: c:\Users\taqmi\02_development\original_program\button_controll_test
Integrity mode: development

## Requirements

### R1. Physical Button and Media Key Event Detection
Capture physical button and earphone media key events across target platforms (Android and iOS) using `flutter/services` (such as `HardwareKeyboard` or `RawKeyboardListener`) for:
- Volume Up (`KEYCODE_VOLUME_UP`)
- Volume Down (`KEYCODE_VOLUME_DOWN`)
- Play / Pause (`KEYCODE_MEDIA_PLAY_PAUSE` or `KEYCODE_MEDIA_PLAY` / `KEYCODE_MEDIA_PAUSE`)
- Next Track (`KEYCODE_MEDIA_NEXT`)
- Previous Track (`KEYCODE_MEDIA_PREVIOUS`)

### R2. Immediate Audio Feedback via flutter_tts
Upon detecting any specified key event, immediately speak out a confirmation phrase (e.g. "音量アップを受信しました", "再生・停止ボタンが押されました") using `flutter_tts` so that button operation can be verified without viewing the display.

### R3. Verification UI with Real-time Log
Provide a clean dark-mode verification interface:
- Center of the screen displays the name of the most recently detected button/key (e.g. `KEYCODE_VOLUME_UP`) in large text.
- Bottom of the screen displays a scrollable real-time log list showing received key events with their timestamps.

### R4. Standalone Deliverable & Dependency Documentation
- Implement the code as a self-contained `lib/main.dart` file that can be dropped in and run directly without depending on existing project code.
- Explicitly document in comments at the top of the file any packages (such as `flutter_tts`) required to be added to `pubspec.yaml`.

### R5. Automated Verification Tests
Provide automated Flutter tests (e.g. widget or unit tests under `test/`) that simulate key press events (Volume Up, Volume Down, Play/Pause, Next, Previous) and verify that key detection, UI updates, and TTS trigger invocations occur as specified.

## Acceptance Criteria

### Functional Verification
- [ ] Key press events for Volume Up, Volume Down, Play/Pause, Next Track, and Previous Track are handled across target platforms.
- [ ] `flutter_tts` is triggered upon key detection with appropriate descriptive speech text in Japanese.
- [ ] The center UI dynamically updates with the most recently pressed button name.
- [ ] The scrollable log list records each received key event with its timestamp in chronological order.

### Code and Documentation
- [ ] `lib/main.dart` is self-contained and ready to execute once dependencies are installed.
- [ ] Comments in `lib/main.dart` specify all necessary dependencies for `pubspec.yaml`.

### Automated Testing
- [ ] Automated Flutter tests execute successfully (`flutter test`).
- [ ] Automated tests simulate key events and assert that UI state updates and speech trigger calls are made.

===
Coordination Details:
- Working directory: .agents/teamwork/orchestrator/
- Workspace root: c:\Users\taqmi\02_development\original_program\button_controll_test
- Authoritative request: c:\Users\taqmi\02_development\original_program\button_controll_test\.agents\teamwork\ORIGINAL_REQUEST.md
- Maintain progress.md and BRIEFING.md in your working directory.
- Report milestone updates and completion back to Sentinel.


## 2026-11-10T10:02:27Z
筋トレアプリ「のう筋」の中間発表プレゼン実演（デモ）において、審査員・聴衆に「スマホを見ずにイヤホンのボタンだけでトレーニングを完結できるコアバリュー（MVP）」を直感的に伝えるためのインタラクティブな操作チュートリアル画面（TutorialScreen）を新設する。

Integrity mode: development

## Requirements

### R1. チュートリアル画面モジュールの新設とエントリーポイントの導線
- 既存の `lib/training_screen.dart` は直接変更せず、新規に `lib/tutorial_screen.dart` を作成して独立した画面モジュールとして実装すること。
- `lib/main.dart`（`ButtonControlScreen`）の既存の「トレーニング開始」ボタンの直下に「操作チュートリアルを体験する」ボタンを配置し、タップで `TutorialScreen` へ遷移できるようにすること。
- チュートリアル完了時（および各ステップのスキップ時）は、既存の `TrainingScreen` へスムーズに遷移できるようにすること。

### R2. 既存音声サービス（TTS・電子音・ダッキング）の再利用と発話制御
- 既存の音声サービス（TTS、ToneGenerator/電子音 `SoundEffectService`、BGMダッキング `AudioDuckingController`）をそのまま呼び出して再利用すること。
- 画面遷移やステップ切り替え時に前のTTS音声が重ならないよう、必ず `flutterTts.stop()` を挟んでから新しい発話を開始すること。
- BGMダッキング（`AudioDuckingController`）をチュートリアル中の全TTS発話・電子音再生時にも漏れなく適用すること。

### R3. メディアボタン操作体系の厳密な適用
- ［再生 / 停止］（MEDIA_PLAY_PAUSE / keyevent 85, 79）:
  - 通常時：トレーニング開始 / 次へ
  - 調整時：【決定ボタン】（項目選択の決定、数値調整の決定）
- ［次の曲へ進む］（MEDIA_NEXT / keyevent 87）:
  - 【調整モードのトグルボタン】（調整モードに入る / 調整完了して通常モードへ戻る）
- ［前の曲へ戻る］（MEDIA_PREVIOUS / keyevent 88）:
  - 【種目内容の確認ボタン】（「{種目名}、{重量}kg、{レップ数}回、{セット数}セット」を読み上げる安全ボタン。画面戻りやキャンセルは行わない）
- ［音量 UP / DOWN］（VOLUME_UP: 24 / VOLUME_DOWN: 25）:
  - 項目送り（進む/戻る）および 数値増減（重量±2.5kg、回数±1、セット数±1）

### R4. UI・演出要件
- スポットライト＆暗転オーバーレイ：各ステップで注目させたいボタンやカード以外を半透明ブラック（Black 70%）で暗転すること。
- 発光枠線：注目要素の周りに呼吸するように滑らかに明滅する発光枠線（ホタルの光のようなグローアニメーション）を適用すること（`AnimationController` ＋ `boxShadow`）。
- 発表用スキップ機能：実機キーやADB操作だけでなく、画面タップや右下の控えめな「スキップ」ボタンでも次のステップへ進めるようにし、デモ発表時の機材トラブルを防止すること。
- PC/エミュレータ検証用バー：画面最下部に疑似メディアキーバー（再生/停止、次曲、前曲、Vol+、Vol-）を配置し、マウスクリックやキーボードでもテスト可能にすること。

### R5. チュートリアルの全6ステップの実装
- Step 1（開始画面）：タイトル「のう筋 操作チュートリアル」、説明文、メインボタン「チュートリアルを開始する」（Step 2へ）、サブボタン「スキップして直接トレーニングへ」（`TrainingScreen`へ直行）。
- Step 2（開始操作体験）：全体暗転・中央「開始」ボタンのみスポットライト＆ホタル発光枠線。案内「イヤホンの［再生/停止］ボタンを押してトレーニングを始めてみましょう」。［再生/停止］（keyevent 85）またはスキップで電子音＋開始アニメーション＋暗転フェードアウト＋TTS「開始、ベンチプレス、60キロ、10回、3セット」発話後、Step 3へ自動遷移。その他キーは反応なし。
- Step 3（調整モード突入＆項目選択）：前半は［次の曲へ進む］（keyevent 87）で電子音＋TTS「調整、種目名」＋種目名ハイライト。後半は［音量＋/−］（keyevent 24/25）で電子音＋選択枠移動（種目名⇄重量⇄レップ数⇄セット数）＋項目名発話。［再生/停止］（keyevent 85）で電子音＋現在値発話（「60キロ」）しStep 4へ遷移。［前の曲へ戻る］（keyevent 88）で内容確認読み上げ。
- Step 4（重量調整とデバウンス体験）：調整中の重量カード（60.0kg）のみスポットライト表示。［音量＋/−］で即座に電子音＋画面重量リアルタイム増減（±2.5kg）、連打停止0.7秒後にTTS発話（デバウンス）。［再生/停止］で電子音＋音声「調整、重量」しStep 5へ遷移。［前の曲へ戻る］で現在値の確認読み上げ。
- Step 5（調整完了の体験）：全体暗転・案内「［次の曲へ進む］ボタンを押して、調整を完了しましょう」。［次の曲へ進む］（keyevent 87）で電子音＋音声「確定」、続けて「開始、ベンチプレス、65キロ、10回、3セット」発話後、Step 6へ自動遷移。その他キーは注意案内を表示。
- Step 6（完了と本編スタート）：暗転解除、タイトル「🎉 チュートリアル完了！」、説明文表示。メインボタン「最初のトレーニングを開始する」タップまたは［再生/停止］キーで本編 `TrainingScreen` へ遷移。

### R6. 自動テストによる検証
- `TutorialScreen` の全6ステップ、UI要素、スキップ機能、仮想キーバー、キーイベントハンドリング、画面遷移を検証する自動 Widget テストを作成すること。

## Acceptance Criteria

### UI and Visual Presentation
- [ ] `TutorialScreen` で各ステップの対象要素以外が半透明ブラック（Black 70%）で暗転されること
- [ ] 注目対象要素の周囲に呼吸するホタル発光アニメーション枠線（boxShadow）が表示されること
- [ ] 各ステップにスキップボタンが配置され、押下により次のステップ（または本編）へ進行できること
- [ ] 画面最下部に疑似メディアキーバー（再生/停止、次曲、前曲、Vol+、Vol-）が常時表示され、各ボタンのタップで該当キーイベントが発火すること

### Key Interaction and Flow (Step 1 - Step 6)
- [ ] Step 1 で「チュートリアルを開始する」タップで Step 2 へ遷移し、「スキップして直接トレーニングへ」で `TrainingScreen` へ遷移すること
- [ ] Step 2 で keyevent 85（再生/停止）受信時に電子音＋開始演出＋TTS発話（「開始、ベンチプレス、60キロ、10回、3セット」）が実行され、発話終了後に Step 3 へ遷移すること
- [ ] Step 3 前半で keyevent 87（次曲）受信時に電子音＋TTS発話（「調整、種目名」）が行われ、後半案内へ切り替わること
- [ ] Step 3 後半で keyevent 24/25（音量±）により項目が切り替わり、keyevent 85（決定）で Step 4 へ遷移すること。keyevent 88 で内容確認読み上げが行われること
- [ ] Step 4 で keyevent 24/25（音量±）によりリアルタイムに重量が±2.5kg増減し、0.7秒のデバウンス後に変更後の重量が読み上げられること
- [ ] Step 4 で keyevent 85（決定）受信により電子音＋「調整、重量」発話後に Step 5 へ遷移すること
- [ ] Step 5 で keyevent 87（次曲）受信により電子音＋「確定」＋「開始、ベンチプレス、65キロ、10回、3セット」発話後に Step 6 へ遷移すること
- [ ] Step 6 で「最初のトレーニングを開始する」タップまたは keyevent 85 で `TrainingScreen` へ遷移すること

### Audio and Lifecycle Control
- [ ] 新しいTTS発話開始前に必ず `flutterTts.stop()` が呼び出され、発話の重複が発生しないこと
- [ ] 全TTS発話および電子音再生時に `AudioDuckingController` のダッキング要求および解除が適切に実行されること
- [ ] `lib/training_screen.dart` は一切変更されず、`lib/tutorial_screen.dart` として独立実装されていること
- [ ] `lib/main.dart` の「トレーニング開始」ボタンの直下に「操作チュートリアルを体験する」ボタンが配置され、タップで `TutorialScreen` へ正常に遷移できること

### Verification
- [ ] `flutter test` を実行し、Step 1〜Step 6 のインタラクション・キーイベント処理・画面遷移を網羅した自動 Widget テストが成功（exit code 0）すること
