# Handoff Report: TutorialScreen Visual Presentation, Layout, and Animation Design

**Folder**: `c:\Users\taqmi\02_development\original_program\noukin_app\.agents\teamwork\explorer_m1_2\`  
**Date**: 2026-11-10  
**Status**: Completed (Hard Handoff)

---

## 1. Observation

1. **`lib/training_screen.dart` の既存UIカード構成と操作バー構造**:
   - `lib/training_screen.dart` 360-382行目に、中央の「開始 / 次へ」ボタン（`Key('btn_next_workout')`）が配置されている。
   - `lib/training_screen.dart` 384-413行目および 431-523行目に、数値調整カード（`card_weight`, `card_reps`, `card_sets`）と増減ボタン（`btn_weight_down`, `btn_weight_up` 等）が配置されている。
   - `lib/training_screen.dart` 658-761行目に、5ボタン構成（`btn_media_prev`, `btn_media_play_pause`, `btn_media_next`, `btn_media_vol_down`, `btn_media_vol_up`）の疑似メディアキーバー（`_buildMediaControlBar`）が実装されている。
2. **`lib/theme/app_colors.dart` のカラーパレット仕様**:
   - `background: Color(0xFF121212)`
   - `surface: Color(0xFF1E1E1E)`
   - `surfaceVariant: Color(0xFF2C2C2C)`
   - `border: Color(0xFF2E2E2E)`
   - `tealAccent: Colors.tealAccent`
   - `primaryAccent: Color(0xFFFF9100)`
3. **`lib/main.dart` のキー配信およびエントリーポイント導線**:
   - `lib/main.dart` 472-524行目: `KeyEventChannelDispatcher` がシングルトンとして最前面画面に `ButtonAction`（85, 79, 24, 25, 87, 88）を配信。
   - `lib/main.dart` 674-702行目: 「トレーニング開始」ボタン（`Key('start_training_button')`）が配置されており、その直下に「操作チュートリアルを体験する」ボタンを追加する導線が存在する。
4. **`test/widget_test.dart` のテスト実行環境**:
   - `sendNativeKeyEvent(tester, keyCode)`（`test/widget_test.dart` 10-32行目）により、キーイベント発火がシミュレーション可能。
   - `AnimationController.repeat(reverse: true)` が稼働したままテスト内で `tester.pumpAndSettle()` を呼ぶと、未完了フレームが持続するためタイムアウトが発生する。
5. **要件ドキュメント（`ORIGINAL_REQUEST.md`）の R4・R5 仕様**:
   - R4: 半透明ブラック（Black 70%）暗転オーバーレイ、ホタルの呼吸発光枠線（`AnimationController` ＋ `boxShadow`）、発表用スキップ機能（右下ボタン＋画面タップ）、画面最下部の疑似メディアキーバー。
   - R5: Step 1（案内画面）、Step 2（開始操作体験）、Step 3（調整モード突入＆項目選択）、Step 4（重量調整とデバウンス体験）、Step 5（調整完了の体験）、Step 6（完了と本編スタート）。

---

## 2. Logic Chain

1. **差分くり抜きスポットライト方式の採用**（Observation 5, 2 に基づく）:
   - 全画面を `Colors.black.withOpacity(0.70)`（`Color(0xB3000000)`）で覆い、注目対象矩形（`targetRect`）を `PathOperation.difference` でくり抜く `SpotlightOverlayPainter` を設計。
   - オフスクリーンバッファを確保する `saveLayer` を使用しないため、描画パフォーマンスが最大化され、くり抜かれたボタンやカードは100%の透過度でクリアに視認できる。
2. **ホタルの呼吸発光枠線と `IgnorePointer`**（Observation 5, 2 に基づく）:
   - 1200ms周期（`Curves.easeInOut`）の `AnimationController` と `AppColors.tealAccent` の二重 `boxShadow` を組み合わせることで、生体的な明滅エフェクトを実現。
   - この発光レイヤーを `Positioned` ＋ `IgnorePointer` で配置することにより、スポットライト内のボタンタップ判定が下層ウィジェットへ完全に透過し、ユーザーが実機画面のボタンを直接タップしても確実に反応する。
3. **テスト安全性引数 `animateGlow` の必然性**（Observation 4 に基づく）:
   - `AnimationController.repeat(reverse: true)` はテスト環境で `pumpAndSettle timed out` を引き起こす。
   - コンストラクタ引数 `animateGlow: bool = true` を設け、テスト時に `animateGlow: false` を渡すことでリピートを開始せず、固定値 1.0 の枠線を表示する設計とした。これにより、テスト実行時にすべてのフレームタイマーが安全に停止し、即座に検証を完了できる。
4. **全6ステップのビジュアルとフォーカス要素の体系化**（Observation 1, 5 に基づく）:
   - Step 1: 全画面案内カード（暗転なし、`targetRect = null`）
   - Step 2: 中央「開始」ボタン（`Key('btn_next_workout')`）をスポットライト
   - Step 3 Part 1: 種目名表示領域をスポットライト（87キーで突入）
   - Step 3 Part 2: 選択中の項目カード（種目名 ⇄ 重量 ⇄ レップ数 ⇄ セット数）にスポットライトが連動移動
   - Step 4: 重量カード（`Key('card_weight')`）をスポットライトし、リアルタイム ±2.5kg 更新と 0.7秒デバウンスTTS読み上げ
   - Step 5: 全画面暗転（`targetRect = null`）、中央に調整完了案内カードを表示
   - Step 6: 暗転解除、祝福カード（`Key('card_step6_celebration')`）と「最初のトレーニングを開始する」ボタン
5. **発表時の機材トラブル防止設計**（Observation 1, 5 に基づく）:
   - 右下に常設スキップボタン（`Key('btn_tutorial_skip')`）を配置し、暗転画面全体のタップフォールバックを組み込むことで、Bluetoothイヤホンの通信トラブル時もプレゼン実演を継続可能とした。
   - 疑似メディアキーバー（`_buildMediaControlBar`）を暗転オーバーレイの最前面（上層）に常設し、PC/エミュレータ/マウスタップでも100%同一の操作パイプラインを実行可能とした。

---

## 3. Caveats

1. **初回ビルド時の `targetRect` 取得**:
   - `GlobalKey` による要素の座標取得（`RenderBox.localToGlobal`）は、最初のフレーム描画完了後（`WidgetsBinding.instance.addPostFrameCallback`）にのみ有効です。そのため、初回フレームでは `_spotlightRect = null`（全画面暗転）で描画され、コールバック内で座標が確定した瞬間にスポットライトくり抜きが適用されます。
2. **`TrainingScreen` の非変更制約**:
   - 既存の `lib/training_screen.dart` は一切変更してはなりません。すべてのUI・アニメーション演出は新規作成する `lib/tutorial_screen.dart` 内に独立して完結させる必要があります。

---

## 4. Conclusion

1. **モジュール設計の確立**:
   - `SpotlightOverlayPainter`（差分減算くり抜き、Black 70%）
   - `_buildGlowOverlay()`（ホタル呼吸発光枠線、`animateGlow` フラグ対応）
   - 全6ステップのビジュアルカード・ガイダンスカード・フォーカス要素
   - 発表用スキップボタン（右下）および画面タップフォールバック
   - 最前面の疑似メディアキーバー（`_buildMediaControlBar`）
   すべての詳細設計・コードスニペット・パラメータが `analysis.md` に網羅されました。
2. **Worker への実装指針**:
   - Worker は本レポートおよび `analysis.md` に定義されたクラス構造・ステートマシン・レイヤー順序に従って `lib/tutorial_screen.dart` の実装を直ちに開始できます。

---

## 5. Verification Method

1. **設計ドキュメントの整合性検証**:
   - `c:\Users\taqmi\02_development\original_program\noukin_app\.agents\teamwork\explorer_m1_2\analysis.md` を閲覧し、以下の要件が完全に満たされていることを確認する：
     - `SpotlightOverlayPainter` の実装コード
     - `animateGlow: bool = true` のテスト安全機構
     - Step 1〜Step 6 の全ビジュアルカードとスポットライト座標指定
     - スキップボタン（`Key('btn_tutorial_skip')`）および画面最下部メディアキーバー（`Key('btn_media_play_pause')` 等）
2. **既存テストスイートの実行確認**:
   ```powershell
   flutter test
   ```
   - 期待値: exit code 0、全14テストパス。
3. **Worker 実装完了後の検証コマンド**:
   ```powershell
   flutter test test/tutorial_screen_test.dart
   ```
   - 期待値: 全6ステップのUI・アニメーション・キー操作・スキップ・仮想キーバーの自動テストがすべて成功すること。
