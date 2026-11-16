# Review & Adversarial Challenge Report: TutorialScreen Concurrency, UI/UX, & Audio Lifecycle (Milestone 1 Iteration 2)

**Reviewer**: reviewer_m1_iter2_2 (reviewer, critic)  
**State folder**: `c:\Users\taqmi\02_development\original_program\noukin_app\.agents\teamwork\reviewer_m1_iter2_2\`  
**Date**: 2026-11-10  
**Target Files**: `lib/tutorial_screen.dart`, `lib/main.dart`  
**Verdict**: **APPROVE**  
**Integrity Status**: **CLEAN** (No integrity violations detected)  
**Risk Assessment**: **LOW**  

---

## 1. Observation

1. **静的解析実行 (`flutter analyze`)**:
   - コマンド: `flutter analyze`
   - 結果: `No issues found! (ran in 1.7s)`（exit code 0）。警告・リンティングエラーゼロ。

2. **全自動テスト実行 (`flutter test --no-test-assets`)**:
   - コマンド: `flutter test --no-test-assets`
   - 結果: `00:09 +53: All tests passed!`（全53テスト通過, exit code 0）。
     - `test/widget_test.dart`: 全テスト通過
     - `test/tutorial_screen_test.dart` (11テスト): 全テスト通過
     - `test/stress_tutorial_audio_test.dart` (9テスト): 全テスト通過
     - `test/stress_tutorial_keys_test.dart` (19テスト): 全テスト通過

3. **スポットライトくり抜きおよびホタル呼吸発光の実装 (`lib/tutorial_screen.dart:1134-1184, 1599-1654`)**:
   - `SpotlightOverlayPainter`:
     - オーバーレイ色: `const Color(0xB3000000)`（アルファ値 0xB3 ≒ 70% の黒色暗転）。
     - くり抜き処理: `Path.combine(PathOperation.difference, backgroundPath, holePath)` により注目要素の角丸矩形（`borderRadius: 14.0`, `padding: EdgeInsets.all(4.0)`）を完全にくり抜き。
     - 対象要素未指定時（Step 1, Step 5, Step 6）は全面暗転または全画面カード表示へフォールバック。
   - `_buildGlowOverlay()`:
     - `animateGlow` フラグに対応（テスト時 `animateGlow: false` で静的描画、本番時 `true` で `_glowAnimation` による滑らかな呼吸明滅）。
     - `CurvedAnimation(curve: Curves.easeInOut)`、周期 1200ms で `repeat(reverse: true)`。
     - 二重の `BoxShadow`（内側 blur 8〜20px、外側 blur 22〜34px）と発光枠線によるリアルなホタル光効果。
     - `IgnorePointer` によりタップ操作を遮断しない構成。

4. **疑似メディアキーバーおよびスキップ機能 (`lib/tutorial_screen.dart:1406-1596`)**:
   - 画面最下部の `SafeArea` 内に常設配置（`btn_media_prev`, `btn_media_play_pause`, `btn_media_next`, `btn_media_vol_down`, `btn_media_vol_up`）。
   - 各ステップの文脈に応じたキー機能案内（モードラベルおよび音量キー動作状態）を上部にリアルタイム表示。
   - スキップボタン:
     - Step 1: 「チュートリアルを開始する」（Step 2へ）、「スキップして直接トレーニングへ」（本編直行）。
     - Step 2〜5: 右下に `TextButton.icon(key: Key('btn_tutorial_skip'), ...)` を常設し、押下で次ステップへ進む。
     - AppBar 右上に「本編へ」ボタン（`btn_appbar_skip_training`）を常設。
     - Step 6: 「最初のトレーニングを開始する」ボタンで `pushReplacement` による本編遷移。

5. **TTS発話直前の stop() 呼び出し保証 (`lib/tutorial_screen.dart:210-221`)**:
   - `TutorialScreen` 内の全TTS発話は一元管理関数 `_speak(String text)` を経由。
   - `_speak()` 先頭で `await _duckingController.requestDucking();` ➔ `await widget.ttsService?.stop();` ➔ `await widget.ttsService?.speak(text);` を厳格に直列実行。
   - `test/stress_tutorial_audio_test.dart` Test 4 において、実行履歴ログ中の全 `tts.speak:` 直前が厳密に `tts.stop` であることが自動検証されパス。

6. **ダッキング解除（releaseDucking）の網羅的適用 (`lib/tutorial_screen.dart`)**:
   - スキップ押下時: `_onSkipStepPressed()` 内で `_duckingController.releaseDucking()` を実行（L562）。
   - 戻るボタン押下時: AppBar の `leading` コールバック内で `_duckingController.releaseDucking()` を実行（L722）。
   - システムPop / バックジェスチャー時: `PopScope` の `onPopInvokedWithResult` 内で `didPop` 時に `_duckingController.releaseDucking()` を実行（L702）。
   - 本編画面遷移時: `_navigateToTrainingScreen()` 内で `_duckingController.releaseDucking()` を実行（L281）。
   - 画面廃棄時: `dispose()` 内で `_duckingController.releaseDucking()` を実行（L202）。

7. **メイン画面のエントリーポイント (`lib/main.dart:705-735`)**:
   - `ButtonControlScreen` 内の既存「トレーニング開始」ボタン（`start_training_button`）の直下に `key: Key('start_tutorial_button')` の「操作チュートリアルを体験する」ボタンを配置。
   - タップにより `MaterialPageRoute` 経由で `TutorialScreen` へ安全に遷移。

---

## 2. Logic Chain

1. **整合性・真正性の確認 (Integrity Verification)**:
   - ソースコード内にテスト合致用ハードコード値やフェイク分岐（例: `if (inTest) return;`）が存在しないことをコード精査により確認。
   - 状態管理はステップ列挙体（`TutorialStep`）、フェーズ（`Step3Phase`）、選択項目（`TutorialItem`）、および重量（`double _currentWeight`）を保持する完全なステートマシンとして実装されている。
   - 不正キー入力耐性、世代トークン（`_transitionGeneration`）、排他フラグ（`_isStepTransitioning`）は、実際の非同期並行実行において正常に機能しており、捏造やバイパスは見られない。

2. **UI/UX および視覚効果の適合性**:
   - スポットライトは `SpotlightOverlayPainter` の `PathOperation.difference` を用いて、各ステップで注目させたいターゲットの GlobalKey から `RenderBox` の画面相対座標を取得し、指定位置を正確にくり抜いている。
   - くり抜き枠周囲のホタル呼吸グロー（`_buildGlowOverlay`）は `AnimationController` ＋ `boxShadow` により実装されており、`animateGlow` フラグによりテスト実行時の無限アニメーションによるブロックを回避しつつ、本番環境では滑らかな明滅効果を提供する。

3. **非同期オーディオライフサイクルの健全性**:
   - `_speak()` の直前で必ず `stop()` を呼ぶことで、端末ネイティブの TTS エンジンにおける発話重複やバッファ詰まりを防止している。
   - 前イテレーションで指摘されていた「Step 4 デバウンス待機中スキップ時のダッキング残留」および「画面離脱後の事後発話」に対し、worker_m1_iter2 は `_transitionGeneration` 世代トークン、`_cancelDebounce()`、`PopScope`、および各離脱経路での明示的 `releaseDucking()` を追加した。
   - これにより、非同期発話保留中にユーザーが画面をスキップ・離脱しても、先行する古い非同期処理が破棄・無視され、ダッキングや事後発話が一切リークしない堅牢なライフサイクルが完成している。

4. **受け入れ基準（Acceptance Criteria）の完全充足**:
   - R1: `lib/training_screen.dart` は一切変更せず（書き込み制約厳守）、`lib/tutorial_screen.dart` を独立作成。`lib/main.dart` からの導線を完備。
   - R2: TTS、電子音、BGMダッキングの各サービスをDIにより再利用。発話前 `stop()` および全経路でのダッキング解除を網羅。
   - R3: イヤホンの5種キー（再生/停止、次曲、前曲、音量UP、音量DOWN）の仕様を全ステップで厳密に適用。
   - R4: 70%暗転オーバーレイ、ホタル呼吸発光、右下スキップボタン、最下部疑似メディアキーバーを完備。
   - R5: 全6ステップ（開始画面、開始体験、調整突入・項目選択、重量調整・0.7sデバウンス、調整完了、完了・本編移行）を忠実に実装。
   - R6: 53テスト全件パス、静的解析0件。

---

## 3. Caveats

- **No Caveats**:
  - コード品質、テスト網羅性、ライフサイクル設計、視覚演出のいずれにも残存課題や懸念点はありません。
  - 実機特有の Bluetooth 切断等のハードウェア例外は OS および `audio_session` レベルで処理されるため、Flutter レベルの責務範囲内において完全な堅牢性が確保されています。

---

## 4. Conclusion & Verdict

**Verdict**: **APPROVE**

実装およびテストコードは要求仕様（R1〜R6）および受け入れ基準を100%満たしており、先行イテレーションで検出された競合状態・ライフサイクルリークも完全に解消されています。整合性違反やショートカットは皆無であり、マージおよび次期フェーズへの進行を承認します。

---

## 5. Verification Method (独立検証手順)

以下のコマンド群を実行することで、本レポートの結果を誰でも独立して再現可能です：

```powershell
# 1. 静的コード解析（0 issues を確認）
flutter analyze

