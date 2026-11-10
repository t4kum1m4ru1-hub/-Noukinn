# UI Rendering and Automated Test Architecture Analysis Report

**Target Module**: `lib/tutorial_screen.dart` & `test/tutorial_screen_test.dart`  
**Application**: のう筋（noukin_app）  
**Date**: 2026-11-10  
**Author**: survey_explorer_3 (UI Rendering & Automated Test Architect)

---

## 1. Executive Summary

本調査は、筋トレアプリ「のう筋」の中間発表プレゼン実演（デモ）において、審査員および聴衆に「スマホを見ずにイヤホンのボタンだけでトレーニングを完結できるコアバリュー（MVP）」を直感的に伝えるためのインタラクティブな操作チュートリアル画面（`TutorialScreen`）の **UI描画演出** と **自動テストアーキテクチャ** を設計・検証したものです。

### 主要な調査結果
1. **スポットライト＆暗転オーバーレイ**:
   - `ClipPath` または `CustomPainter` 内で `Path.combine(PathOperation.difference, ...)` を使用し、全画面の半透明ブラック（`Colors.black.withOpacity(0.70)`）から注目要素の角丸矩形（`RRect`）を透過（くり抜き）することで、GPU負荷を最小限に抑えつつ完全なスポットライト効果を実現できます。
2. **ホタル発光枠線（呼吸アニメーション）**:
   - `AnimationController`（1200ms周期、`easeInOut` の `repeat(reverse: true)`）と `boxShadow`（多層の光彩拡散・ブラー）を組み合わせ、スポットライト枠の周囲に呼吸するように明滅するエフェクトを適用します。
3. **プレゼン用スキップ＆安全機構**:
   - 右下に控えめな「スキップ >」ボタンを配置し、画面全体のタップフォールバックも備えることで、本番デモでの機材トラブルや通信断に即座に対処可能です。
4. **画面最下部の疑似メディアキーバー**:
   - 既存の `TrainingScreen` の操作バーと同一の 5ボタン（再生/停止、次曲、前曲、Vol+、Vol-）を配置し、物理ボタン、ADB、PCキーボード、マウスクリックで100%同一のロジックを共有します。
5. **テスト容易性とDI設計**:
   - `lib/main.dart` にすでに実装・検証済みの `FakeTtsService`、`FakeSoundEffectService`、`FakeAudioDuckingController` をそのまま再利用可能。外部DIライブラリに依存せず、コンストラクタのオプショナル引数として受け取る標準的なDIを採用することで、`flutter test` で全6ステップ・デバウンス・画面遷移を100%網羅して瞬時に検証できます。

---

## 2. UI Presentation & Effects Deep Dive

### 2.1 スポットライト＆暗転オーバーレイ（Black 70%）

#### 実装方針の比較
| 手法 | 描画方式 | メリット | デメリット / 対策 |
| :--- | :--- | :--- | :--- |
| **A. `Path.combine` による差分くり抜き（推奨）** | `CustomPainter` または `ClipPath` で全画面矩形から注目要素の `RRect` を減算 | `saveLayer` を消費せず高速、Impeller/Skia で安定、くり抜き部分の透明度が100%保たれる | 注目要素の座標（`Rect`）の取得が必要。`GlobalKey` と `addPostFrameCallback` で解決 |
| **B. `BlendMode.clear` + `saveLayer`** | キャンバス全体に黒70%を塗り、`BlendMode.clear` でくり抜く | 描画が直感的 | `saveLayer` のGPUメモリ割り当てオーバーヘッドがあり、アニメーション時にフレーム落ちのリスク |
| **C. コンポーネント単位の Dimming** | 各カードに個別に半透明ブラックを重ねる | 座標計算が不要 | カード間の隙間や背景、アプリアイコン等の全体暗転が不完全になりやすい |

#### 推奨実装（`SpotlightOverlayPainter`）
全画面の暗転とくり抜きを1つの Painter で行います：

