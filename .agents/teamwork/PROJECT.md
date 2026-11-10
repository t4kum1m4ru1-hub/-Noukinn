# Project: noukin_app TutorialScreen

## Architecture
- **Interactive Presentation Tutorial Screen (`lib/tutorial_screen.dart`)**:
  - Independent, dedicated module providing an end-to-end interactive tutorial for training without touching the smartphone.
  - Implements a deterministic 6-step state machine (`TutorialStep.step1Intro` to `TutorialStep.step6Completed`).
  - Seamless dependency injection of existing audio services (`TtsService`, `SoundEffectService`, `AudioDuckingController`) and optional test control flag (`animateGlow: bool = true`).
  - Navigation from/to: Triggered from `lib/main.dart` (`ButtonControlScreen`), completes or skips into `TrainingScreen` using `pushReplacement`.
- **UI & Presentation Effects**:
  - Semi-transparent dark overlay (`Colors.black.withOpacity(0.70)`) with punch-through spotlight via `CustomPainter` and `Path.combine(PathOperation.difference)`.
  - Firefly breathing glow animation around the focused element (`AnimationController` repeating with reverse, glowing `boxShadow`, `Positioned` + `IgnorePointer`).
  - Emergency presentation skip button at bottom-right plus screen touch triggers.
  - PC/Emulator/Testing virtual media key bar at bottom of screen (Prev, Play/Pause, Next, Vol-, Vol+) hooked into the same action pipeline.
- **Key Event Interception & Audio Synchronization**:
  - Double key input interception: Listens to native `KeyEventChannelDispatcher` (Android earphone/ADB keyevents 85, 79, 87, 88, 24, 25) and Flutter `Focus` keyboard events (`LogicalKeyboardKey.mediaPlayPause`, `audioVolumeUp`, etc.).
  - Step 3 two-phase selection: Part 1 toggle mode with Next key (87), Part 2 cycle items with Vol+/- (24/25) and select with Play/Pause (85).
  - Step 4 debounced weight adjustment: 0.7-second debounce timer (`Timer(Duration(milliseconds: 700))`) for TTS readout of adjusted weight, immediate beep and +/-2.5kg UI updates on key press, immediate timer cancellation on step transition or skip.
  - Audio exclusivity: Explicit `await ttsService?.stop()` before every new TTS utterance, with `AudioDuckingController` active throughout.
- **Automated Verification**:
  - Automated widget test suite (`test/tutorial_screen_test.dart`) exercising all 6 steps, key events, skip routes, virtual bar, debounce, and TTS speech calls using `FakeTtsService`, `FakeSoundEffectService`, and `sendNativeKeyEvent`.

