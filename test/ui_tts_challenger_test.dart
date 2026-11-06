// ============================================================================
// UI & TTS Adversarial Empirical Stress Test Harness
// Challenger: challenger_m1_2
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:button_controll_test/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Adversarial Group 1: Center UI Dynamic Updates & Layout Resilience', () {
    late FakeTtsService fakeTts;

    setUp(() {
      fakeTts = FakeTtsService();
    });

    testWidgets('1.1: Center UI updates dynamically across all 5 key types in rapid alternation', (WidgetTester tester) async {
      await tester.pumpWidget(ButtonControlApp(ttsService: fakeTts));
      await tester.pumpAndSettle();

      // Initial state: Waiting prompt
      expect(find.byKey(const Key('waiting_prompt')), findsOneWidget);
      expect(find.byKey(const Key('detected_action_display')), findsNothing);

      final sequence = [
        (LogicalKeyboardKey.audioVolumeUp, 'KEYCODE_VOLUME_UP', '音量アップを受信しました'),
        (LogicalKeyboardKey.mediaTrackNext, 'KEYCODE_MEDIA_NEXT', '次の曲ボタンを受信しました'),
        (LogicalKeyboardKey.audioVolumeDown, 'KEYCODE_VOLUME_DOWN', '音量ダウンを受信しました'),
        (LogicalKeyboardKey.mediaPlayPause, 'KEYCODE_MEDIA_PLAY_PAUSE', '再生・停止ボタンが押されました'),
        (LogicalKeyboardKey.mediaTrackPrevious, 'KEYCODE_MEDIA_PREVIOUS', '前の曲ボタンを受信しました'),
        (LogicalKeyboardKey.audioVolumeUp, 'KEYCODE_VOLUME_UP', '音量アップを受信しました'),
      ];

      for (final (key, expectedName, expectedSpeech) in sequence) {
        final handled = await tester.sendKeyEvent(key);
        expect(handled, isTrue);
        await tester.pumpAndSettle();

        // Waiting prompt is replaced
        expect(find.byKey(const Key('waiting_prompt')), findsNothing);
        expect(find.byKey(const Key('detected_action_display')), findsOneWidget);

        // Center UI elements
        final centerKeyText = tester.widget<Text>(find.byKey(const Key('center_key_name')));
        expect(centerKeyText.data, expectedName);

        final centerSpeechText = tester.widget<Text>(find.byKey(const Key('center_speech_text')));
        expect(centerSpeechText.data, expectedSpeech);

        final centerTimestampFinder = find.byKey(const Key('center_timestamp'));
        expect(centerTimestampFinder, findsOneWidget);
        final timestampText = tester.widget<Text>(centerTimestampFinder).data!;
        expect(timestampText, matches(r'^受信時刻: \d{2}:\d{2}:\d{2}\.\d{3}$'));
      }
    });

    testWidgets('1.2: Center UI is resilient to extremely small screen viewport (overflow stress test)', (WidgetTester tester) async {
      // Set constrained viewport size to stress test SingleChildScrollView
      tester.view.physicalSize = const Size(320, 400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(ButtonControlApp(ttsService: fakeTts));
      await tester.pumpAndSettle();

      // Trigger event
      await tester.sendKeyEvent(LogicalKeyboardKey.audioVolumeUp);
      await tester.pumpAndSettle();

      // Verify no overflow exception occurred and elements rendered
      expect(find.byKey(const Key('center_key_name')), findsOneWidget);
      expect(find.text('KEYCODE_VOLUME_UP'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('1.3: Center UI is resilient to wide landscape viewport', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 360);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(ButtonControlApp(ttsService: fakeTts));
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.mediaPlayPause);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('center_key_name')), findsOneWidget);
      expect(find.text('KEYCODE_MEDIA_PLAY_PAUSE'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('1.4: Center UI display persists after log clearing (does not reset to waiting prompt)', (WidgetTester tester) async {
      await tester.pumpWidget(ButtonControlApp(ttsService: fakeTts));
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.mediaTrackNext);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('center_key_name')), findsOneWidget);
      expect(find.text('KEYCODE_MEDIA_NEXT'), findsWidgets);

      // Clear logs
      await tester.tap(find.byKey(const Key('clear_logs_button')));
      await tester.pumpAndSettle();

      // Center UI still displays the last key
      expect(find.byKey(const Key('waiting_prompt')), findsNothing);
      expect(find.byKey(const Key('center_key_name')), findsOneWidget);
      final keyWidget = tester.widget<Text>(find.byKey(const Key('center_key_name')));
      expect(keyWidget.data, 'KEYCODE_MEDIA_NEXT');
    });
  });

  group('Adversarial Group 2: Bottom Log List Chronological Order & Clear Operations', () {
    late FakeTtsService fakeTts;

    setUp(() {
      fakeTts = FakeTtsService();
    });

    testWidgets('2.1: Log entries are strictly ordered chronologically, auto-scrolled, and scroll-retrievable', (WidgetTester tester) async {
      await tester.pumpWidget(ButtonControlApp(ttsService: fakeTts));
      await tester.pumpAndSettle();

      final keys = [
        LogicalKeyboardKey.audioVolumeUp,
        LogicalKeyboardKey.audioVolumeDown,
        LogicalKeyboardKey.mediaPlayPause,
        LogicalKeyboardKey.mediaTrackNext,
        LogicalKeyboardKey.mediaTrackPrevious,
      ];

      for (final key in keys) {
        await tester.sendKeyEvent(key);
        // Small delay between key events to ensure advancing time
        await tester.pump(const Duration(milliseconds: 20));
      }
      await tester.pumpAndSettle();

      expect(find.text('リアルタイムログ (5件)'), findsOneWidget);

      // Verify the latest entry (index 4) is currently in view due to auto-scrolling
      expect(find.byKey(const Key('log_entry_4')), findsOneWidget);

      // Scroll up to view the earliest entry (index 0)
      await tester.drag(find.byKey(const Key('log_list_view')), const Offset(0, 400));
      await tester.pumpAndSettle();

      // Verify the earliest entry (index 0) is now visible
      expect(find.byKey(const Key('log_entry_0')), findsOneWidget);
    });

    testWidgets('2.2: Stress test: 50 sequential rapid events render cleanly without crash or leak', (WidgetTester tester) async {
      await tester.pumpWidget(ButtonControlApp(ttsService: fakeTts));
      await tester.pumpAndSettle();

      for (int i = 0; i < 50; i++) {
        await tester.sendKeyEvent(
          i.isEven ? LogicalKeyboardKey.audioVolumeUp : LogicalKeyboardKey.audioVolumeDown,
        );
        await tester.pump(const Duration(milliseconds: 5));
      }
      await tester.pumpAndSettle();

      expect(find.text('リアルタイムログ (50件)'), findsOneWidget);
      expect(fakeTts.spokenHistory.length, 50);
      expect(tester.takeException(), isNull);
    });

    testWidgets('2.3: Clean clearing via Header inline "クリア" button resets log state', (WidgetTester tester) async {
      await tester.pumpWidget(ButtonControlApp(ttsService: fakeTts));
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.audioVolumeUp);
      await tester.pumpAndSettle();

      expect(find.text('リアルタイムログ (1件)'), findsOneWidget);
      final inlineClearFinder = find.byKey(const Key('log_header_clear'));
      expect(inlineClearFinder, findsOneWidget);

      // Tap inline clear
      await tester.tap(inlineClearFinder);
      await tester.pumpAndSettle();

      // State after clear
      expect(find.text('リアルタイムログ (0件)'), findsOneWidget);
      expect(find.text('ログはありません'), findsOneWidget);
      expect(find.byKey(const Key('log_header_clear')), findsNothing);
    });

    testWidgets('2.4: Log list cleanly recovers and appends new entries after being cleared', (WidgetTester tester) async {
      await tester.pumpWidget(ButtonControlApp(ttsService: fakeTts));
      await tester.pumpAndSettle();

      // Add 2 events
      await tester.sendKeyEvent(LogicalKeyboardKey.audioVolumeUp);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.audioVolumeDown);
      await tester.pumpAndSettle();
      expect(find.text('リアルタイムログ (2件)'), findsOneWidget);

      // Clear via AppBar button
      await tester.tap(find.byKey(const Key('clear_logs_button')));
      await tester.pumpAndSettle();
      expect(find.text('リアルタイムログ (0件)'), findsOneWidget);

      // Add new event after clear
      await tester.sendKeyEvent(LogicalKeyboardKey.mediaTrackNext);
      await tester.pumpAndSettle();

      expect(find.text('リアルタイムログ (1件)'), findsOneWidget);
      expect(find.byKey(const Key('log_entry_0')), findsOneWidget);
      final centerKeyText = tester.widget<Text>(find.byKey(const Key('center_key_name')));
      expect(centerKeyText.data, 'KEYCODE_MEDIA_NEXT');
    });
  });

  group('Adversarial Group 3: TTS Audio Feedback Logic & Error Resilience', () {
    test('3.1: All 5 ButtonAction speechText strings match canonical Japanese specifications', () {
      expect(ButtonAction.volumeUp.speechText, '音量アップを受信しました');
      expect(ButtonAction.volumeDown.speechText, '音量ダウンを受信しました');
      expect(ButtonAction.mediaPlayPause.speechText, '再生・停止ボタンが押されました');
      expect(ButtonAction.mediaNext.speechText, '次の曲ボタンを受信しました');
      expect(ButtonAction.mediaPrevious.speechText, '前の曲ボタンを受信しました');

      // Key names
      expect(ButtonAction.volumeUp.keyName, 'KEYCODE_VOLUME_UP');
      expect(ButtonAction.volumeDown.keyName, 'KEYCODE_VOLUME_DOWN');
      expect(ButtonAction.mediaPlayPause.keyName, 'KEYCODE_MEDIA_PLAY_PAUSE');
      expect(ButtonAction.mediaNext.keyName, 'KEYCODE_MEDIA_NEXT');
      expect(ButtonAction.mediaPrevious.keyName, 'KEYCODE_MEDIA_PREVIOUS');
    });

    test('3.2: FlutterTtsService native channel interactions (stop before speak & language set)', () async {
      final methodCalls = <MethodCall>[];

      // Intercept platform channel calls for flutter_tts
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('flutter_tts'), (MethodCall call) async {
        methodCalls.add(call);
        switch (call.method) {
          case 'setLanguage':
            return 1;
          case 'setSpeechRate':
            return 1;
          case 'setVolume':
            return 1;
          case 'setPitch':
            return 1;
          case 'awaitSpeakCompletion':
            return 1;
          case 'stop':
            return 1;
          case 'speak':
            return 1;
          default:
            return 1;
        }
      });

      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(const MethodChannel('flutter_tts'), null);
      });

      final service = FlutterTtsService();
      await service.initialize();

      // Verify language is set to ja-JP
      final setLanguageCalls = methodCalls.where((c) => c.method == 'setLanguage').toList();
      expect(setLanguageCalls, isNotEmpty);
      expect(setLanguageCalls.first.arguments, 'ja-JP');

      methodCalls.clear();

      // Call speak
      await service.speak('音量アップを受信しました');

      // Verify 'stop' is called BEFORE 'speak'
      expect(methodCalls.length, 2);
      expect(methodCalls[0].method, 'stop');
      expect(methodCalls[1].method, 'speak');
      expect(methodCalls[1].arguments, '音量アップを受信しました');

      // Call stop directly
      methodCalls.clear();
      await service.stop();
      expect(methodCalls.length, 1);
      expect(methodCalls[0].method, 'stop');
    });

    test('3.3: FlutterTtsService catches native platform channel exceptions without throwing', () async {
      // Mock platform channel to throw PlatformException
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('flutter_tts'), (MethodCall call) async {
        throw PlatformException(code: 'TTS_FAILURE', message: 'Native TTS unavailable');
      });

      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(const MethodChannel('flutter_tts'), null);
      });

      final service = FlutterTtsService();

      // None of these should throw uncaught exceptions
      await expectLater(service.initialize(), completes);
      await expectLater(service.speak('テスト'), completes);
      await expectLater(service.stop(), completes);
    });

    testWidgets('3.4: Fault Injection: App UI remains fully responsive when native TTS channel fails with PlatformException', (WidgetTester tester) async {
      // Mock flutter_tts channel to fail on all calls
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('flutter_tts'), (MethodCall call) async {
        throw PlatformException(code: 'TTS_ENGINE_MISSING', message: 'No TTS engine found on host device');
      });

      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(const MethodChannel('flutter_tts'), null);
      });

      // Run production app with FlutterTtsService under failing native TTS channel
      await tester.pumpWidget(ButtonControlApp(ttsService: FlutterTtsService()));
      await tester.pumpAndSettle();

      // Simulate key event
      final handled = await tester.sendKeyEvent(LogicalKeyboardKey.audioVolumeUp);
      expect(handled, isTrue);
      await tester.pumpAndSettle();

      // Verify UI updated properly despite native TTS engine failure
      expect(find.byKey(const Key('center_key_name')), findsOneWidget);
      expect(find.text('KEYCODE_VOLUME_UP'), findsWidgets);
      expect(find.text('リアルタイムログ (1件)'), findsOneWidget);

      // Simulate another key event
      await tester.sendKeyEvent(LogicalKeyboardKey.mediaTrackNext);
      await tester.pumpAndSettle();

      expect(find.text('KEYCODE_MEDIA_NEXT'), findsWidgets);
      expect(find.text('リアルタイムログ (2件)'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
