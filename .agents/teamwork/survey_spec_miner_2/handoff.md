# Handoff Report — Key Event Specification Mining

**Agent**: `survey_spec_miner_2` (Key Event Spec Miner)  
**Date**: 2026-11-05T23:42:00Z  
**Target Milestone**: Survey / Specification Mining  
**Integrity Mode**: development  

---

## 1. Observation

Direct observations from the Flutter SDK framework source files located at `C:\Users\taqmi\06_一時保管\flutter\packages\flutter\lib\src\services` and `test` suites:

### 1.1 Key Event Handling Mechanisms
- **`HardwareKeyboard` (`hardware_keyboard.dart`)**:
  - Accessed via singleton `HardwareKeyboard.instance` or `ServicesBinding.instance.keyboard` (line 414).
  - Registers listeners via `void addHandler(KeyEventCallback handler)` (lines 552-577).
  - Callback signature: `typedef KeyEventCallback = bool Function(KeyEvent event)`.
  - Behavior: All registered handlers are invoked regardless of return value. Returning `true` signals that Flutter handles the event and prevents propagation to native parent views in add-to-app contexts.
  - Crucial advantage: Operates globally at the binding level without requiring an active `FocusNode` in the widget tree.
  - Cleanup: Requires `removeHandler(handler)` on disposal to avoid memory leaks.
- **`Focus` Widget (`focus_manager.dart`, `focus_scope.dart`)**:
  - Widget-level key interception using `Focus(autofocus: true, onKeyEvent: (FocusNode node, KeyEvent event) => KeyEventResult.handled, child: ...)`.
  - Event propagation stops if `KeyEventResult.handled` or `KeyEventResult.skipRemainingHandlers` is returned.
  - Requires keyboard focus on the widget tree.
- **`KeyboardListener` Widget (`keyboard_listener.dart`)**:
  - Wraps `Focus` with `onKeyEvent: (FocusNode node, KeyEvent event) { onKeyEvent?.call(event); return KeyEventResult.ignored; }`.
  - Note: Always returns `KeyEventResult.ignored`, meaning it cannot consume/block key propagation.
- **`RawKeyboardListener` / `RawKeyboard` (`raw_keyboard.dart`, `raw_keyboard_listener.dart`)**:
  - Explicitly marked `@Deprecated('Platform specific key event data is no longer available. See KeyEvent for what is available. This feature was deprecated after v3.18.0-2.0.pre.')`.
  - Replaced by `HardwareKeyboard` and `KeyEvent`.

### 1.2 Exact Key Mappings (from `keyboard_key.g.dart` & `keyboard_maps.g.dart`)

| Action Name | Android KeyCode Name (Constant) | Android KeyCode Value | Android ScanCode | iOS Virtual KeyCode | LogicalKeyboardKey Constant | Logical Key ID (`keyId`) | PhysicalKeyboardKey Constant | Physical USB HID (`usbHid`) |
|---|---|---|---|---|---|---|---|---|
| **Volume Up** | `KEYCODE_VOLUME_UP` | `24` | `115` | `0x80` (`128`) | `LogicalKeyboardKey.audioVolumeUp` | `0x00100000a10` | `PhysicalKeyboardKey.audioVolumeUp` | `0x00070080` |
| **Volume Down** | `KEYCODE_VOLUME_DOWN` | `25` | `114` | `0x81` (`129`) | `LogicalKeyboardKey.audioVolumeDown` | `0x00100000a0f` | `PhysicalKeyboardKey.audioVolumeDown` | `0x00070081` |
| **Play / Pause (Toggle)** | `KEYCODE_MEDIA_PLAY_PAUSE` | `85` | `164` | N/A (RemoteCommand) | `LogicalKeyboardKey.mediaPlayPause` | `0x00100000a05` | `PhysicalKeyboardKey.mediaPlayPause` | `0x000c00cd` |
| **Play (Discrete)** | `KEYCODE_MEDIA_PLAY` | `126` | `200` / `207` | N/A | `LogicalKeyboardKey.mediaPlay` | `0x00100000d2f` | `PhysicalKeyboardKey.mediaPlay` | `0x000c00b0` |
| **Pause (Discrete)** | `KEYCODE_MEDIA_PAUSE` | `127` | `201` | N/A | `LogicalKeyboardKey.mediaPause` | `0x00100000d2e` | `PhysicalKeyboardKey.mediaPause` | `0x000c00b1` |
| **Next Track** | `KEYCODE_MEDIA_NEXT` | `87` | `163` | N/A | `LogicalKeyboardKey.mediaTrackNext` | `0x00100000a08` | `PhysicalKeyboardKey.mediaTrackNext` | `0x000c00b5` |
| **Previous Track** | `KEYCODE_MEDIA_PREVIOUS` | `88` | `165` | N/A | `LogicalKeyboardKey.mediaTrackPrevious` | `0x00100000a09` | `PhysicalKeyboardKey.mediaTrackPrevious` | `0x000c00b6` |

