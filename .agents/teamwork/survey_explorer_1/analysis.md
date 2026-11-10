# アーキテクチャ調査レポート: `noukin_app` の構造とチュートリアル画面新設方針

## 1. エグゼクティブサマリー

「のう筋」アプリは、スマートフォンの画面を触らずにイヤホンや物理ボタンのみでトレーニングを進行できるハンズフリー体験（MVP）を提供しています。本調査では、新設予定の操作チュートリアル画面（`TutorialScreen`）を安全かつ既存アーキテクチャと整合性を保って組み込むため、以下3点の詳細調査を実施しました。

1. **`lib/main.dart`（`ButtonControlScreen`）**:
   - `Column` レイアウトの先頭に「トレーニング開始」ボタンが配置されており、その直下に新規の「操作チュートリアルを体験する」ボタンを直接の子ウィジェットとして追加可能。
2. **`lib/training_screen.dart`（※完全読み取り専用）**:
   - コンストラクタ引数はすべてオプショナル（`ttsService`, `soundEffectService`, `controller`）。
   - チュートリアル完了時またはスキップ時には、`TutorialScreen` から同一の音声サービスインスタンスを引き継いで `TrainingScreen` へスムーズに画面遷移可能。
3. **音声サービスレイヤー（TTS・電子音・BGMダッキング）**:
   - `lib/main.dart` 内に `TtsService`（`FlutterTtsService`）、`SoundEffectService`（`PlatformSoundEffectService`）、`AudioDuckingController`（`AudioSessionDuckingController`）が定義済み。
   - `FlutterTtsService` 内部ですでに発話開始直前のダッキング要求、発話完了・中断・エラー時のダッキング解除、および連続呼び出し時の `flutterTts.stop()` が実装されており、`TutorialScreen` 側でもこの抽象サービスを再利用することで統一的な音声制御が可能。

---

## 2. `lib/main.dart` の構造調査

### 2.1 `ButtonControlScreen` の全体構造
- クラス定義: `lib/main.dart` 591〜603行目
  ```dart
  class ButtonControlScreen extends StatefulWidget {
    final TtsService ttsService;
    final SoundEffectService? soundEffectService;

    const ButtonControlScreen({
      super.key,
      required this.ttsService,
      this.soundEffectService,
    });

    @override
    State<ButtonControlScreen> createState() => _ButtonControlScreenState();
  }
  ```
- ライフサイクル（612〜624行目）:
  - `initState()` で `widget.ttsService.initialize()` を呼び出し、`KeyEventChannelDispatcher.instance.registerListener(_processAction)` によりハードウェアキーを登録。
  - `dispose()` でリスナー解除、スクロールコントローラ破棄、`widget.ttsService.stop()` を実行。
- ウィジェットツリー（657〜718行目）:
  ```dart
  Scaffold(
    appBar: AppBar(...),
    body: Column(
      children: [
        // 1. トレーニング開始ボタン (Padding)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: ElevatedButton.icon(...), // key: Key('start_training_button')
        ),
        // 2. 画面中央のボタン入力検知巨大表示
        Expanded(
          flex: 5,
          child: _buildCenterDisplay(),
        ),
        const Divider(height: 1, color: Color(0xFF333333)),
        // 3. ログヘッダー
        _buildLogHeader(),
        // 4. 受信ログ一覧（スクロール可能）
        Expanded(
          flex: 5,
          child: _buildLogList(),
        ),
      ],
    ),
  )
  ```

