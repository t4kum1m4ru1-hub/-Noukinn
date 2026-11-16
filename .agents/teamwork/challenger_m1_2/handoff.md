# Handoff Report: TutorialScreen Audio Concurrency & Lifecycle Adversarial Challenge

**Agent**: challenger_m1_2 (empirical-challenger, critic, specialist)  
**State folder**: `c:\Users\taqmi\02_development\original_program\noukin_app\.agents\teamwork\challenger_m1_2\`  
**Date**: 2026-11-10  
**Status**: Hard Handoff (Completed)  
**Verdict**: **REQUEST_CHANGES**

---

## 1. Observation

1. **既存テストスイートの通過確認**:
   - `flutter analyze` 実行結果: `No issues found! (ran in 2.3s)`（exit code 0）。
   - `flutter test --no-test-assets test/tutorial_screen_test.dart` 実行結果: `00:04 +11: All tests passed!`（exit code 0）。
   - 既存のハッピーパス中心のテストマトリクスはすべて合格していた。

2. **新規作成した敵対的ストレステストスイート**:
   - テストファイル: `test/stress_tutorial_audio_test.dart`（全9テストケース）。
   - 実行コマンド: `flutter test --no-test-assets test/stress_tutorial_audio_test.dart`
   - 実行結果: `00:05 +3 -6: Some tests failed.`（exit code 1）。

3. **検出された具体的な失敗ログ（抜粋）**:
   - **Test 1（Step 2 キー85連打時の多重発話）**:
     ```
     ══╡ EXCEPTION CAUGHT BY FLUTTER TEST FRAMEWORK ╞════════════════════════════════════════════════════
     The following TestFailure was thrown running a test:
     Expected: <1>
       Actual: <3>
     Step 2 開始キーの連打で複数回 TTS が多重発話されてはならない (再入防止)
     line 185 in test/stress_tutorial_audio_test.dart
     ```
   - **Test 2（Step 2 発話保留中にスキップ連打で Step 4 に進んだ後の逆流）**:
     ```
     ══╡ EXCEPTION CAUGHT BY FLUTTER TEST FRAMEWORK ╞════════════════════════════════════════════════════
     The following TestFailure was thrown running a test:
     Expected: exactly one matching candidate
       Actual: _TextContainingWidgetFinder:<Found 0 widgets with text containing 重量調整と音声: []>
        Which: means none were found but one was expected
     Step 2 の非同期コールバック完了によって Step 4 から Step 3 へ先祖返りしてはならない
     line 231 in test/stress_tutorial_audio_test.dart
     ```
   - **Test 3（Step 4 重量変更後にデバウンスを待たずスキップした際のダッキング残留）**:
     ```
     ══╡ EXCEPTION CAUGHT BY FLUTTER TEST FRAMEWORK ╞════════════════════════════════════════════════════
     The following TestFailure was thrown running a test:
     Expected: <false>
       Actual: <true>
     デバウンスTTSがスキップされた場合、オーディオダッキングは解除されなければならない
     line 278 in test/stress_tutorial_audio_test.dart
     ```
   - **Test 6（Step 4 デバウンス中に AppBar 戻るボタンで pop した際の事後発話）**:
     ```
     ══╡ EXCEPTION CAUGHT BY FLUTTER TEST FRAMEWORK ╞════════════════════════════════════════════════════
     The following TestFailure was thrown running a test:
     Expected: empty
       Actual: ['62.5キロ']
     line 444 in test/stress_tutorial_audio_test.dart
     ```
   - **Test 8（Step 3 決定発話保留中にスキップ連打で Step 5 に進んだ後の逆流）**:
     ```
     ══╡ EXCEPTION CAUGHT BY FLUTTER TEST FRAMEWORK ╞════════════════════════════════════════════════════
     The following TestFailure was thrown running a test:
     Expected: exactly one matching candidate
       Actual: _TextContainingWidgetFinder:<Found 0 widgets with text containing 調整の完了: []>
     Step 3 の決定発話完了によって Step 5 から Step 4 へ先祖返りしてはならない
     line 525 in test/stress_tutorial_audio_test.dart
     ```
   - **Test 9（Step 5 確定キー87連打時の確定音声多重発話）**:
     ```
     ══╡ EXCEPTION CAUGHT BY FLUTTER TEST FRAMEWORK ╞════════════════════════════════════════════════════
     The following TestFailure was thrown running a test:
     Expected: <1>
       Actual: <3>
     Step 5 確定キー連打で複数回 TTS が多重発話されてはならない
     line 563 in test/stress_tutorial_audio_test.dart
     ```

4. **合格した領域（堅牢性が実証されたテスト）**:
   - **Test 4**: `speak()` 直前の `stop()` 呼び出し順序（Audio Hygiene）は完全順守（100% stop 先行）。
   - **Test 5**: TTS発話中の画面 pop においてクラッシュや `setState after dispose` は発生せず安全にアンマウント。
   - **Test 7**: 最下部仮想キーバー Vol+ の20回高速連打で、リアルタイムUI更新（110 kg）とデバウンス発話（「110キロ」1回のみ）が正常動作。

---

## 2. Logic Chain

1. **ステートマシン逆流バグ（Bug 1）の原因分析**:
   - `lib/tutorial_screen.dart` の 328〜338行目（`_proceedFromStep2`）および 375〜384行目（`_handleStep3Action` 内の再生キー分岐）において、非同期処理 `await _speak(...)` の後に実行される `setState` は、`if (!mounted) return;` のみをチェックしている。
   - ユーザーが音声待機中にスキップボタン（`Key('btn_tutorial_skip')`）を押した場合、`_currentStep` は直ちに次以降のステップ（Step 3 ➔ Step 4、または Step 4 ➔ Step 5）へ前進する。
   - しかし、先行して走っていた非同期発話が完了した瞬間に `setState(() { _currentStep = TutorialStep.step3Select; })` や `setState(() { _currentStep = TutorialStep.step4Adjust; })` が無条件に実行され、**現在の進んだステップを上書きして過去のステップへと巻き戻してしまう**。
   - 実演プレゼン時、音声の終了を待たずに画面を進めた発表者が強制的に過去ステップへ引き戻され、進行不能・混乱に陥る致命的な欠陥である。

2. **オーディオダッキング残留リーク（Bug 2）の原因分析**:
   - `lib/tutorial_screen.dart` の 394〜409行目において、Step 4 の音量ボタン押下時に `await _playBeep()` が呼ばれ、`_duckingController.requestDucking()` が実行される。
   - この直後に0.7秒のデバウンスタイマーが始動し、TTS発話が予約される。
   - ユーザーが0.7秒以内にスキップボタンを押すと、443〜472行目の `_onSkipStepPressed()` が呼ばれ、`_cancelDebounce()` でタイマーが破棄される。
   - その結果、TTS発話（およびTTS完了時のダッキング解除）は永久に実行されず、かつ `_onSkipStepPressed()` 自体も `_duckingController.releaseDucking()` を呼ばない。
   - したがって、**電子音再生のために要求された BGM ダッキングが未来永劫解除されず、BGM 音量が小さくなったまま放置される**（Acceptance Criteria「全TTS発話および電子音再生時に AudioDuckingController のダッキング要求および解除が適切に実行されること」の明確な違反）。

3. **ボタン連打時の多重発話（Bug 3）の原因分析**:
   - `_proceedFromStep2()` および `_handleStep5Action()` は、再入（リエントラント）ガード（処理中フラグ等）を持っていない。
   - キーや画面タップが連続して発生すると、1回目の `await _playBeep()` や `await _speak()` が保留されている間に2回目・3回目の呼び出しが並行実行され、電子音が複数回鳴り、TTS発話も複数回キューイングされる。

4. **画面離脱時のデバウンスタイマー事後発話（Bug 4）の原因分析**:
   - AppBar の「戻る」ボタン（588行目 `onPressed: () => Navigator.of(context).pop()`）は、画面を閉じるアニメーションを開始するだけで、保留中の `_debounceTimer` をキャンセルしない。
   - 加えて、100ms周期の `_framePumpTimer` がフレーム要求を続けるため、Pop遷移中に0.7秒が経過して `_speak('62.5キロ')` が発火する。ユーザーが画面を閉じた後にイヤホンから音声が漏れ出す。

---

## 3. Caveats

- **テストコード自体の分離**:
  - 本検証で作成したテストコードは `test/stress_tutorial_audio_test.dart` として独立しており、`PROJECT.md` のレイアウト規約（テストは `test/` に配置）を遵守している。
- **実装コードの非改変（Review-Only 制約）**:
  - Challenger は Review-Only エージェントであるため、`lib/tutorial_screen.dart` への修正は一切加えていない。
- **既存テストへの影響**:
  - 既存の `test/tutorial_screen_test.dart`（11テスト）および `test/widget_test.dart`（14テスト）はすべて通過しており、Worker が実装した基本機能そのものには破壊的デグレはない。今回発見されたのは高負荷・非同期割り込み時のエッジケース耐性である。

---

## 4. Conclusion

- **判定**: **REQUEST_CHANGES**
- **理由**:
  1. 音声発話待機中のスキップ操作により、ステートマシンが過去のステップへ巻き戻る（先祖返り）重大な非同期レースコンディションが実証された（Bug 1）。
  2. デバウンス待機中にスキップした際、オーディオダッキングが解除されず BGM 音量が低下したまま残留するリークが実証された（Bug 2）。
  3. ボタン連打時に開始・確定音声が多重発話される（Bug 3）。
  4. 戻るボタン押下時にデバウンス音声が事後発話される（Bug 4）。

### Worker への修正要求事項（Action Items）

1. **ステートマシンの非同期完了ガード**:
   - `_proceedFromStep2()`:
     ```dart
     if (!mounted || _currentStep != TutorialStep.step2Start) return;
     ```
   - `_handleStep3Action()`（決定キー分岐）:
     ```dart
     if (!mounted || _currentStep != TutorialStep.step3Select) return;
     ```
   - `_handleStep5Action()`:
     ```dart
     if (!mounted || _currentStep != TutorialStep.step5Confirm) return;
     ```
2. **スキップ処理およびデバウンス破棄時のダッキング解除**:
   - `_onSkipStepPressed()` の先頭で `_cancelDebounce()`、`widget.ttsService?.stop()` に加え、`_duckingController.releaseDucking()` を確実に呼び出す。
3. **ステップ遷移中の再入ガード**:
   - `_isTransitioning` などのフラグを導入し、ステップ進行アニメーション・TTS発話中は同一キーの再受付をブロックする。
4. **画面離脱時のクリーンアップ**:
   - AppBar の戻るボタン押下時、および `PopScope` を用いて画面離脱開始時に `_cancelDebounce()`、`widget.ttsService?.stop()`、`_duckingController.releaseDucking()` を即座に実行する。

---

## 5. Verification Method

Worker または後続の検証者は、以下のコマンドを実行して Bug 1〜4 の再現および修正後の完全通過を確認できる：

```powershell
flutter test --no-test-assets test/stress_tutorial_audio_test.dart
```

- **現在の結果（再現の確認）**:
  - `00:05 +3 -6: Some tests failed.`（Test 1, 2, 3, 6, 8, 9 が失敗）
- **合格基準（修正完了の確認）**:
  - `00:05 +9: All tests passed!`（全9テストが exit code 0 で完全成功）
  - かつ `flutter test --no-test-assets` で全34テスト（既存25＋ストレステスト9）が 100% 成功すること。