```dart
class SpotlightOverlayPainter extends CustomPainter {
  final Rect? targetRect;
  final double borderRadius;
  final Color overlayColor;

  SpotlightOverlayPainter({
    required this.targetRect,
    this.borderRadius = 14.0,
    this.overlayColor = const Color(0xB3000000), // Colors.black.withOpacity(0.70)
  });

  @override
  void paint(Canvas canvas, Size size) {
    final fullRect = Offset.zero & size;
    final bgPaint = Paint()..color = overlayColor;

    if (targetRect == null) {
      // Step 1 や Step 5 等、全体を均一に暗転する場合
      canvas.drawRect(fullRect, bgPaint);
      return;
    }

    final backgroundPath = Path()..addRect(fullRect);
    final holePath = Path()
      ..addRRect(RRect.fromRectAndRadius(
        targetRect!.inflate(3.0), // カードの周囲にわずかな余白を設ける
        Radius.circular(borderRadius),
      ));
    // 全体矩形から穴部分を減算くり抜き
    final spotlightPath = Path.combine(
      PathOperation.difference,
      backgroundPath,
      holePath,
    );
    canvas.drawPath(spotlightPath, bgPaint);
  }

  @override
  bool shouldRepaint(covariant SpotlightOverlayPainter oldDelegate) {
    return oldDelegate.targetRect != targetRect ||
        oldDelegate.borderRadius != borderRadius ||
        oldDelegate.overlayColor != overlayColor;
  }
}
```

### 2.2 ホタルの呼吸発光枠線（AnimationController ＋ boxShadow）

#### アニメーション設計
- **周期**: 1200ms（吸気 600ms、呼気 600ms）
- **カーブ**: `Curves.easeInOut`
- **リピート**: `_glowController.repeat(reverse: true)`
- **二重の光彩レイヤー（`BoxShadow`）**:
  1. 内側（コア発光）: `AppColors.tealAccent` を強めに発光（blurRadius: 10〜22px, spreadRadius: 2〜5px）
  2. 外側（環境光）: 半透明の柔らかな発光（blurRadius: 20〜30px）

#### スポットライト上への配置（`Positioned` ＋ `IgnorePointer`）
くり抜かれた `targetRect` の直上に、`Stack` 内で発光装飾コンテナを重ねます：

```dart
Widget _buildGlowOverlay(Rect rect) {
  return Positioned(
    left: rect.left - 3.0,
    top: rect.top - 3.0,
    width: rect.width + 6.0,
    height: rect.height + 6.0,
    child: IgnorePointer(
      child: AnimatedBuilder(
        animation: _glowAnimation,
        builder: (context, _) {
          final t = _glowAnimation.value; // 0.0 〜 1.0
          return Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16.0),
              border: Border.all(
                color: AppColors.tealAccent.withOpacity(0.5 + 0.5 * t),
                width: 2.0 + 1.0 * t,
              ),
              boxShadow: [
                // 内側の明瞭な発光
                BoxShadow(
                  color: AppColors.tealAccent.withOpacity(0.35 + 0.35 * t),
                  blurRadius: 10.0 + 12.0 * t,
                  spreadRadius: 2.0 + 3.0 * t,
                ),
                // 外側へ広がるホタルの淡いオーラ
                BoxShadow(
                  color: AppColors.tealAccent.withOpacity(0.15 * t),
                  blurRadius: 24.0 + 8.0 * t,
                  spreadRadius: 4.0 + 4.0 * t,
                ),
              ],
            ),
          );
        },
      ),
    ),
  );
}
```
※ `IgnorePointer` を挟んでいるため、ユーザーや発表者がスポットライト内のボタン・カードを直接タップした際もイベントが透過し、確実に反応します。

### 2.3 発表用スキップ機能とデモ安全設計

デモ発表時のイヤホン接続不良や制限時間を考慮し、以下の3重のフォールバックを設けます：

1. **右下スキップボタン（`const Key('btn_tutorial_skip')`）**:
   - 画面右下、疑似メディアキーバーの直上に配置。
   - スタイル: `TextButton.icon`、文字色 `Colors.white60`、文字サイズ 13、控えめなデザインで聴衆の邪魔をしない。
   - 押下時: 直ちに次のステップへ進行（Step 2 -> 3, Step 3 -> 4, Step 4 -> 5, Step 5 -> 6）。
2. **Step 1 の「スキップして直接トレーニングへ」（`const Key('btn_skip_to_training')`）**:
   - チュートリアルを即座に終了し、本編 `TrainingScreen` へ直行する脱出導線。
3. **画面全体のタップフォールバック**:
   - 暗転領域や案内カードをタップすることでも、安全に次のステップへ進行可能。

### 2.4 画面最下部の疑似メディアキーバー

`TrainingScreen` の実績あるレイアウトと完全同一の 5ボタン構成を採用します。
```
［前曲 (内容確認)］ ［再生/停止 (決定/次へ)］ ［次曲 (調整/完了)］ ［Vol-］ ［Vol+］
```
- **配置**: `SafeArea` の最下部に固定（スクロールや暗転オーバーレイの影響を受けない前面レイヤー）。
- **共通ハンドラ**:
  タップ時は `_handleButtonAction(action)` を呼び出し、ネイティブ物理ボタン（`KeyEventChannelDispatcher`）や PCキーボード（`Focus.onKeyEvent`）と100%同一の処理ルートを通過します。

