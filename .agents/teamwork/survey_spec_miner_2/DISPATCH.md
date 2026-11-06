## 2026-11-05T23:34:11Z
You are survey_spec_miner_2 (Key Event Spec Miner).
Your working directory is: c:\Users\taqmi\02_development\original_program\button_controll_test\.agents\teamwork\survey_spec_miner_2\
Read the authoritative user request at:
c:\Users\taqmi\02_development\original_program\button_controll_test\.agents\teamwork\ORIGINAL_REQUEST.md

Your task:
1. Investigate the Flutter key event mechanisms (`flutter/services.dart`, `HardwareKeyboard`, `ServicesBinding.instance.keyboard`, `RawKeyboardListener`, `Focus` / `KeyEvent`, `LogicalKeyboardKey`, `PhysicalKeyboardKey`).
2. Specifically determine exact LogicalKeyboardKey and PhysicalKeyboardKey mappings for:
   - Volume Up (`KEYCODE_VOLUME_UP`, `audioVolumeUp`)
   - Volume Down (`KEYCODE_VOLUME_DOWN`, `audioVolumeDown`)
   - Play / Pause (`KEYCODE_MEDIA_PLAY_PAUSE`, `mediaPlayPause`, `mediaPlay`, `mediaPause`)
   - Next Track (`KEYCODE_MEDIA_NEXT`, `mediaTrackNext`)
   - Previous Track (`KEYCODE_MEDIA_PREVIOUS`, `mediaTrackPrevious`)
3. Determine cross-platform nuances on Android and iOS (e.g. how iOS or Android handles volume keys vs media keys, whether volume keys can be intercepted or if default OS volume HUD triggers, how key events propagate when app is in foreground).
4. Detail how to simulate these exact key events in automated Flutter widget tests using `simulateKeyEvent` or `tester.sendKeyEvent`.
5. Record your complete specification findings in `c:\Users\taqmi\02_development\original_program\button_controll_test\.agents\teamwork\survey_spec_miner_2\handoff.md`.
6. Send a message to your orchestrator when finished.
