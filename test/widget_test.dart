// ============================================================================
// Automated Verification Test Suite for Button Control Application
// ============================================================================
//
// Fulfills Requirement R5:
// - Simulates hardware key press events: Volume Up, Volume Down, Play/Pause,
//   Next Track, Previous Track.
// - Verifies key event interception, center display readout, timestamped log,
//   and flutter_tts invocation via FakeTtsService.
// - Multi-tier structure:
//     Tier 1: Feature coverage for each target key
//     Tier 2: Boundary & Corner cases (discrete keys, unhandled keys, deduplication)
//     Tier 3: Sequential & combinatorial key events
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:button_controll_test/main.dart';

void main() {
  group('Unit Tests: Domain Models & Helpers', () {
    test('ButtonAction.fromLogicalKey maps all target logical keys correctly', () {
      expect(ButtonAction.fromLogicalKey(LogicalKeyboardKey.audioVolumeUp), ButtonAction.volumeUp);
      expect(ButtonAction.fromLogicalKey(LogicalKeyboardKey.audioVolumeDown), ButtonAction.volumeDown);
      expect(ButtonAction.fromLogicalKey(LogicalKeyboardKey.mediaPlayPause), ButtonAction.mediaPlayPause);
      expect(ButtonAction.fromLogicalKey(LogicalKeyboardKey.mediaPlay), ButtonAction.mediaPlayPause);
      expect(ButtonAction.fromLogicalKey(LogicalKeyboardKey.mediaPause), ButtonAction.mediaPlayPause);
      expect(ButtonAction.fromLogicalKey(LogicalKeyboardKey.mediaTrackNext), ButtonAction.mediaNext);
      expect(ButtonAction.fromLogicalKey(LogicalKeyboardKey.mediaTrackPrevious), ButtonAction.mediaPrevious);

      // Unhandled keys must return null
      expect(ButtonAction.fromLogicalKey(LogicalKeyboardKey.keyA), isNull);
      expect(ButtonAction.fromLogicalKey(LogicalKeyboardKey.enter), isNull);
      expect(ButtonAction.fromLogicalKey(LogicalKeyboardKey.escape), isNull);
      expect(ButtonAction.fromLogicalKey(LogicalKeyboardKey.audioVolumeMute), isNull);
    });

    test('KeyEventLog formattedTime produces zero-padded HH:mm:ss.SSS', () {
      final log = KeyEventLog(
        timestamp: DateTime(2026, 11, 6, 9, 5, 3, 42),
        action: ButtonAction.volumeUp,
      );
      expect(log.formattedTime, '09:05:03.042');
    });

    test('FakeTtsService records history and clears correctly', () async {
      final fakeTts = FakeTtsService();
      expect(fakeTts.isInitialized, isFalse);
      expect(fakeTts.spokenHistory, isEmpty);
      expect(fakeTts.lastSpoken, isNull);

      await fakeTts.speak('テスト1');
      expect(fakeTts.isInitialized, isTrue);
      expect(fakeTts.spokenHistory, ['テスト1']);
      expect(fakeTts.lastSpoken, 'テスト1');

      await fakeTts.speak('テスト2');
      expect(fakeTts.spokenHistory, ['テスト1', 'テスト2']);
      expect(fakeTts.lastSpoken, 'テスト2');

      fakeTts.clear();
      expect(fakeTts.spokenHistory, isEmpty);
      expect(fakeTts.lastSpoken, isNull);
    });
  });

  group('Tier 1: Feature Coverage (Core Key Actions)', () {
    late FakeTtsService fakeTts;

    setUp(() {
      fakeTts = FakeTtsService();
    });

    testWidgets('1.0: Initial State displays waiting prompt, empty log, and disabled clear button', (WidgetTester tester) async {
      await tester.pumpWidget(ButtonControlApp(ttsService: fakeTts));
      await tester.pumpAndSettle();

      // Center idle prompt
      expect(find.text('ボタンを押してください'), findsOneWidget);
      expect(find.text('Volume Up/Down または イヤホンボタン'), findsOneWidget);

      // Empty log indicator
      expect(find.text('ログはありません'), findsOneWidget);
      expect(find.text('リアルタイムログ (0件)'), findsOneWidget);

      // Clear button disabled
      final clearButton = tester.widget<IconButton>(find.byKey(const Key('clear_logs_button')));
      expect(clearButton.onPressed, isNull);

      // TTS initialized without utterances
      expect(fakeTts.isInitialized, isTrue);
      expect(fakeTts.spokenHistory, isEmpty);
    });

    testWidgets('1.1: Volume Up key event updates center UI, adds log entry, and calls TTS', (WidgetTester tester) async {
      await tester.pumpWidget(ButtonControlApp(ttsService: fakeTts));
      await tester.pumpAndSettle();

      final handled = await tester.sendKeyEvent(LogicalKeyboardKey.audioVolumeUp);
      await tester.pumpAndSettle();

      expect(handled, isTrue);
      expect(find.text('KEYCODE_VOLUME_UP'), findsWidgets);
      expect(find.text('音量アップを受信しました'), findsWidgets);
      expect(find.text('リアルタイムログ (1件)'), findsOneWidget);
      expect(fakeTts.spokenHistory, ['音量アップを受信しました']);
      expect(fakeTts.lastSpoken, '音量アップを受信しました');
    });

    testWidgets('1.2: Volume Down key event updates center UI, adds log entry, and calls TTS', (WidgetTester tester) async {
      await tester.pumpWidget(ButtonControlApp(ttsService: fakeTts));
      await tester.pumpAndSettle();

      final handled = await tester.sendKeyEvent(LogicalKeyboardKey.audioVolumeDown);
      await tester.pumpAndSettle();

      expect(handled, isTrue);
      expect(find.text('KEYCODE_VOLUME_DOWN'), findsWidgets);
      expect(find.text('音量ダウンを受信しました'), findsWidgets);
      expect(find.text('リアルタイムログ (1件)'), findsOneWidget);
      expect(fakeTts.spokenHistory, ['音量ダウンを受信しました']);
      expect(fakeTts.lastSpoken, '音量ダウンを受信しました');
    });

    testWidgets('1.3: Media Play/Pause toggle key event updates center UI, adds log entry, and calls TTS', (WidgetTester tester) async {
      await tester.pumpWidget(ButtonControlApp(ttsService: fakeTts));
      await tester.pumpAndSettle();

      final handled = await tester.sendKeyEvent(LogicalKeyboardKey.mediaPlayPause);
      await tester.pumpAndSettle();

      expect(handled, isTrue);
      expect(find.text('KEYCODE_MEDIA_PLAY_PAUSE'), findsWidgets);
      expect(find.text('再生・停止ボタンが押されました'), findsWidgets);
      expect(find.text('リアルタイムログ (1件)'), findsOneWidget);
      expect(fakeTts.spokenHistory, ['再生・停止ボタンが押されました']);
      expect(fakeTts.lastSpoken, '再生・停止ボタンが押されました');
    });

    testWidgets('1.4: Media Next Track key event updates center UI, adds log entry, and calls TTS', (WidgetTester tester) async {
      await tester.pumpWidget(ButtonControlApp(ttsService: fakeTts));
      await tester.pumpAndSettle();

      final handled = await tester.sendKeyEvent(LogicalKeyboardKey.mediaTrackNext);
      await tester.pumpAndSettle();

      expect(handled, isTrue);
      expect(find.text('KEYCODE_MEDIA_NEXT'), findsWidgets);
      expect(find.text('次の曲ボタンを受信しました'), findsWidgets);
      expect(find.text('リアルタイムログ (1件)'), findsOneWidget);
      expect(fakeTts.spokenHistory, ['次の曲ボタンを受信しました']);
      expect(fakeTts.lastSpoken, '次の曲ボタンを受信しました');
    });

    testWidgets('1.5: Media Previous Track key event updates center UI, adds log entry, and calls TTS', (WidgetTester tester) async {
      await tester.pumpWidget(ButtonControlApp(ttsService: fakeTts));
      await tester.pumpAndSettle();

      final handled = await tester.sendKeyEvent(LogicalKeyboardKey.mediaTrackPrevious);
      await tester.pumpAndSettle();

      expect(handled, isTrue);
      expect(find.text('KEYCODE_MEDIA_PREVIOUS'), findsWidgets);
      expect(find.text('前の曲ボタンを受信しました'), findsWidgets);
      expect(find.text('リアルタイムログ (1件)'), findsOneWidget);
      expect(fakeTts.spokenHistory, ['前の曲ボタンを受信しました']);
      expect(fakeTts.lastSpoken, '前の曲ボタンを受信しました');
    });
  });

  group('Tier 2: Boundary & Corner Cases', () {
    late FakeTtsService fakeTts;

    setUp(() {
      fakeTts = FakeTtsService();
    });

    testWidgets('2.1: Discrete KEYCODE_MEDIA_PLAY maps to mediaPlayPause action', (WidgetTester tester) async {
      await tester.pumpWidget(ButtonControlApp(ttsService: fakeTts));
      await tester.pumpAndSettle();

      final handled = await tester.sendKeyEvent(LogicalKeyboardKey.mediaPlay);
      await tester.pumpAndSettle();

      expect(handled, isTrue);
      expect(find.text('KEYCODE_MEDIA_PLAY_PAUSE'), findsWidgets);
      expect(fakeTts.lastSpoken, '再生・停止ボタンが押されました');
      expect(find.text('リアルタイムログ (1件)'), findsOneWidget);
    });

    testWidgets('2.2: Discrete KEYCODE_MEDIA_PAUSE maps to mediaPlayPause action', (WidgetTester tester) async {
      await tester.pumpWidget(ButtonControlApp(ttsService: fakeTts));
      await tester.pumpAndSettle();

      final handled = await tester.sendKeyEvent(LogicalKeyboardKey.mediaPause);
      await tester.pumpAndSettle();

      expect(handled, isTrue);
      expect(find.text('KEYCODE_MEDIA_PLAY_PAUSE'), findsWidgets);
      expect(fakeTts.lastSpoken, '再生・停止ボタンが押されました');
      expect(find.text('リアルタイムログ (1件)'), findsOneWidget);
    });

    testWidgets('2.3: Unhandled keys (KeyA, Escape, Enter, Space) pass through without triggering UI or TTS', (WidgetTester tester) async {
      await tester.pumpWidget(ButtonControlApp(ttsService: fakeTts));
      await tester.pumpAndSettle();

      final unhandledKeys = [
        LogicalKeyboardKey.keyA,
        LogicalKeyboardKey.escape,
        LogicalKeyboardKey.enter,
        LogicalKeyboardKey.space,
      ];

      for (final key in unhandledKeys) {
        final handled = await tester.sendKeyEvent(key);
        expect(handled, isFalse, reason: 'Key ${key.debugName} should not be handled');
      }
      await tester.pumpAndSettle();

      // UI remains in initial state
      expect(find.text('ボタンを押してください'), findsOneWidget);
      expect(find.text('ログはありません'), findsOneWidget);
      expect(find.text('リアルタイムログ (0件)'), findsOneWidget);
      expect(fakeTts.spokenHistory, isEmpty);
    });

    testWidgets('2.4: Non-KeyDown events (KeyUp, KeyRepeat) are filtered to prevent duplicate triggers', (WidgetTester tester) async {
      await tester.pumpWidget(ButtonControlApp(ttsService: fakeTts));
      await tester.pumpAndSettle();

      // 1. Send single KeyDown event
      final downHandled = await tester.sendKeyDownEvent(LogicalKeyboardKey.audioVolumeUp);
      await tester.pump();
      expect(downHandled, isTrue);
      expect(fakeTts.spokenHistory.length, 1);

      // 2. Send KeyRepeat event (holding key)
      final repeatHandled = await tester.sendKeyRepeatEvent(LogicalKeyboardKey.audioVolumeUp);
      await tester.pump();
      expect(repeatHandled, isFalse);
      expect(fakeTts.spokenHistory.length, 1); // No duplicate trigger

      // 3. Send KeyUp event (releasing key)
      final upHandled = await tester.sendKeyUpEvent(LogicalKeyboardKey.audioVolumeUp);
      await tester.pumpAndSettle();
      expect(upHandled, isFalse);
      expect(fakeTts.spokenHistory.length, 1); // Still exactly 1
      expect(find.text('リアルタイムログ (1件)'), findsOneWidget);

      // 4. Standalone KeyUp event without prior KeyDown
      final standaloneUpHandled = await tester.sendKeyUpEvent(LogicalKeyboardKey.audioVolumeDown);
      await tester.pumpAndSettle();
      expect(standaloneUpHandled, isFalse);
      expect(fakeTts.spokenHistory.length, 1);
      expect(find.text('リアルタイムログ (1件)'), findsOneWidget);
    });

    testWidgets('2.5: Clear log button empties log list while retaining center display', (WidgetTester tester) async {
      await tester.pumpWidget(ButtonControlApp(ttsService: fakeTts));
      await tester.pumpAndSettle();

      // Generate two key events
      await tester.sendKeyEvent(LogicalKeyboardKey.audioVolumeUp);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.mediaTrackNext);
      await tester.pumpAndSettle();

      expect(find.text('リアルタイムログ (2件)'), findsOneWidget);
      expect(find.text('KEYCODE_MEDIA_NEXT'), findsWidgets);

      // Tap AppBar clear action
      final clearButtonFinder = find.byKey(const Key('clear_logs_button'));
      expect(clearButtonFinder, findsOneWidget);
      await tester.tap(clearButtonFinder);
      await tester.pumpAndSettle();

      // Logs are cleared
      expect(find.text('リアルタイムログ (0件)'), findsOneWidget);
      expect(find.text('ログはありません'), findsOneWidget);

      // Center display still retains latest key readout
      expect(find.text('KEYCODE_MEDIA_NEXT'), findsOneWidget);

      // Clear button is disabled again
      final clearButton = tester.widget<IconButton>(clearButtonFinder);
      expect(clearButton.onPressed, isNull);
    });

    testWidgets('2.6: State disposal cleans up key event handler and stops TTS', (WidgetTester tester) async {
      await tester.pumpWidget(ButtonControlApp(ttsService: fakeTts));
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.audioVolumeUp);
      await tester.pumpAndSettle();
      expect(fakeTts.spokenHistory.length, 1);

      // Dispose widget tree by replacing with empty Container
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();

      // Verify TTS stop was called on disposal
      expect(fakeTts.stopCallCount, greaterThanOrEqualTo(1));

      // Key event dispatched after disposal must NOT be handled
      final handledAfterDispose = await tester.sendKeyEvent(LogicalKeyboardKey.audioVolumeUp);
      expect(handledAfterDispose, isFalse);
      expect(fakeTts.spokenHistory.length, 1);
    });
  });

  group('Tier 3: Sequential & Combinatorial Key Events', () {
    late FakeTtsService fakeTts;

    setUp(() {
      fakeTts = FakeTtsService();
    });

    testWidgets('3.1: Alternating volume and media buttons maintain chronological log order and speech sequence', (WidgetTester tester) async {
      await tester.pumpWidget(ButtonControlApp(ttsService: fakeTts));
      await tester.pumpAndSettle();

      final sequence = [
        LogicalKeyboardKey.audioVolumeUp,
        LogicalKeyboardKey.mediaPlayPause,
        LogicalKeyboardKey.audioVolumeDown,
        LogicalKeyboardKey.mediaTrackNext,
        LogicalKeyboardKey.audioVolumeUp,
        LogicalKeyboardKey.mediaTrackPrevious,
      ];

      for (final key in sequence) {
        final handled = await tester.sendKeyEvent(key);
        expect(handled, isTrue);
        await tester.pumpAndSettle();
      }

      // Verify exact chronological speech sequence
      expect(fakeTts.spokenHistory, [
        '音量アップを受信しました',
        '再生・停止ボタンが押されました',
        '音量ダウンを受信しました',
        '次の曲ボタンを受信しました',
        '音量アップを受信しました',
        '前の曲ボタンを受信しました',
      ]);

      // Verify log count and final center readout
      expect(find.text('リアルタイムログ (6件)'), findsOneWidget);
      expect(find.text('KEYCODE_MEDIA_PREVIOUS'), findsWidgets);
    });

    testWidgets('3.2: Rapid consecutive presses of identical key produce multiple distinct log entries and speech calls', (WidgetTester tester) async {
      await tester.pumpWidget(ButtonControlApp(ttsService: fakeTts));
      await tester.pumpAndSettle();

      for (int i = 0; i < 5; i++) {
        final handled = await tester.sendKeyEvent(LogicalKeyboardKey.audioVolumeUp);
        expect(handled, isTrue);
        await tester.pumpAndSettle();
      }

      expect(fakeTts.spokenHistory.length, 5);
      expect(fakeTts.spokenHistory.every((text) => text == '音量アップを受信しました'), isTrue);
      expect(find.text('リアルタイムログ (5件)'), findsOneWidget);
    });

    testWidgets('3.3: Rapid Play/Pause toggling across toggle and discrete events', (WidgetTester tester) async {
      await tester.pumpWidget(ButtonControlApp(ttsService: fakeTts));
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.mediaPlayPause);
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.mediaPlay);
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.mediaPause);
      await tester.pumpAndSettle();

      expect(fakeTts.spokenHistory, [
        '再生・停止ボタンが押されました',
        '再生・停止ボタンが押されました',
        '再生・停止ボタンが押されました',
      ]);
      expect(find.text('リアルタイムログ (3件)'), findsOneWidget);
      expect(find.text('KEYCODE_MEDIA_PLAY_PAUSE'), findsWidgets);
    });

    testWidgets('3.4: Complete all 5 target keys sequential full traversal', (WidgetTester tester) async {
      await tester.pumpWidget(ButtonControlApp(ttsService: fakeTts));
      await tester.pumpAndSettle();

      final allKeys = [
        (LogicalKeyboardKey.audioVolumeUp, 'KEYCODE_VOLUME_UP', '音量アップを受信しました'),
        (LogicalKeyboardKey.audioVolumeDown, 'KEYCODE_VOLUME_DOWN', '音量ダウンを受信しました'),
        (LogicalKeyboardKey.mediaPlayPause, 'KEYCODE_MEDIA_PLAY_PAUSE', '再生・停止ボタンが押されました'),
        (LogicalKeyboardKey.mediaTrackNext, 'KEYCODE_MEDIA_NEXT', '次の曲ボタンを受信しました'),
        (LogicalKeyboardKey.mediaTrackPrevious, 'KEYCODE_MEDIA_PREVIOUS', '前の曲ボタンを受信しました'),
      ];

      for (final (key, expectedName, expectedSpeech) in allKeys) {
        final handled = await tester.sendKeyEvent(key);
        expect(handled, isTrue);
        await tester.pumpAndSettle();

        expect(fakeTts.lastSpoken, expectedSpeech);
        expect(find.text(expectedName), findsWidgets);
      }

      expect(fakeTts.spokenHistory.length, 5);
      expect(find.text('リアルタイムログ (5件)'), findsOneWidget);
    });
  });
}
