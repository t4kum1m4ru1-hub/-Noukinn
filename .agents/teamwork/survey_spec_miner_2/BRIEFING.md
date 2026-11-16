# BRIEFING — 2026-11-10T10:09:00Z

## Mission
Mine exact specifications for TutorialScreen key events, 6-step state machine, media key mappings, debounce concurrency, and audio synchronization.

## 🔒 My Identity
- Archetype: Specification Miner
- Roles: survey_spec_miner_2 (Key Event Spec Miner)
- Working directory: c:\Users\taqmi\02_development\original_program\button_controll_test\.agents\teamwork\survey_spec_miner_2
- Original parent: 4c8ae3a7-ebb5-4c14-9019-42e6ab31053f
- Milestone: Key Event Spec Mining
- Archetype: Specification Miner
- Roles: survey_spec_miner_2 (TutorialScreen Key Events & 6-step State Machine Spec Miner)
- Working directory: c:\Users\taqmi\02_development\original_program\noukin_app
- State folder: c:\Users\taqmi\02_development\original_program\noukin_app\.agents\teamwork\survey_spec_miner_2\
- Original parent: 2710972e-05b0-491e-8e81-953af37d2751
- Milestone: TutorialScreen Key Events and 6-Step State Machine Specification

## 🔒 Key Constraints
- Read-only on codebase/production files; only write to .agents/teamwork/survey_spec_miner_2/
- Follow Handoff Protocol (Observation, Logic Chain, Caveats, Conclusion, Verification Method)
- Report findings with Features Discovered and Edge Cases tables
- Thoroughly probe all key event mechanisms, key mappings, iOS/Android differences, and widget testing simulation
- Follow GEMINI.md rules: no external repo context, explain clearly for non-engineers, stop and ask if ambiguous
- lib/training_screen.dart must remain unmodified; lib/tutorial_screen.dart is implemented independently
- lib/main.dart adds "操作チュートリアルを体験する" button directly below "トレーニング開始"
- Re-use existing audio services (TtsService, SoundEffectService, AudioDuckingController) and ensure flutterTts.stop() before any speech

## Current Parent
- Conversation ID: 2710972e-05b0-491e-8e81-953af37d2751
- Updated: 2026-11-10T10:09:00Z

## Task Summary
- **What to build**: Specification mining analysis (analysis.md) and handoff report (handoff.md) for TutorialScreen key events and 6-step state machine.
- **Success criteria**: Detailed specification for Steps 1 through 6, key code / logical key mappings, state machine transitions, concurrency & debounce timer cancellation, and test simulation guidelines.
- **Interface contracts**: ORIGINAL_REQUEST.md
- **Code layout**: .agents/teamwork/survey_spec_miner_2/

## Key Decisions Made
- Investigated existing codebase: `KeyEventChannelDispatcher` manages native Android key events (codes 85, 79, 24, 25, 87, 88). In `TrainingScreen`, both `KeyEventChannelDispatcher` and `Focus(onKeyEvent: ...)` are wired.
- In `TrainingScreen`, PC keyboard shortcuts (arrowUp/arrowDown/space/arrowLeft/arrowRight) map to `ButtonAction` for emulator/desktop testing, and a virtual media control bar at the bottom provides on-screen buttons.
- For `TutorialScreen`, R4 specifies: Spotlight & dim overlay (Black 70%), Firefly pulsing glow border (`AnimationController` + `boxShadow`), Skip button, and PC/emulator virtual media key bar at the bottom.
- Step 1 to Step 6 state machine design analyzed: Step 1 (Intro/Entry), Step 2 (Start operation), Step 3 (Adjustment entry & item selection), Step 4 (Weight adjustment with 0.7s debounce), Step 5 (Adjustment finish), Step 6 (Completion & navigation to TrainingScreen).

## Artifact Index
- DISPATCH.md — Task assignment
- BRIEFING.md — Situational awareness
- progress.md — Liveness heartbeat
- analysis.md — Full specification mining report
- handoff.md — 5-component handoff report
