# BRIEFING — 2026-11-10T20:01:45+09:00

## Mission
Formulate an exact fix strategy for state machine reversion (先祖返り) when skipping during speech in lib/tutorial_screen.dart (specifically addressing Test 2 and Test 8 in test/stress_tutorial_audio_test.dart).

## 🔒 My Identity
- Archetype: explorer
- Roles: investigator, analyzer, synthesizer
- Working directory: c:\Users\taqmi\02_development\original_program\noukin_app
- State folder: c:\Users\taqmi\02_development\original_program\noukin_app\.agents\teamwork\explorer_m1_iter2_2\
- Original parent: 2710972e-05b0-491e-8e81-953af37d2751
- Milestone: M1 Iteration 2

## 🔒 Key Constraints
- Read-only investigation — do NOT implement
- Analyze why skipping during Step 2, Step 3, or Step 5 speech causes the delayed async callback to overwrite `_currentStep` back to an earlier step
- Design explicit step checks (`if (!mounted || _currentStep != expectedStep) return;`) after every `await _speak(...)`
- Ensure skip actions reset any in-flight transition locks so the user can immediately interact with the newly skipped step
- Verify how this resolves Test 2 and Test 8 in test/stress_tutorial_audio_test.dart

## Current Parent
- Conversation ID: 2710972e-05b0-491e-8e81-953af37d2751
- Updated: 2026-11-10T20:01:45+09:00

## Investigation State
- **Explored paths**:
  - `lib/tutorial_screen.dart` (lines 300-480, 575-605, 620-660, 750-810)
  - `test/stress_tutorial_audio_test.dart` (Tests 1 through 9)
  - `test/tutorial_screen_test.dart`
  - `challenger_m1_2/handoff.md` and `analysis.md`
- **Key findings**:
  - Confirmed state machine reversion occurs because delayed async callbacks execute `setState(() { _currentStep = target; })` with only `if (!mounted) return;`. When user skips, `_currentStep` advances, but when speech completes, the stale callback overwrites `_currentStep` backwards.
  - Formulated explicit step verification: `if (!mounted || _currentStep != expectedStep || _transitionId != opId) return;` after every `await _playBeep()` and `await _speak(...)`.
  - Formulated transition lock and generation token architecture: `_isTransitioning` prevents re-entrancy / double speech (Tests 1 & 9).
  - Formulated skip reset rule: `_onSkipStepPressed()` MUST reset `_isTransitioning = false` and increment `_transitionId` so the user can immediately interact with the newly skipped step and prevent stale callbacks from modifying state or clearing new locks.
  - Formulated complete fixes for Tests 2 and 8, as well as Tests 1, 3, 6, and 9.
- **Unexplored areas**: None. Analysis complete.

## Key Decisions Made
- Use generation token `_transitionId` alongside `_currentStep != expectedStep` for provably race-free cancellation of abandoned transitions.
- Reset `_isTransitioning = false` inside `_onSkipStepPressed` to guarantee immediate UI responsiveness upon skipping.

## Artifact Index
- DISPATCH.md — Received dispatch instructions
- BRIEFING.md — Persistent working memory
- progress.md — Liveness heartbeat and completed tasks
- analysis.md — Detailed technical analysis and step-by-step fix blueprint
- handoff.md — Structured 5-component handoff report for Worker and Orchestrator
