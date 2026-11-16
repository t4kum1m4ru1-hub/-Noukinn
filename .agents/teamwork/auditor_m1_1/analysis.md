# Forensic Integrity Analysis Report: TutorialScreen Deliverable

**Auditor**: auditor_m1_1 (Forensic Auditor)  
**Date**: 2026-11-10  
**Target Deliverable**: `lib/tutorial_screen.dart`, `lib/main.dart`, `test/tutorial_screen_test.dart`  
**Integrity Mode**: Development (from `ORIGINAL_REQUEST.md`)  
**Verdict**: **CLEAN**

---

## 1. Executive Summary

A forensic integrity examination was conducted on the implementation and tests for the `TutorialScreen` feature in `noukin_app`. All forensic checks specified under the General Project Integrity Forensics profile and dispatch objectives passed empirically without qualification:
1. **No Cheat Branches or Hardcoded Test Outcomes**: Production code contains 0 test bypasses, synthetic flags, or dummy constants tailored to pass tests artificially.
2. **No Facade Implementations**: All components—including the 6-step state machine, `SpotlightOverlayPainter`, `_glowController`, and `0.7s` debounce timer—are concrete, genuine implementations.
3. **No Fabricated Verification Artifacts**: No pre-populated test results or fake execution logs exist in the repository.
4. **Preservation of `lib/training_screen.dart` (R1)**: Strictly untouched by worker; verified via filesystem timestamp and git history.
5. **Empirical Verification**:
   - `flutter analyze`: **0 issues found** (exit code 0).
   - `flutter test --no-test-assets --reporter expanded`: **25/25 tests passed** (11 new tutorial tests + 14 existing regression tests, exit code 0).
6. **Non-Tautological Test Suite**: Tests in `test/tutorial_screen_test.dart` rigorously assert real widget tree nodes, state transitions, mock invocation histories, and timer debouncing intervals.

---

## 2. Phase 1: Mode-Agnostic Investigation (Forensic Observations)

### Check 1.1: Hardcoded Test Outcomes & Cheat Branch Analysis
- **Target Files**: `lib/tutorial_screen.dart`, `lib/main.dart`
- **Method**: Regex and AST-level inspection searching for test hooks (`isTest`, `kDebugMode`, `mock`, `fake`, `dummy`, `bypass`, `cheat`, synthetic branch short-circuits).
- **Observation**:
  - `Select-String -Path "lib\tutorial_screen.dart" -Pattern "test|mock|fake|dummy|bypass|cheat|kDebug"` returned only standard Flutter framework identifier matches (`createState`, `HitTestBehavior.translucent`).
  - No conditional logic checks whether tests are running.
  - Weight values (`_currentWeight = 60.0`, increment `+2.5`, decrement `-2.5`) are computed dynamically with `.clamp(0.0, 500.0)`.
  - Step progression is governed strictly by state transitions reacting to `ButtonAction` events or user interaction.
- **Result**: **PASS**

