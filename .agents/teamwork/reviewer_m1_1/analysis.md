# Analysis Report: Independent Quality & Adversarial Review of TutorialScreen

**Reviewer**: reviewer_m1_1 (reviewer, critic)  
**Date**: 2026-11-10  
**Target Milestone**: M1 (Interactive Presentation TutorialScreen)  
**Verdict**: **APPROVE**  

---

## 1. Executive Summary

This independent quality and adversarial review evaluated the implementation of `TutorialScreen` in `lib/tutorial_screen.dart`, entry navigation in `lib/main.dart`, and the automated test suite in `test/tutorial_screen_test.dart`.

All requirements (R1 through R6) and corresponding Acceptance Criteria defined in `ORIGINAL_REQUEST.md` and `PROJECT.md` have been verified as fully satisfied. Audio hygiene (exclusive TTS stop and AudioDuckingController ducking request/release) and resource lifecycle hygiene (debounce timer cancellation, animation controller disposal, focus node cleanup, event listener deregistration) are implemented strictly.

Static analysis (`flutter analyze`) and the automated test suite (`flutter test --no-test-assets`) executed with zero errors, zero warnings, and 100% test pass (25 of 25 tests passed).

No integrity violations, fake facade implementations, or hardcoded cheating were identified.

---

## 2. Requirement Traceability Matrix (R1 – R6 & Acceptance Criteria)

| Req # | Specification | Implementation Location | Compliance Assessment |
|---|---|---|---|
| **R1** | **チュートリアル画面の新設・導線**<br>- `lib/training_screen.dart` は直接変更しない。<br>- `lib/tutorial_screen.dart` を独立モジュールとして作成。<br>- `lib/main.dart` の「トレーニング開始」直下に「操作チュートリアルを体験する」ボタン配置。<br>- 完了/スキップ時に `TrainingScreen` へスムーズに遷移（`pushReplacement`）。 | `lib/tutorial_screen.dart`<br>`lib/main.dart:705-734`<br>`lib/tutorial_screen.dart:264-278` | **PASS**<br>- `lib/training_screen.dart` へのマイルストーン内での変更なし。<br>- `start_tutorial_button` が「トレーニング開始」直下に正確に配置。<br>- `Navigator.pushReplacement` により安全に `TrainingScreen` に引き継ぎ。 |
| **R2** | **既存音声サービスの再利用と発話制御**<br>- TTS (`TtsService`), 効果音 (`SoundEffectService`), ダッキング (`AudioDuckingController`) をそのまま再利用。<br>- 発話重複防止のため、全発話の直前に `await ttsService?.stop()` を実行。<br>- 全TTS発話および電子音再生時に BGM ダッキング要求を適用。 | `lib/tutorial_screen.dart:206-224`<br>`lib/tutorial_screen.dart:191-200` | **PASS**<br>- 全発話が `_speak()` を経由し、必ず `requestDucking()` と `await ttsService?.stop()` を実行。<br>- 全ビープ音が `_playBeep()` を経由し `requestDucking()` を実行。<br>- `dispose()` および画面離脱時に `releaseDucking()` と `stop()` を確実に実行。 |
| **R3** | **メディアボタン操作体系の厳密な適用**<br>- ［再生/停止］(85, 79): 通常時開始/次へ、調整時決定。<br>- ［次曲］(87): 調整モードトグル（突入/確定）。<br>- ［前曲］(88): 種目内容の安全確認読み上げ（画面戻りなし）。<br>- ［音量±］(24/25): 項目送り、数値増減（±2.5kg）。 | `lib/tutorial_screen.dart:284-441` | **PASS**<br>- `effectiveAction` でキー 79 (`headsetHook`) を 85 に正規化。<br>- Step 2 で 85 で開始。<br>- Step 3 Part 1 で 87 で調整突入、Part 2 で 24/25 で項目循環＋読み上げ、85 で決定。<br>- Step 4 で 24/25 で ±2.5kg 更新＋デバウンス、85 で決定。<br>- Step 3/4 いずれも 88 で内容確認読み上げ（遷移なし）。<br>- Step 5 で 87 で確定、他キーは注意表示。 |
| **R4** | **UI・演出要件**<br>- 70%半透明ブラック暗転（`Color(0xB3000000)`）＋スポットライトくり抜き (`SpotlightOverlayPainter`)。<br>- ホタル呼吸発光枠線（`AnimationController` ＋ `boxShadow`）。<br>- 発表用スキップ機能（右下スキップボタン `btn_tutorial_skip`、画面タップフォールバック）。<br>- 画面最下部に疑似メディアキーバー（5ボタン）。 | `lib/tutorial_screen.dart:576-675`<br>`lib/tutorial_screen.dart:997-1046`<br>`lib/tutorial_screen.dart:1268-1294`<br>`lib/tutorial_screen.dart:1321-1400`<br>`lib/tutorial_screen.dart:1463-1517` | **PASS**<br>- `Path.combine(PathOperation.difference, ...)` で対象矩形を完全くり抜き。<br>- 呼吸発光枠線は `IgnorePointer` で包まれ、タッチを阻害しない。<br>- 疑似キーバーは常設され、各ボタンが `_handleButtonAction` を呼出。<br>- 右下スキップボタンおよびタップフォールバックによりデモ発表時の安全性を担保。 |
| **R5** | **全6ステップの実装**<br>- Step 1: タイトル、説明、開始ボタン、スキップボタン。<br>- Step 2: 開始操作体験（中央開始ボタンスポットライト、キー85で電子音＋開始TTS＋Step 3自動遷移）。<br>- Step 3: 調整モード突入＆項目選択（Part 1 次曲で「調整、種目名」、Part 2 音量±で項目送り、再生停止で決定）。<br>- Step 4: 重量調整とデバウンス体験（重量カードスポットライト、音量±で±2.5kg即時更新＋0.7sデバウンスTTS、決定で即時破棄＋Step 5）。<br>- Step 5: 調整完了の体験（全体暗転、次曲で「確定、開始...」＋Step 6）。<br>- Step 6: 完了とおさらい（「最初のトレーニングを開始する」またはキー85で本編遷移）。 | `lib/tutorial_screen.dart:284-472`<br>`lib/tutorial_screen.dart:682-1264` | **PASS**<br>- 全6ステップの状態遷移とUIが要件通り実装。<br>- Step 3/4 のキー 88（内容確認）も完全動作。<br>- Step 5 での対象外キー押下時の警告バナー表示も確認。 |
| **R6** | **自動テストによる検証**<br>- 全6ステップ、UI要素、スキップ、仮想キーバー、キーイベント処理、画面遷移を網羅。 | `test/tutorial_screen_test.dart` | **PASS**<br>- 11個のテストケース（マトリクス9項目＋画面遷移＋発光アニメーション）が全パス。 |

