# BRIEFING — 2026-11-10T10:18:00Z

## Mission
Formulate the exact visual presentation, layout, and animation design for TutorialScreen in lib/tutorial_screen.dart (Spotlight overlay, firefly glow animation, 6-step visual cards, presentation skip controls, virtual media key bar, and Worker guidelines).

## 🔒 My Identity
- Archetype: explorer
- Roles: Automated Test Design Explorer
- Working directory: c:\Users\taqmi\02_development\original_program\button_controll_test\.agents\teamwork\explorer_m1_2
- Original parent: 4c8ae3a7-ebb5-4c14-9019-42e6ab31053f
- Milestone: M1 (Architecture and Test Design)
- Archetype: explorer
- Roles: UI Presentation & Animation Design Explorer
- Working directory: c:\Users\taqmi\02_development\original_program\noukin_app
- State folder: c:\Users\taqmi\02_development\original_program\noukin_app\.agents\teamwork\explorer_m1_2\
- Original parent: 2710972e-05b0-491e-8e81-953af37d2751
- Milestone: M1 (TutorialScreen Implementation)

## 🔒 Key Constraints
- Read-only investigation — do NOT implement
- Multi-tier test suite design (Tier 1: Feature coverage, Tier 2: Boundary/Corner, Tier 3: Sequential/Combinatorial)
- FakeTtsService injection into ButtonControlApp(ttsService: fakeTts)
- tester.sendKeyEvent deterministic simulation without external mock packages
- Read-only investigation — do NOT implement source code
- lib/training_screen.dart must remain UNTOUCHED
- Semi-transparent black overlay (Colors.black.withOpacity(0.70)) with punch-through spotlight Rect/RRect
- Breathing firefly glow animation (AnimationController repeat with reverse, animated boxShadow, Positioned + IgnorePointer)
- animateGlow: bool = true parameter handling for test safety (prevent pumpAndSettle timeout)
- All 6 steps visual cards & spotlight targets fully formulated
- Bottom virtual media key bar and presentation skip controls designed

## Current Parent
- Conversation ID: 2710972e-05b0-491e-8e81-953af37d2751
- Updated: 2026-11-10T10:15:31Z

## Investigation State
- **Explored paths**:
  - `ORIGINAL_REQUEST.md`, `PROJECT.md`
  - `survey_explorer_3/handoff.md`, `survey_explorer_3/analysis.md`
  - `survey_spec_miner_2/handoff.md`
  - `lib/training_screen.dart`, `lib/main.dart`, `lib/theme/app_colors.dart`, `test/widget_test.dart`
- **Key findings**:
  - `SpotlightOverlayPainter` with `Path.combine(PathOperation.difference, fullPath, holePath)` provides 100% clarity punch-through with zero `saveLayer` performance penalty.
  - Firefly glow animation using `AnimationController` + layered `boxShadow` over `IgnorePointer` allows seamless screen interaction.
  - Setting `animateGlow: false` during widget tests prevents `pumpAndSettle timed out` while keeping visual verification intact.
  - 6-step layout cleanly builds on the exact visual cards from `TrainingScreen` with floating guidance cards and responsive spotlight coordinates.
- **Unexplored areas**: None. Visual presentation and animation design is fully established.

## Key Decisions Made
- `SpotlightOverlayPainter` uses dynamic `Rect` from `GlobalKey` with fallback bounds for first frame.
- Firefly glow animation uses dual-layer `boxShadow` (tealAccent core + aura) wrapped in `IgnorePointer` and positioned at target coordinates.
- Emergency presentation skip button (`btn_tutorial_skip`) fixed at bottom-right above virtual media key bar.
- Virtual media key bar (`_buildMediaControlBar`) fixed at screen bottom in foreground (above overlay) for PC/emulator/touch operations.

## Artifact Index
- `DISPATCH.md` — Incoming dispatch log
- `BRIEFING.md` — Working memory and identity index
- `progress.md` — Heartbeat and status
- `analysis.md` — Comprehensive visual presentation, layout, and animation design document
- `handoff.md` — 5-component handoff report for Worker