### 2.2 既存「トレーニング開始」ボタンの配置と画面遷移
- 該当箇所: `lib/main.dart` 674〜702行目
  ```dart
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

### 2.3 新規「操作チュートリアルを体験する」ボタンの推奨配置
- **配置位置**: `Column` の子要素リスト内において、上記「トレーニング開始」ボタンの `Padding` の直下。
- **レイアウト考慮事項**:
  - `Expanded(flex: 5)` が中央表示とログ一覧で画面を二等分しているため、ボタンを縦に2つ並べても `Expanded` が自動的に高さを吸収し、レイアウト破綻は発生しません。
  - 余白は既存の `fromLTRB(16, 12, 16, 4)` に合わせ、新設ボタンは `fromLTRB(16, 4, 16, 8)` とすることで上下バランスが均等になります。
- **提案コードスニペット**:
  ```dart
  // メイン画面上部：新規操作チュートリアルボタン（トレーニング開始ボタンの直下）
  Padding(
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
    child: OutlinedButton.icon(
      key: const Key('start_tutorial_button'),
      onPressed: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => TutorialScreen(
              ttsService: widget.ttsService,
              soundEffectService: widget.soundEffectService,
            ),
          ),
        );
      },
      icon: const Icon(Icons.school_outlined),
      label: const Text(
        '操作チュートリアルを体験する',
        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
      ),
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.amberAccent,
        side: const BorderSide(color: Colors.amberAccent, width: 1.5),
        minimumSize: const Size.fromHeight(46),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    ),
  ),
  ```

---

## 3. `lib/training_screen.dart` の構造調査（※完全読み取り専用）

### 3.1 コンストラクタ引数と初期化ロジック
- クラス定義: `lib/training_screen.dart` 16〜26行目
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

    @override
    State<TrainingScreen> createState() => _TrainingScreenState();
  }
  ```
- 引数はすべて**オプショナル**（`null` 許容）。
- `_TrainingScreenState.initState()`（41〜51行目）:
  ```dart
  if (widget.controller != null) {
    _controller = widget.controller!;
    _ownsController = false;
  } else {
    _controller = TrainingController(
      ttsService: widget.ttsService,
      soundEffectService: widget.soundEffectService,
      onWorkoutCompleted: _navigateToReviewScreen,
    );
    _ownsController = true;
  }
  ```
  `controller` が渡されなかった場合は、内部で `TrainingController` を自動生成し、画面破棄時に自前で `dispose()` します。

### 3.2 アプリ内における `TrainingScreen` への遷移経路
1. `ButtonControlScreen` からの通常遷移:
   `Navigator.of(context).push(MaterialPageRoute(builder: (context) => TrainingScreen(...)))`
2. `TrainingScreen` からの戻り:
   AppBar leading の戻るボタン押下で `Navigator.of(context).pop()`
3. `TrainingScreen` からの完了遷移:
   最終種目完了時に `ReviewScreen` へ `Navigator.of(context).push(...)`

### 3.3 `TutorialScreen` からの遷移方針
`ORIGINAL_REQUEST.md` の要求仕様：
- Step 1 の「スキップして直接トレーニングへ」
- Step 6 の「最初のトレーニングを開始する」または［再生/停止］キー

遷移実装方法の選択肢：
- `pushReplacement`:
  チュートリアル画面をスタックから破棄して `TrainingScreen` に置き換える。トレーニング終了後に「戻る」ボタンを押した際、チュートリアル画面を経由せず直接 `ButtonControlScreen`（メイン画面）へ戻れるため、プレゼン実演および実利用体験として最も自然です。
  ```dart
  Navigator.of(context).pushReplacement(
    MaterialPageRoute(
      builder: (context) => TrainingScreen(
        ttsService: widget.ttsService,
        soundEffectService: widget.soundEffectService,
      ),
    ),
  );
  ```

---

## 4. 音声サービスレイヤーの調査

### 4.1 アーキテクチャ階層
`lib/main.dart` にて以下のインターフェースと実装クラス群が提供されています。

