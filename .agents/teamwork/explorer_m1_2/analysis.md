# TutorialScreen Visual Presentation, Layout, and Animation Design Report

**Target Module**: `lib/tutorial_screen.dart`  
**Application**: のう筋（noukin_app）  
**Date**: 2026-11-10  
**Author**: explorer_m1_2 (UI Presentation & Animation Design Explorer)

---

## 1. Executive Summary & Architectural Overview

本設計書は、筋トレアプリ「のう筋」の中間発表プレゼン実演（デモ）において、審査員および聴衆に「**スマートフォンをポケットに入れたまま、イヤホンのボタンだけでトレーニングを完結できるコアバリュー（MVP）**」を視覚的・直感的に伝えるためのインタラクティブな操作チュートリアル画面（`TutorialScreen`）の **視覚演出・画面レイアウト・アニメーション詳細設計** を定義したものです。

### 設計の柱
1. **GPU負荷ゼロの差分くり抜きスポットライト（`SpotlightOverlayPainter`）**:
   - `Path.combine(PathOperation.difference, ...)` による全画面半透明ブラック（70% = `Color(0xB3000000)`）の差分減算くり抜きを採用。`saveLayer` によるオフスクリーンバッファを使わず、Impeller / Skia で極めて滑らかに60fps/120fps描画を維持します。
2. **生体的なホタル呼吸発光枠線（Firefly Glow Animation）**:
   - `AnimationController.repeat(reverse: true)`（1200ms周期、`Curves.easeInOut`）と二重の `boxShadow`（ティールアクセント）を組み合わせ、注目要素を呼吸するように発光させます。
   - `Positioned` + `IgnorePointer` のレイヤー構成により、発光装飾が下層ウィジェットのタップ判定を一切阻害しません。
   - テスト安全性引数 `animateGlow: bool = true` を設け、ウィジェットテスト時の無限フレームタイマーによる `pumpAndSettle timed out` を完全防止します。
3. **プレゼン本番の機材トラブル完全防止機構**:
   - 画面右下の常設「スキップ >」ボタン（`Key('btn_tutorial_skip')`）および暗転画面全体のタップフォールバックを実装。実機イヤホン接続やADBコマンドが不安定な場合でも、画面タップでプレゼンを淀みなく進行できます。
4. **最前面の常設疑似メディアキーバー（`_buildMediaControlBar`）**:
   - 暗転オーバーレイの影響を受けない最前面レイヤーに 5ボタン（前曲、再生/停止、次曲、Vol-、Vol+）を配置。PCキーボード、マウスクリック、イヤホン物理ボタンで100%同一のロジックを共有します。

---

## 2. CustomPainter: 半透明ブラック暗転オーバーレイとスポットライトくり抜き

### 2.1 描画仕様と `SpotlightOverlayPainter` 実装

画面全体を黒70%（`Colors.black.withOpacity(0.70)` = `Color(0xB3000000)`）で覆い、注目させたいボタンやカードの座標（`targetRect`）のみを角丸矩形（`RRect`）で100%透過（完全くり抜き）します。

```dart
import 'package:flutter/material.dart';

/// 半透明ブラック（Black 70%）の背景から注目要素の矩形を完全にくり抜く CustomPainter
class SpotlightOverlayPainter extends CustomPainter {
  final Rect? targetRect;
  final double borderRadius;
  final Color overlayColor;
  final EdgeInsets padding;

  SpotlightOverlayPainter({
    required this.targetRect,
    this.borderRadius = 14.0,
    this.overlayColor = const Color(0xB3000000), // Colors.black.withOpacity(0.70)
    this.padding = const EdgeInsets.all(4.0),
  });

  @override
  void paint(Canvas canvas, Size size) {
    final fullRect = Offset.zero & size;
    final bgPaint = Paint()..color = overlayColor;

    // 注目要素がない場合（Step 1案内、Step 5全体暗転など）は全画面を塗りつぶし
    if (targetRect == null || targetRect!.isEmpty) {
      canvas.drawRect(fullRect, bgPaint);
      return;
    }

    final backgroundPath = Path()..addRect(fullRect);

    // 要素の境界にわずかな呼吸余白（padding）を持たせた角丸矩形
    final inflatedRect = Rect.fromLTRB(
      targetRect!.left - padding.left,
      targetRect!.top - padding.top,
      targetRect!.right + padding.right,
      targetRect!.bottom + padding.bottom,
    );

    final holePath = Path()
      ..addRRect(RRect.fromRectAndRadius(
        inflatedRect,
        Radius.circular(borderRadius),
      ));

    // 全画面矩形から穴矩形を減算合成（difference）
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
        oldDelegate.overlayColor != overlayColor ||
        oldDelegate.padding != padding;
  }
}
```

