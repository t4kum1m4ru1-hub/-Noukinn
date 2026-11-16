# Empirical Stress Analysis: Key Event Handling & State Transitions

**Agent**: challenger_m1_1 (Adversarial Key Event Challenger)  
**Date**: 2026-11-10  
**Target**: `lib/tutorial_screen.dart`  
**Test Harness**: `test/stress_tutorial_keys_test.dart` (19 challenge test cases)

---

## 1. Executive Summary

Empirical stress testing of `lib/tutorial_screen.dart` was conducted across four critical challenge dimensions:
1. **Invalid and unexpected key events** across all six tutorial steps (Steps 1–6).
2. **Step 4 weight adjustment stress**: 10 rapid succession clicks, alternating ±2.5kg clicks, lower-bound clamping at 0.0kg, upper-bound clamping at 500.0kg, and pending debounce cancellation by Key 85 (決定) and Skip.
3. **Keyboard & Virtual media bar resilience**: Typing spam (A-Z, digits, Enter, Tab, Escape) and rapid virtual button clicks.
4. **Asynchronous key event re-entrancy / rapid double-press handling**: Key 85/87 rapid succession during in-flight sound effect and TTS playback.

### Empirical Result:
- **PASSED**: Step 4 debounce timer resilience (10 rapid clicks fire exactly 1 debounced speech), lower bound clamping at 0.0kg, keyboard typing spam filtering, and Step 5 notice prompt display on invalid keys.
- **FAILED (CRITICAL CONCURRENCY BUG)**: **Asynchronous Re-entrancy during Step Transitions (Steps 2, 3, 4, 5)**.
  Rapid double-press of transition keys (Key 85 at Step 2 & Step 4, Key 87 at Step 3 & Step 5) causes duplicate beeps, duplicate TTS speech invocations, and race conditions, because `_currentStep` is only updated *after* awaiting `_playBeep()` and `_speak()`, with no in-flight transition lock.

**Verdict**: **`REQUEST_CHANGES`**

---

## 2. Detailed Empirical Findings

### Finding 1: Asynchronous Re-entrancy / Double-Click Vulnerability (CRITICAL)

#### Observation
In `test/stress_tutorial_keys_test.dart`:
```
00:01 +2 -1: Step 2 (Start Experience): キー85の連続連打（ダブルクリック等）で多重発話・重複ビープが発生しないこと（再入防止） [E]
  Expected: <1>
    Actual: <2>
  Step 2 開始キーの連打でビープが重複再生されてはならない

00:02 +2 -2: Step 3 Part 1 (Enter Mode): キー87の連続連打で多重発話・重複ビープが発生しないこと（再入防止） [E]
  Expected: <1>
    Actual: <2>
  Step 3 突入キー連打でビープが重複再生されてはならない

00:04 +5 -4: Step 4 (Weight Adjustment): 決定キー(85)の連続連打で多重発話・重複ビープが発生しないこと（再入防止） [E]
  Expected: <1>
    Actual: <2>
  Step 4 決定キー連打でビープが重複再生されてはならない

00:02 +2 -3: Step 5 (Adjustment Completion): 確定キー(87)の連続連打で多重発話・重複ビープが発生しないこと（再入防止） [E]
  Expected: <1>
    Actual: <2>
  Step 5 確定キー連打でビープが重複再生されてはならない
```

#### Code Analysis (`lib/tutorial_screen.dart`)
Consider `_proceedFromStep2`:
```dart
  Future<void> _proceedFromStep2() async {
    await _playBeep();
    await _speak('開始、ベンチプレス、60キロ、10回、3セット');
    if (!mounted) return;
    setState(() {
      _currentStep = TutorialStep.step3Select;
      _step3Phase = Step3Phase.enterMode;
    });
    _startGlowIfNeeded();
    _updateSpotlightRect();
  }
```
And in `_handleButtonAction`:
```dart
      case TutorialStep.step2Start:
        if (effectiveAction == ButtonAction.mediaPlayPause) {
          _proceedFromStep2();
        }
        break;
```
1. When Key 85 arrives, `_proceedFromStep2()` is called asynchronously.
2. It executes `await _playBeep()` and then `await _speak(...)`.
3. While waiting for audio playback, execution is suspended. `_currentStep` is STILL `TutorialStep.step2Start`.
4. If the user presses Key 85 again (e.g. earphone double-tap or stutter click), `_handleButtonAction` sees `_currentStep == TutorialStep.step2Start` and calls `_proceedFromStep2()` a second time!
5. Consequently, `_playBeep()` is called twice, `_speak()` is called twice, and two overlapping audio streams fight for playback.
6. The same exact vulnerability exists in:
   - Step 3 Part 1 (`_handleStep3Action`, Key 87 `enterMode` -> `cycleItem`)
   - Step 4 (`_handleStep4Action`, Key 85 `step4Adjust` -> `step5Confirm`)
   - Step 5 (`_handleStep5Action`, Key 87 `step5Confirm` -> `step6Complete`)