```
[OS / Hardware]
      ▲
      │ (AudioSession / MethodChannel / Platform Channel)
      ▼
┌──────────────────────────────────────────────────────────┐
│ AudioDuckingController                                   │
│  - configure()                                           │
│  - requestDucking()                                      │
│  - releaseDucking()                                      │
│  Impl: AudioSessionDuckingController / FakeAudio...      │
└───────────────┬──────────────────────────┬───────────────┘
                │                          │
                ▼                          ▼
┌───────────────────────────────┐ ┌────────────────────────┐
│ SoundEffectService            │ │ TtsService             │
│  - playBeep()                 │ │  - initialize()        │
│  Impl: PlatformSoundEffect... │ │  - speak(text)         │
│        FakeSoundEffect...     │ │  - stop()              │
│                               │ │  - setVolume(vol)      │
│                               │ │  Impl: FlutterTts...   │
│                               │ │        FakeTts...      │
└───────────────────────────────┘ └────────────────────────┘
```

### 4.2 提供メソッドと動作詳細

#### (1) `AudioDuckingController`（59〜156行目）
- **`configure()`**: `audio_session` パッケージを設定。
  - iOS: `AVAudioSessionCategory.playback` + `duckOthers` + Bluetooth許可
  - Android: `gainTransientMayDuck` + `assistanceNavigationGuidance`
- **`requestDucking()`**: `_session.setActive(true)` を呼び出し、再生中のBGM音量を減衰させる。
- **`releaseDucking()`**: `_session.setActive(false)` を呼び出し、BGM音量を復帰させる。

#### (2) `SoundEffectService`（163〜200行目）
- **`playBeep()`**:
  - `PlatformSoundEffectService`:
    1. `duckingController?.requestDucking()` を呼び出し
    2. Androidネイティブ（`MainActivity.kt`）の `ToneGenerator`（MethodChannel経由）を呼び出し
    3. `SystemSound.play(SystemSoundType.click)` で即時フォールバック電子音を再生
  - `FakeSoundEffectService`:
    - `beepCount` をインクリメント。テスト検証用。

#### (3) `TtsService`（208〜400行目）
- **`initialize()`**: 言語（ja-JP）、速度（0.5）、音量（1.0）、コールバックハンドラ（`setCompletionHandler`, `setCancelHandler`, `setErrorHandler`）を設定。
- **`speak(String text)`**:
  - **重要**: 既に発話中またはダッキング中の場合、内部で `_flutterTts.stop()` を呼び出し、キャンセル完了を待機（最大80ms）した上で一度ダッキングを解除し、再度 `requestDucking()` してから `_flutterTts.speak(text)` を発行。
  - 発話終了（`setCompletionHandler`）時、自動で `_releaseDuckingIfNeeded()` が呼ばれてダッキング解除される。
- **`stop()`**:
  - `_flutterTts.stop()` を呼び出し、`finally` ブロックで確実にダッキング解除（`_releaseDuckingIfNeeded()`）を実行。
- **`setVolume(double volume)`**: 音量を `0.0` 〜 `1.0` で設定。

### 4.3 `TutorialScreen` でのクリーンな音声呼び出し設計

1. **多重発話の防止**:
   - `FlutterTtsService.speak()` は内部で先行発話を自動停止しますが、チュートリアルのステップ切り替え時やユーザーがスキップボタンを押した際には、状態更新の直前に明示的に `await ttsService?.stop();` を実行することで、前ステップの残存音声を完全にクリアできます。
   - `TutorialScreen.dispose()` 時にも必ず `ttsService?.stop();` を呼び出します。
2. **電子音とダッキングの連携**:
   - ボタン操作（次曲、前曲、音量、再生停止）検知時は即座に `soundEffectService?.playBeep()` を実行。
   - `PlatformSoundEffectService` は `duckingController` を保持していれば自動でダッキング要求を行います。
3. **0.7秒デバウンス制御**:
   - Step 4（重量調整）では、キー連打時に電子音は即座に鳴らしつつ、TTS発話は0.7秒間追加入力がなかった時のみ実行します（`TrainingController._scheduleDebouncedSpeech` と同様の `Timer(const Duration(milliseconds: 700), ...)` パターンを採用）。

