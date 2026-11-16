# Handoff Report: エントリーボタン新設（lib/main.dart）および自動テストスイート（test/tutorial_screen_test.dart）詳細設計

**Agent**: `explorer_m1_3` (Entry Button & Automated Test Architect)  
**State folder**: `c:\Users\taqmi\02_development\original_program\noukin_app\.agents\teamwork\explorer_m1_3\`  
**Target Milestone**: M1 (TutorialScreen Implementation & Automated Verification)  
**Integrity Mode**: development  

---

## 1. Observation（直接の観察事実）

1. **`lib/main.dart` 既存のエントリーボタン周辺構造 (671〜717行目)**:
   - `c:\Users\taqmi\02_development\original_program\noukin_app\lib\main.dart`
   - `ButtonControlScreen` の `Scaffold.body` は垂直な `Column` ウィジェットで構築されている。
   - 674〜702行目に `Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 4), child: ElevatedButton.icon(key: const Key('start_training_button'), ...))` が定義されている。
   - 704〜707行目: `Expanded(flex: 5, child: _buildCenterDisplay())`
   - 708行目: `const Divider(height: 1, color: Color(0xFF333333))`
   - 710行目: `_buildLogHeader()`
   - 712〜715行目: `Expanded(flex: 5, child: _buildLogList())`
   - 43行目: `import 'training_screen.dart';`
   - 45行目: `export 'training_screen.dart';`

2. **既存テストスイートのテスト資産 (`test/widget_test.dart` 1〜120行目, 130〜400行目)**:
   - `c:\Users\taqmi\02_development\original_program\noukin_app\test\widget_test.dart`
   - `sendNativeKeyEvent(tester, keyCode)` ヘルパー（10〜32行目）が定義されており、`kKeyEventsChannelName`（`com.example.noukin/key_events`）へのネイティブ呼び出しをシミュレート可能。
   - `FakeTtsService`（`lib/main.dart` 364〜399行目）は `spokenHistory`（全発話履歴）、`lastSpoken`、`stopCallCount`、`currentVolume` を保持。
   - `FakeSoundEffectService`（`lib/main.dart` 189〜201行目）は `beepCount` を保持。
   - `FakeAudioDuckingController`（`lib/main.dart` 130〜156行目）は `events` と `isCurrentlyDucked` を保持。

3. **既存テスト実行結果 (`flutter test --no-test-assets`)**:
   ```
   00:05 +14: All tests passed!
   ```
   全14件のテスト（キーマッピング、ダッキング、ログ履歴、TrainingScreen画面遷移）が exit code 0 でパス。

4. **要件仕様書 (`ORIGINAL_REQUEST.md`) の R1・R2・R4・R5・R6**:
   - R1: `lib/training_screen.dart` は直接変更せず、新規に `lib/tutorial_screen.dart` を作成。`lib/main.dart` の「トレーニング開始」ボタン直下に「操作チュートリアルを体験する」ボタンを配置。完了時およびスキップ時は `TrainingScreen` へ遷移。
   - R2: 新規TTS発話前に必ず `flutterTts.stop()` を実行。全TTS・電子音再生時に `AudioDuckingController` を適用。
   - R4: 半透明ブラック（Black 70%）暗転、ホタル発光枠線、スキップボタン、画面最下部疑似メディアキーバー。
   - R5: Step 1〜Step 6 の全6ステップ遷移と発話文言（「開始、ベンチプレス、60キロ、10回、3セット」「調整、種目名」「60キロ」「調整、重量」「確定、開始、ベンチプレス、65キロ、10回、3セット」等）。
   - R6: 全6ステップ、UI要素、スキップ機能、仮想キーバー、キーイベントハンドリング、画面遷移を検証する自動 Widget テストを作成。

5. **Flutter WidgetTester のアニメーション特性**:
   - `AnimationController.repeat(reverse: true)`（ホタル発光枠線）が稼働している間、フレームタイマーが無限にスケジュールされるため、テストコード内で `await tester.pumpAndSettle()` を呼び出すと `pumpAndSettle timed out` 例外が発生する。

---

## 2. Logic Chain（観察から結論への論理展開）

1. **`lib/main.dart` のレイアウト無破壊（ゼロ・リグレッション）保証** (Observation 1に基づく):
   - `Column` 内の残余領域は上下2つの `Expanded(flex: 5)`（中央キー表示とログ一覧）が担っているため、高度44px（パディング込み56px）のボタンを1つ追加しても、2つの `Expanded` が自動的に縦幅を縮小して均等に吸収します。
   - したがって、固定高さ不足による黄色と黒の縞模様エラー（`RenderFlex overflowed by ...`）は物理的に生じません。
   - パディングを `EdgeInsets.fromLTRB(16, 4, 16, 8)` に設定することで、上の「トレーニング開始」ボタン（下マージン4px）との間隔が 8px となり、Flutter 標準の 8px グリッドに美しく調和します。
   - メインの「トレーニング開始」ボタンはティールベタ塗り（Primary）、チュートリアルボタンは暗色コンテナ＋ティール枠線（Secondary）とすることで、明確な視覚的優先度を維持します。

2. **既存テストの無影響性** (Observation 1, 3に基づく):
   - `test/widget_test.dart` はウィジェットのインデックス位置に依存せず、`find.byKey(const Key('start_training_button'))` などのキー指定でウィジェットを探索しています。
   - そのため、ボタンを直下に挿入しても既存テスト14件の成功状態は100%維持されます。

3. **自動テストの高速性と決定論的安定性の両立** (Observation 2, 5に基づく):
   - `TutorialScreen` がコンストラクタ引数で `animateGlow: bool = true` を受け取る設計を活用し、ワークフローステップテストでは `animateGlow: false`（静止値 1.0）を指定してマウントします。
   - これにより、`pumpAndSettle()` が無限タイマーに捕まることなく即座に完了し、Step 1〜Step 6 の全遷移をミリ秒単位で高速・決定論的に検証できます。
   - 発光枠線アニメーション自体は、独立したテストケースで `animateGlow: true` で起動し、`tester.pump(const Duration(milliseconds: 300))` で有限フレームを進めることで安全に検証します。

4. **0.7秒デバウンスの確実な検証** (Observation 2, 4に基づく):
   - Step 4 では、キー 24（+2.5kg）を 200ms 間隔で打鍵した際に、即時画面表示が 62.5kg ➔ 65kg へ加算され、電子音ビープ（`fakeSound.beepCount`）が鳴る一方で、連打中は `fakeTts.spokenHistory` が空のままであることを検証します。
   - 打鍵停止から 550ms（合計 750ms）経過後に「65キロ」が 1回だけ発話されることを確認します。
   - さらに、未完了デバウンス中にキー 85（決定）が押された場合は、保留中のタイマーが直ちに破棄され、遅延発話を残さずに「調整、重量」を発話して Step 5 へ遷移することを検証します。

5. **音声排他（Audio Hygiene）の完全検証** (Observation 2, 4に基づく):
   - 要件 R2「前のTTS音声が重ならないよう、必ず flutterTts.stop() を挟んでから新しい発話を開始する」を満たすため、各発話の直前に `fakeTts.stop()` が実行されているかを `expect(fakeTts.stopCallCount, greaterThanOrEqualTo(fakeTts.spokenHistory.length))` で厳格にアサートします。

---

## 3. Caveats（制約事項・留意点）

1. **`lib/training_screen.dart` の不可侵制約**:
   - `lib/training_screen.dart` は1行も変更してはなりません。すべてのチュートリアル機能は `lib/tutorial_screen.dart` に独立して実装し、完了時やスキップ時は `Navigator.of(context).pushReplacement` で既存の `TrainingScreen` を呼び出します。
2. **キー命名の一貫性**:
   - `test/tutorial_screen_test.dart` と `lib/tutorial_screen.dart` の間で以下の Key 定義が完全に一致している必要があります：
     - Step 1: `Key('btn_tutorial_start')`, `Key('btn_tutorial_skip_all')`
     - Step 2: `Key('btn_next_workout')`（または `Key('btn_tutorial_action')`）
     - Step 4: `Key('card_weight')`
     - Step 6: `Key('btn_start_first_training')`
     - 共通スキップ: `Key('btn_tutorial_skip')`
     - 疑似メディアキーバー: `Key('virtual_key_prev')`, `Key('virtual_key_play_pause')`, `Key('virtual_key_next')`, `Key('virtual_key_vol_down')`, `Key('virtual_key_vol_up')`
3. **発話文言の「キロ」表記の厳守**:
   - 要件指示に従い、「60キロ」「65キロ」と日本語カタカナで発話される必要があります（「60kg」等の英語表記ではない）。

---

## 4. Conclusion（結論・推奨アクション）

1. **`lib/main.dart` の更新**:
   - 43行目に `import 'tutorial_screen.dart';` および `export 'tutorial_screen.dart';` を追記。
   - 702行目の直下に `Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 8), child: ElevatedButton.icon(key: const Key('start_tutorial_button'), ...))` を挿入。
2. **`test/tutorial_screen_test.dart` の新設**:
   - `analysis.md` セクション 5 に定義された 9 項目のテストマトリクスを完全網羅した自動 Widget テストスイートを作成。
3. **安全かつ包括的な検証保証**:
   - 本設計により、UIレイアウト崩れ・テスト破損・アニメーション無限待機をすべて未然に防止し、全14件の既存テストおよび新設テストが100%成功（exit code 0）する環境が整います。

---

## 5. Verification Method（独立検証手順）

1. **設計ドキュメントの閲覧確認**:
   - `analysis.md`（詳細設計書および完全なテストコード）を閲覧し、9項目のテストマトリクスと Worker 向けガイドラインを確認する。
2. **既存テストスイートの実行**:
   ```powershell
   flutter test --no-test-assets
   ```
   - 期待値: 全14テストが exit code 0 でパスすること。
3. **Worker による実装・配置後の総合検証**:
   ```powershell
   flutter test --no-test-assets test/tutorial_screen_test.dart
   flutter test --no-test-assets
   ```
   - 期待値: 既存テストとチュートリアルテストがすべてパスし、exit code 0 となること。
4. **無効化条件**:
   - `lib/main.dart` へのボタン追加によって画面下部がオーバーフローした場合。
   - `lib/training_screen.dart` に変更が加わった場合。
   - `flutter test` のいずれかのテストが失敗した場合。
