# Project: button_controll_test

## Architecture
- Standalone Flutter application (`lib/main.dart`) capturing physical buttons and earphone media keys across Android and iOS.
- Decoupled `TtsService` interface (`FlutterTtsService` for production, `FakeTtsService` for testing) eliminating `MissingPluginException` in headless tests while keeping `lib/main.dart` standalone.
- Global hardware key event listener using `HardwareKeyboard.instance.addHandler` filtering for `KeyDownEvent`.
- Dark-mode UI with dynamic key name readout in large text (center) and auto-scrolling timestamped event log (bottom).
- Dedicated widget test suite (`test/widget_test.dart`) exercising all 5 target button actions and verifying UI/TTS reactions.

## Feature Inventory
| # | Feature | Description | Milestone | Source |
|---|---------|-------------|-----------|--------|
| 1 | Workspace Scaffolding & Dependencies | Flutter project scaffold, pubspec.yaml with flutter_tts, Android queries tag | M1 | Survey (explorer_1) |
| 2 | TtsService Abstraction | Abstract TtsService with FlutterTtsService and FakeTtsService implementations | M1 | Survey (explorer_3) |
| 3 | Key Event Interception | Global HardwareKeyboard listener filtering KeyDownEvent and mapping logical keys | M1 | Survey (spec_miner_2) |
| 4 | ButtonAction Mapping | Volume Up/Down, Media Play/Pause/Play/Pause, Media Next/Previous mappings & Japanese speech phrases | M1 | Survey (spec_miner_2 & ORIGINAL_REQUEST) |
| 5 | Dark-Mode Verification UI | Dark surface theme, large center key display, scrollable real-time timestamped log | M1 | Survey (explorer_3 & ORIGINAL_REQUEST) |
| 6 | Self-Contained Dependency Documentation | Comments at top of lib/main.dart detailing pubspec.yaml and platform configurations | M1 | Survey (explorer_3 & ORIGINAL_REQUEST) |
| 7 | Multi-Tier Automated Tests | Widget tests for all 5 key events, UI state changes, speech invocations, and edge cases | M2 | Survey (spec_miner_2, explorer_3, ORIGINAL_REQUEST) |
| 8 | E2E Execution & Forensic Verification | Full flutter test execution, coverage verification, and clean forensic audit | M3 | Survey & System Prompt |

## Milestones
| # | Name | Scope | Dependencies | Status |
|---|------|-------|-------------|--------|
| M1 | Workspace & Core Implementation | Initialize Flutter scaffold, pubspec.yaml, Android manifest queries, lib/main.dart | none | DONE |
| M2 | Automated Test Suite (test/) | Comprehensive widget tests simulating key events and verifying UI/TTS (19 core + 20 adversarial tests) | M1 | DONE |
| M3 | Integration Gate & Forensic Audit | Run flutter test, verify pass rate, Reviewer + Challenger + Auditor gate | M2 | DONE |

## Interface Contracts
### Key Listener ↔ ButtonAction
- Input: `KeyEvent` from `HardwareKeyboard`
- Filter: `event is KeyDownEvent`
- Mapping: `ButtonAction.fromLogicalKey(event.logicalKey)` -> returns `ButtonAction?`
- Action: If matched, updates UI state and calls `ttsService.speak(action.speechText)`. Returns `true` (handled). If unmatched, returns `false`.

### Application ↔ TtsService
- Interface:
  - `Future<void> initialize()`
  - `Future<void> speak(String text)`
  - `Future<void> stop()`
- Production: `FlutterTtsService` initializes `FlutterTts`, sets language to `ja-JP`, handles iOS audio categories.
- Test Fake: `FakeTtsService` records `spokenHistory` (List<String>) and `lastSpoken` (String?), non-blocking.

## Code Layout
- `pubspec.yaml`: Project configuration, SDK constraints, `flutter_tts: ^4.2.5`, `flutter_test`.
- `lib/main.dart`: Completely self-contained application (TtsService, ButtonAction, ButtonControlApp, VerificationScreen).
- `test/widget_test.dart`: Automated verification tests simulating hardware keys via `tester.sendKeyEvent` and asserting UI and TTS states.
- `android/app/src/main/AndroidManifest.xml`: TTS_SERVICE queries block.