### Check 1.2: Facade Detection
- **Target**: `lib/tutorial_screen.dart`
- **Method**: Inspection of class and method bodies for empty implementations, placeholder stubs, or fake delegation.
- **Observations**:
  1. **Deterministic 6-Step State Machine**:
     - `TutorialStep` (`step1Intro`, `step2Start`, `step3Select`, `step4Adjust`, `step5Confirm`, `step6Complete`).
     - `Step3Phase` (`enterMode`, `cycleItem`).
     - `TutorialItem` (`exerciseName`, `weight`, `reps`, `sets`) with cyclic getters `.next` and `.previous`.
     - `_handleButtonAction` processes each step deterministically and handles key event mapping (`headsetHook` -> `mediaPlayPause`).
  2. **Punch-Through Spotlight (`SpotlightOverlayPainter`)**:
     - Uses `Path.combine(PathOperation.difference, backgroundPath, holePath)` to subtract the rounded rect of the focused widget from the 70% black overlay (`const Color(0xB3000000)`).
     - Dynamically calculates target widget bounds via `RenderBox.localToGlobal` and `RenderBox.globalToLocal` relative to `_stackKey`.
  3. **Breathing Glow Animation**:
     - Uses `AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))` repeating with reverse (`repeat(reverse: true)`).
     - Renders dual-layer glowing box shadows (`blurRadius: 8.0 + 12.0 * t`, `spreadRadius: 1.5 + 2.5 * t` and ambient blur `22.0 + 12.0 * t`, `spreadRadius: 4.0 + 4.0 * t`).
     - Correctly honors `widget.animateGlow` flag (defaults to `true`, can be set to `false` during tests to prevent continuous frames).
  4. **0.7-Second Debounce Timer**:
     - `_startWeightDebounce` instantiates a genuine `Timer(const Duration(milliseconds: 700))` for speech generation.
     - Accompanied by a `Timer.periodic(100ms)` triggering `SchedulerBinding.instance.scheduleFrame()` to ensure the Flutter pipeline processes timer advancement smoothly in test harnesses.
     - Immediately cancelled via `_cancelDebounce()` upon pressing `ButtonAction.mediaPlayPause` (85), skipping steps, navigating away, or disposing.
  5. **Audio Exclusivity & Ducking**:
     - `_speak(String text)` enforces `await _duckingController.requestDucking()`, followed immediately by `await widget.ttsService?.stop()`, and finally `await widget.ttsService?.speak(text)`.
     - `_playBeep()` requests ducking before sounding beep.
     - `dispose()` calls `widget.ttsService?.stop()` and `_duckingController.releaseDucking()`.
- **Result**: **PASS**

### Check 1.3: Pre-Populated Artifact Detection
- **Method**: Recursive filesystem scan for `.log`, `.txt`, `result*`, `output*` files in repository.
- **Observation**:
  - Only standard Gradle cache files (`android/.gradle/buildOutputCleanup/...`) exist.
  - Zero pre-populated test results, benchmark logs, or static attestation files exist in the project or agent folders.
- **Result**: **PASS**

### Check 1.4: Strict Read-Only Preservation of `lib/training_screen.dart` (R1)
- **Method**: Git status, git diff, and filesystem timestamp analysis.
- **Evidence**:
  - `Get-Item lib/training_screen.dart | Select-Object LastWriteTimeUtc` -> `2026/11/10 09:46:15 UTC`.
  - Task approval timestamp: `2026-11-10T10:01:02Z`.
  - Worker edits: `lib/main.dart` (10:33:07Z), `lib/tutorial_screen.dart` (10:39:52Z), `test/tutorial_screen_test.dart` (10:40:57Z).
  - Git diff on `lib/training_screen.dart` confirmed pre-existing uncommitted work prior to the task prompt; zero changes made by `worker_m1`.
  - `lib/main.dart` directly links to `TutorialScreen` on line 713; `TutorialScreen` transitions to `TrainingScreen` on line 272 without altering `TrainingScreen` internals.
- **Result**: **PASS**