*Related Keys Discovered*:
- **Media Stop**: Android `KEYCODE_MEDIA_STOP` (`86`), `LogicalKeyboardKey.mediaStop` (`0x00100000a07`), `PhysicalKeyboardKey.mediaStop` (`0x000c00b7`).
- **Volume Mute**: Android `KEYCODE_VOLUME_MUTE` (`164`), `LogicalKeyboardKey.audioVolumeMute` (`0x00100000a11`), `PhysicalKeyboardKey.audioVolumeMute` (`0x0007007f`).

### 1.3 Event Lifecycle & Types
- A key press generates a sequence:
  1. `KeyDownEvent`: Initial press down.
  2. `KeyRepeatEvent`: If held down, repeated pulses.
  3. `KeyUpEvent`: Release of the key.
- To avoid duplicate handling (e.g. triggering TTS and UI logs twice per click), listener logic MUST explicitly filter `if (event is KeyDownEvent)`.

### 1.4 Test Simulation APIs (from `controller.dart` & `event_simulation.dart` in `flutter_test`)
- **`WidgetTester.sendKeyEvent`**:
  ```dart
  Future<bool> sendKeyEvent(
    LogicalKeyboardKey key, {
    String? platform,
    String? character,
    PhysicalKeyboardKey? physicalKey,
  })
  ```
  Dispatches a `KeyDownEvent` followed by a `KeyUpEvent`. Returns `true` if handled.
- **`simulateKeyDownEvent` / `simulateKeyUpEvent`**:
  ```dart
  await simulateKeyDownEvent(LogicalKeyboardKey.audioVolumeUp);
  await tester.pump();
  await simulateKeyUpEvent(LogicalKeyboardKey.audioVolumeUp);
  await tester.pump();
  ```
- Both methods operate universally in mock framework tests without needing physical hardware attached.

---

## 2. Logic Chain

1. **API Selection (HardwareKeyboard vs Focus vs RawKeyboard)**:
   - Observation 1.1 reveals that `RawKeyboardListener` has been deprecated in Flutter 3.18+.
   - `HardwareKeyboard.instance.addHandler` listens globally without requiring the user to tap on a text field or hold widget focus.
   - For a verification utility app where the display may not be viewed (R2: auditory verification), `HardwareKeyboard.instance.addHandler` (or a root `Focus(autofocus: true, ...)` wrapping the entire Scaffold) is the most robust architecture.
   - Using both or combining `HardwareKeyboard.instance.addHandler` ensures all key events are captured regardless of focus state.

2. **Key Mapping Logic**:
   - The user specification mandates capturing Volume Up, Volume Down, Play/Pause, Next Track, and Previous Track.
   - Flutter's `keyboard_maps.g.dart` maps Android's `KEYCODE_VOLUME_UP` (24) directly to `LogicalKeyboardKey.audioVolumeUp`, and `KEYCODE_VOLUME_DOWN` (25) to `LogicalKeyboardKey.audioVolumeDown`.
   - Media buttons vary: some headsets send toggle `mediaPlayPause` (85), while others send discrete `mediaPlay` (126) and `mediaPause` (127). The app should match any of these three to fulfill "Play / Pause".
   - Next Track maps cleanly to `LogicalKeyboardKey.mediaTrackNext`, and Previous Track to `LogicalKeyboardKey.mediaTrackPrevious`.

