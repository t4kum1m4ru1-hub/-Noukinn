## 2026-11-10T10:24:52Z
Read ORIGINAL_REQUEST.md at c:\Users\taqmi\02_development\original_program\noukin_app\.agents\teamwork\ORIGINAL_REQUEST.md before starting work.
Also read PROJECT.md at c:\Users\taqmi\02_development\original_program\noukin_app\.agents\teamwork\PROJECT.md.
Also read the detailed Explorer reports:
- c:\Users\taqmi\02_development\original_program\noukin_app\.agents\teamwork\explorer_m1_1\handoff.md and analysis.md
- c:\Users\taqmi\02_development\original_program\noukin_app\.agents\teamwork\explorer_m1_2\handoff.md and analysis.md
- c:\Users\taqmi\02_development\original_program\noukin_app\.agents\teamwork\explorer_m1_3\handoff.md and analysis.md

Working directory: c:\Users\taqmi\02_development\original_program\noukin_app
State folder: c:\Users\taqmi\02_development\original_program\noukin_app\.agents\teamwork\worker_m1\

MANDATORY INTEGRITY WARNING:
DO NOT CHEAT. All implementations must be genuine. DO NOT hardcode test results, create dummy/facade implementations, or circumvent the intended task. A teamwork_auditor will independently verify your work. Integrity violations WILL be detected and your work WILL be rejected.

Write Ownership:
You exclusively own and may modify or create the following files:
1. c:\Users\taqmi\02_development\original_program\noukin_app\lib\tutorial_screen.dart (New file: complete interactive tutorial module)
2. c:\Users\taqmi\02_development\original_program\noukin_app\lib\main.dart (Add import/export of tutorial_screen.dart and insert start_tutorial_button right below start_training_button)
3. c:\Users\taqmi\02_development\original_program\noukin_app\test\tutorial_screen_test.dart (New automated widget test suite)

STRICT PROHIBITION:
You MUST NOT modify c:\Users\taqmi\02_development\original_program\noukin_app\lib\training_screen.dart. It is strictly read-only per R1!

Implementation Objectives:
1. Implement lib/tutorial_screen.dart:
   - Stateful widget `TutorialScreen` with DI constructor (`ttsService`, `soundEffectService`, `duckingController`, `animateGlow = true`).
   - 6-step state machine (`TutorialStep.step1Intro` to `step6Completed`) and Step 3 sub-phase.
   - Listen to `KeyEventChannelDispatcher` and `Focus(onKeyEvent: ...)`. Handle keycodes 85/79, 87, 88, 24, 25.
   - Step 1: Title, description, "チュートリアルを開始する", "スキップして直接トレーニングへ".
   - Step 2: Dark overlay + spotlight & firefly glow on center start button. Keyevent 85 or start button tap or skip tap -> beep + start animation + dark fade out + TTS "開始、ベンチプレス、60キロ、10回、3セット" -> auto-transition to Step 3. Other keys ignored.
   - Step 3: Part 1 keyevent 87 -> beep + TTS "調整、種目名" + highlight exercise name. Part 2 keyevent 24/25 -> beep + cycle items (種目名 ⇄ 重量 ⇄ レップ数 ⇄ セット数) + item name TTS. Keyevent 85 on weight -> beep + "60キロ" -> Step 4. Keyevent 88 -> safety readout.
   - Step 4: Weight adjustment (60.0kg initial). Spotlight on weight card. Keyevent 24/25 -> immediate beep + real-time +/-2.5kg (min 0.0kg). Debounce 0.7s timer: speak new weight ("62.5キロ", "65キロ") after 0.7s inactivity. Keyevent 85 -> cancel debounce timer, beep + "調整、重量" -> Step 5. Keyevent 88 -> safety readout.
   - Step 5: Dark overlay + prompt: "［次の曲へ進む］ボタンを押して、調整を完了しましょう". Keyevent 87 -> beep + "確定" + "開始、ベンチプレス、65キロ、10回、3セット" -> Step 6. Other keys show notice.
   - Step 6: Dark overlay cleared, title "🎉 チュートリアル完了！", description. Main button "最初のトレーニングを開始する" or keyevent 85 -> Navigator.pushReplacement to `TrainingScreen`.
   - Audio exclusivity: `await ttsService?.stop()` before every speech, and wrap with ducking request/release.
   - UI: `SpotlightOverlayPainter` (70% black with `Path.combine(PathOperation.difference)`), firefly breathing glow (`AnimationController.repeat(reverse: true)` + `boxShadow`), bottom virtual media key bar, bottom-right skip button (`btn_tutorial_skip`).
2. Update lib/main.dart:
   - Add import and export for `tutorial_screen.dart`.
   - Insert `start_tutorial_button` directly below `start_training_button` (lines 674-703) using Secondary style, navigating to `TutorialScreen`.
3. Create test/tutorial_screen_test.dart:
   - Implement the complete 9-group test matrix designed in explorer_m1_3 report.
4. Run verification commands:
   - `flutter analyze`
   - `flutter test --no-test-assets`
   - Verify that all tests (both existing 14 and new tutorial tests) pass cleanly with exit code 0.

Output:
Write changes to the codebase and document implementation details and test command outputs in c:\Users\taqmi\02_development\original_program\noukin_app\.agents\teamwork\worker_m1\handoff.md. Send a completion message back to the orchestrator.
