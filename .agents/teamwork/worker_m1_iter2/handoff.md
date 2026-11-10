# Handoff Report: TutorialScreen Concurrency & Lifecycle Remediation

**Agent**: worker_m1_iter2 (implementer, qa, specialist)  
**State folder**: `c:\Users\taqmi\02_development\original_program\noukin_app\.agents\teamwork\worker_m1_iter2\`  
**Target File**: `c:\Users\taqmi\02_development\original_program\noukin_app\lib\tutorial_screen.dart`  
**Date**: 2026-11-10  
**Handoff Type**: Hard Handoff (Task Complete)  

---

## 1. Observation

1. **初期テスト実行（再現確認）**:
   - `test/stress_tutorial_keys_test.dart`:
     - コマンド: `flutter test --no-test-assets test/stress_tutorial_keys_test.dart`
     - 結果: 19テスト中4テスト失敗（exit code 1）。
       - Step 2 Key 85連打: `Expected: <1>, Actual: <2>`
       - Step 3 Part 1 Key 87連打: `Expected: <1>, Actual: <2>`
       - Step 4 Key 85連打: `Expected: <1>, Actual: <2>`
       - Step 5 Key 87連打: `Expected: <1>, Actual: <2>`
   - `test/stress_tutorial_audio_test.dart`:
     - コマンド: `flutter test --no-test-assets test/stress_tutorial_audio_test.dart`
     - 結果: 9テスト中6テスト失敗（exit code 1）。
       - Test 1 (連打による多重発話 Actual: <3>)
       - Test 2 (Step 2 発話保留中スキップによる Step 4 ➔ Step 3 先祖返り)
       - Test 3 (Step 4 デバウンス待機中スキップによるダッキング残留 `Expected: <false>, Actual: <true>`)
       - Test 6 (Step 4 デバウンス待機中画面 pop 時の事後発話 `Expected: empty, Actual: ['62.5キロ']`)
       - Test 8 (Step 3 決定発話保留中スキップによる Step 5 ➔ Step 4 先祖返り)
       - Test 9 (Step 5 確定キー連打時の重複発話 Actual: <3>)

2. **コード構造の確認 (`lib/tutorial_screen.dart`)**:
   - `_isNavigating`（本編遷移用）フラグは存在したが、ステップ間の非同期音声処理待機中における再入防止排他フラグおよび世代トークンが存在しなかった。
   - `_proceedFromStep2()`, `_handleStep3Action()`, `_handleStep4Action()`, `_handleStep5Action()` は `await _playBeep()` および `await _speak(...)` 完了後に `if (!mounted) return;` のみをチェックしており、保留中にスキップ等で進んだステップを検証していなかったため状態巻き戻し（先祖返り）が発生していた。
   - `_onSkipStepPressed()` で `_duckingController.releaseDucking()` を呼んでいなかったため、デバウンス中にスキップした際にBGMダッキング状態が残留していた。
   - 画面離脱（AppBar 戻るボタンやシステムPop）時にデバウンスタイマー破棄・TTS停止・ダッキング解除が先行して呼ばれず、画面離脱アニメーション中にタイマーが発火して事後発話が発生していた。

3. **修正後の検証実行結果**:
   - `flutter analyze` ➔ `No issues found! (ran in 1.7s)` (exit code 0)
   - `flutter test --no-test-assets test/stress_tutorial_keys_test.dart` ➔ `00:08 +19: All tests passed!` (19/19 passed, exit code 0)
   - `flutter test --no-test-assets test/stress_tutorial_audio_test.dart` ➔ `00:04 +9: All tests passed!` (9/9 passed, exit code 0)
   - `flutter test --no-test-assets test/tutorial_screen_test.dart` ➔ `00:04 +11: All tests passed!` (11/11 passed, exit code 0)
   - `flutter test --no-test-assets` ➔ `00:06 +53: All tests passed!` (全53テスト通過, exit code 0)

---

## 2. Logic Chain

1. **非同期再入（リエントラント）の解決**:
   - 状態変数に `bool _isStepTransitioning = false;` および `int _transitionGeneration = 0;` を追加。
   - `_handleButtonAction` の先頭ガードに `if (!mounted || _isNavigating || _isStepTransitioning) return;` を配置。
   - `_proceedFromStep2()`, `_handleStep3Action()`, `_handleStep4Action()`, `_handleStep5Action()` の各遷移処理先頭で `if (_isStepTransitioning) return; _isStepTransitioning = true; final gen = ++_transitionGeneration;` を実行。
   - 処理完了の `finally` ブロックで `if (mounted && gen == _transitionGeneration) { _isStepTransitioning = false; }` を実行。
   - これにより、キー連打や画面連続タップが発生しても、非同期発話完了まで後続の同一アクションが完全にブロックされ、多重ビープおよび多重発話（Actual: 2 や 3）が解消された。
   - 一方、Step 4 の音量キー連打（±2.5kgリアルタイム加算）はステップ遷移ではないため `_isStepTransitioning` ロックの対象外とし、高速連打性能を完全維持。

2. **ステートマシン先祖返り（State Reversion）の解決**:
   - `_proceedFromStep2()`, `_handleStep3Action()`, `_handleStep4Action()`, `_handleStep5Action()` の非同期処理（`await _playBeep()`, `await _speak(...)`）直後に：
     ```dart
     if (!mounted || _currentStep != expectedStep || gen != _transitionGeneration) {
       return;
     }
     ```
     を必ず実行するように改修。
   - ユーザーが音声再生中にスキップボタンを押下すると、`_onSkipStepPressed()` 内で `_transitionGeneration++` がインクリメントされ、`_currentStep` が即座に前進する。
   - 遅延していた音声 Future が完了しても `gen != _transitionGeneration` または `_currentStep != expectedStep` に合致して即時 return するため、過去のステップ番号で `setState` が上書きされる先祖返りが完全に防止された。
   - 同時に `_onSkipStepPressed()` で `_isStepTransitioning = false;` にリセットされるため、スキップ先ステップで即座にユーザー操作を受け付けることができる。

3. **オーディオダッキング残留（Ducking Leak）の解決**:
   - `_onSkipStepPressed()` において `_cancelDebounce()` および `widget.ttsService?.stop()` に加え、`_duckingController.releaseDucking();` を明示的に呼び出し。
   - 同様に `_navigateToTrainingScreen()`（本編遷移時）にも `_duckingController.releaseDucking();` を配置。
   - これにより、Step 4 で音量キー押下によりダッキングが掛かった後、0.7秒デバウンスを待たずにスキップや遷移を行っても、BGM音量が低下したまま放置されるリークが解消された。

4. **画面離脱後の事後発話（Post-Dispose Speech）の解決**:
   - AppBar の戻るボタン（`Icons.arrow_back`）の `onPressed` で `_cancelDebounce(); widget.ttsService?.stop(); _duckingController.releaseDucking(); Navigator.of(context).pop();` を実行。
   - さらに `Scaffold` を `PopScope` でラップし、システムPop（OSバックジェスチャー等）時にも `onPopInvokedWithResult: (didPop, _) { if (didPop) { _cancelDebounce(); widget.ttsService?.stop(); _duckingController.releaseDucking(); } }` を実行。
   - デバウンスタイマーのコールバック先頭および `_speak()` の先頭に `if (!mounted) return;` の二重防壁を追加。
   - これにより、離脱アニメーション中（未dispose時）やdispose後に保留中タイマーが発話を行う不具合が完全に解消された。

---

## 3. Caveats

- **制約遵守の確認**:
  - `lib/training_screen.dart` は一切変更していません（R1 / Write Ownership 厳守）。
  - 変更ファイルは `lib/tutorial_screen.dart` のみです。
- **No Caveats**:
  - 全ての既存単体テスト、新規キーストレステスト、新規オーディオストレステストがパスしており、残存課題はありません。

---

## 4. Conclusion

`lib/tutorial_screen.dart` に対する再入防止ロック、世代トークンによる先祖返り防止、スキップ・離脱時のダッキング解除、および PopScope / デバウンスガードの実装が完了しました。

### 修正サマリ
1. `_isStepTransitioning` 排他フラグと `_transitionGeneration` 世代トークンの追加
2. 各ステップ遷移ハンドラ（Step 2, Step 3 Part 1/2, Step 4, Step 5）への `try-finally` ガード適用
3. 非同期音声・電子音待機直後における `gen != _transitionGeneration` および `_currentStep != expectedStep` 検証
4. `_onSkipStepPressed()` における `_transitionGeneration++`, `_isStepTransitioning = false`, `releaseDucking()`
5. AppBar 戻るボタンおよび `PopScope` による画面離脱時の `_cancelDebounce()`, `stop()`, `releaseDucking()` 即座実行
6. デバウンスコールバックおよび `_speak()` における `mounted` ガード適用
7. Dart 分析ルール（`curly_braces_in_flow_control_structures`）に準拠したブロック記述

---

## 5. Verification Method

以下のコマンド群を実行して独立検証可能です：

```powershell
# 1. 静的解析（0 issues を確認）
flutter analyze

# 2. キーストレステスト（19/19 通過を確認）
flutter test --no-test-assets test/stress_tutorial_keys_test.dart

# 3. オーディオ＆並行性ストレステスト（9/9 通過を確認）
flutter test --no-test-assets test/stress_tutorial_audio_test.dart

# 4. チュートリアル画面単体テスト（11/11 通過を確認）
flutter test --no-test-assets test/tutorial_screen_test.dart

# 5. ワークスペース全テスト（53/53 通過を確認）
flutter test --no-test-assets
```

- **合格判定**: 全テストが Exit code 0 でパスすること。
- **失効条件**: いずれかのテストで失敗が発生した場合、または `lib/training_screen.dart` に変更が加えられた場合は無効。
