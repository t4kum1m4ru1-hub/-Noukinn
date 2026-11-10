# Handoff Report: Adversarial Key Event & State Transition Stress Test

**Agent**: challenger_m1_1 (critic, specialist)  
**State folder**: `c:\Users\taqmi\02_development\original_program\noukin_app\.agents\teamwork\challenger_m1_1\`  
**Date**: 2026-11-10  
**Status**: Hard Handoff (Completed with Verdict: **`REQUEST_CHANGES`**)

---

## 1. Observation

1. **Adversarial Stress Test Suite Authoring**:
   - Authored and executed an empirical stress harness in `test/stress_tutorial_keys_test.dart` comprising 19 targeted adversarial test cases across all steps of `TutorialScreen`.
2. **Empirical Failure Reproduction (Asynchronous Re-entrancy / Rapid Double-Press)**:
   - When running `flutter test --no-test-assets test/stress_tutorial_keys_test.dart`, 4 test cases consistently failed with duplicate audio/TTS calls:
     ```
     Step 2 (Start Experience): キー85の連続連打（ダブルクリック等）で多重発話・重複ビープが発生しないこと（再入防止） [E]
       Expected: <1>
         Actual: <2>
       Step 2 開始キーの連打でビープが重複再生されてはならない

     Step 3 Part 1 (Enter Mode): キー87の連続連打で多重発話・重複ビープが発生しないこと（再入防止） [E]
       Expected: <1>
         Actual: <2>
       Step 3 突入キー連打でビープが重複再生されてはならない

     Step 4 (Weight Adjustment): 決定キー(85)の連続連打で多重発話・重複ビープが発生しないこと（再入防止） [E]
       Expected: <1>
         Actual: <2>
       Step 4 決定キー連打でビープが重複再生されてはならない

     Step 5 (Adjustment Completion): 確定キー(87)の連続連打で多重発話・重複ビープが発生しないこと（再入防止） [E]
       Expected: <1>
         Actual: <2>
       Step 5 確定キー連打でビープが重複再生されてはならない
     ```
3. **Step 4 Debounce & Boundary Clamping Successes**:
   - **10 rapid clicks**: Volume Up pressed 10 times in 300ms updated UI from 60.0kg to 85.0kg immediately. Exactly 1 debounced speech (`'85キロ'`) fired after 750ms.
   - **Debounce Interruption**: Pressing Key 85 (決定) while the 0.7s debounce timer was pending immediately cancelled the timer. Spoke `'調整、重量'`, and the pending `'65キロ'` speech was completely suppressed.
   - **Lower Bound Clamping**: Pressing Volume Down 30 times (reducing 75kg) clamped strictly at `0.0kg` (`'0 kg'` UI, `'0キロ'` TTS), with no negative values.
4. **Invalid Key Filtering & Guidance Prompting Successes**:
   - Step 1: Unhandled keys (24, 25, 87, 88, 999) caused no side effects.
   - Step 2: Spamming volume and next/prev keys caused no beeps or speech.
   - Step 5: Pressing any invalid key (85, 79, 24, 25, 88) correctly displayed the notice prompt `'［次の曲へ進む］ボタンを押して調整を完了してください'` without advancing state. Pressing Key 87 cleared the prompt and advanced to Step 6.
   - Keyboard typing spam (A-Z, digits, Enter, Tab, Escape) was ignored cleanly (`KeyEventResult.ignored`).

---

## 2. Logic Chain

1. **Step Transition Mechanism in `lib/tutorial_screen.dart`**:
   - In `_proceedFromStep2()`, `_handleStep3Action()`, `_handleStep4Action()`, and `_handleStep5Action()`, the method performs `await _playBeep()` followed by `await _speak(...)` BEFORE updating the state variable `_currentStep` via `setState(...)`.
   - Lines 328–338 (`_proceedFromStep2`):
     ```dart
     Future<void> _proceedFromStep2() async {
       await _playBeep();
       await _speak('開始、ベンチプレス、60キロ、10回、3セット');
       if (!mounted) return;
       setState(() {
         _currentStep = TutorialStep.step3Select;
         _step3Phase = Step3Phase.enterMode;
       });
     }
     ```
2. **Asynchronous Re-entrancy Vulnerability**:
   - While `_speak()` and `_playBeep()` are awaiting, Dart's event loop continues processing incoming native MethodChannel messages dispatched by `KeyEventChannelDispatcher`.
   - Because `_currentStep` has not yet transitioned to the next step and there is no boolean in-flight lock (such as `_isStepTransitioning`), a second key event (e.g. user double-tapping or contact jitter) invokes the same transition handler again.
   - This results in two concurrent execution chains, producing 2 sound effects and 2 overlapping TTS speech commands, breaking audio hygiene and creating race conditions if the user skips steps during speech.
3. **Mitigation Path**:
   - Adding a re-entrancy lock `bool _isStepTransitioning = false;` or advancing the state synchronously before awaiting audio playback guarantees that subsequent key presses during speech are either ignored or handled in the new step context.

---

## 3. Caveats

1. **Static Analysis**: `flutter analyze` passes with 0 issues. The vulnerability is an asynchronous runtime concurrency flaw, undetectable by static analysis alone.
2. **Unit Test Pass Rates in Non-Adversarial Scenarios**: All original 25 tests in `widget_test.dart` and `tutorial_screen_test.dart` pass because they sequentially await `pumpAndSettle()` between each key event. The issue only manifests under realistic physical input conditions (rapid successive key presses within the audio playback window).

---

## 4. Conclusion

- **Verdict**: **`REQUEST_CHANGES`**
- **Required Fix**:
  In `lib/tutorial_screen.dart`, guard all step transition handlers (`_proceedFromStep2`, Step 3 `enterMode` transition, Step 4 `mediaPlayPause` transition, and Step 5 `mediaNext` transition) with an asynchronous re-entrancy lock (e.g., `_isStepTransitioning`) or update step states synchronously prior to audio playback to prevent duplicate beeps and overlapping TTS utterances upon rapid double-pressing.

---

## 5. Verification Method

To independently reproduce this finding:
```powershell
flutter test --no-test-assets test/stress_tutorial_keys_test.dart
```

- **Expected Failure**:
  - `Step 2 (Start Experience): キー85の連続連打（ダブルクリック等）で多重発話・重複ビープが発生しないこと（再入防止）` -> fails with `Expected: <1>, Actual: <2>`.
  - `Step 3 Part 1 (Enter Mode): キー87の連続連打で多重発話・重複ビープが発生しないこと（再入防止）` -> fails with `Expected: <1>, Actual: <2>`.
  - `Step 4 (Weight Adjustment): 決定キー(85)の連続連打で多重発話・重複ビープが発生しないこと（再入防止）` -> fails with `Expected: <1>, Actual: <2>`.
  - `Step 5 (Adjustment Completion): 確定キー(87)の連続連打で多重発話・重複ビープが発生しないこと（再入防止）` -> fails with `Expected: <1>, Actual: <2>`.
- **Invalidation Condition**:
  - If a re-entrancy guard is added to `lib/tutorial_screen.dart` and all 19 tests in `test/stress_tutorial_keys_test.dart` pass (19/19 passed, exit code 0).