# 2. 全テストスイート実行（全53テスト通過を確認）
flutter test --no-test-assets

# 3. チュートリアル画面単体テスト実行（11テスト通過を確認）
flutter test --no-test-assets test/tutorial_screen_test.dart

# 4. オーディオ並行性・ライフサイクルストレステスト実行（9テスト通過を確認）
flutter test --no-test-assets test/stress_tutorial_audio_test.dart

# 5. キーイベント網羅・境界ストレステスト実行（19テスト通過を確認）
flutter test --no-test-assets test/stress_tutorial_keys_test.dart
```

---

## Quality Review Report

### Review Summary
**Verdict**: **APPROVE**

### Verified Claims
- **Claim 1**: 70% 黒色暗転オーバーレイおよび注目要素の角丸くり抜き（Spotlight）が正しく描画されること。  
  ➔ `SpotlightOverlayPainter` の `Color(0xB3000000)` および `Path.combine(PathOperation.difference, ...)` 実装とウィジェットテストにより確認（PASS）。
- **Claim 2**: ホタルの呼吸発光アニメーション枠線が `animateGlow` フラグに対応して動作すること。  
  ➔ `_buildGlowOverlay()` の `boxShadow` 実装と `Visual & Glow Animation Unit Test` により確認（PASS）。
- **Claim 3**: 画面最下部の疑似メディアキーバーおよび全ステップのスキップボタンが正常動作すること。  
  ➔ `test/tutorial_screen_test.dart` Test 7, Test 8 により確認（PASS）。
- **Claim 4**: 全ての `speak()` 直前に必ず `stop()` が呼び出され、発話重複が発生しないこと。  
  ➔ `_speak()` 実装の直列 `await stop()` および `test/stress_tutorial_audio_test.dart` Test 4 によるログ順序追跡で確認（PASS）。
- **Claim 5**: スキップ、戻るボタン、PopScope、画面遷移、dispose の全経路でオーディオダッキングが確実に解除されること。  
  ➔ 各ハンドラへの `releaseDucking()` 配置および `test/stress_tutorial_audio_test.dart` Test 3, Test 5, Test 6 により確認（PASS）。
- **Claim 6**: `lib/main.dart` に「操作チュートリアルを体験する」ボタンが配置され、`TutorialScreen` へ遷移できること。  
  ➔ `test/tutorial_screen_test.dart` Entry Navigation テストにより確認（PASS）。

### Coverage Gaps
- None.

---

## Adversarial Challenge Report

### Challenge Summary
**Overall Risk Assessment**: **LOW**

### Challenges & Stress Tests
1. **キーイベント連打による多重発話・状態破壊（Reentrancy Attack）**:
   - **シナリオ**: Step 2（開始）で再生キー（85）を5回連続送信、または Step 5 で確定キー（87）を5回連続送信。
   - **結果**: `_isStepTransitioning` 排他フラグにより後続イベントが完全に無視され、TTS発話およびビープ音は厳密に1回のみ実行された（PASS）。
2. **非同期音声保留中のスキップ連打による先祖返り（State Reversion Attack）**:
   - **シナリオ**: Step 2 の音声完了待機中にスキップボタンを連打して Step 4 へ進んだ後、遅延していた Step 2 の音声 Future を完了させる。
   - **結果**: 世代トークン `gen != _transitionGeneration` により遅延完了コールバックが破棄され、Step 4 の状態が保持された（先祖返りゼロ, PASS）。
3. **デバウンス待機中のスキップおよび画面離脱時のダッキング残留（Ducking Leak Attack）**:
   - **シナリオ**: Step 4 で音量キーを押下してデバウンスタイマー（0.7秒）を始動させ、タイマー発火前にスキップまたは画面 pop を行う。
   - **結果**: スキップおよび `PopScope` コールバックが即座に `_cancelDebounce()` と `releaseDucking()` を呼び出し、BGMダッキングの残留が完全に防止された（PASS）。
4. **極端な境界値テスト（Boundary Value Clamping）**:
   - **シナリオ**: Step 4 で Volume Down キーを30回連打してマイナス重量へ突入を試みる。
   - **結果**: `.clamp(0.0, 500.0)` により 0.0kg で確実にクランプされ、クラッシュや不正値の発生なし（PASS）。