3. **Platform Nuances (Android vs iOS Real Device Behavior)**:
   - **Android**:
     - The native `FlutterActivity` receives `onKeyDown` for `KEYCODE_VOLUME_UP`, `KEYCODE_VOLUME_DOWN`, `KEYCODE_MEDIA_*`.
     - When intercepted and returned `true` by the Flutter framework/embedder, Android suppresses the volume HUD. If not consumed, Android changes the media volume and shows the HUD.
     - Headset media buttons in modern Android (API 26+) are routed to `MediaSessionCompat`. If no `MediaSession` is registered by the app, Android may forward clicks to the last active media player (e.g. Spotify) rather than the foreground app.
   - **iOS**:
     - iOS UIKit (`pressesBegan:withEvent:`) only dispatches key events from connected external hardware keyboards (Bluetooth / Smart Folio).
     - Physical side volume buttons on iOS are NOT delivered to `UIKey` or Flutter's `HardwareKeyboard`. They are handled exclusively by Apple CoreAudio/AVFoundation. Intercepting them on real iPhones requires native AVAudioSession outputVolume KVO observation and `MPVolumeView`.
     - Earphone media buttons on iOS are handled via `MPRemoteCommandCenter` (MediaPlayer framework), not keyboard events.
   - **Testing & Emulation**:
     - Regardless of real-device platform limits, Flutter's framework level (`HardwareKeyboard`, `simulateKeyEvent`, `tester.sendKeyEvent`) abstracts all platforms identically. Automated widget tests (`flutter test`) test the exact Flutter key event pipeline deterministically.

4. **Event Deduplication Logic**:
   - `tester.sendKeyEvent` issues both `KeyDownEvent` and `KeyUpEvent`.
   - Real keyboards issue `KeyDownEvent`, zero or more `KeyRepeatEvent`, and `KeyUpEvent`.
   - Speech synthesis and UI logging must trigger ONLY on `event is KeyDownEvent` to avoid duplicated announcements.

---

## 3. Features Discovered

