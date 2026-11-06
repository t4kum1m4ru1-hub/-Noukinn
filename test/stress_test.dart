// ============================================================================
// Empirical Stress Test Harness for Button Control Application
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:button_controll_test/main.dart';

void main() {
  group('Empirical Challenge 1: Key Repeat & Key Up Stress Harness', () {
    late FakeTtsService fakeTts;

    setUp(() {
      fakeTts = FakeTtsService();
    });

    testWidgets('1.1: Sustained key hold: 100 consecutive KeyRepeatEvents', (WidgetTester tester) async {
      await tester.pumpWidget(ButtonControlApp(ttsService: fakeTts));
      await tester.pumpAndSettle();

      // Initial valid key down
      final downHandled = await tester.sendKeyDownEvent(LogicalKeyboardKey.audioVolumeUp);
      await tester.pump();
      expect(downHandled, isTrue);
      expect(fakeTts.spokenHistory.length, 1);
      expect(find.text('リアルタイムログ (1件)'), findsOneWidget);

      // Now simulate 100 rapid repeat events from holding the key
      for (int i = 0; i < 100; i++) {
        final repeatHandled = await tester.sendKeyRepeatEvent(LogicalKeyboardKey.audioVolumeUp);
        expect(repeatHandled, isFalse, reason: 'Repeat event $i must return false (not handled)');
      }
      await tester.pump();

      // Ensure absolutely no duplicate speech or logs
      expect(fakeTts.spokenHistory.length, 1, reason: 'Key repeat must never trigger additional TTS calls');
      expect(find.text('リアルタイムログ (1件)'), findsOneWidget);

      // Release key
      final upHandled = await tester.sendKeyUpEvent(LogicalKeyboardKey.audioVolumeUp);
      expect(upHandled, isFalse);
      await tester.pumpAndSettle();

      expect(fakeTts.spokenHistory.length, 1);
      expect(find.text('リアルタイムログ (1件)'), findsOneWidget);
    });

    testWidgets('1.2: Standalone KeyUp events across all target keys without prior KeyDown', (WidgetTester tester) async {
      await tester.pumpWidget(ButtonControlApp(ttsService: fakeTts));
      await tester.pumpAndSettle();

      final targetKeys = [
        LogicalKeyboardKey.audioVolumeUp,
        LogicalKeyboardKey.audioVolumeDown,
        LogicalKeyboardKey.mediaPlayPause,
        LogicalKeyboardKey.mediaPlay,
        LogicalKeyboardKey.mediaPause,
        LogicalKeyboardKey.select,
        LogicalKeyboardKey.mediaTrackNext,
        LogicalKeyboardKey.mediaTrackPrevious,
      ];

      for (final key in targetKeys) {
        final upHandled = await tester.sendKeyUpEvent(key);
        expect(upHandled, isFalse, reason: 'KeyUp for ${key.debugName} must not be handled');
      }
      await tester.pumpAndSettle();

      // UI state must remain untouched
      expect(find.text('ボタンを押してください'), findsOneWidget);
      expect(find.text('ログはありません'), findsOneWidget);
      expect(fakeTts.spokenHistory, isEmpty);
    });

    testWidgets('1.3: Noisy input stream with interleaved KeyUp, KeyRepeat, and unhandled keys', (WidgetTester tester) async {
      await tester.pumpWidget(ButtonControlApp(ttsService: fakeTts));
      await tester.pumpAndSettle();

      // Sequence with noise
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyB);
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.keyB);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyB);

      // Legitimate key down 1
      final vUp = await tester.sendKeyDownEvent(LogicalKeyboardKey.audioVolumeUp);
      expect(vUp, isTrue);

      // Noise during key press
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.audioVolumeUp);
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.audioVolumeUp);

      // Release key
      await tester.sendKeyUpEvent(LogicalKeyboardKey.audioVolumeUp);

      // Legitimate key down 2
      final nextTrack = await tester.sendKeyDownEvent(LogicalKeyboardKey.mediaTrackNext);
      expect(nextTrack, isTrue);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.mediaTrackNext);

      await tester.pumpAndSettle();

      expect(fakeTts.spokenHistory, [
        '音量アップを受信しました',
        '次の曲ボタンを受信しました',
      ]);
      expect(find.text('リアルタイムログ (2件)'), findsOneWidget);
    });
  });

  group('Empirical Challenge 2: Keyboard Spam & Non-Target Keys', () {
    late FakeTtsService fakeTts;

    setUp(() {
      fakeTts = FakeTtsService();
    });

    testWidgets('2.1: Full QWERTY and functional keyboard spam', (WidgetTester tester) async {
      await tester.pumpWidget(ButtonControlApp(ttsService: fakeTts));
      await tester.pumpAndSettle();

      final nonNavigationalKeys = [
        LogicalKeyboardKey.keyA,
        LogicalKeyboardKey.keyZ,
        LogicalKeyboardKey.digit0,
        LogicalKeyboardKey.digit9,
        LogicalKeyboardKey.enter,
        LogicalKeyboardKey.space,
        LogicalKeyboardKey.escape,
        LogicalKeyboardKey.tab,
        LogicalKeyboardKey.backspace,
        LogicalKeyboardKey.delete,
        LogicalKeyboardKey.shiftLeft,
        LogicalKeyboardKey.controlLeft,
        LogicalKeyboardKey.altLeft,
        LogicalKeyboardKey.metaLeft,
        LogicalKeyboardKey.f1,
        LogicalKeyboardKey.f12,
        LogicalKeyboardKey.audioVolumeMute,
      ];

      for (final key in nonNavigationalKeys) {
        final handled = await tester.sendKeyEvent(key);
        expect(handled, isFalse, reason: 'Key ${key.debugName} must not be handled by app');
        expect(ButtonAction.fromLogicalKey(key), isNull);
      }

      // Navigational keys (arrow keys) may be handled by Flutter's Scrollable/Focus tree,
      // but must strictly NOT trigger our TTS or log action
      final navigationalKeys = [
        LogicalKeyboardKey.arrowUp,
        LogicalKeyboardKey.arrowDown,
        LogicalKeyboardKey.arrowLeft,
        LogicalKeyboardKey.arrowRight,
      ];

      for (final key in navigationalKeys) {
        expect(ButtonAction.fromLogicalKey(key), isNull);
        await tester.sendKeyEvent(key);
      }

      await tester.pumpAndSettle();

      // In all cases, app state must remain completely pristine
      expect(fakeTts.spokenHistory, isEmpty);
      expect(find.text('リアルタイムログ (0件)'), findsOneWidget);
      expect(find.text('ボタンを押してください'), findsOneWidget);
    });
  });

  group('Empirical Challenge 3: High-Frequency Burst & Log Integrity Stress', () {
    late FakeTtsService fakeTts;

    setUp(() {
      fakeTts = FakeTtsService();
    });

    testWidgets('3.1: 100 rapid consecutive key events with rapid UI pumps', (WidgetTester tester) async {
      await tester.pumpWidget(ButtonControlApp(ttsService: fakeTts));
      await tester.pumpAndSettle();

      final keys = [
        LogicalKeyboardKey.audioVolumeUp,
        LogicalKeyboardKey.audioVolumeDown,
        LogicalKeyboardKey.mediaPlayPause,
        LogicalKeyboardKey.mediaTrackNext,
        LogicalKeyboardKey.mediaTrackPrevious,
      ];

      for (int i = 0; i < 100; i++) {
        final key = keys[i % keys.length];
        final handled = await tester.sendKeyEvent(key);
        expect(handled, isTrue);
        // Micro pump between events to simulate high event velocity with animation overlap
        await tester.pump(const Duration(milliseconds: 5));
      }

      await tester.pumpAndSettle();

      expect(fakeTts.spokenHistory.length, 100);
      expect(find.text('リアルタイムログ (100件)'), findsOneWidget);

      // Verify log entries exist in widget tree
      expect(find.byKey(const Key('log_list_view')), findsOneWidget);
    });

    testWidgets('3.2: Concurrent clear action during key arrival does not crash', (WidgetTester tester) async {
      await tester.pumpWidget(ButtonControlApp(ttsService: fakeTts));
      await tester.pumpAndSettle();

      for (int i = 0; i < 20; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.audioVolumeUp);
        await tester.pump(const Duration(milliseconds: 10));

        if (i == 10) {
          // Clear while events are arriving
          final clearBtn = find.byKey(const Key('clear_logs_button'));
          await tester.tap(clearBtn);
          await tester.pump(const Duration(milliseconds: 10));
        }
      }

      await tester.pumpAndSettle();

      // First 11 were cleared, remaining 9 should be present
      expect(fakeTts.spokenHistory.length, 20);
      expect(find.text('リアルタイムログ (9件)'), findsOneWidget);
    });
  });

  group('Empirical Challenge 4: Physical Key Fallback Verification', () {
    late FakeTtsService fakeTts;

    setUp(() {
      fakeTts = FakeTtsService();
    });

    testWidgets('4.1: Fallback when logicalKey is unidentified but physicalKey matches', (WidgetTester tester) async {
      await tester.pumpWidget(ButtonControlApp(ttsService: fakeTts));
      await tester.pumpAndSettle();

      // Simulate an exotic OEM keyboard event where logicalKey is unidentified/none
      // but physicalKey is audioVolumeUp
      // Dispatch KeyDownEvent with unidentified logical key and physical audioVolumeUp
      final event1 = KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.audioVolumeUp,
        logicalKey: LogicalKeyboardKey.unidentified,
        timeStamp: Duration.zero,
      );
      final handled1 = HardwareKeyboard.instance.handleKeyEvent(event1);
      expect(handled1, isTrue);
      await tester.pumpAndSettle();

      expect(fakeTts.spokenHistory, ['音量アップを受信しました']);
      expect(find.text('KEYCODE_VOLUME_UP'), findsWidgets);

      // Alternatively test ButtonAction.fromKeyEvent directly to verify domain fallback
      final actionPhysicalVolumeUp = ButtonAction.fromKeyEvent(event1);
      expect(actionPhysicalVolumeUp, ButtonAction.volumeUp);

      final eventMediaSelect = KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.mediaSelect,
        logicalKey: LogicalKeyboardKey.unidentified,
        timeStamp: Duration.zero,
      );
      expect(ButtonAction.fromKeyEvent(eventMediaSelect), ButtonAction.mediaPlayPause);

      final eventNext = KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.mediaTrackNext,
        logicalKey: LogicalKeyboardKey.unidentified,
        timeStamp: Duration.zero,
      );
      expect(ButtonAction.fromKeyEvent(eventNext), ButtonAction.mediaNext);

      final eventPrev = KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.mediaTrackPrevious,
        logicalKey: LogicalKeyboardKey.unidentified,
        timeStamp: Duration.zero,
      );
      expect(ButtonAction.fromKeyEvent(eventPrev), ButtonAction.mediaPrevious);
    });
  });

  group('Empirical Challenge 5: Lifecycle & Leak Stress', () {
    testWidgets('5.1: 10 rapid mount / unmount cycles do not leak handlers or throw', (WidgetTester tester) async {
      for (int i = 0; i < 10; i++) {
        final fakeTts = FakeTtsService();
        await tester.pumpWidget(ButtonControlApp(ttsService: fakeTts));
        await tester.pump();

        final handled = await tester.sendKeyEvent(LogicalKeyboardKey.audioVolumeUp);
        expect(handled, isTrue);
        expect(fakeTts.spokenHistory.length, 1);

        // Unmount
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        expect(fakeTts.stopCallCount, greaterThanOrEqualTo(1));

        // Event dispatched while unmounted must NOT be handled
        final postHandled = await tester.sendKeyEvent(LogicalKeyboardKey.audioVolumeUp);
        expect(postHandled, isFalse);
      }
    });
  });
}