### 2.2 座標取得（Coordinate Resolution）メカニズム

注目対象要素（中央ボタン、各調整カード）は画面レイアウト内に配置されており、画面サイズやステータスバー高さにより座標が変動します。
以下の堅牢な座標解決フローを実装します：

1. **`GlobalKey` の付与**:
   - `_startBtnKey = GlobalKey()`
   - `_exerciseCardKey = GlobalKey()`
   - `_weightCardKey = GlobalKey()`
   - `_repsCardKey = GlobalKey()`
   - `_setsCardKey = GlobalKey()`
   - ルート `Stack` に `_stackKey = GlobalKey()` を付与。
2. **`addPostFrameCallback` による座標更新**:
   ステップ切り替え時や画面再描画完了後に、ルート `Stack` に対する相対座標（`globalToLocal`）を算出します。
   ```dart
   void _updateSpotlightRect() {
     WidgetsBinding.instance.addPostFrameCallback((_) {
       if (!mounted) return;
       final targetKey = _getCurrentTargetKey();
       if (targetKey == null || targetKey.currentContext == null) {
         if (_spotlightRect != null) {
           setState(() => _spotlightRect = null);
         }
         return;
       }

       final renderBox = targetKey.currentContext!.findRenderObject() as RenderBox?;
       final stackBox = _stackKey.currentContext?.findRenderObject() as RenderBox?;
       if (renderBox != null && renderBox.hasSize && stackBox != null) {
         final globalPos = renderBox.localToGlobal(Offset.zero);
         final localPos = stackBox.globalToLocal(globalPos);
         final newRect = localPos & renderBox.size;
         if (_spotlightRect != newRect) {
           setState(() => _spotlightRect = newRect);
         }
       }
     });
   }
   ```
3. **初回フレームのフォールバック**:
   初回描画完了前（1フレーム目）は `_spotlightRect == null` となり全画面暗転が描画されます。フレーム完了と同時に `_updateSpotlightRect()` が走り、瞬時にくり抜きが適用されます。

---

## 3. Breathing Firefly Glow Animation（ホタルの呼吸発光枠線）

### 3.1 視覚デザインと光彩パラメータ

注目要素の輪郭が、夏のホタルの光のように柔らかく膨張・収縮（明滅）する演出です。
- **カラー**: `AppColors.tealAccent`（`Colors.tealAccent` = `#64FFDA`）
- **周期**: 1200ms（往復で1呼吸: 600ms吸気、600ms呼気）
- **アニメーションカーブ**: `Curves.easeInOut`
- **二重光彩レイヤー（`BoxShadow`）**:
  - コア光彩（内側・高輝度）:
    - color: `AppColors.tealAccent.withOpacity(0.35 + 0.35 * t)` (0.35〜0.70)
    - blurRadius: `8.0 + 12.0 * t` (8px〜20px)
    - spreadRadius: `1.5 + 2.5 * t` (1.5px〜4.0px)
  - 環境オーラ（外側・淡い拡散光）:
    - color: `AppColors.tealAccent.withOpacity(0.12 + 0.18 * t)` (0.12〜0.30)
    - blurRadius: `22.0 + 12.0 * t` (22px〜34px)
    - spreadRadius: `4.0 + 4.0 * t` (4.0px〜8.0px)
  - ボーダー枠線:
    - color: `AppColors.tealAccent.withOpacity(0.5 + 0.5 * t)` (0.50〜1.00)
    - width: `2.0 + 1.0 * t` (2.0px〜3.0px)

