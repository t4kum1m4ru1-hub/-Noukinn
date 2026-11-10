# Adversarial Challenge Report: TutorialScreen Audio Concurrency & Lifecycle

**Evaluator**: challenger_m1_2 (empirical-challenger, critic, specialist)  
**Target Code**: `lib/tutorial_screen.dart`  
**Test Suite**: `test/stress_tutorial_audio_test.dart`  
**Date**: 2026-11-10  
**Overall Risk Assessment**: **HIGH**  
**Verdict**: **REQUEST_CHANGES**

---

## 1. Challenge Summary

チュートリアル画面（`TutorialScreen`）の音声並行制御、BGMダッキングライフサイクル、および高負荷・非同期割り込み耐性に関する敵対的ストレステスト（`test/stress_tutorial_audio_test.dart` 計9テスト）を設計・実行した。

その結果、**4つの具体的な障害モード（Bug 1〜4）**が実証的に再現・確認された。
特に、音声発話中のスキップ操作による**ステートマシンの先祖返り（画面逆流バグ）**、およびデバウンス途中でスキップした際の**BGMダッキング永久残留（音声減衰リーク）**は、中間発表プレゼン実演時の聴衆体験を著しく損なう危険性があるため、コード修正が必要と判定した。

---

## 2. Challenges & Confirmed Failure Modes

### [High] Challenge 1: 非同期完了待機中のスキップ割り込みによるステートマシンの先祖返り（State Machine Regression）

- **Assumption challenged**:
  「Step 2 または Step 3 で `_speak(...)` が完了した後に `setState(() { _currentStep = nextStep; })` を呼べば、安全に次のステップへ進める」という暗黙の前提。
- **Attack scenario**:
  1. ユーザー（発表者）が Step 2 でイヤホンの再生ボタン（keyevent 85）を押す。
  2. 長い開始音声ガイダンス「開始、ベンチプレス、60キロ、10回、3セット」の発話（約5秒）が開始される。
  3. 発表者がデモ時間の都合等で、音声終了を待たずに画面右下のスキップボタン（`btn_tutorial_skip`）を2回タップして Step 4（重量調整）へ進める。
  4. その後、遅延していた Step 2 の `_speak(...)` 完了コールバックが発火する。
  5. コールバック内の `setState(() { _currentStep = TutorialStep.step3Select; })` が無条件に実行される。
- **Blast radius**:
  Step 4 にいた画面が突如 **Step 3 へ強制的に引き戻される（先祖返り）**。Step 3 の決定発話時（Test 8）にも同様に Step 5 から Step 4 へ逆流する。プレゼン実演中に画面が過去のステップへ逆走しデモが破綻する。
- **Empirical Evidence (`test/stress_tutorial_audio_test.dart: Test 2 & Test 8`)**:
  ```
  Expected: exactly one matching candidate
    Actual: _TextContainingWidgetFinder:<Found 0 widgets with text containing 重量調整と音声: []>
  Step 2 の非同期コールバック完了によって Step 4 から Step 3 へ先祖返りしてはならない
  ```
- **Mitigation (修正案)**:
  非同期発話完了後の `setState` 実行前に、現在のステップが遷移元と一致しているかを必ず検証するガードを追加する：
  ```dart
  if (!mounted || _currentStep != TutorialStep.step2Start) return;
  ```
  Step 3（決定）、Step 5（確定）の全非同期完了ハンドラにも同様のステップ一致ガードを適用する。

---

### [High] Challenge 2: デバウンス待機中のスキップによる BGM オーディオダッキングの永久リーク

- **Assumption challenged**:
  「ステップスキップ時に `_cancelDebounce()` と `widget.ttsService?.stop()` を呼べば、ダッキングも自動的に解消される」という前提。
- **Attack scenario**:
  1. Step 4 で音量ボタン（keyevent 24/25）を押して重量を変更する。
  2. `_playBeep()` が呼ばれ、`_duckingController.requestDucking()` が実行されて BGM が減衰する。
  3. 0.7秒のデバウンスタイマーが始動する。
  4. 0.7秒経過前に発表者がスキップボタン（`btn_tutorial_skip`）をタップして Step 5 へ進む。
  5. `_onSkipStepPressed()` が `_cancelDebounce()` を実行し、タイマーが破棄されるため `_speak()` は呼ばれない。
  6. `widget.ttsService?.stop()` は呼ばれるが、TTSサービス自体は発話前（`_isDucked = false`）のため `releaseDucking()` を呼ばない。
  7. `_onSkipStepPressed()` も `_duckingController.releaseDucking()` を呼ばない。
- **Blast radius**:
  Step 4 で電子音のために要求されたオーディオダッキングが解除されず、**Step 5 以降も BGM 音量が低下したまま（蚊の鳴くような音量）で放置される**。
- **Empirical Evidence (`test/stress_tutorial_audio_test.dart: Test 3`)**:
  ```
  Expected: <false>
    Actual: <true>
  デバウンスTTSがスキップされた場合、オーディオダッキングは解除されなければならない
  ```
- **Mitigation (修正案)**:
  1. `_onSkipStepPressed()` 内で `_duckingController.releaseDucking()` を明示的に呼び出す。
  2. `_cancelDebounce()` 実行時、または `_playBeep()` 単体完了時にもダッキングが残留しない安全機構（または `_cancelDebounce` 時に確実に `releaseDucking()` を呼ぶ等）を設ける。

---

### [Medium] Challenge 3: ボタン・キー連打時の再入（リエントラント）による重複発話・電子音スパム

- **Assumption challenged**:
  「ユーザーはボタンやイヤホンキーを1回だけ落ち着いて押す」という暗黙の前提。
