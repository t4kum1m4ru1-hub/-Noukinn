# Handoff Report: noukin_app アーキテクチャ調査

## 1. Observation（直接の観察結果）

### O1. `lib/main.dart`（`ButtonControlScreen` の構造と既存ボタン配置）
- ファイルパス: `c:\Users\taqmi\02_development\original_program\noukin_app\lib\main.dart`
- 行番号: 591〜718行目
- `ButtonControlScreen` は `Scaffold` を返し、その `body` は `Column` で構成されています。
- 既存の「トレーニング開始」ボタンは 674〜702行目に `Padding` ウィジェットとして配置されています：
  ```dart
  // メイン画面上部のトレーニング開始ボタン
  Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
    child: ElevatedButton.icon(
      key: const Key('start_training_button'),
      onPressed: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => TrainingScreen(
              ttsService: widget.ttsService,
              soundEffectService: widget.soundEffectService,
            ),
          ),
        );
      },
      icon: const Icon(Icons.fitness_center),
      label: const Text(
        'トレーニング開始',
        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.tealAccent,
        foregroundColor: Colors.black,
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    ),
  ),
  ```
- その下には `Expanded(flex: 5, child: _buildCenterDisplay())`、`Divider`、`_buildLogHeader()`、`Expanded(flex: 5, child: _buildLogList())` が続きます（704〜716行目）。

### O2. `lib/training_screen.dart`（引数仕様と画面遷移）
- ファイルパス: `c:\Users\taqmi\02_development\original_program\noukin_app\lib\training_screen.dart`
- 行番号: 16〜51行目
- コンストラクタ定義（16〜26行目）：
  ```dart
  class TrainingScreen extends StatefulWidget {
    final TtsService? ttsService;
    final SoundEffectService? soundEffectService;
    final TrainingController? controller;

    const TrainingScreen({
      super.key,
      this.ttsService,
      this.soundEffectService,
      this.controller,
    });
  ```
- 全パラメータが null 許容です。`controller` が渡されない場合、`initState()`（45〜50行目）にて自前で生成されます：
  ```dart
  _controller = TrainingController(
    ttsService: widget.ttsService,
    soundEffectService: widget.soundEffectService,
    onWorkoutCompleted: _navigateToReviewScreen,
  );
  _ownsController = true;
  ```
- 戻り遷移: AppBar の leading（223行目）にて `Navigator.of(context).pop()`。
- ワークアウト完了遷移: 80〜89行目にて `Navigator.of(context).push(MaterialPageRoute(builder: (context) => const ReviewScreen()))`。

### O3. 音声サービスとダッキング制御の定義
- ファイルパス: `c:\Users\taqmi\02_development\original_program\noukin_app\lib\main.dart`
- 行番号: 59〜400行目
  - **`AudioDuckingController`**（59〜156行目）：
    - インターフェース: `configure()`, `requestDucking()`, `releaseDucking()`
    - 本番実装: `AudioSessionDuckingController`（`audio_session` パッケージを利用し、iOS は `duckOthers`、Android は `AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK` を適用）
    - テスト実装: `FakeAudioDuckingController`（`isCurrentlyDucked` とイベント履歴を管理）
  - **`SoundEffectService`**（163〜200行目）：
    - インターフェース: `playBeep()`
    - 本番実装: `PlatformSoundEffectService`（`duckingController?.requestDucking()`、Android は `MethodChannel('com.example.noukin/key_events').invokeMethod('playBeep')`、システム音 `SystemSound.play(SystemSoundType.click)` を実行）
    - テスト実装: `FakeSoundEffectService`（`beepCount` を保持）
  - **`TtsService`**（208〜400行目）：
    - インターフェース: `initialize()`, `speak(String text)`, `stop()`, `setVolume(double volume)`
    - 本番実装: `FlutterTtsService`
      - `speak()` 内で既に発話中の場合は `await _flutterTts.stop()` と最大80msの中断完了待機、ダッキング一時解除後に再ダッキング要求と `_flutterTts.speak()` を実施（317〜333行目）。
      - 発話完了コールバック（`setCompletionHandler`、260〜263行目）および停止（`stop()`、342〜351行目）で確実にダッキングを解除。
    - テスト実装: `FakeTtsService`（`spokenHistory`, `lastSpoken`, `stopCallCount`）

### O4. 既存テストの実行結果
- 実行コマンド: `flutter test`
- 結果:
  ```
  00:04 +14: All tests passed!
  ```
  既存の全14テスト（ユニットテスト・ダッキングテスト・ウィジェットテスト・キーイベントテスト）が成功。

---

## 2. Logic Chain（観察から結論への論理展開）

