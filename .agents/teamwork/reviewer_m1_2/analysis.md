# Comprehensive Review & Adversarial Analysis: TutorialScreen (M1)

**Reviewer / Critic**: reviewer_m1_2  
**Date**: 2026-11-10  
**Scope**: `lib/tutorial_screen.dart`, `lib/main.dart`, `test/tutorial_screen_test.dart`, layout compliance, media key handling, audio lifecycle, visual presentation.  
**Integrity Status**: CLEAN (No integrity violations detected)  
**Overall Verdict**: **APPROVE** (with non-blocking edge-case findings)

---

## 1. Executive Summary

An independent, rigorous quality review and adversarial challenge was conducted on the implementation of `TutorialScreen` (`lib/tutorial_screen.dart`), its integration point in `lib/main.dart`, and the associated test suite `test/tutorial_screen_test.dart`.

### Verification Highlights
- `flutter analyze`: **0 issues found** (ran in 1.7s, exit code 0).
- `flutter test --no-test-assets`: **25/25 tests passed** (including 11 new tutorial tests and 14 existing regression tests, ran in ~5s, exit code 0).
- Non-invasiveness guarantee: `lib/training_screen.dart` is strictly preserved without new modifications for this milestone.
- Visual presentation: Custom punch-through spotlight (`PathOperation.difference` with 70% black overlay) and breathing firefly glow (`AnimationController` + dual-layer `BoxShadow`) match presentation design specifications.
- Audio hygiene: Mandatory `ttsService.stop()` preceding every speech utterance and active BGM ducking integration (`AudioDuckingController`) verified both statically and dynamically.

---

## 2. Integrity Audit (Anti-Cheating Check)

| Check Item | Result | Evidence |
|---|---|---|
| Hardcoded test outputs | PASS | No test-specific branching or canned outputs in `tutorial_screen.dart`. Real mathematical adjustments (`(_currentWeight + 2.5).clamp(0.0, 500.0)`), dynamic string formatters (`formatWeightSpeech`), and true 700ms `Timer` instances. |
| Dummy or facade code | PASS | Full 1517-line production-ready widget featuring complete 6-step state machine, `CustomPainter`, `FocusNode` keyboard shortcuts, native `KeyEventChannelDispatcher`, and virtual media bar. |
| Task bypass / external delegation | PASS | All 6 steps, UI components, and animations built natively from scratch in Flutter without unvetted external dependencies. |
| Fabricated verification logs | PASS | Direct independent shell execution of `flutter analyze` and `flutter test --no-test-assets` confirms 100% genuine pass. |
| Self-certifying work | PASS | Independent subagent review with adversarial test analysis and edge-case mining. |

---

## 3. UI Presentation & Visual Review

### 3.1 70% Black Punch-Through Spotlight (`SpotlightOverlayPainter`)
- **Implementation**: Lines 1463–1517 in `lib/tutorial_screen.dart`.
- **Overlay Color**: Uses `const Color(0xB3000000)` where `0xB3` (179 / 255) equals exactly 70.2% opacity.
- **Punch-Through Hole**: Constructed via `Path.combine(PathOperation.difference, backgroundPath, holePath)` using rounded rectangles (`RRect.fromRectAndRadius`) with 14.0dp corner radius and 4.0dp padding inflation.
- **Null Safety / Degraded State**: When `targetRect == null || targetRect.isEmpty` (e.g. during Step 1 or Step 5), cleanly draws full-screen overlay without crashing.
- **Layering**: Positioned inside `Stack(fit: StackFit.expand)` above the workout background and below the guidance cards. Touch taps on the overlay are captured via `GestureDetector(behavior: HitTestBehavior.translucent)` preventing unwanted touches from interacting with background widgets.