### 3.2 レイヤー構成と `IgnorePointer` の重要性

発光エフェクトは、くり抜かれた `targetRect` の直上に `Positioned` で重ねます。
このとき **必ず `IgnorePointer` でラップ** します。
これにより、ユーザーや発表者がスポットライト枠内のボタンやカードを直接タップした際、タップ判定が下層のボタンへ100%透過し、確実に入力が受け付けられます。

```dart
Widget _buildGlowOverlay() {
  if (_spotlightRect == null) return const SizedBox.shrink();

  final inflated = Rect.fromLTRB(
    _spotlightRect!.left - 4.0,
    _spotlightRect!.top - 4.0,
    _spotlightRect!.right + 4.0,
    _spotlightRect!.bottom + 4.0,
  );

  return Positioned(
    left: inflated.left,
    top: inflated.top,
    width: inflated.width,
    height: inflated.height,
    child: IgnorePointer(
      child: AnimatedBuilder(
        animation: _glowAnimation,
        builder: (context, _) {
          final t = widget.animateGlow ? _glowAnimation.value : 1.0;
          return Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16.0),
              border: Border.all(
                color: AppColors.tealAccent.withOpacity(0.5 + 0.5 * t),
                width: 2.0 + 1.0 * t,
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.tealAccent.withOpacity(0.35 + 0.35 * t),
                  blurRadius: 8.0 + 12.0 * t,
                  spreadRadius: 1.5 + 2.5 * t,
                ),
                BoxShadow(
                  color: AppColors.tealAccent.withOpacity(0.12 + 0.18 * t),
                  blurRadius: 22.0 + 12.0 * t,
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

### 3.3 テスト安全設計（`animateGlow: bool = true`）

Flutter の `AnimationController.repeat()` は、終了のない連続フレームタイマーを生成します。そのため、ウィジェットテスト環境で `await tester.pumpAndSettle()` を実行すると、フレーム更新が止まらず **「pumpAndSettle timed out」** が発生します。

これを防止するため、`TutorialScreen` のコンストラクタ引数に `animateGlow: bool = true` を設けます：
```dart
@override
void initState() {
  super.initState();
  _glowController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );
  if (widget.animateGlow) {
    _glowController.repeat(reverse: true);
  } else {
    // テスト時はリピートを開始せず、固定値 1.0 で発光枠線を表示
    _glowController.value = 1.0;
  }
  _glowAnimation = CurvedAnimation(
    parent: _glowController,
    curve: Curves.easeInOut,
  );
}
```
- **本番アプリ実行時**: `animateGlow: true`（デフォルト）により、呼吸する美しいホタルアニメーションが動作。
- **自動テスト実行時**: `TutorialScreen(animateGlow: false, ...)` を注入することで、未完了タイマーをゼロに保ち、`tester.pumpAndSettle()` を安全に使用可能。

---

## 4. 全6ステップのビジュアルカードとスポットライト設計

画面全体の構成は、下層に「トレーニング画面レイアウト」、中層に「スポットライト暗転オーバーレイ＆発光枠線」、上層に「案内フローティングカード＆スキップボタン＆最下部メディアキーバー」を配置する 3層スタック構造とします。

```
┌────────────────────────────────────────────────────────┐
│ [上層 3] 案内カード (Floating Guidance Card)           │
├────────────────────────────────────────────────────────┤
│ [中層 2] スポットライト暗転 (70% Black) ＋ ホタル発光  │
├────────────────────────────────────────────────────────┤
│ [下層 1] トレーニング画面（画像、種目名、重量、回数）  │
├────────────────────────────────────────────────────────┤
│ [上層 3] スキップボタン (右下) ＋ 仮想メディアキーバー │
└────────────────────────────────────────────────────────┘
```

各ステップのビジュアルとフォーカス要素の詳細は以下の通りです：

### Step 1: 開始画面（Intro Screen）
- **スポットライト対象**: `null`（暗転なし、専用の全画面紹介カードを表示）
- **ビジュアル構成**:
  - 中央配置の洗練されたカード（`Card`、背景色: `AppColors.surface`、角丸 16px、枠線: `AppColors.border`）
  - アイコン: 大きなダンベルアイコン（`Icons.fitness_center`、色: `AppColors.tealAccent`、サイズ 56）
  - タイトル: 「のう筋 操作チュートリアル」（フォントサイズ 22、太字、白）
  - 説明文:
    > 「スマートフォンをポケットに入れたまま、イヤホンのボタン操作だけでトレーニングを開始・調整・進行する体験を約1分で学べます。」
  - 操作概要のリスト表示:
    - 🎧 **［再生/停止］**: トレーニング開始 / 次へ
    - ⏭️ **［次の曲］**: 重量・回数の調整モード切替
    - 🔊 **［音量＋/−］**: 数値の増減・項目選択
    - ⏮️ **［前の曲］**: 種目内容の音声安全確認
  - メインボタン: 「チュートリアルを開始する」（`Key('btn_start_tutorial_flow')`、背景色: `AppColors.primaryAccent`、文字色: 黒、高さ 50）
  - サブボタン: 「スキップして直接トレーニングへ」（`Key('btn_skip_to_training')`、`TextButton`、文字色: `AppColors.textSecondary`）
- **キー・操作受付**:
  - メインボタンタップ または キー85（再生/停止） ➔ Step 2 へ遷移。
  - サブボタンタップ ➔ `Navigator.pushReplacement` で本編 `TrainingScreen` へ直行。

### Step 2: 開始操作体験（Start Operation Experience）
- **スポットライト対象**: 中央の「開始」ボタン（`Key('btn_next_workout')`）
- **ビジュアル構成**:
  - 背景にトレーニング画面（ベンチプレス画像、種目名、60kg等）を暗転70%で表示。
  - 中央の「開始」ボタンのみが丸ごとくり抜かれ、周囲にホタルの呼吸発光枠線が明滅。
  - スポットライトの上部にフローティング案内カードを表示：
    - ステップバッジ: 「STEP 1/5」
    - ガイダンステキスト: 「イヤホンの［再生/停止］ボタンを押してトレーニングを始めてみましょう」（`Key('text_step2_guidance')`）
    - 視覚ヒント: `Icons.headphones` ＋ `Icons.play_arrow`
- **キー・操作受付**:
  - キー85（再生/停止）、中央「開始」ボタンタップ、または画面タップ / スキップボタン：
    1. `soundEffectService.playBeep()`
    2. 暗転フェードアウト
    3. `flutterTts.stop()` ➔ `flutterTts.speak("開始、ベンチプレス、60キロ、10回、3セット")`
    4. 発話開始後（または完了時）、Step 3 へ自動遷移。
  - その他のキー（24, 25, 87, 88）：無反応（誤操作を完全遮断）。

### Step 3: 調整モード突入＆項目選択（Adjustment Mode Entry & Item Selection）
Step 3 は、2つの連続したフェーズ（Part 1 と Part 2）で構成されます。

#### Step 3 Part 1（調整モード突入）:
- **スポットライト対象**: 画面上部の「種目名」（ベンチプレス表示領域）
- **ビジュアル構成**:
  - フローティング案内カード：
    - ステップバッジ: 「STEP 2/5 (1/2)」
    - ガイダンステキスト: 「イヤホンの［次の曲へ進む］ボタンを押して、調整モードに入りましょう」（`Key('text_step3_guidance_part1')`）
    - 視覚ヒント: `Icons.skip_next`（ティール発光アイコン）
- **キー・操作受付**:
  - キー87（次の曲へ進む）：
    1. `soundEffectService.playBeep()`
    2. `flutterTts.stop()` ➔ `flutterTts.speak("調整、種目名")`
    3. 種目名枠がハイライトされ、Part 2 へ自動切り替え。
  - キー88（前の曲）：安全読み上げ「ベンチプレス、60キロ、10回、3セット」。

#### Step 3 Part 2（項目選択）:
- **スポットライト対象**: 現在選択中の項目カード（種目名 ⇄ 重量 ⇄ レップ数 ⇄ セット数）
  - 初期選択: 「種目名」
  - 音量＋/−キーの押下に合わせて、スポットライトとホタル発光枠線がスムーズに該当カードへジャンプ移動！
- **ビジュアル構成**:
  - フローティング案内カード：
    - ステップバッジ: 「STEP 2/5 (2/2)」
    - ガイダンステキスト: 「［音量＋/−］で項目を切り替え、［再生/停止］で決定してください」（`Key('text_step3_guidance_part2')`）
    - 視覚ヒント: `Icons.volume_up` ➔ `Icons.play_arrow`
- **キー・操作受付**:
  - キー24/25（音量＋/−）：
    1. `soundEffectService.playBeep()`
    2. 選択インデックスを移動（種目名 ⇄ 重量 ⇄ レップ数 ⇄ セット数）
    3. スポットライト位置を更新（`_updateSpotlightRect()`）
    4. `flutterTts.stop()` ➔ 選択された項目名を発話（「重量」「レップ数」等）
  - キー85（再生/停止）：
    1. 「重量」選択時（または決定時）に `soundEffectService.playBeep()`
    2. `flutterTts.stop()` ➔ 現在値を発話（「60キロ」）
    3. Step 4 へ遷移！
  - キー88（前の曲）：安全読み上げ「ベンチプレス、60キロ、10回、3セット」。

### Step 4: 重量調整とデバウンス体験（Weight Adjustment & Debounce）
- **スポットライト対象**: 「重量」カードのみ（`Key('card_weight')`、初期値「60.0 kg」）
- **ビジュアル構成**:
  - 重量カード以外の全領域を黒70%で暗転。
  - 重量カードの左右にある［−］［＋］ボタンおよび中央の「60.0 kg」数値が鮮やかにくり抜かれ、発光枠線で包まれます。
  - フローティング案内カード：
    - ステップバッジ: 「STEP 3/5: 連打と音声の仕組み」
    - ガイダンステキスト: 「［音量＋/−］で重量を調整（連打対応）。指を離して0.7秒後に最新の重量を読み上げます。終わったら［再生/停止］で決定。」（`Key('text_step4_guidance')`）
    - 連打ヒント: 「💡 連打中は画面がリアルタイムに更新され、最後の1回だけ発話されます」
- **キー・操作受付**:
  - キー24（音量UP）：
    1. `soundEffectService.playBeep()`
    2. 画面上の重量表示を即座に +2.5kg 加算（60.0 ➔ 62.5 ➔ 65.0kg）
    3. 保留中の 0.7秒デバウンスタイマーをリセット（`_debounceTimer?.cancel()`）
    4. 0.7秒間キー入力が途切れた時点で `flutterTts.stop()` ➔ `flutterTts.speak("${weight.toInt()}キロ")`（例: 「65キロ」）
  - キー25（音量DOWN）：
    1. `soundEffectService.playBeep()`
    2. 画面上の重量表示を即座に -2.5kg 減算（0.0kg 未満にはクランプ）
    3. 0.7秒デバウンスタイマーをリセット＆タイマー完了時に発話。
  - キー85（再生/停止）：
    1. 保留中のデバウンスタイマーを即座に破棄（遅延音声がStep 5に漏れるのを防止）
    2. `soundEffectService.playBeep()`
    3. `flutterTts.stop()` ➔ `flutterTts.speak("調整、重量")`
    4. Step 5 へ遷移！
  - キー88（前の曲）：安全読み上げ。

### Step 5: 調整完了の体験（Adjustment Completion）
- **スポットライト対象**: `null`（全画面暗転70%）
- **ビジュアル構成**:
  - 画面中央に配置された調整完了カード（`Card`、角丸 16px、枠線: `AppColors.tealAccent`）
  - アイコン: 円形に囲まれた大きな次曲アイコン（`Icons.skip_next`、サイズ 48、色: `AppColors.tealAccent`）
  - ステップバッジ: 「STEP 4/5: 調整の完了」
  - ガイダンステキスト: 「イヤホンの［次の曲へ進む］ボタンを押して、調整を完了しましょう」（`Key('text_step5_guidance')`）
  - 説明文: 「調整モードが解除され、更新された種目・重量でトレーニングが再開されます。」
- **キー・操作受付**:
  - キー87（次の曲へ進む）：
    1. `soundEffectService.playBeep()`
    2. `flutterTts.stop()` ➔ `flutterTts.speak("確定")`
    3. 続けて発話: `「開始、ベンチプレス、${weight.toInt()}キロ、10回、3セット」`（例: 65キロ）
    4. 発話開始後、Step 6 へ自動遷移！
  - その他のキー（85, 24, 25, 88）：
    - 状態は遷移せず、案内文「［次の曲へ進む］ボタンを押して調整を完了してください」（`Key('text_step5_notice')`）を強調表示。

### Step 6: 完了と本編スタート（Celebration & Handoff）
- **スポットライト対象**: `null`（暗転オーバーレイは完全解除）
- **ビジュアル構成**:
  - 祝福演出カード（`Key('card_step6_celebration')`）
  - トップ絵文字・アイコン: 🎉 （クラッカー絵文字 / `Icons.emoji_events`、サイズ 54、ゴールド）
  - タイトル: 「チュートリアル完了！」（`Key('text_tutorial_completed_title')`、フォントサイズ 24、太字、白）
  - サブタイトル: 「イヤホン操作の準備が整いました」
  - 学習した操作のおさらいリスト（チェックマーク付き）:
    - ✅ **開始 / 次へ**: ［再生/停止］ボタン
    - ✅ **調整モード**: ［次の曲］ボタンでON/OFF
    - ✅ **重量・回数変更**: ［音量＋/−］ボタン（連打可能）
    - ✅ **内容の確認**: ［前の曲］ボタン（いつでも安全）
  - メインアクションボタン:
    - ラベル: 「最初のトレーニングを開始する」（`Key('btn_start_workout_after_tutorial')`）
    - スタイル: 背景色 `AppColors.tealAccent`、文字色 `Colors.black`、高さ 52、アイコン `Icons.play_arrow`
- **キー・操作受付**:
  - メインボタンタップ または キー85（再生/停止）：
    - `Navigator.of(context).pushReplacement` で本編 `TrainingScreen` へ遷移！

---

## 5. 発表用スキップ機能とデモ安全設計

中間発表の実演において、Bluetoothイヤホンの接続遅延やペアリング断、ADBコマンドの送信エラーなどの機材トラブルが起きても、発表がストップしないよう **3重のセーフティネット** を組み込みます。

### 5.1 右下常設スキップボタン（`Key('btn_tutorial_skip')`）
- **配置**: 画面右下、仮想メディアキーバーの直上に固定配置（`Positioned(right: 16, bottom: 74, child: ...)`）。
- **デザイン**:
  - 聴衆の注意を奪わない、半透明で控えめなカプセルデザイン。
  - `TextButton.icon`、背景色: `Color(0x33FFFFFF)`、角丸: 20px。
  - アイコン: `Icons.fast_forward`、文字: 「スキップ >」、文字色: `Colors.white70`、フォントサイズ 13。
- **表示ステップ**: Step 2、Step 3、Step 4、Step 5。
- **動作**:
  - 押下されると、現在のステップの音声・タイマーを即座に破棄し、確定的に次のステップへジャンプします。
  - 連打防止フラグ（`_isTransitioning`）により、誤って複数回タップしても安全に処理されます。

### 5.2 Step 1 の直行ボタン（`Key('btn_skip_to_training')`）
- Step 1 の案内カード下部に配置された「スキップして直接トレーニングへ」。
- デモの持ち時間が逼迫している場合、チュートリアル全体をバイパスして即座に本編 `TrainingScreen` へ遷移可能です。

### 5.3 暗転領域の画面タップフォールバック
- 暗転オーバーレイ（`SpotlightOverlayPainter`）の背後に `GestureDetector(behavior: HitTestBehavior.translucent, onTap: _onScreenTapped)` を配置。
- 発表者が実機の画面を軽くタップするだけでも、該当ステップの操作（キー85またはスキップ）とみなしてスムーズに次へ進めます。

---

## 6. 画面最下部：疑似メディアキーバー（`_buildMediaControlBar`）

PCエミュレータ検証、マウス操作、およびイヤホン不調時の手動操作を可能にするため、`TrainingScreen` の実績あるレイアウトと完全互換の 5ボタンバーを実装します。

### 6.1 Z-Index レイヤー配置の鉄則
**重要**: 疑似メディアキーバーは、暗転オーバーレイ（`SpotlightOverlayPainter`）の下に入れてはなりません。
必ず `Stack` の最前面（オーバーレイの上）に配置し、暗転中であっても常に 100% の輝度と明瞭さで操作できるようにします。

### 6.2 レイアウトとコンポーネント構成
```dart
Widget _buildMediaControlBar() {
  final (modeLabel, volLabel) = _getMediaBarLabels();

  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: const BoxDecoration(
      color: AppColors.surface,
      border: Border(top: BorderSide(color: AppColors.border, width: 1.0)),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ガイダンスインジケータ行
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              modeLabel,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: AppColors.tealAccent,
              ),
            ),
            Text(
              volLabel,
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textTertiary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        // 5つのメディア操作ボタン
        Row(
          children: [
            _buildMediaBarButton(
              buttonKey: const Key('btn_media_prev'),
              icon: Icons.skip_previous,
              label: '前曲 (内容確認)',
              onTap: () => _handleButtonAction(ButtonAction.mediaPrevious),
            ),
            const SizedBox(width: 4),
            _buildMediaBarButton(
              buttonKey: const Key('btn_media_play_pause'),
              icon: Icons.play_arrow,
              label: '再生/停止 (決定/次へ)',
              isPrimary: true,
              onTap: () => _handleButtonAction(ButtonAction.mediaPlayPause),
            ),
            const SizedBox(width: 4),
            _buildMediaBarButton(
              buttonKey: const Key('btn_media_next'),
              icon: Icons.skip_next,
              label: '次曲 (調整/完了)',
              onTap: () => _handleButtonAction(ButtonAction.mediaNext),
            ),
            const SizedBox(width: 4),
            _buildMediaBarButton(
              buttonKey: const Key('btn_media_vol_down'),
              icon: Icons.volume_down,
              label: 'Vol-',
              onTap: () => _handleButtonAction(ButtonAction.volumeDown),
            ),
            const SizedBox(width: 4),
            _buildMediaBarButton(
              buttonKey: const Key('btn_media_vol_up'),
              icon: Icons.volume_up,
              label: 'Vol+',
              onTap: () => _handleButtonAction(ButtonAction.volumeUp),
            ),
          ],
        ),
      ],
    ),
  );
}
```

### 6.3 ボタン状態とヒント表示の動的切り替え
- **Step 2**: `modeLabel = "［チュートリアル］Step 1: 開始操作体験"`, `volLabel = "音量キー: 無効"`
- **Step 3 (Part 1)**: `modeLabel = "［チュートリアル］Step 2: 調整モード起動"`, `volLabel = "音量キー: 無効"`
- **Step 3 (Part 2)**: `modeLabel = "［チュートリアル］Step 2: 項目選択"`, `volLabel = "音量キー: 項目切り替え"`
- **Step 4**: `modeLabel = "［チュートリアル］Step 3: 重量調整（連打デバウンス）"`, `volLabel = "音量キー: 重量±2.5kg"`
- **Step 5**: `modeLabel = "［チュートリアル］Step 4: 調整完了操作"`, `volLabel = "音量キー: 無効"`
- **Step 6**: `modeLabel = "［チュートリアル］Step 5: 完了"`, `volLabel = "音量キー: 無効"`

---

## 7. Concrete Implementation Guidelines for Worker

Worker が `lib/tutorial_screen.dart` を実装する際に準拠すべき具体的なクラス構成とライフサイクル設計です。

### 7.1 クラス宣言と依存性注入（DI）
```dart
class TutorialScreen extends StatefulWidget {
  final TtsService? ttsService;
  final SoundEffectService? soundEffectService;
  final AudioDuckingController? duckingController;
  final bool animateGlow;