### Check 1.5: Test Assertion Authenticity & Non-Tautological Verification
- **Target**: `test/tutorial_screen_test.dart`
- **Method**: Code review of all 11 test cases across the 3 test groups.
- **Findings**:
  - **Group 1 (Entry Navigation)**: Asserts existence of `start_tutorial_button`, text `操作チュートリアルを体験する`, presence of existing `start_training_button`, taps button and verifies `TutorialScreen` is pushed.
  - **Matrix Test 1 (Step 1)**: Asserts intro text, tests start button advancing to Step 2, tests skip-all button navigating directly to `TrainingScreen`.
  - **Matrix Test 2 (Step 2)**: Asserts unhandled key codes (24, 25, 87) do not trigger beeps or TTS; verifies key 85 increments `beepCount` to 1, sets `fakeTts.lastSpoken` to `'開始、ベンチプレス、60キロ、10回、3セット'`, and advances to Step 3.
  - **Matrix Test 3 (Step 3)**: Exercises two-phase selection. Part 1: tests key 88 safety readout, key 87 entering adjust mode (`'調整、種目名'`). Part 2: tests key 24 item cycling (`'重量'`), key 88 safety readout, and key 85 selecting weight (`'60キロ'`) and advancing to Step 4.
  - **Matrix Test 4 (Step 4 Debounce)**: Taps key 24 at 200ms intervals; checks screen updates to `62.5 kg` and `65 kg` immediately while `spokenHistory` remains empty. After 550ms (total 750ms > 700ms debounce), asserts `fakeTts.spokenHistory` contains exactly `['65キロ']`. Taps key 24 again and immediately presses key 85; verifies debounce is cancelled, TTS speaks `'調整、重量'`, and `67.5キロ` is never spoken even after a 1-second delay.
  - **Matrix Test 5 (Step 5 Confirmation)**: Exercises invalid keys (85, 24) and verifies warning banner; tests key 87 confirming workout (`'確定、開始、ベンチプレス、60キロ、10回、3セット'`) and advancing to Step 6.
  - **Matrix Test 6 (Step 6 Completion)**: Verifies completion screen and navigation to `TrainingScreen`.
  - **Matrix Test 7 (Skip route)**: Verifies `btn_tutorial_skip` advances through each step in sequence.
  - **Matrix Test 8 (Virtual media key bar)**: Verifies virtual buttons fire the exact same action pipeline as physical/native key events.
  - **Matrix Test 9 (Audio exclusivity & ducking)**: Verifies `stopCallCount >= spokenHistory.length` and `events.contains('requestDucking') == true`.
  - **Visual & Glow Unit Test**: Verifies `animateGlow: true` advances finite frames cleanly.
  - **Tautology count**: 0. Every assertion checks real widget trees, mock logs, or state values.
- **Result**: **PASS**

---

## 3. Phase 2: Mode-Specific Flagging

- **Specified Integrity Mode**: `development` (per `ORIGINAL_REQUEST.md`).
- Evaluation against Development Mode rules:
  - Hardcoded test results: **None** (Clean)
  - Facade implementation: **None** (Clean)
  - Fabricated verification output: **None** (Clean)
- Cross-check against Demo / Benchmark criteria:
  - Copying core logic from external packages: **None** (Clean)
  - Pre-built framework delegation for core feature: **None** (Built from standard Flutter primitives)
  - Reverse-engineering test expectations: **None** (Implemented to specification)
- **Flag count**: 0

---

## 4. Empirical Test & Analysis Results

### Raw `flutter analyze` Output
```
Resolving dependencies...
Downloading packages...
Got dependencies!
Analyzing noukin_app...                                         
No issues found! (ran in 1.7s)
```
- Exit Code: **0**

### Raw `flutter test --no-test-assets --reporter expanded` Output
```
00:00 +0: loading test/tutorial_screen_test.dart
00:00 +0: Entry Navigation: lib/main.dart -> TutorialScreen メイン画面にチュートリアルボタンが存在し、タップでTutorialScreenへ遷移できること
...
00:04 +9: TutorialScreen Widget Test Suite (Matrix 1 - 9) 9. 音声排他制御（stopCallCount >= 発話回数）およびダッキング要求の整合性
00:04 +10: Visual & Glow Animation Unit Test animateGlow: true で有限フレーム進めた際にアニメーションが正常に稼働すること
...
00:04 +24: Widget Tests: TrainingScreen UI & ステートマシン・メディアキー新仕様検証 新仕様メディアキー：次曲(87)=調整モードトグル、再生停止(85)=決定、前曲(88)=全モード共通確認ボタンが完全動作すること
00:05 +25: All tests passed!
```
- Exit Code: **0**
- Total Tests Run: **25** (11 TutorialScreen tests + 14 pre-existing regression tests)
- Total Passed: **25**
- Total Failed: **0**

---

## 5. Binary Forensic Verdict

**Verdict**: **CLEAN**  
The work product authentically implements all requirements of `ORIGINAL_REQUEST.md`, respects all structural constraints (R1 read-only guarantee for `lib/training_screen.dart`), and demonstrates complete implementation integrity with zero artificial test bypasses.