#### Blast Radius
- Physical earphone buttons are prone to contact bounce or user double-clicking.
- Duplicate beeps and overlapping TTS speeches violate the core product promise of "hands-free audio guidance while training".
- Furthermore, if the user hits "Skip" during this async window, `_currentStep` can regress back to an earlier step upon completion of the pending `setState`.

#### Recommended Mitigation
Introduce an async transition lock in `_TutorialScreenState`:
```dart
bool _isTransitioning = false;
```
In `_proceedFromStep2`, Step 3 `enterMode`, Step 4 `mediaPlayPause`, and Step 5 `mediaNext`:
```dart
if (_isTransitioning) return;
_isTransitioning = true;
try {
  await _playBeep();
  await _speak(...);
  if (!mounted) return;
  setState(() {
    _currentStep = ...;
  });
} finally {
  if (mounted) {
    _isTransitioning = false;
  }
}
```
Or immediately advance `_currentStep` synchronously before awaiting the speech, so subsequent key events are evaluated in the context of the new step.

---

### Finding 2: Step 4 Debounce & Boundary Clamping (VERIFIED ROBUST)

#### Observation
1. **10 Rapid Succession Clicks (+25kg)**:
   - UI updated immediately from 60.0kg to 85.0kg on each click.
   - `fakeSound.beepCount` reached 10.
   - Zero TTS calls during the burst (< 700ms).
   - After 750ms, exactly 1 debounced speech was emitted: `"85キロ"`.
2. **Alternating Burst (5 Up + 5 Down)**:
   - Weight climbed to 72.5kg then dropped to 60.0kg.
   - Debounce timer was repeatedly reset.
   - After 750ms from final click, exactly 1 debounced speech was emitted: `"60キロ"`.
3. **Key 85 (決定) Interruption of Debounce**:
   - 2 Up clicks (+5kg -> 65.0kg).
   - Debounce active (150ms elapsed, 550ms remaining).
   - Key 85 pressed.
   - `_cancelDebounce()` immediately cancelled the pending timer.
   - TTS emitted `"調整、重量"`.
   - Advanced fake clock by 1000ms: `"65キロ"` was NEVER spoken. Spoken history contains only `['調整、重量']`.
4. **Lower Bound Clamping at 0.0kg**:
   - 30 Volume Down clicks (60 - 75 = -15kg theoretical).
   - Weight clamped at `0.0kg`. UI displayed `'0 kg'`.
   - Debounce speech emitted `"0キロ"`.
   - 5 additional Volume Down clicks at 0.0kg maintained `0.0kg` and emitted `"0キロ"`. Negative numbers are impossible.

---

### Finding 3: Invalid Key Event Matrix & Prompts (VERIFIED ROBUST)

#### Observation
- **Step 1**: Volume Up/Down, Next, Prev, Unknown (999) produce zero side effects. Step remains Step 1.
- **Step 2**: Volume Up/Down, Next, Prev spam produce zero sound/TTS.
- **Step 3 (enterMode)**: Volume Up/Down and Key 85 are ignored. Key 88 provides content safety readout without changing phase.
- **Step 3 (cycleItem)**: Key 87 is ignored. Volume Up/Down successfully cycles all 4 items bidirectionally (wrapping around).
- **Step 4**: Key 87 is ignored. Key 88 provides content safety readout without cancelling or corrupting weight adjustment.
- **Step 5**: Invalid keys (85, 79, 24, 25, 88) do NOT advance to Step 6. They set `_warningMessage = '［次の曲へ進む］ボタンを押して調整を完了してください'`, displaying the amber notice card. Pressing Key 87 clears the warning and advances to Step 6.
- **Step 6**: Volume Up/Down, Next, Prev are ignored. Key 85 transitions to `TrainingScreen`.

---

### Finding 4: Keyboard & Virtual Media Bar Resilience (VERIFIED ROBUST)

#### Observation
- Keyboard typing spam (A-Z, digits, Enter, Tab, Escape) returns `KeyEventResult.ignored`. No side-effects.
- Space, Arrow keys, and Virtual Media Bar buttons map seamlessly to the identical button action pipeline.
