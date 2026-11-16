# Survey Handoff Report: UI Rendering and Automated Test Architecture

**State folder**: `c:\Users\taqmi\02_development\original_program\noukin_app\.agents\teamwork\survey_explorer_3\`  
**Date**: 2026-11-10  
**Status**: Completed (Hard Handoff)

---

## 1. Observation

1. **`lib/main.dart` の既存モック・フェイクおよびディスパッチャ構造**:
   - `lib/main.dart` 130-156行目に `FakeAudioDuckingController` が定義されている。
   - `lib/main.dart` 189-201行目に `FakeSoundEffectService`（`beepCount` 計測）が定義されている。
   - `lib/main.dart` 363-399行目に `FakeTtsService`（`spokenHistory`, `stopCallCount`, `currentVolume` 記録）が定義されている。
   - `lib/main.dart` 472-524行目に `KeyEventChannelDispatcher` がシングルトンとして実装され、`registerListener` / `unregisterListener` で最前面のリスナーへキーイベント（85, 79, 24, 25, 87, 88）を配信している。
   - `lib/main.dart` 674-702行目に「トレーニング開始」ボタン（`Key('start_training_button')`）が配置されている。
2. **`lib/training_screen.dart` の構成と非変更制約**:
   - `ORIGINAL_REQUEST.md` R1:「既存の `lib/training_screen.dart` は直接変更せず、新規に `lib/tutorial_screen.dart` を作成して独立した画面モジュールとして実装すること。」
   - `lib/training_screen.dart` 658-701行目において、画面最下部に 5ボタン構成（再生/停止、次曲、前曲、Vol-、Vol+）の疑似メディアキーバー（`_buildMediaControlBar`）がすでに実装されている。
3. **`test/widget_test.dart` のテスト実行環境**:
   - `sendNativeKeyEvent(tester, keyCode)`（`test/widget_test.dart` 10-32行目）により、ネイティブ MethodChannel 経由のキーイベント発火がテスト可能。
   - `flutter test` コマンドを実行した結果、14個の全テストが 5.0秒で成功（exit code 0）することを確認。
4. **Flutter の `AnimationController.repeat` によるテスト待機挙動**:
   - `AnimationController.repeat(reverse: true)` がアクティブな状態で `await tester.pumpAndSettle()` を実行すると、フレーム更新が停止しないためタイムアウト（`pumpAndSettle timed out`）が発生する。
5. **暗転オーバーレイとスポットライトの描画API**:
   - `CustomPainter` 内で `Path.combine(PathOperation.difference, backgroundPath, holePath)` を使用することで、`Colors.black.withOpacity(0.70)` から特定ウィジェットの `RRect` をハードウェアアクセラレーションで高速かつ完全にくり抜き可能。

---

## 2. Logic Chain

1. **暗転オーバーレイとスポットライトの最適解の導出**（Observation 5 に基づく）:
   - 全画面の黒70%半透明描画から、注目対象の `targetRect` を `PathOperation.difference` でくり抜くことで、くり抜かれた領域は100%の透過度となり、下層のカードやボタンの輝度・視認性が最高状態に保たれる。
   - `saveLayer` を用いる `BlendMode.clear` 方式と異なり、オフスクリーンバッファをアロケーションしないため、60fps/120fps の滑らかなアニメーションを維持できる。
2. **ホタルの呼吸発光アニメーションの実装方式**（Observation 5 に基づく）:
   - `targetRect` の直上に `Positioned` + `IgnorePointer` のコンテナを重ね、`AnimationController`（1200ms周期、`Curves.easeInOut`）で `boxShadow` の `blurRadius` と `spreadRadius` を動的に伸縮させる。
   - `IgnorePointer` によりタップ判定が透過するため、ユーザーがスポットライトされたボタンやカードを直接タップした際もイベントが確実に下層へ伝達される。
3. **安全なテスト設計とDI（依存性の注入）**（Observation 1, 3, 4 に基づく）:
   - `TutorialScreen` が `ttsService`、`soundEffectService`、`duckingController`、および `animateGlow`（デフォルト `true`）をコンストラクタで受け取る設計とすることで、既存の `FakeTtsService`、`FakeSoundEffectService`、`FakeAudioDuckingController` をそのまま注入できる。
   - テスト実行時は `animateGlow: false` を指定することで、`pumpAndSettle()` のタイムアウトを回避しながら全6ステップの状態遷移・キーハンドリングを瞬時に検証可能となる。
4. **仮想メディアキーバーとキー入力の完全一致**（Observation 1, 2 に基づく）:
   - 最下部の仮想キーバーの各ボタン押下時に、ネイティブキー受信時と同一のハンドラメソッド（`_handleButtonAction`）を呼び出す設計とすることで、Bluetoothイヤホン、ADB、PCキーボード、マウスクリックのすべてで挙動の完全な一致が保証される。
5. **発話重複防止とライフサイクル**（Observation 1 に基づく）:
   - `TutorialScreen` 内の発話メソッドで `await widget.ttsService?.stop()` を呼んでから `speak()` を実行することで、R2 要件（前の発話を中断して新しい発話を開始）が確実に満たされ、`FakeTtsService.stopCallCount` で検証可能となる。

---

## 3. Caveats

- **Caveat 1 (初回ビルド時の `targetRect` 取得)**:
  `GlobalKey` を用いた要素の矩形座標取得は、最初のフレーム描画完了後（`WidgetsBinding.instance.addPostFrameCallback`）にのみ有効です。そのため、初回フレームでは全画面暗転またはフォールバック座標を保持し、コールバックで `setState` して正確なくり抜き矩形を確定させる必要があります。
- **Caveat 2 (AVIF画像アセットのウィジェットテスト環境)**:
  テスト環境では AVIF 画像のデコードで警告が出る場合がありますが、既存の `TrainingScreen` と同様に `errorBuilder` を実装することでテスト実行を妨げません。

---

## 4. Conclusion

1. **UI描画演出**:
   - `Path.combine(PathOperation.difference)` によるスポットライト暗転オーバーレイ（`SpotlightOverlayPainter`）と、`Positioned` + `IgnorePointer` による二重 `boxShadow` ホタル呼吸枠線を組み合わせることで、要件（Black 70% 暗転、ホタル発光枠線）を最高水準の描画パフォーマンスで達成可能。
2. **自動テスト構成**:
   - `TutorialScreen` に DI 引数（`ttsService`, `soundEffectService`, `duckingController`, `animateGlow`）を設けることで、既存の `FakeTtsService` 等を活用し、`test/tutorial_screen_test.dart` において全6ステップ、デバウンス、スキップ、疑似メディアキーバーを100%網羅した自動テストを安全・高速に実行可能。
3. **詳細ドキュメント**:
   - 詳細なクラス設計、コードスニペット、全6ステップのテストマトリクスは `analysis.md` に記載済み。

---

## 5. Verification Method

1. **既存テストの健全性確認**:
   ```powershell
   flutter test
   ```
   - 期待値: exit code 0、全14テストパス。
2. **分析レポートの精査**:
   - `c:\Users\taqmi\02_development\original_program\noukin_app\.agents\teamwork\survey_explorer_3\analysis.md` を閲覧し、UI演出・DI設計・6ステップテスト設計が揃っていることを確認。
3. **将来の `TutorialScreen` 実装後の検証コマンド**:
   ```powershell
   flutter test test/tutorial_screen_test.dart
   ```
   - 期待値: 全6ステップ、スキップボタン、仮想キーバー、デバウンス、TTS重複防止のテストがすべて成功すること。
