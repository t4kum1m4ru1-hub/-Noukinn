## 2026-11-10T11:06:15Z
Read ORIGINAL_REQUEST.md at c:\Users\taqmi\02_development\original_program\noukin_app\.agents\teamwork\ORIGINAL_REQUEST.md before starting work.
Also read PROJECT.md at c:\Users\taqmi\02_development\original_program\noukin_app\.agents\teamwork\PROJECT.md.

Read the detailed Iteration 2 Explorer reports:
- c:\Users\taqmi\02_development\original_program\noukin_app\.agents\teamwork\explorer_m1_iter2_1\handoff.md and analysis.md
- c:\Users\taqmi\02_development\original_program\noukin_app\.agents\teamwork\explorer_m1_iter2_2\handoff.md and analysis.md
- c:\Users\taqmi\02_development\original_program\noukin_app\.agents\teamwork\explorer_m1_iter2_3\handoff.md and analysis.md

Working directory: c:\Users\taqmi\02_development\original_program\noukin_app
State folder: c:\Users\taqmi\02_development\original_program\noukin_app\.agents\teamwork\worker_m1_iter2\

MANDATORY INTEGRITY WARNING:
DO NOT CHEAT. All implementations must be genuine. DO NOT hardcode test results, create dummy/facade implementations, or circumvent the intended task. A teamwork_auditor will independently verify your work. Integrity violations WILL be detected and your work WILL be rejected.

Write Ownership:
You exclusively own and may modify:
- c:\Users\taqmi\02_development\original_program\noukin_app\lib\tutorial_screen.dart

STRICT PROHIBITION:
You MUST NOT modify lib/training_screen.dart. It is strictly read-only per R1!

Remediation Objectives in lib/tutorial_screen.dart:
1. Re-entrancy & Concurrency Guard:
   - Add state fields: `bool _isStepTransitioning = false;` and `int _transitionGeneration = 0;`
   - In transition handlers `_proceedFromStep2()`, `_handleStep3Action()` (87 and 85), `_handleStep4Action()` (85), and `_handleStep5Action()` (87):
     Guard with `if (_isStepTransitioning) return; _isStepTransitioning = true; final gen = ++_transitionGeneration;`
     In `finally` block: `if (mounted && gen == _transitionGeneration) _isStepTransitioning = false;`
2. State Reversion Prevention:
   - After every `await _playBeep()` and `await _speak(...)`, check `if (!mounted || _currentStep != expectedStep || gen != _transitionGeneration) return;` before calling `setState(() { _currentStep = target; })`.
   - In `_onSkipStepPressed()`:
     Reset `_isStepTransitioning = false; _transitionGeneration++;`
     Cancel debounce, stop TTS, and call `_duckingController.releaseDucking();`
3. Audio Ducking Leak Prevention:
   - Ensure `_duckingController.releaseDucking();` is called when skipping during Step 4 debounce (`_onSkipStepPressed()`) and in `_navigateToTrainingScreen()`.
4. Lifecycle Post-Dispose Speech Prevention:
   - In AppBar back button: `_cancelDebounce(); widget.ttsService?.stop(); _duckingController.releaseDucking(); Navigator.of(context).pop();`
   - Wrap Scaffold with `PopScope(canPop: true, onPopInvokedWithResult: (didPop, _) { if (didPop) { _cancelDebounce(); widget.ttsService?.stop(); _duckingController.releaseDucking(); } })`
   - In `_debounceTimer` callback and `_speak()`: check `if (!mounted) return;`

Verification Requirements:
Run the test suites and verify:
1. `flutter analyze` -> 0 issues found!
2. `flutter test --no-test-assets test/stress_tutorial_keys_test.dart` -> 19/19 passed!
3. `flutter test --no-test-assets test/stress_tutorial_audio_test.dart` -> 9/9 passed!
4. `flutter test --no-test-assets test/tutorial_screen_test.dart` -> 11/11 passed!
5. `flutter test --no-test-assets` -> all 53 tests in workspace passed!

Output:
Write changes to lib/tutorial_screen.dart and document test outputs and implementation details in c:\Users\taqmi\02_development\original_program\noukin_app\.agents\teamwork\worker_m1_iter2\handoff.md. Send a completion message back to the orchestrator.