  const TutorialScreen({
    super.key,
    this.ttsService,
    this.soundEffectService,
    this.duckingController,
    this.animateGlow = true,
  });

  @override
  State<TutorialScreen> createState() => _TutorialScreenState();
}
```

### 7.2 ステート列挙型と状態変数
```dart
enum TutorialStep {
  step1Intro,
  step2Start,
  step3SelectTarget,
  step4AdjustWeight,
  step5FinishAdjustment,
  step6Completed,
}

enum TutorialStep3Phase {
  part1Enter,
  part2Select,
}
```
主要な状態変数：
- `TutorialStep _currentStep = TutorialStep.step1Intro;`
- `TutorialStep3Phase _step3Phase = TutorialStep3Phase.part1Enter;`
- `AdjustmentTarget _selectedTarget = AdjustmentTarget.exerciseName;`
- `double _weight = 60.0;`
- `Rect? _spotlightRect;`
- `Timer? _debounceTimer;`
- `bool _isTransitioning = false;`

### 7.3 音声発話の共通メソッド（R2要件の厳守）
```dart
Future<void> _speak(String text) async {
  // 前の発話を中断（重複防止）
  await widget.ttsService?.stop();
  // ダッキング要求
  await widget.duckingController?.requestDucking();
  // 発話
  await widget.ttsService?.speak(text);
}
```

### 7.4 0.7秒デバウンスタイマーの処理
```dart
void _onWeightAdjusted(double delta) {
  widget.soundEffectService?.playBeep();
  setState(() {
    _weight = (_weight + delta).clamp(0.0, 300.0);
  });

  _debounceTimer?.cancel();
  _debounceTimer = Timer(const Duration(milliseconds: 700), () {
    if (!mounted) return;
    _speak('${_weight.toInt()}キロ');
  });
}
```
※ Step 4 から Step 5 への遷移時、スキップ時、および `dispose()` 時には必ず `_debounceTimer?.cancel()` を呼び出します。

### 7.5 キーイベントリスナーの登録と破棄
```dart
@override
void initState() {
  super.initState();
  // ハードウェアキー（イヤホン／ADB）の購読
  KeyEventChannelDispatcher.instance.registerListener(_handleButtonAction);
  // アニメーション初期化
  ...
}

@override
void dispose() {
  KeyEventChannelDispatcher.instance.unregisterListener(_handleButtonAction);
  _debounceTimer?.cancel();
  _glowController.dispose();
  widget.ttsService?.stop();
  widget.duckingController?.releaseDucking();
  _keyboardFocusNode.dispose();
  super.dispose();
}
```

---

## 8. 結論

本設計により、発表デモにおける**「スマホを見ずにイヤホンだけで操作できる直感的な体験」**を、
1. 半透明ブラック70%と差分くり抜きスポットライト（`SpotlightOverlayPainter`）
2. 呼吸するホタル発光枠線（`AnimationController` ＋ `boxShadow`）
3. 発表トラブルを防ぐ 3重のスキップ・タップフォールバック
4. 暗転の影響を受けない最前面の疑似メディアキーバー
の組み合わせによって、最高の描画品質・堅牢性・テスト容易性で実現できます。
Worker は本設計書および `handoff.md` に従って実装を進めることが可能です。
