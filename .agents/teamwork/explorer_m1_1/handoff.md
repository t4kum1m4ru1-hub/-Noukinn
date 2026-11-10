# Handoff Report: TutorialScreen ステートマシン＆オーディオ・キーイベント管理設計

## 1. Observation（直接の観察結果）

1. **`lib/main.dart` 内のキーイベントディスパッチ機構（行 472-524）**:
   ```dart
   class KeyEventChannelDispatcher {
     KeyEventChannelDispatcher._();
     static final KeyEventChannelDispatcher instance = KeyEventChannelDispatcher._();
     static const MethodChannel _channel = MethodChannel(kKeyEventsChannelName);
     final List<void Function(ButtonAction action)> _listeners = [];
     ...
     if (action != null && _listeners.isNotEmpty) {
       _listeners.last(action);
       return true;
     }
   }
   ```
   ディスパッチャは `_listeners.last`（最前面のアクティブ画面リスナー）のみにイベントを通知する仕様となっており、`TutorialScreen` の `initState` で登録し `dispose` で解除することで、重なり合う画面間での競合なく正しくイベントを専有できる。

2. **`lib/main.dart` 内の音声サービス（行 60-399）**:
   `AudioDuckingController`, `SoundEffectService`, `TtsService` の3つの抽象クラスおよびそれらの Fake 実装（`FakeAudioDuckingController`, `FakeSoundEffectService`, `FakeTtsService`）が定義済みである。`TtsService.stop()` は現在発話中の音声をキャンセルし、BGMダッキングを復帰させる。また `FakeTtsService` では `stopCallCount` で `stop()` の呼出回数を追跡可能。

3. **`lib/training_controller.dart` 内の 0.7 秒デバウンス実装（行 510-536）**:
   ```dart
   _debounceTimer = Timer(const Duration(milliseconds: 700), () {
     _framePumpTimer?.cancel();
     _framePumpTimer = null;
     _debounceTimer = null;
     _speak(speechBuilder());
   });
   _framePumpTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
     if (_debounceTimer == null || !_debounceTimer!.isActive) {
       timer.cancel();
       return;
     }
     try {
       SchedulerBinding.instance.scheduleFrame();
     } catch (_) {}
   });
   ```
   Widget テストの `tester.pumpAndSettle()` 実行時にも、100ms ごとの `SchedulerBinding.instance.scheduleFrame()` パルスによりタイマー未消化例外（`A Timer is still pending`）を起こさず安全に完了する。

4. **テスト実行結果**:
   `flutter test` の実行により、既存の全14テストケースが exit code 0 でパスすることを確認（00:04 +14: All tests passed!）。

---

## 2. Logic Chain（論理的推論の連鎖）

1. **[Observation 1 に基づく] リスナー管理の局所性**:
   - `TutorialScreen` の `initState` で `KeyEventChannelDispatcher.instance.registerListener(_handleButtonAction)` を呼び出し、`dispose` で `unregisterListener` を呼び出す。
   - `TutorialScreen` が最前面に存在するとき、`_listeners.last` が `TutorialScreen` のハンドラを指すため、下層の `ButtonControlScreen` へのイベント漏洩を防止できる。
2. **[Observation 2 に基づく] 発話排他とダッキングの保証**:
   - 要件 R2 および AC では「新しいTTS発話開始前に必ず `flutterTts.stop()` が呼び出され、発話の重複が発生しないこと」が要求されている。
   - `TutorialScreen` 内の `_speak(String text)` メソッドで `await widget.duckingController?.requestDucking();` ➔ `await widget.ttsService?.stop();` ➔ `await widget.ttsService?.speak(text);` の順で呼び出すことで、重複発話を防ぎ `stopCallCount` を確実にインクリメントする。
3. **[Observation 3 に基づく] 0.7 秒デバウンスと即時決定・破棄の安全性**:
   - Step 4 で音量キー（24/25）が連打された場合、即座にビープ音を再生し画面数値を更新しつつ、前回のタイマーをキャンセルして新しい 700ms タイマーを開始する。
   - 0.7秒以内に決定ボタン（85）またはスキップが押された場合は、`_cancelDebounce()` を即座に実行し、未完了の重量読み上げが Step 5 へ漏洩することを防ぐ。
   - `dispose()` 時にも `_cancelDebounce()` を呼ぶことでメモリリークおよび未消化タイマー例外を排除する。
4. **統合入力パイプライン**:
   - 物理キーイベント（MethodChannel）、PC キーボード（`Focus`）、疑似メディアキーバー（タップ）のすべてが同一の `_handleButtonAction(ButtonAction action)` を経由することで、実機・エミュレータ・テスト環境の全域で 100% 一貫したステートマシン動作を保証する。

---

## 3. Caveats（前提条件および留意事項）

1. **テスト環境でのアニメーション制御**:
   - `animateGlow: false`（または `widget.animateGlow == false`）のオプション引数を設けない場合、リピートする `AnimationController` によりテストの `pumpAndSettle()` が無限ループに陥る恐れがある。Worker 実装時に `animateGlow` フラグを反映すること。
2. **Step 5 での対象外キー入力**:
   - Step 5 ではキー 87 以外のキー押下時に状態遷移をさせず注意案内を表示する。音声ガイダンスではなく画面上の案内表示（SnackBar またはインラインメッセージ）とすることで、イヤホン音声の進行を乱さない設計とする。

---

## 4. Conclusion（結論）

1. **状態モデル**:
   `TutorialStep`（`step1Intro`, `step2Start`, `step3Select`, `step4Adjust`, `step5Confirm`, `step6Complete`）の 6 ステップと、Step 3 の `Step3Phase`（`enterMode`, `cycleItem`）により、中間発表プレゼンの要件を網羅する完全な決定論的ステートマシンを設計した。
2. **オーディオおよびキー制御**:
   `KeyEventChannelDispatcher` への確実な登録・解除、発話前の `stop()` 呼び出し、ダッキング連携、および 0.7 秒デバウンスタイマー破棄機構により、競合と未完了タイマーのない堅牢な実行環境を確立した。
3. **成果物**:
   詳細な設計およびコードパターンを `.agents/teamwork/explorer_m1_1/analysis.md` にまとめた。

---

## 5. Verification Method（独立検証手順）

1. **設計ドキュメントの確認**:
   - `.agents/teamwork/explorer_m1_1/analysis.md` を閲覧し、Enum 定義、主要変数、`_speak` 実装、0.7 秒デバウンスロジック、およびステップ別遷移マトリクスを検証する。
2. **テストコマンドによる基本検証**:
   - `flutter test` を実行し、既存テスト 14 件がすべて正常終了（exit code 0）することを確認する。
3. **無効化条件**:
   - Step 4 から Step 5 への遷移時にデバウンスタイマーがキャンセルされずに前の重量が読み上げられる場合、または `widget.ttsService?.stop()` が発話前に呼ばれず発話が重複する場合は本設計の前提が無効となる。
