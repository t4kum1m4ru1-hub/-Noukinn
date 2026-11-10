# BRIEFING — 2026-11-10T11:02:00Z

## Mission
Formulate an exact fix strategy for audio ducking leak and lifecycle post-dispose speech in TutorialScreen (Test 3 and Test 6).

## 🔒 My Identity
- Archetype: explorer
- Roles: read-only investigation, problem analysis, synthesis, structured report
- Working directory: c:\Users\taqmi\02_development\original_program\noukin_app
- State folder: c:\Users\taqmi\02_development\original_program\noukin_app\.agents\teamwork\explorer_m1_iter2_3\
- Original parent: 2710972e-05b0-491e-8e81-953af37d2751
- Milestone: m1_iter2

## 🔒 Key Constraints
- Read-only investigation — do NOT implement directly into project source code
- Adhere to GEMINI.md golden rules (no AI context jargon, explain clearly, respect repository constraints)
- Provide exact findings, logic chain, caveats, conclusion, and verification method in handoff.md

## Current Parent
- Conversation ID: 2710972e-05b0-491e-8e81-953af37d2751
- Updated: 2026-11-10T11:02:00Z

## Investigation State
- **Explored paths**:
  - `lib/tutorial_screen.dart` (lines 1-1517: debounce, audio lifecycle, button action, step transitions, AppBar, build)
  - `lib/main.dart` (lines 140-330: AudioDuckingController, SoundEffectService, FlutterTtsService ducking lifecycles)
  - `test/stress_tutorial_audio_test.dart` (9 stress tests, specifically Test 1, 2, 3, 6, 8, 9)
  - `test/tutorial_screen_test.dart` & `test/widget_test.dart` (existing baseline tests)
  - `.agents/teamwork/challenger_m1_2/handoff.md` and `analysis.md`
- **Key findings**:
  - Test 3 root cause: `_playBeep()` in Step 4 requests ducking, but when skipped before 0.7s debounce completes, `_onSkipStepPressed()` cancels debounce without releasing ducking.
  - Test 6 root cause: AppBar back button (`Icons.arrow_back`) calls `Navigator.of(context).pop()` without cancelling debounce or stopping audio; `_framePumpTimer` continues pumping frames during route pop transition, allowing the 0.7s timer to fire `_speak('62.5キロ')` while popped.
  - Test 1 & 9 root cause: Lack of reentrancy guard (`_isTransitioning`) allows button mash to queue multiple simultaneous async audio pipelines.
  - Test 2 & 8 root cause: Missing step verification guard (`_currentStep != expectedStep`) after async `_speak()` lets late callbacks roll back the state machine.
- **Unexplored areas**: None. Full execution and lifecycle paths mapped.

## Key Decisions Made
- Solution design adopts symmetric cleanup pattern (`_cancelDebounce()`, `stop()`, `releaseDucking()`) across all exit paths (`_onSkipStepPressed`, AppBar pop, `PopScope`, `_navigateToTrainingScreen`, and `dispose`).
- Do NOT place `releaseDucking()` inside `_cancelDebounce()` itself to prevent audio fluttering during high-speed Vol+/- button presses (Test 7).
- Include comprehensive defense-in-depth: `PopScope(canPop: true, onPopInvokedWithResult: ...)`, `!mounted` checks in timer callbacks and `_speak()`, and `_isTransitioning` reentrancy lock.

## Artifact Index
- `analysis.md` — In-depth architectural root-cause analysis and exact fix design.
- `handoff.md` — 5-component handoff report (Observation, Logic Chain, Caveats, Conclusion, Verification Method).
- `progress.md` — Liveness heartbeat and progress tracking.
- `DISPATCH.md` — Received dispatch instructions.
