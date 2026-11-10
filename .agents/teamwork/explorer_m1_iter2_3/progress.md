# Progress — explorer_m1_iter2_3

- Last visited: 2026-11-10T11:02:00Z
- Status: Investigation and strategy formulation complete. Preparing analysis.md and handoff.md.

## Findings Summary
1. **Audio Ducking Leak in Step 4 Skip (Test 3)**:
   - Root cause: In Step 4 volume adjustments, `_playBeep()` calls `_duckingController.requestDucking()`. When skipped before 0.7s debounce finishes, `_onSkipStepPressed()` cancels debounce and stops TTS, but never calls `_duckingController.releaseDucking()`.
   - Fix: Explicit `_duckingController.releaseDucking()` call in `_onSkipStepPressed()`.
2. **Late Speech After Screen Pop / Lifecycle (Test 6)**:
   - Root cause: AppBar back button (`Icons.arrow_back`) directly invokes `Navigator.of(context).pop()` without calling `_cancelDebounce()`, `stop()`, or `releaseDucking()`. `_framePumpTimer` keeps pumping frames during transition, allowing the 0.7s timer to expire and speak `62.5キロ`.
   - Fix: Call `_cancelDebounce()`, `widget.ttsService?.stop()`, and `_duckingController.releaseDucking()` in AppBar `leading` `onPressed`, wrap screen in `PopScope(canPop: true, onPopInvokedWithResult: ...)`, and add `!mounted` guards in debounce callback and `_speak()`.
3. **Comprehensive Edge Cases (Tests 1, 2, 8, 9)**:
   - Add reentrancy guard (`_isTransitioning`) and state-matching guard (`if (!mounted || _currentStep != expectedStep) return;`) for Step 2, Step 3, and Step 5 asynchronous completions.