### 3.2 Breathing Firefly Glow Animation (`_buildGlowOverlay`)
- **Implementation**: Lines 157–165, 176–189, and 997–1046 in `lib/tutorial_screen.dart`.
- **Animation Details**: 1200ms `CurvedAnimation(curve: Curves.easeInOut)` repeating with reverse (`repeat(reverse: true)`).
- **Visual Stacking**: Dual-layer `BoxShadow`:
  - Inner glow: `blurRadius: 8.0 + 12.0 * t`, `spreadRadius: 1.5 + 2.5 * t`, teal opacity `0.35 + 0.35 * t`.
  - Outer atmospheric aura: `blurRadius: 22.0 + 12.0 * t`, `spreadRadius: 4.0 + 4.0 * t`, teal opacity `0.12 + 0.18 * t`.
- **Test Safety (`animateGlow` flag)**:
  - Animation only loops when `widget.animateGlow == true` and current step is in Steps 2–5.
  - In Step 1 and Step 6, the animation is explicitly stopped and set to `1.0`. This prevents `tester.pumpAndSettle()` in integration tests (e.g. from `main.dart` entry button) from hanging indefinitely.
  - Wrapped in `IgnorePointer` to prevent intercepting touch events.

### 3.3 Virtual Media Key Bar & Skip Controls
- **Bottom Virtual Bar**: Dedicated 5-button bar (`virtual_key_prev`, `virtual_key_play_pause`, `virtual_key_next`, `virtual_key_vol_down`, `virtual_key_vol_up`) placed in `Scaffold(bottomNavigationBar: SafeArea(...))`.
- **State Badging**: Top indicator dynamically updates to display current mode (`modeLabel`) and volume key functionality (`volLabel`).
- **Emergency Skip Buttons**:
  - Right-bottom floating pill button (`btn_tutorial_skip`) visible in Steps 2–5.
  - Step 1 dedicated skip button (`btn_tutorial_skip_all`).
  - AppBar action button (`btn_appbar_skip_training`) for instant bailout.
  - All skip paths cancel pending debounce timers and invoke `pushReplacement` to `TrainingScreen`.

---

## 4. Key Event Handling & Step State Machine Review

### 4.1 Key Architecture & Multi-Source Dispatch
- Key events are captured via:
  1. `KeyEventChannelDispatcher` (Android earphone hardware buttons / ADB keyevents 85, 79, 87, 88, 24, 25).
  2. Flutter `Focus` node (`LogicalKeyboardKey` space, arrows, media keys).
  3. Bottom virtual media key bar buttons.
- `headsetHook` (keycode 79) is properly normalized to `mediaPlayPause` (keycode 85).

### 4.2 Step Progression Analysis
- **Step 1 (Intro)**: Shows training philosophy, control legend, start button, and skip-to-training button. Key 85 or start button moves to Step 2.
- **Step 2 (Start Experience)**: Only key 85 (or screen tap / button tap) triggers start sequence. Rejects keys 24, 25, 87, 88. Plays beep, speaks `開始、ベンチプレス、60キロ、10回、3セット`, and automatically advances to Step 3.
- **Step 3 (Adjustment Entry & Selection)**:
  - **Part 1 (`enterMode`)**: Key 87 plays beep, speaks `調整、種目名`, and switches to Part 2. Key 88 provides safe readout of current workout status (`ベンチプレス、60キロ、10回、3セット`).
  - **Part 2 (`cycleItem`)**: Keys 24/25 cycle item focus with wrapping (`exerciseName` ⇄ `weight` ⇄ `reps` ⇄ `sets`) accompanied by beep and item name TTS. Key 85 speaks current value (`60キロ`) and transitions to Step 4. Key 88 provides safe readout.
- **Step 4 (Weight Adjustment & Debounce)**:
  - Weight card spotlighted.
  - Keys 24/25 immediately beep and adjust `_currentWeight` by ±2.5kg (clamped 0.0–500.0kg) with real-time screen update.
  - Cancels prior debounce and sets 700ms timer. If no keys are pressed for 700ms, speaks updated weight (e.g. `65キロ`).
  - Key 85 immediately cancels pending debounce timer, beeps, speaks `調整、重量`, and transitions to Step 5.
  - Key 88 provides safe readout.