---

## 3. Automated Test Infrastructure & DI Design

### 3.1 既存テスト資産の確認と再利用性

`lib/main.dart` および `test/widget_test.dart` を精査した結果、以下のモック・フェイク実装がすでに完全に整備されており、追加のテストパッケージなしですべての検証が可能です：

1. **`FakeTtsService`**（`lib/main.dart` 364行目）:
   - `spokenHistory`: 発話された文言の全履歴（`List<String>`）
   - `lastSpoken`: 最後に発話された文字列
   - `stopCallCount`: `stop()` が呼ばれた回数
   - 発話前の `stop()` 呼び出し検証（R2要件）にそのまま使用可能。
2. **`FakeSoundEffectService`**（`lib/main.dart` 190行目）:
   - `beepCount`: 電子音（ビープ）が鳴った回数。
3. **`FakeAudioDuckingController`**（`lib/main.dart` 131行目）:
   - `events`: `['configure', 'requestDucking', 'releaseDucking']` のイベント履歴。
   - `isCurrentlyDucked`: 現在ダッキング中かどうかの真偽値。
4. **`sendNativeKeyEvent`**（`test/widget_test.dart` 10行目）:
   - Android ネイティブの MethodChannel（`com.example.noukin/key_events`）から指定のキーコード（85, 87, 88, 24, 25 等）を擬似送信するテストヘルパー。

### 3.2 `TutorialScreen` の Dependency Injection（DI）構造

テスト時にフェイク実装を容易に注入できるよう、`TutorialScreen` にコンストラクタ引数を設けます：

```dart
class TutorialScreen extends StatefulWidget {
  final TtsService? ttsService;
  final SoundEffectService? soundEffectService;
  final AudioDuckingController? duckingController;
  final VoidCallback? onCompleted;
  final bool animateGlow; // テスト時の pumpAndSettle 制御用

  const TutorialScreen({
    super.key,
    this.ttsService,
    this.soundEffectService,
    this.duckingController,
    this.onCompleted,
    this.animateGlow = true,
  });

  @override
  State<TutorialScreen> createState() => _TutorialScreenState();
}
```

- **本番実行時**: `main.dart` から `widget.ttsService` および `widget.soundEffectService` をそのまま渡すだけで動作。
- **テスト実行時**: `TutorialScreen(ttsService: fakeTts, soundEffectService: fakeSound, duckingController: fakeDucking, animateGlow: false)` を渡すことで、プラットフォーム依存なしに安全かつ高速にテスト可能。

### 3.3 Flutter WidgetTester における「アニメーション無限待機」対策

#### ⚠️ 重要な知見
Flutter の `AnimationController.repeat(reverse: true)` は終了しないタイマーをスケジュールし続けるため、テストコードで不用意に `await tester.pumpAndSettle()` を呼ぶと **「pumpAndSettle timed out」エラー** が発生します。

#### 対策アーキテクチャ
1. **`animateGlow: false` フラグ**:
   - `animateGlow == false` の場合、`AnimationController.repeat()` をスキップし、固定値（1.0）を発光枠線に適用。これにより、ステップ進行のテスト全体で `tester.pumpAndSettle()` を安全に使用可能。
2. **発光アニメーション単体テスト**:
   - 発光機能自体のテストでは `animateGlow: true` で起動し、`tester.pump(const Duration(milliseconds: 300))` を呼んで値の変化をフレーム単位で検証。

### 3.4 0.7秒デバウンス（重量調整）のテスト手法

Step 4 での音量連打とデバウンス発話の検証手順：
```dart
// 1回目押下 (+2.5kg): 画面は即座に 62.5kg になるが、TTSはまだ発話されない
await sendNativeKeyEvent(tester, 24);
await tester.pump(const Duration(milliseconds: 200));
expect(find.text('62.5 kg'), findsOneWidget);
expect(fakeSound.beepCount, 1);
expect(fakeTts.spokenHistory, isEmpty);

// 2回目押下 (+2.5kg): 画面は 65kg に更新、タイマーリセット
await sendNativeKeyEvent(tester, 24);
await tester.pump(const Duration(milliseconds: 200));
expect(find.text('65 kg'), findsOneWidget);
expect(fakeSound.beepCount, 2);
expect(fakeTts.spokenHistory, isEmpty);

// 連打停止から 0.7秒（750ms）経過: TTSが「65キロ」を1回だけ発話
await tester.pump(const Duration(milliseconds: 550));
expect(fakeTts.spokenHistory, ['65キロ']);
```