---

## 3. Audio & Resource Lifecycle Hygiene Audit

### 3.1 Audio Hygiene Verification
1. **排他制御 (`await ttsService?.stop()`)**:
   - `_speak()` メソッド内において、`await _duckingController.requestDucking();` に続き `await widget.ttsService?.stop();` が明示的に呼び出されている。
   - ステップ遷移時（`_onSkipStepPressed()`, `_navigateToTrainingScreen()`, `_proceedFromStep2()` など）および `dispose()` 時にも `widget.ttsService?.stop()` が漏れなく呼び出されている。
   - テストスイート Test 9 において、`stopCallCount >= spokenHistory.length` のアサーションがパスしていることを確認。
2. **オーディオダッキング制御 (`AudioDuckingController`)**:
   - TTS 発話時およびビープ音再生時に `_duckingController.requestDucking()` が先行実行される。
   - 画面離脱時（`_navigateToTrainingScreen()`）およびウィジェット破棄時（`dispose()`）に `_duckingController.releaseDucking()` が確実に実行され、BGM音量の低下が残留するリスクを排除。

### 3.2 Resource & Lifecycle Hygiene Verification
1. **0.7秒デバウンスタイマー (`Timer? _debounceTimer`, `Timer? _framePumpTimer`)**:
   - 重量調整時に新しいタイマーを発行する前に `_cancelDebounce()` で既存タイマーを確実にキャンセル。
   - Step 4 から Step 5 への決定キー（85）押下時、スキップボタン押下時、本編画面遷移時、および `dispose()` 時に `_cancelDebounce()` が明示的に呼ばれ、未実行のタイマーコールバックが破棄されることを確認（テスト4で保留中音声が発話されないことを検証済み）。
2. **アニメーションコントローラ (`AnimationController _glowController`)**:
   - `dispose()` 内で `_glowController.dispose()` が呼び出されている。
   - `_startGlowIfNeeded()` により、スポットライトが存在しない Step 1 および Step 6 ではアニメーションが停止（`_glowController.stop()`）され、無駄なリフレッシュ負荷やウィジェットテストでの `pumpAndSettle()` 無限待機を防止。