| # | Category | Feature | Description | Inputs | Outputs | Error Behavior | Discovered Via |
|---|---|---|---|---|---|---|---|
| 1 | Event Interception | `HardwareKeyboard.instance.addHandler` | Global listener for hardware key events across the entire Flutter app | `KeyEventCallback handler` (takes `KeyEvent`) | Registers handler; returns `void`. Handler returns `bool` (handled) | Handlers throwing exceptions are caught and logged by Flutter framework | `hardware_keyboard.dart:570` |
| 2 | Event Interception | `HardwareKeyboard.instance.removeHandler` | Deregisters global key event handler | `KeyEventCallback handler` | `void` | No-op if handler not found | `hardware_keyboard.dart:588` |
| 3 | Event Interception | `Focus.onKeyEvent` | Widget-tree level key event interceptor | `(FocusNode, KeyEvent) -> KeyEventResult` | `KeyEventResult` (`handled`, `ignored`, `skipRemainingHandlers`) | If widget loses focus, events bypass handler | `keyboard_listener.dart:71`, `focus_manager.dart` |
| 4 | Key Constant | `LogicalKeyboardKey.audioVolumeUp` | Logical representation of Volume Up (`0x00100000a10`) | Key press | Logical key object with `keyId: 0x00100000a10`, `debugName: 'Audio Volume Up'` | None | `keyboard_key.g.dart:1375` |
| 5 | Key Constant | `LogicalKeyboardKey.audioVolumeDown` | Logical representation of Volume Down (`0x00100000a0f`) | Key press | Logical key object with `keyId: 0x00100000a0f`, `debugName: 'Audio Volume Down'` | None | `keyboard_key.g.dart:1370` |
| 6 | Key Constant | `LogicalKeyboardKey.mediaPlayPause` | Logical representation of Play/Pause toggle (`0x00100000a05`) | Key press | Logical key object with `keyId: 0x00100000a05`, `debugName: 'Media Play Pause'` | None | `keyboard_key.g.dart:1325` |
| 7 | Key Constant | `LogicalKeyboardKey.mediaPlay` | Logical representation of dedicated Play (`0x00100000d2f`) | Key press | Logical key object with `keyId: 0x00100000d2f`, `debugName: 'Media Play'` | None | `keyboard_key.g.dart:1725` |
| 8 | Key Constant | `LogicalKeyboardKey.mediaPause` | Logical representation of dedicated Pause (`0x00100000d2e`) | Key press | Logical key object with `keyId: 0x00100000d2e`, `debugName: 'Media Pause'` | None | `keyboard_key.g.dart:1720` |
| 9 | Key Constant | `LogicalKeyboardKey.mediaTrackNext` | Logical representation of Next Track (`0x00100000a08`) | Key press | Logical key object with `keyId: 0x00100000a08`, `debugName: 'Media Track Next'` | None | `keyboard_key.g.dart:1335` |
| 10 | Key Constant | `LogicalKeyboardKey.mediaTrackPrevious` | Logical representation of Previous Track (`0x00100000a09`) | Key press | Logical key object with `keyId: 0x00100000a09`, `debugName: 'Media Track Previous'` | None | `keyboard_key.g.dart:1340` |
| 11 | Key Constant | `PhysicalKeyboardKey.audioVolumeUp` | Physical USB HID code for Volume Up (`0x00070080`) | Hardware scan code | Physical key object (`0x00070080`) | None | `keyboard_key.g.dart:4486` |
| 12 | Key Constant | `PhysicalKeyboardKey.audioVolumeDown` | Physical USB HID code for Volume Down (`0x00070081`) | Hardware scan code | Physical key object (`0x00070081`) | None | `keyboard_key.g.dart:4492` |
| 13 | Key Constant | `PhysicalKeyboardKey.mediaPlayPause` | Physical USB HID code for Media Play/Pause (`0x000c00cd`) | Hardware scan code | Physical key object (`0x000c00cd`) | None | `keyboard_key.g.dart:4817` |
| 14 | Key Constant | `PhysicalKeyboardKey.mediaTrackNext` | Physical USB HID code for Next Track (`0x000c00b5`) | Hardware scan code | Physical key object (`0x000c00b5`) | None | `keyboard_key.g.dart:4795` |
| 15 | Key Constant | `PhysicalKeyboardKey.mediaTrackPrevious` | Physical USB HID code for Previous Track (`0x000c00b6`) | Hardware scan code | Physical key object (`0x000c00b6`) | None | `keyboard_key.g.dart:4801` |
| 16 | Test Simulation | `tester.sendKeyEvent` | Simulates a full key tap (KeyDown + KeyUp) on `WidgetTester` | `LogicalKeyboardKey key`, optional `platform`, `physicalKey` | `Future<bool>` indicating whether event was handled | Re-throws assertions if invalid key state | `controller.dart:2213` |
| 17 | Test Simulation | `simulateKeyDownEvent` | Simulates only a key down event | `LogicalKeyboardKey key`, optional `platform`, `physicalKey` | `Future<bool>` | Unbalanced keys cleared after test | `controller.dart:2257` |
| 18 | Test Simulation | `simulateKeyUpEvent` | Simulates only a key up event | `LogicalKeyboardKey key`, optional `platform`, `physicalKey` | `Future<bool>` | None | `controller.dart:2293` |
| 19 | Related Key | `LogicalKeyboardKey.audioVolumeMute` | Logical representation of Audio Volume Mute (`0x00100000a11`) | Android KEYCODE_VOLUME_MUTE (164) | Logical key object | None | `keyboard_key.g.dart:1380` |
| 20 | Related Key | `LogicalKeyboardKey.mediaStop` | Logical representation of Media Stop (`0x00100000a07`) | Android KEYCODE_MEDIA_STOP (86) | Logical key object | None | `keyboard_key.g.dart:1330` |