---

## 5. ハードウェアキー・メディアキーの統合方式

- **ディスパッチャ**: `KeyEventChannelDispatcher.instance`（472〜524行目）
  - Android ネイティブ層（`MethodChannel("com.example.noukin/key_events")`）から送られるキーコードを `ButtonAction` 列挙型に変換。
  - `registerListener((action) => ...)` でアクティブな最前面画面がリスナーを登録。
  - `unregisterListener(...)` で登録解除。
- **キーコード対応表**:
  | ボタン | キーコード | `ButtonAction` | チュートリアルでの役割 |
  |---|---|---|---|
  | 再生/停止 | 85 (`KEYCODE_MEDIA_PLAY_PAUSE`), 79 (`KEYCODE_HEADSETHOOK`) | `ButtonAction.mediaPlayPause` / `headsetHook` | 開始 / 決定 / 次へ |
  | 次の曲へ | 87 (`KEYCODE_MEDIA_NEXT`) | `ButtonAction.mediaNext` | 調整モード突入 / 確定完了 |
  | 前の曲へ | 88 (`KEYCODE_MEDIA_PREVIOUS`) | `ButtonAction.mediaPrevious` | 安全確認ボタン（現在内容読み上げ） |
  | 音量UP | 24 (`KEYCODE_VOLUME_UP`) | `ButtonAction.volumeUp` | 項目送り / 重量+2.5kg |
  | 音量DOWN | 25 (`KEYCODE_VOLUME_DOWN`) | `ButtonAction.volumeDown` | 項目戻し / 重量-2.5kg |

---

## 6. 自動テスト（`flutter test`）環境と検証方法

- 既存テストコード（`test/widget_test.dart`）の構成:
  - `sendNativeKeyEvent(tester, keyCode)`: `MethodChannel` 経由のハードウェアキー入力をシミュレートする標準ヘルパー。
  - `FakeTtsService`: `spokenHistory`、`lastSpoken`、`speakCount` を保持し、発話テキストの完全一致を検証可能。
  - `FakeSoundEffectService`: `beepCount` を保持し、ビープ音が正しく鳴ったかを検証可能。
- チュートリアル画面テスト用の設計:
  - `TutorialScreen(ttsService: fakeTts, soundEffectService: fakeSound)` を直接マウントし、`sendNativeKeyEvent` または疑似メディアキーバーをタップして Step 1 〜 Step 6 の進行を決定論的に検証可能。

---

## 7. 実装者向け推奨アーキテクチャ指針まとめ

1. **画面モジュール**:
   `lib/tutorial_screen.dart` を新規作成（`lib/training_screen.dart` は変更禁止）。
2. **エントリーポイント**:
   `lib/main.dart` の「トレーニング開始」ボタン（674行目）直下に「操作チュートリアルを体験する」ボタンを追加。
3. **UI・視覚効果**:
   - 暗転オーバーレイ: `Colors.black.withOpacity(0.7)` または `Colors.black.withAlpha(178)`
   - ホタル発光枠線: `AnimationController`（`CurvedAnimation(..., curve: Curves.easeInOut)`）による `boxShadow`（`AppColors.tealAccent` または `AppColors.primaryAccent` のグロー）
   - 疑似メディアキーバー: 画面最下部に固定表示（`test/widget_test.dart` や PC/エミュレータ操作用）
4. **音声発話文言の厳密性**:
   `ORIGINAL_REQUEST.md` の仕様に準拠：
   - Step 2: 「開始、ベンチプレス、60キロ、10回、3セット」
   - Step 3前半: 「調整、種目名」
   - Step 3後半: 各項目名（「種目名」「重量」「レップ数」「セット数」）、決定時「60キロ」
   - Step 4: 「62.5キロ」「65キロ」等のデバウンス発話、決定時「調整、重量」
   - Step 5: 「確定」、続けて「開始、ベンチプレス、65キロ、10回、3セット」