---

## 4. 全6ステップのインタラクション＆テスト設計マトリクス

| ステップ | 注目要素 (Spotlight) | 案内メッセージ / 目的 | 対象キー / 操作 | 期待される動作 (UI / 音声 / 状態) |
| :--- | :--- | :--- | :--- | :--- |
| **Step 1**<br>(開始画面) | なし (中央カード表示) | タイトル「のう筋 操作チュートリアル」<br>説明文 | メインボタンタップ / キー85<br>---<br>スキップボタンタップ | Step 2 へ遷移<br>---<br>`TrainingScreen` へ直行 |
| **Step 2**<br>(開始体験) | 中央「開始」ボタン | 「イヤホンの［再生/停止］ボタンを押してトレーニングを始めてみましょう」 | ［再生/停止］(85, 79)<br>---<br>スキップ / タップ<br>---<br>その他キー (24, 25, 87) | 電子音再生 ＋ 開始演出 ＋ TTS発話「開始、ベンチプレス、60キロ、10回、3セット」 ＋ Step 3 へ自動遷移<br>---<br>無反応 |
| **Step 3 前半**<br>(調整モード突入) | 「種目名」領域 | 「［次の曲へ進む］ボタンを押して、調整モードに入りましょう」 | ［次の曲へ進む］(87)<br>---<br>［前の曲へ］(88) | 電子音再生 ＋ TTS発話「調整、種目名」 ＋ 種目名ハイライト ＋ Step 3 後半へ<br>---<br>TTS「ベンチプレス、60キロ、10回、3セット」 |
| **Step 3 後半**<br>(項目選択) | 選択中の各項目<br>(種目名/重量/レップ数/セット数) | 「［音量＋/−］で項目送り、［再生/停止］で決定」 | ［音量＋/−］(24, 25)<br>---<br>［再生/停止］(85)<br>---<br>［前の曲へ］(88) | 電子音 ＋ 選択枠移動 ＋ 項目名発話（「重量」等）<br>---<br>電子音 ＋ 現在値発話（「60キロ」） ＋ Step 4 へ遷移<br>---<br>内容確認読み上げ |
| **Step 4**<br>(重量調整＆デバウンス) | 「重量」カードのみ<br>(60.0kg) | 「［音量＋/−］で重量を調整（連打対応）。終わったら［再生/停止］で決定」 | ［音量＋/−］(24, 25)<br>---<br>0.7秒連打停止<br>---<br>［再生/停止］(85)<br>---<br>［前の曲へ］(88) | 電子音 ＋ 即座に重量表示増減 (±2.5kg)<br>---<br>変更後重量のTTS発話 (「65キロ」)<br>---<br>電子音 ＋ TTS発話「調整、重量」 ＋ Step 5 へ遷移<br>---<br>内容確認読み上げ |
| **Step 5**<br>(調整完了体験) | なし (全体暗転) | 「［次の曲へ進む］ボタンを押して、調整を完了しましょう」 | ［次の曲へ進む］(87)<br>---<br>その他キー | 電子音 ＋ TTS「確定」 ＋ 続けて「開始、ベンチプレス、65キロ、10回、3セット」 ＋ Step 6 へ自動遷移<br>---<br>案内注意メッセージ表示 |
| **Step 6**<br>(完了と本編スタート) | なし (暗転解除) | 「🎉 チュートリアル完了！」<br>説明文 | メインボタンタップ / キー85<br>---<br>スキップタップ | `TrainingScreen` へ画面遷移 |

---

## 5. 設計結論と実装への提言

1. **ファイル構成**:
   - `lib/tutorial_screen.dart` を完全新規モジュールとして新設。
   - `lib/training_screen.dart` は一切変更しない。
   - `lib/main.dart` は「トレーニング開始」ボタンの直下に「操作チュートリアルを体験する」ボタン（`Key('open_tutorial_button')`）を追加するのみ。
2. **自動テスト構成**:
   - 新規に `test/tutorial_screen_test.dart` を作成し、全6ステップの正常系、スキップ系、疑似キーバー連動、デバウンス、ライフサイクル（`flutterTts.stop`）を網羅するテスト群を構築。
   - 既存の `test/widget_test.dart` と合わせて一括で `flutter test` を実行し、全テストパス（exit code 0）を担保可能。