1. **ボタン配置の安全性（O1より）**:
   `ButtonControlScreen` の `body` は `Column` であり、既存の「トレーニング開始」ボタン `Padding` の直下に新規ウィジェットを直接配置可能です。残りのスペースは上下二分割された `Expanded(flex: 5)` が担っているため、ボタンを追加してもレイアウトオーバーフローを起こすことなく自然に縦幅が調整されます。
2. **画面遷移の互換性と独立性（O2より）**:
   `TrainingScreen` の引数はすべてオプショナルであり、`ttsService` と `soundEffectService` を渡すだけで安全に初期化・画面表示されます。`ORIGINAL_REQUEST.md` の要求通り、`lib/training_screen.dart` を1行も修正することなく、`TutorialScreen` 側から `Navigator.of(context).pushReplacement` を呼び出すことで、チュートリアルからトレーニング本編へのシームレスな引き継ぎが可能です。
3. **音声多重発話防止とダッキング整合性（O3より）**:
   `FlutterTtsService` は自身でダッキングの獲得・解放と重複発話キャンセル機構を持っています。`TutorialScreen` ではステップ変更時やスキップ時に明示的に `await ttsService?.stop();` を呼び出してから新しい音声を `speak()` することで、要件 R2（前のTTS音声が重ならず停止してから開始、BGMダッキングの漏れなき適用）を100%満たすことができます。
4. **テスト容易性（O3, O4より）**:
   既存テストスイートで利用されている `FakeTtsService`、`FakeSoundEffectService`、`sendNativeKeyEvent` ヘルパーをそのまま活用することで、モック不要で Step 1 〜 Step 6 のキーイベント進行を高速かつ安定して検証できます。

---

## 3. Caveats（制約事項・考慮点）

1. **`lib/training_screen.dart` の不変性**:
   本要件では `lib/training_screen.dart` へのコード変更は禁止されています。すべてのチュートリアル機能は `lib/tutorial_screen.dart` 内に完結させる必要があります。
2. **発話文言の表記揺れ（「キロ」 vs 「kg」）**:
   `ORIGINAL_REQUEST.md` の記述では「60キロ」「62.5キロ」「65キロ」と日本語カタカナで指定されています（`TrainingController` 内部では `${formatWeightNumber(weight)}kg`）。TTSエンジンやテストの検証文字列において表記不整合が発生しないよう、`TutorialScreen` の実装および自動テストでは `ORIGINAL_REQUEST.md` に記載された指定文字列（「60キロ」等）に厳密に一致させる必要があります。
3. **Android ネイティブキーコードとの一致**:
   再生/停止（85, 79）、次曲（87）、前曲（88）、音量UP/DOWN（24, 25）の6種類以外のキーはチュートリアル中に無視するか、必要に応じて画面上に注意案内を出す必要があります。

---

## 4. Conclusion（結論・推奨アクション）

1. **新規ファイル `lib/tutorial_screen.dart` の作成**:
   - `TtsService?` と `SoundEffectService?` を受け取る `StatefulWidget` として実装する。
   - 暗転オーバーレイ（Black 70%）、ホタル発光アニメーション枠線（`AnimationController` ＋ `boxShadow`）、控えめなスキップボタン、最下部疑似メディアキーバーを配置する。
   - Step 1 〜 Step 6 のステートマシンを内部で保持し、各キーイベントに応じた電子音再生、TTS発話（必ず直前 `stop()`）、画面更新を実行する。
   - 完了時およびスキップ時は `Navigator.of(context).pushReplacement` で `TrainingScreen` へ遷移する。
2. **`lib/main.dart` へのエントリーボタン追加**:
   - 674行目の `start_training_button` の直下に、`start_tutorial_button`（「操作チュートリアルを体験する」）を追加する。
3. **自動テストの作成**:
   - `test/tutorial_test.dart`（または既存テストファイル）に全6ステップの自動 Widget テストを作成し、全テストパス（exit code 0）を担保する。

---

## 5. Verification Method（独立検証手順）

1. **コード配置の確認**:
   - `lib/main.dart` の 674〜702行目付近を `read_file` で閲覧し、「トレーニング開始」ボタンの構造と直下のレイアウトを確認する。
   - `lib/training_screen.dart` の 16〜30行目および 80〜90行目を閲覧し、コンストラクタ引数および画面遷移を確認する。
2. **テストコマンドの実行**:
   ```powershell
   flutter test
   ```
   - 期待値: 14 tests passed, exit code 0。
3. **無効化条件**:
   - `lib/training_screen.dart` に変更が加わった場合。
   - `flutter test` の既存テストが破損した場合。
