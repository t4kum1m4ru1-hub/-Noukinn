# BRIEFING — 2026-11-10T10:20:00Z

## Mission
Formulate the exact state machine and audio/key management implementation design for TutorialScreen in lib/tutorial_screen.dart (Milestone 1).

## 🔒 My Identity
- Archetype: explorer
- Roles: investigation, state machine & audio/key management design
- Working directory: c:\Users\taqmi\02_development\original_program\noukin_app
- State folder: c:\Users\taqmi\02_development\original_program\noukin_app\.agents\teamwork\explorer_m1_1\
- Original parent: 2710972e-05b0-491e-8e81-953af37d2751
- Milestone: milestone_1 (TutorialScreen State Machine & Audio/Key Management Design)

## 🔒 Key Constraints
- Read-only investigation — do NOT implement directly in project code
- Detailed specifications for TutorialStep enum (step1 to step6) and step3 sub-phase
- Exact KeyEventChannelDispatcher listener lifecycle
- Keycode mapping (85/79, 87, 88, 24, 25)
- Step transitions, Step 4 debounce timer (0.7s) logic for +/-2.5kg
- Audio method _speak(String text) ducking / await stop
- Concrete architecture guidelines for Worker

## Current Parent
- Conversation ID: 2710972e-05b0-491e-8e81-953af37d2751
- Updated: not yet

## Investigation State
- **Explored paths**:
  - `lib/main.dart` (lines 55-520, 674-703: AudioDuckingController, SoundEffectService, TtsService, KeyEventChannelDispatcher, ButtonControlScreen)
  - `lib/training_controller.dart` (lines 180-215, 510-547: debounce timer with frame pump, weight format, audio integration)
  - `lib/training_screen.dart` (lines 1-125: KeyEventChannelDispatcher lifecycle, Focus keyboard handler)
  - `test/widget_test.dart` (lines 1-599: sendNativeKeyEvent, FakeTtsService, FakeSoundEffectService, TimelineDuckingController)
  - `.agents/teamwork/survey_spec_miner_2/analysis.md`
  - `.agents/teamwork/survey_explorer_3/analysis.md`
- **Key findings**:
  - `KeyEventChannelDispatcher` dispatches events to `_listeners.last`, so registering in `initState` and unregistering in `dispose` cleanly isolates topmost screen.
  - Calling `await ttsService?.stop()` prior to `speak()` prevents overlapping speech and satisfies AC.
  - Periodic `scheduleFrame` pulse inside 0.7s debounce timer enables `pumpAndSettle()` in widget tests without pending timer errors.
- **Unexplored areas**: None for state machine and audio/key management design.

## Key Decisions Made
- Formulated 6-step state machine (`TutorialStep.step1Intro` to `TutorialStep.step6Complete`) and 2-phase Step 3 (`Step3Phase.enterMode`, `Step3Phase.cycleItem`).
- Designed single key input pipeline routing native keyevents, PC shortcuts, and virtual key bar taps.
- Detailed debounce timer cancellation on early confirm, skip, or dispose.

## Artifact Index
- DISPATCH.md — incoming dispatch instructions
- BRIEFING.md — persistent working memory
- progress.md — liveness heartbeat
- analysis.md — comprehensive technical analysis & design
- handoff.md — 5-component handoff report