- **Attack scenario**:
  1. Step 2（開始）でイヤホンボタンや画面中央ボタンを連打（チャタリングまたは焦りによる2〜3回打鍵）する。
  2. `_proceedFromStep2()` が同時に複数並行して起動する。
  3. 電子音が複数回連続再生され、長い開始音声「開始、ベンチプレス...」が重複・再発話される（Actual: 3回）。
  4. Step 5（確定）でも同様に、キー87連打で確定音声が多重発話される（Actual: 3回）。
- **Blast radius**:
  音声が重なり合い、音響的に不快なノイズ・連打スパム音が発生し、発表の完成度・信頼感を損なう。
- **Empirical Evidence (`test/stress_tutorial_audio_test.dart: Test 1 & Test 9`)**:
  ```
  Test 1:
  Expected: <1>
    Actual: <3>
  Step 2 開始キーの連打で複数回 TTS が多重発話されてはならない (再入防止)

  Test 9:
  Expected: <1>
    Actual: <3>
  Step 5 確定キー連打で複数回 TTS が多重発話されてはならない
  ```
- **Mitigation (修正案)**:
  `_isProcessingAction`（または各ステップのトランジション中フラグ）を設け、非同期遷移中に追加の入力が受け付けられないように再入防止ガードを設ける。

---

### [Medium] Challenge 4: AppBar 戻るボタン押下時のデバウンスタイマー未破棄による事後発話

- **Assumption challenged**:
  「画面を閉じる（pop）際は `dispose()` ですべて安全にクリーンアップされる」という前提。
- **Attack scenario**:
  1. Step 4 で重量を変更し、0.7秒デバウンスタイマーが始動する。
  2. タイマーが完了する前（100ms〜300ms）にユーザーが AppBar の左上「戻る」ボタン（`Icons.arrow_back`）を押す。
  3. `onPressed: () => Navigator.of(context).pop()` は画面遷移（Popアニメーション）を開始するが、`_cancelDebounce()` を呼ばない。
  4. `_framePumpTimer` が100msごとにフレーム要求を継続するため、700ms経過時に `_debounceTimer` のコールバックが発火し、閉じつつある（または閉じた後の）画面に対して `_speak('62.5キロ')` が実行される。
- **Blast radius**:
  チュートリアル画面を閉じてメイン画面に戻ったにもかかわらず、直後にイヤホンから「62.5キロ」と音声が突然鳴り響く。
- **Empirical Evidence (`test/stress_tutorial_audio_test.dart: Test 6`)**:
  ```
  Expected: empty
    Actual: ['62.5キロ']
  ```
- **Mitigation (修正案)**:
  AppBar の `onPressed` ハンドラ内で画面を閉じる前に `_cancelDebounce()` および `ttsService?.stop()` を即座に呼ぶ、または `PopScope` を用いて画面離脱開始時に即時キャンセルする。

---

## 3. Robust & Verified Areas (堅牢性が確認された領域)

以下の領域については、ストレステストにおいて極めて堅牢に動作することが実証された：

1. **Audio Hygiene（音声排他制御）**:
   - `test/stress_tutorial_audio_test.dart: Test 4` で検証。
   - すべての `ttsService.speak()` の直前に例外なく `ttsService.stop()` が先行して実行されており、要件 R2 の排他原則が厳密に順守されている。
2. **高速連打時の数値整合性**:
   - `test/stress_tutorial_audio_test.dart: Test 7` で検証。
   - 最下部仮想キーバーの `virtual_key_vol_up` を20回連続（50ms間隔）で連打した際、画面表示は `110 kg` に正確に追従し、0.7秒停止後に最後の「110キロ」のみが1回だけ正しく発話された。
3. **TTS発話中のアンマウント耐性**:
   - `test/stress_tutorial_audio_test.dart: Test 5` で検証。
   - 発話処理中に画面が pop された場合でも、`!mounted` チェックにより `setState` 例外は生じずクラッシュを回避できている。

---

## 4. Empirical Stress Test Results Summary

| # | Test Case Description | Target Risk | Actual Behavior | Result |
|---|---|---|---|---|
| 1 | Step 2 キー85連打時の重複発話 | 再入・音声スパム | Actual: 3回発話 | **FAIL** |
| 2 | Step 2 発話保留中のスキップ連打（Step 4への進行） | ステートマシン先祖返り | Step 4からStep 3へ逆流 | **FAIL** |
| 3 | Step 4 重量調整後の即時スキップ | BGMダッキングリーク | `isCurrentlyDucked` が `true` のまま残留 | **FAIL** |
| 4 | speak() 直前の stop() 順序性検証 | 音声排他・割り込み | 全ログで stop が speak に先行 | **PASS** |
| 5 | TTS発話中の画面 pop | ライフサイクルクラッシュ | 例外なくアンマウント完了 | **PASS** |
| 6 | Step 4 デバウンス中の AppBar 戻るボタン | 離脱後の事後発話 | 離脱後に「62.5キロ」が発話される | **FAIL** |
| 7 | 仮想キーバー Vol+ 20回高速連打 | デバウンスと数値整合性 | 110kg・最終値のみ1回発話 | **PASS** |
| 8 | Step 3 決定発話保留中のスキップ連打 | ステートマシン先祖返り | Step 5からStep 4へ逆流 | **FAIL** |
| 9 | Step 5 確定キー連打時の重複発話 | 再入・確定音声スパム | Actual: 3回発話 | **FAIL** |

**総合結果**: 9テスト中 3テスト PASS / **6テスト FAIL**