---

## 4. Edge Cases

| # | Feature | Input | Observed Behavior | Handling / Recommendation |
|---|---|---|---|---|
| 1 | Event Type Filtering | `tester.sendKeyEvent(...)` | Generates both `KeyDownEvent` and `KeyUpEvent` in succession. | Handler must filter `if (event is! KeyDownEvent) return false;` to avoid double speech and duplicate logs. |
| 2 | Long Press / Key Hold | User holds physical button | Generates `KeyDownEvent` followed by multiple `KeyRepeatEvent` instances before `KeyUpEvent`. | Ignore `KeyRepeatEvent` unless continuous volume ramping is desired. For discrete announcements, process only `event is KeyDownEvent`. |
| 3 | Media Play/Pause Fragmentation | Headset sends `KEYCODE_MEDIA_PLAY` or `KEYCODE_MEDIA_PAUSE` instead of `KEYCODE_MEDIA_PLAY_PAUSE` | Different hardware vendors emit separate play and pause key codes. | Check: `event.logicalKey == LogicalKeyboardKey.mediaPlayPause \|\| event.logicalKey == LogicalKeyboardKey.mediaPlay \|\| event.logicalKey == LogicalKeyboardKey.mediaPause`. |
| 4 | Widget Focus Loss | App launches or user touches non-focusable widget | If using `Focus` without autofocus or losing focus, key events are ignored. | Use `HardwareKeyboard.instance.addHandler` which does not depend on widget focus, or ensure root `Focus(autofocus: true)` is maintained. |
| 5 | Memory Leak on Hot Reload / Dispose | Stateful widget registered `addHandler` in `initState` | If `removeHandler` is omitted in `dispose`, old handlers persist across rebuilds causing duplicated invocations. | Always pair `HardwareKeyboard.instance.addHandler` with `HardwareKeyboard.instance.removeHandler` in `dispose()`. |
| 6 | iOS Native Volume Buttons | User presses physical volume buttons on real iPhone | iOS does not emit `UIKey` events for physical side buttons. `HardwareKeyboard` receives nothing on real iOS device hardware. | Document this iOS platform limitation clearly in code comments. In automated tests (`flutter_test`), `sendKeyEvent` works seamlessly. On real devices, third-party plugin (`volume_button_listener`) is required for iOS side buttons. |
| 7 | Android Native Media Buttons | User clicks headset button when background music app is running | Android OS routes headset buttons to active `MediaSession`. If app has no `MediaSession`, background app takes priority. | Document that for production audio earphone control on real Android devices, `MediaSession` integration (e.g. `audio_service`) is standard. `flutter/services` handles direct hardware keyboard events and automated test events. |
| 8 | Unhandled Keys | User presses Back (`LogicalKeyboardKey.goBack`) or Enter | If handler returns `true` for all keys, navigation and normal keyboard entry breaks. | Return `true` ONLY for matched volume/media keys; return `false` for all other keys so system behavior is preserved. |

---

## 5. Caveats

1. **Hardware Keyboard vs OS Hardware Buttons on Physical Devices**:
   - Flutter's `flutter/services` key pipeline (`HardwareKeyboard`) is fundamentally designed for hardware keyboards (Bluetooth keyboards, USB HID keyboards, OTG keyboards, emulator keyboard input).
   - On physical Android devices, volume keys are normally dispatched to the activity as keyboard keys, but some vendor skins or lock states may consume them.
   - On physical iOS devices, the physical side buttons are strictly not keyboard keys. They never pass through `UIKey` unless an external keyboard is connected.
2. **Automated Testing Reliability**:
   - In automated widget testing (`flutter test`), `WidgetTester.sendKeyEvent` operates at the Flutter engine framework boundary. It does NOT invoke native OS drivers and behaves identically across Windows, macOS, Linux, Android, and iOS test targets. All test assertions will succeed reliably.
