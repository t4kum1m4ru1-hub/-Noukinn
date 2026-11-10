# BRIEFING — 2026-11-10T11:05:00Z

## Mission
Formulate an exact fix strategy for the asynchronous re-entrancy bug in lib/tutorial_screen.dart under rapid key presses, ensuring all 19 stress tests pass.

## 🔒 My Identity
- Archetype: explorer
- Roles: investigation, synthesis
- Working directory: c:\Users\taqmi\02_development\original_program\noukin_app
- State folder: c:\Users\taqmi\02_development\original_program\noukin_app\.agents\teamwork\explorer_m1_iter2_1\
- Original parent: 2710972e-05b0-491e-8e81-953af37d2751
- Milestone: m1_iter2

## 🔒 Key Constraints
- Read-only investigation — do NOT implement
- Follow GEMINI.md golden rules: no out-of-repo context in docs/comments, no forbidden jargon, non-engineer friendly explanation
- Maintain strict file workspace discipline (.agents/teamwork/explorer_m1_iter2_1/ only for writing)

## Current Parent
- Conversation ID: 2710972e-05b0-491e-8e81-953af37d2751
- Updated: 2026-11-10T11:05:00Z

## Investigation State
- **Explored paths**:
  - `lib/tutorial_screen.dart`: lines 1–1517 (state machine, key routing, audio playback, debounce timer, skip controls, virtual bar).
  - `test/stress_tutorial_keys_test.dart`: lines 1–607 (all 19 adversarial key stress tests).
  - `test/stress_tutorial_audio_test.dart`: lines 1–570 (all 9 audio concurrency & lifecycle stress tests).
  - `test/tutorial_screen_test.dart`: all 11 existing unit/widget tests.
  - `test/widget_test.dart`: all 14 existing app tests.
- **Key findings**:
  - Root cause of 4 failing tests in `stress_tutorial_keys_test.dart` (Step 2, Step 3 Part 1, Step 4, Step 5) is unshielded asynchronous step transitions (`await _playBeep()`, `await _speak(...)`) while `_currentStep` has not yet advanced.
  - Rapid double-pressing invokes the transition method a second time, triggering duplicate beeps and overlapping TTS speeches.
  - Synchronous advancement prior to audio playback would violate specification requirement ("発話終了後に Step X へ遷移すること") and cause visual UI mismatch during speech.
  - Recommended fix: In-flight Transition Lock (`_isStepTransitioning`) combined with a Generation Token (`_transitionGeneration`).
  - Skipping and screen popping must also clean up debounce, release ducking, and invalidate pending generation to eliminate state regression ("先祖返り") and ducking leaks.
- **Unexplored areas**: None. Complete causal chain mapped to exact line numbers and proposed code edits.

## Key Decisions Made
- Selected Transition Lock + Generation Token pattern over premature step advancement.
- Ensured non-transition rapid actions (Step 4 Volume Up/Down debouncing) remain responsive and unaffected by the lock.
- Incorporated audio ducking release and pop cleanup to fix audio concurrency completely.

## Artifact Index
- DISPATCH.md — incoming dispatch instructions
- BRIEFING.md — working memory
- progress.md — liveness heartbeat
- analysis.md — comprehensive technical root cause and design analysis
- handoff.md — 5-component handoff report for implementer