## Feature Inventory
| # | Feature | Description | Milestone | Source |
|---|---------|-------------|-----------|--------|
| 1 | Entry Point Navigation | 「操作チュートリアルを体験する」ボタン in `lib/main.dart`, navigating to `TutorialScreen` | M1 | Survey (explorer_1) & R1 |
| 2 | Read-Only TrainingScreen Guarantee | `lib/training_screen.dart` remains untouched; `TutorialScreen` transitions to it via `pushReplacement` | M1 | Survey (explorer_1) & R1 |
| 3 | Audio Services & Ducking Integration | Direct reuse of `TtsService`, `SoundEffectService`, `AudioDuckingController` with mandatory `stop()` before speech | M1 | Survey (explorer_1, miner_2) & R2 |
| 4 | Media Key Handling Framework | Interception of keycodes 85/79, 87, 88, 24, 25 via `KeyEventChannelDispatcher` and `Focus` | M1 | Survey (miner_2) & R3 |
| 5 | Spotlight & Dark Overlay Painter | 70% black overlay with punch-through spotlight `CustomPainter` | M1 | Survey (explorer_3) & R4 |
| 6 | Firefly Glow Animation | Breathing glow animation (`AnimationController` + `boxShadow`) with `animateGlow` flag | M1 | Survey (explorer_3) & R4 |
| 7 | Skip Controls & Virtual Key Bar | Unobtrusive skip button and bottom 5-button virtual media key bar | M1 | Survey (miner_2, explorer_3) & R4 |
| 8 | Step 1: Start Screen | Title, description, "チュートリアルを開始する", "スキップして直接トレーニングへ" | M1 | Survey (miner_2) & R5 |
| 9 | Step 2: Start Operation Experience | Central start button spotlight, keyevent 85/skip trigger, sound, start animation, TTS "開始、ベンチプレス、60キロ、10回、3セット", auto-transition to Step 3 | M1 | Survey (miner_2) & R5 |
| 10 | Step 3: Adjustment Entry & Item Selection | Part 1 keyevent 87 -> sound + TTS "調整、種目名". Part 2 keyevent 24/25 -> sound + cycle items + item TTS. Keyevent 85 -> sound + "60キロ" -> Step 4. Keyevent 88 -> safety readout | M1 | Survey (miner_2) & R5 |
| 11 | Step 4: Weight Adjustment & Debounce | Spotlight weight card (60.0kg). Keyevent 24/25 -> immediate beep + real-time +/-2.5kg. 0.7s debounced TTS. Keyevent 85 -> sound + "調整、重量" -> Step 5. Keyevent 88 -> safety readout | M1 | Survey (miner_2) & R5 |
| 12 | Step 5: Adjustment Completion | Dark overlay + notice. Keyevent 87 -> beep + "確定" + "開始、ベンチプレス、65キロ、10回、3セット" -> Step 6. Other keys show notice | M1 | Survey (miner_2) & R5 |
| 13 | Step 6: Completion & Handoff | Celebration screen, "最初のトレーニングを開始する" or keyevent 85 -> navigate to `TrainingScreen` | M1 | Survey (miner_2) & R5 |
| 14 | Automated Widget Test Suite | Comprehensive tests in `test/tutorial_screen_test.dart` verifying all 6 steps, key events, UI elements, audio calls, debounce, and transitions | M1 | Survey (explorer_3, miner_2) & R6 |
| 15 | Multi-Perspective Verification & Forensic Integrity | Reviewers (APPROVE), Challengers (PASS), Forensic Auditor (CLEAN), 100% test pass | M1 | System Prompt & AC |

## Milestones
| # | Name | Scope | Dependencies | Status |
|---|------|-------|-------------|--------|
| M1 | TutorialScreen Implementation & Automated Verification | Implement `lib/tutorial_screen.dart`, update `lib/main.dart` entry button, create comprehensive `test/tutorial_screen_test.dart`, and verify via multi-agent gate | Survey completed | DONE |

## Interface Contracts
### Main Screen ↔ TutorialScreen
- Entry:
  ```dart
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (context) => TutorialScreen(
        ttsService: widget.ttsService,
        soundEffectService: widget.soundEffectService,
      ),
    ),
  );
  ```
- Exit (Completion or Skip to TrainingScreen):
  ```dart
  Navigator.of(context).pushReplacement(
    MaterialPageRoute(
      builder: (context) => TrainingScreen(
        ttsService: widget.ttsService,
        soundEffectService: widget.soundEffectService,
      ),
    ),
  );
  ```

### TutorialScreen Constructor & DI
```dart
class TutorialScreen extends StatefulWidget {
  final TtsService? ttsService;
  final SoundEffectService? soundEffectService;
  final AudioDuckingController? duckingController;
  final bool animateGlow;

  const TutorialScreen({
    super.key,
    this.ttsService,
    this.soundEffectService,
    this.duckingController,
    this.animateGlow = true,
  });
}
```

### Key Event Mapping Contract
- `KeyEventChannelDispatcher` (or virtual key bar / keyboard focus):
  - `ButtonAction.mediaPlayPause` (85, 79)
  - `ButtonAction.mediaNext` (87)
  - `ButtonAction.mediaPrevious` (88)
  - `ButtonAction.volumeUp` (24)
  - `ButtonAction.volumeDown` (25)

## Code Layout
- `lib/tutorial_screen.dart`: Complete interactive tutorial module (Steps 1-6 state machine, overlay painter, firefly glow, debounce timer, media control bar).
- `lib/main.dart`: Add `start_tutorial_button` directly below `start_training_button` (lines 674-703).
- `lib/training_screen.dart`: UNTOUCHED (read-only constraint).
- `test/tutorial_screen_test.dart`: Complete automated widget test suite exercising all 6 steps, key events, transitions, debounce, and TTS speech calls.