3. **Deprecated APIs**:
   - Although the user request mentions `RawKeyboardListener`, all code in Flutter 3.18+ should use `HardwareKeyboard` or `Focus(onKeyEvent: ...)`. The report specifies the modern equivalents.

---

## 6. Conclusion

1. **Recommended Architecture for `lib/main.dart`**:
   - Implement key detection using `HardwareKeyboard.instance.addHandler` in the root stateful widget (`initState`) with `HardwareKeyboard.instance.removeHandler` in `dispose()`.
   - Wrap the Scaffold with `Focus(autofocus: true, ...)` as defense-in-depth to ensure focus is always held.
   - Restrict action execution strictly to `event is KeyDownEvent`.
   - Map keys to standardized actions:
     - `LogicalKeyboardKey.audioVolumeUp` -> "音量アップを受信しました" (`KEYCODE_VOLUME_UP`)
     - `LogicalKeyboardKey.audioVolumeDown` -> "音量ダウンを受信しました" (`KEYCODE_VOLUME_DOWN`)
     - `LogicalKeyboardKey.mediaPlayPause`, `mediaPlay`, `mediaPause` -> "再生・停止ボタンが押されました" (`KEYCODE_MEDIA_PLAY_PAUSE`)
     - `LogicalKeyboardKey.mediaTrackNext` -> "次の曲ボタンを受信しました" (`KEYCODE_MEDIA_NEXT`)
     - `LogicalKeyboardKey.mediaTrackPrevious` -> "前の曲ボタンを受信しました" (`KEYCODE_MEDIA_PREVIOUS`)
2. **Recommended Automated Testing Architecture for `test/`**:
   - Use `await tester.sendKeyEvent(LogicalKeyboardKey.audioVolumeUp)` followed by `await tester.pump()` for each specified key.
   - Mock or stub `FlutterTts` (or inject a TTS handler callback / interface) so that widget tests execute without requiring native TTS engines or crashing on missing platform channels.

---

## 7. Verification Method

### 7.1 Key Mapping Verification Command
Verify the existence and values of the key constants directly in Flutter SDK:
```powershell
dart -e "import 'package:flutter/services.dart'; print(LogicalKeyboardKey.audioVolumeUp.keyId); print(LogicalKeyboardKey.audioVolumeDown.keyId); print(LogicalKeyboardKey.mediaPlayPause.keyId); print(LogicalKeyboardKey.mediaTrackNext.keyId); print(LogicalKeyboardKey.mediaTrackPrevious.keyId);"
```

### 7.2 Automated Test Simulation Snippet
The following test pattern directly exercises the key simulation:
```dart
testWidgets('Verify key events update UI and trigger speech', (WidgetTester tester) async {
  await tester.pumpWidget(const MyApp());
  await tester.pumpAndSettle();

  // Test Volume Up
  await tester.sendKeyEvent(LogicalKeyboardKey.audioVolumeUp);
  await tester.pump();
  expect(find.textContaining('KEYCODE_VOLUME_UP'), findsOneWidget);

  // Test Volume Down
  await tester.sendKeyEvent(LogicalKeyboardKey.audioVolumeDown);
  await tester.pump();
  expect(find.textContaining('KEYCODE_VOLUME_DOWN'), findsOneWidget);

  // Test Play/Pause
  await tester.sendKeyEvent(LogicalKeyboardKey.mediaPlayPause);
  await tester.pump();
  expect(find.textContaining('KEYCODE_MEDIA_PLAY_PAUSE'), findsOneWidget);

  // Test Next Track
  await tester.sendKeyEvent(LogicalKeyboardKey.mediaTrackNext);
  await tester.pump();
  expect(find.textContaining('KEYCODE_MEDIA_NEXT'), findsOneWidget);

  // Test Previous Track
  await tester.sendKeyEvent(LogicalKeyboardKey.mediaTrackPrevious);
  await tester.pump();
  expect(find.textContaining('KEYCODE_MEDIA_PREVIOUS'), findsOneWidget);
});
```
Verification passes when all 5 keys simulate cleanly and trigger expected assertions under `flutter test`.