3. **キーボードフォーカスノード (`FocusNode _keyboardFocusNode`)**:
   - `dispose()` 内で `_keyboardFocusNode.dispose()` が呼び出されている。
4. **イベントリスナー (`KeyEventChannelDispatcher`)**:
   - `initState()` で `KeyEventChannelDispatcher.instance.registerListener(_handleButtonAction)`、`dispose()` で `KeyEventChannelDispatcher.instance.unregisterListener(_handleButtonAction)` が対称に呼び出されており、メモリリークのリスクなし。
5. **画面遷移二重実行ガード (`bool _isNavigating`)**:
   - `_navigateToTrainingScreen()` の先頭で `if (!mounted || _isNavigating) return; _isNavigating = true;` によるガードがあり、連打時の多重遷移を防止。

---

## 4. Adversarial Challenge Analysis & Edge Case Stress-Testing

### Challenge 1: スポットライト座標のレイアウト不整合・例外発生リスク
- **仮説**: ウィジェットツリーの再描画中やキーボード表示時、`_spotlightRect` の計算で `RenderBox` が null またはサイズ未確定となり、座標計算エラーや `NoSuchMethodError` が発生するのではないか？
- **検証結果**: `_updateSpotlightRect()` 内で `WidgetsBinding.instance.addPostFrameCallback` を使用し、さらに `renderBox != null && renderBox.hasSize && stackBox != null && stackBox.hasSize` のサイズ確定ガードを設けている。また、旧値と新値が一致する場合は `setState` をスキップする最適化が行われており、無限再描画ループも防止されている。**PASS (堅牢)**。

### Challenge 2: Step 4 重量調整の極値入力（境界値・オーバーフロー）
- **仮説**: 音量マイナスキーを連打し続けた場合、重量が負の値になる、あるいは上限値を超えて表示が崩れるのではないか？
- **検証結果**: `(_currentWeight +/- 2.5).clamp(0.0, 500.0)` により、0.0kg から 500.0kg の範囲に厳格にクリップされている。0kg 未満への突入は不可能。**PASS (堅牢)**。

### Challenge 3: プレゼン本番でのキーイベント不通・イヤホン不調
- **仮説**: デモ発表時に実機イヤホンの Bluetooth 接続が切断された場合、チュートリアルがその場で停止してしまうのではないか？
- **検証結果**:
  1. 画面最下部に疑似メディアキーバー（5ボタン）が常設されており、画面タップで全操作が可能。
  2. 右下に常設スキップボタン（`Key('btn_tutorial_skip')`）が配置されており、ワンタップで次ステップへ進める。
  3. Step 2 では画面中央タップでも開始アクションが発火する。
  4. AppBar 右上に「本編へ」ボタンが常設されており、いつでも本編 `TrainingScreen` へ直行可能。
  デモ本番のフェイルセーフは多重に構築されている。**PASS (堅牢)**。

### Challenge 4: テスト環境での無限アニメーションタイマー
- **仮説**: `AnimationController.repeat()` が常時回っていると、ウィジェットテストの `tester.pumpAndSettle()` がタイムアウトで停止するのではないか？
- **検証結果**:
  1. `TutorialScreen` のコンストラクタ引数に `animateGlow: false` を受け取れる設計となっており、テスト時に制御可能。
  2. Step 1（初期画面）および Step 6（完了画面）ではアニメーションを自動停止するため、`main.dart` からの結合遷移テストでも `pumpAndSettle()` が即座に完了する。**PASS (堅牢)**。

---

## 5. Integrity & Forensic Audit

- **テスト結果のハードコード**: ソースコード内にテスト用フラグや固定の期待値埋め込みは一切なし。状態遷移、デバウンス、キーコード分岐、座標計算はすべて実ロジックで動作。
- **ダミー/ファサード実装**: 全6ステップのUI、オーバーレイ描画、アニメーション、音声呼び出しが実体を伴って実装されている。
- **ショートカット/バイパス**: 既存音声サービス（`TtsService`, `SoundEffectService`, `AudioDuckingController`）を正当にDIし、要件通りの連携を行っている。
- **検証ログの真正性**: `flutter analyze` および `flutter test --no-test-assets` を独立実行し、25/25テスト成功を確認（偽装なし）。

---

## 6. Review Verdict

**APPROVE**

実装は設計契約、UI演出要件、メディアキー操作仕様、音声排他・ダッキング制御、リソースライフサイクルのすべてにおいて高品質であり、本番プレゼンテーションデモでの実演に耐えうる堅牢性を備えています。
