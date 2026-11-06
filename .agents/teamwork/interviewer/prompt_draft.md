Create a minimal cross-platform Flutter verification application in `lib/main.dart` that captures physical buttons (Volume Up/Down) and earphone media keys (Play/Pause, Next, Previous) across Android and iOS, immediately reading out detected actions via `flutter_tts`, accompanied by automated tests.

Working directory: c:\Users\taqmi\02_development\original_program\button_controll_test
Integrity mode: development

## Requirements

### R1. Physical Button and Media Key Event Detection
Capture physical button and earphone media key events across target platforms (Android and iOS) using `flutter/services` (such as `HardwareKeyboard` or `RawKeyboardListener`) for:
- Volume Up (`KEYCODE_VOLUME_UP`)
- Volume Down (`KEYCODE_VOLUME_DOWN`)
- Play / Pause (`KEYCODE_MEDIA_PLAY_PAUSE` or `KEYCODE_MEDIA_PLAY` / `KEYCODE_MEDIA_PAUSE`)
- Next Track (`KEYCODE_MEDIA_NEXT`)
- Previous Track (`KEYCODE_MEDIA_PREVIOUS`)

### R2. Immediate Audio Feedback via flutter_tts
Upon detecting any specified key event, immediately speak out a confirmation phrase (e.g. "音量アップを受信しました", "再生・停止ボタンが押されました") using `flutter_tts` so that button operation can be verified without viewing the display.

### R3. Verification UI with Real-time Log
Provide a clean dark-mode verification interface:
- Center of the screen displays the name of the most recently detected button/key (e.g. `KEYCODE_VOLUME_UP`) in large text.
- Bottom of the screen displays a scrollable real-time log list showing received key events with their timestamps.

### R4. Standalone Deliverable & Dependency Documentation
- Implement the code as a self-contained `lib/main.dart` file that can be dropped in and run directly without depending on existing project code.
- Explicitly document in comments at the top of the file any packages (such as `flutter_tts`) required to be added to `pubspec.yaml`.

### R5. Automated Verification Tests
Provide automated Flutter tests (e.g. widget or unit tests under `test/`) that simulate key press events (Volume Up, Volume Down, Play/Pause, Next, Previous) and verify that key detection, UI updates, and TTS trigger invocations occur as specified.

## Acceptance Criteria

### Functional Verification
- [ ] Key press events for Volume Up, Volume Down, Play/Pause, Next Track, and Previous Track are handled across target platforms.
- [ ] `flutter_tts` is triggered upon key detection with appropriate descriptive speech text in Japanese.
- [ ] The center UI dynamically updates with the most recently pressed button name.
- [ ] The scrollable log list records each received key event with its timestamp in chronological order.

### Code and Documentation
- [ ] `lib/main.dart` is self-contained and ready to execute once dependencies are installed.
- [ ] Comments in `lib/main.dart` specify all necessary dependencies for `pubspec.yaml`.

### Automated Testing
- [ ] Automated Flutter tests execute successfully (`flutter test`).
- [ ] Automated tests simulate key events and assert that UI state updates and speech trigger calls are made.