- **Step 5 (Adjustment Confirmation)**:
  - Inactive keys display amber warning banner: `［次の曲へ進む］ボタンを押して調整を完了してください`.
  - Key 87 plays beep, speaks `確定、開始、ベンチプレス、{weight}キロ、10回、3セット`, and automatically advances to Step 6.
- **Step 6 (Celebration & Transition)**:
  - Shows completion checkmark and congratulations.
  - Main button or key 85 replaces route with `TrainingScreen`.

---

## 5. Adversarial Challenge & Edge-Case Findings

### [Minor Finding 1] Asynchronous State Overwrite on Concurrent Skip During Speech
- **Where**: `lib/tutorial_screen.dart`, lines 328–338 (`_proceedFromStep2`), 350–357 (`_handleStep3Action`), 426–435 (`_handleStep5Action`).
- **Attack Scenario**:
  1. User is on Step 2. User presses Play/Pause (key 85).
  2. `_proceedFromStep2()` begins: plays beep, starts `await _speak('開始、ベンチプレス、60キロ、10回、3セット')`.
  3. Real TTS speech takes ~2.5 seconds. At t = 0.5s, the user taps the floating "スキップ >" button (`btn_tutorial_skip`) twice.
  4. The skip button synchronously advances `_currentStep` to Step 3, then Step 4.
  5. At t = 2.5s, `await _speak(...)` in `_proceedFromStep2()` finishes and executes:
     ```dart
     if (!mounted) return;
     setState(() {
       _currentStep = TutorialStep.step3Select;
       _step3Phase = Step3Phase.enterMode;
     });
     ```
  6. **Result**: The user was already at Step 4, but is unexpectedly pulled back to Step 3.
- **Impact / Blast Radius**: Low-to-Medium in rapid touch-skipping during active speech. Does not crash or deadlock, but regresses the step machine.
- **Suggested Defense**:
  Check whether `_currentStep` is still the expected step before updating state post-`await`:
  ```dart
  if (!mounted || _currentStep != TutorialStep.step2Start) return;
  ```

### [Minor Finding 2] Key Re-entrancy During Step Transition Speech
- **Where**: `lib/tutorial_screen.dart`, lines 303, 348, 425.
- **Attack Scenario**:
  During the 2–3 seconds when `_proceedFromStep2()` or `_handleStep5Action()` is awaiting TTS speech, `_currentStep` has not yet transitioned. If the presenter presses key 85 or key 87 again, the event handler fires a second time, triggering redundant beeps and restarting the speech.
- **Impact / Blast Radius**: Low. Causes audio restart jitter during live presentation if the button is double-tapped.
- **Suggested Defense**:
  Add a boolean guard `bool _isStepTransitioning = false;` during async step advancement, or advance `_currentStep` immediately before speaking.

---

## 6. Test Suite Quality Review (`test/tutorial_screen_test.dart`)

The test suite contains 11 tests organized logically into:
1. Entry navigation from `main.dart`
2. Matrix 1–9 covering Steps 1 through 6, skip actions, virtual media keys, and audio hygiene.
3. Glow animation finite pump execution.

**Key strengths observed**:
- Correct use of `FakeTtsService`, `FakeSoundEffectService`, and `FakeAudioDuckingController`.
- Direct platform event injection using `sendNativeKeyEvent`.
- Verifies both the debounce wait (750ms) and the cancellation on early Play/Pause press (ensuring no orphan speech).
- Verifies that `stopCallCount >= spokenHistory.length`.

**Coverage Suggestion**:
- Test 7 exercises `btn_start_first_training` in Step 6. Adding a one-line test asserting that `sendNativeKeyEvent(tester, 85)` also navigates to `TrainingScreen` in Step 6 would achieve 100% test contract parity.

---

## 7. Review Summary & Conclusion

- **Verdict**: **APPROVE**
- **Integrity**: Clean. No facades, no cheating, no regressions.
- **Code Quality**: Clean architecture, clear separation of concerns, excellent adherence to project styling (`AppColors`).
- **Read-Only Compliance**: `lib/training_screen.dart` is untouched.
- **Readiness**: Fully ready for demonstration and presentation integration. Minor edge cases documented above can be resolved in a routine polish pass.
