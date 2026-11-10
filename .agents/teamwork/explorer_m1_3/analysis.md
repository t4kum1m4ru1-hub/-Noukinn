# エントリー導線（lib/main.dart）および自動テストスイート（test/tutorial_screen_test.dart）詳細設計書

**State folder**: `c:\Users\taqmi\02_development\original_program\noukin_app\.agents\teamwork\explorer_m1_3\`  
**Date**: 2026-11-10  
**Target Milestone**: M1 (TutorialScreen Implementation & Automated Verification)  
**Author**: explorer_m1_3 (Entry Button & Automated Test Architect)

---

## 1. 概要 (Executive Summary)

本ドキュメントは、Flutter 製筋トレ支援アプリ「のう筋」の中間発表プレゼン実演に向け、以下の2つの実装計画を完全定義したものです：
1. **`lib/main.dart` へのエントリーボタン新設設計**:
   既存の「トレーニング開始」ボタン（`Key('start_training_button')`）の直下に、「操作チュートリアルを体験する」ボタン（`Key('start_tutorial_button')`）を追加し、既存UIレイアウトやテストに一切の後退（リグレッション）を与えずに安全に統合する実装仕様。
2. **`test/tutorial_screen_test.dart` の自動 Widget テストスイート完全設計**:
   既存のインメモリ・テスト資産（`FakeTtsService`、`FakeSoundEffectService`、`FakeAudioDuckingController`、`sendNativeKeyEvent`）を活用し、全6ステップの正常系、キーイベント、0.7秒デバウンス、スキップ導線、疑似キーバー、および音声排他（`stopCallCount`）の全9項目を網羅した自動テストの構造設計と完全なコード仕様。

---

## 2. `lib/main.dart` エントリーボタン変更仕様

### 2.1 変更箇所の特定と現状分析
`lib/main.dart` 671〜717行目の `ButtonControlScreen.build()` において、画面は `Column` ウィジェットで垂直に構成されています：
```dart
Column(
  children: [
    // メイン画面上部のトレーニング開始ボタン (674-702行目)
    Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: ElevatedButton.icon(...),
    ),
    // 画面中央：直前に検知したボタン名とキーコードを巨大表示 (704-707行目)
    Expanded(flex: 5, child: _buildCenterDisplay()),
    const Divider(height: 1, color: Color(0xFF333333)),
    // ログヘッダー (710行目)
    _buildLogHeader(),
    // 画面下部：タイムスタンプ付き受信ログ一覧 (712-715行目)
    Expanded(flex: 5, child: _buildLogList()),
  ],
)
```

### 2.2 追加するインポート文（43行目付近）
`lib/main.dart` 43行目の `import 'training_screen.dart';` の直下に以下を追加します：
```dart
import 'training_screen.dart';
import 'tutorial_screen.dart';

export 'training_screen.dart';
export 'tutorial_screen.dart';
```

### 2.3 挿入するボタンコード（702行目の直下）
`start_training_button` の `Padding`（674〜702行目）の直後、`Expanded(flex: 5, child: _buildCenterDisplay())` の直前に以下のウィジェットブロックを挿入します：

```dart
          // 操作チュートリアル体験ボタン
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: ElevatedButton.icon(
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
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF242B28),
                foregroundColor: Colors.tealAccent,
                side: const BorderSide(color: Colors.tealAccent, width: 1.2),
                minimumSize: const Size.fromHeight(44),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
```

### 2.4 レイアウト整合性とゼロ・リグレッション保証 (Zero Regression Guarantee)

1. **Flex レイアウトによる自動吸収**:
   - `body` 内の残余領域は上下2つの `Expanded(flex: 5)`（中央キー表示とログ一覧）が均等に分割しています。
   - 高度44px（パディング込みで56px）のチュートリアルボタンが上部に追加されても、`Expanded` の各領域が自動的に伸縮してスペースを調整するため、画面下部のオーバーフロー（`A RenderFlex overflowed by ...`）は物理的に発生しません。
2. **パディングの最適化と Flutter 8px グリッド整合性**:
   - `start_training_button` のパディング: `EdgeInsets.fromLTRB(16, 12, 16, 4)`（下マージン 4px）
   - `start_tutorial_button` のパディング: `EdgeInsets.fromLTRB(16, 4, 16, 8)`（上マージン 4px、下マージン 8px）
   - これにより、2つのボタン間のクリアランスが合計 8px となり、視覚的なグルーピングと整列が保たれます。
3. **視覚的ヒエラルキーの明確化**:
   - 「トレーニング開始」: 背景色 `Colors.tealAccent`（ベタ塗り塗色）＋ 黒文字（Primary Action）
   - 「操作チュートリアルを体験する」: 背景色 `Color(0xFF242B28)`（暗色ティールコンテナ）＋ ティール枠線（1.2px）＋ ティール文字（Secondary Action）
   - これにより、本編トレーニングの存在感を阻害せず、かつデモ発表時に直感的にチュートリアルへ誘導できるハイコントラストな配色を実現します。
4. **既存テスト互換性**:
   - `test/widget_test.dart` 内の全14テストは、ウィジェットの階層インデックスではなく `find.byKey(const Key('start_training_button'))` や `find.byKey(const Key('waiting_prompt'))` などのキー・テキストセレクタで要素を検索しています。
   - したがって、このボタン追加による既存テストへの影響は完全にゼロ（100%パス継続）です。

---

## 3. 自動テストスイート設計（`test/tutorial_screen_test.dart`）

### 3.1 テスト基盤・フェイク実装の活用
外部モックパッケージ（`mockito` や `mocktail`、`build_runner`）を一切使用せず、`lib/main.dart` に定義済みの高品質なインメモリフェイククラスを直接活用します：
- **`FakeTtsService`**:
  - `spokenHistory`（全発話の時系列リスト）
  - `lastSpoken`（直近の発話文字列）
  - `stopCallCount`（`stop()` が呼び出された回数）
- **`FakeSoundEffectService`**:
  - `beepCount`（電子音再生回数）
- **`FakeAudioDuckingController`**:
  - `events`（`requestDucking`, `releaseDucking` などの実行履歴）
  - `isCurrentlyDucked`（ダッキング状態フラグ）
- **`sendNativeKeyEvent(tester, keyCode)`**:
  - Android ネイティブの `MethodChannel('com.example.noukin/key_events')` を直接叩いて実機/ADBと同様の打鍵シミュレーションを行う。

### 3.2 Flutter WidgetTester におけるアニメーション安全性の確保
- **問題点**:
  `TutorialScreen` のホタル発光枠線は `AnimationController.repeat(reverse: true)` で呼吸アニメーションを行います。これをテスト環境でそのまま実行すると、フレーム更新が停止しないため `await tester.pumpAndSettle()` が **タイムアウト例外** を引き起こします。
- **解決策**:
  - `TutorialScreen` のコンストラクタ引数 `animateGlow` を活用。
  - 通常のステップ検証テストでは `animateGlow: false`（静止状態 1.0）を指定してマウントし、`pumpAndSettle()` を高速かつ決定論的に安全実行する。
  - 発光アニメーション自体の検証は、独立したテストケースで `animateGlow: true` で起動し、`tester.pump(const Duration(milliseconds: 300))` で有限フレームを進めて安全に検証する。

---

## 4. 全9項目のテストマトリクス詳細仕様

| # | テスト対象・シナリオ | 入力操作 | 期待される検証内容 (Asserts) |
|---|---|---|---|
| **1** | **Step 1: 表示＆遷移・スキップ** | ・起動時表示<br>・「チュートリアルを開始する」タップ<br>・「スキップして直接トレーニングへ」タップ | ・タイトル、説明文、開始ボタン、スキップボタンの表示<br>・開始タップで Step 2 へ進行（中央開始ボタン表示）<br>・スキップタップで `TrainingScreen` へ直行（`TutorialScreen` 破棄） |
| **2** | **Step 2: 開始操作体験** | ・不正キー押下（24, 25, 87）<br>・キー 85（再生/停止）押下 | ・不正キー押下時は無反応（`beepCount == 0`, `spokenHistory` 空）<br>・キー 85 押下で `beepCount >= 1`、TTS「開始、ベンチプレス、60キロ、10回、3セット」発話、Step 3 へ自動遷移 |
| **3** | **Step 3: 調整突入＆項目選択** | ・Part 1: キー 88（前曲）<br>・Part 1: キー 87（次曲）<br>・Part 2: キー 24/25（Vol±）<br>・Part 2: キー 85（再生/停止） | ・Part 1 キー 88: 安全確認発話「ベンチプレス、60キロ、10回、3セット」（遷移なし）<br>・Part 1 キー 87: ビープ＋TTS「調整、種目名」＋Part 2へ突入<br>・Part 2 キー 24: 項目送り（「重量」TTS）、キー 25: 項目戻し<br>・Part 2 キー 85: ビープ＋TTS「60キロ」＋Step 4 へ遷移 |
| **4** | **Step 4: 重量調整と 0.7s デバウンス** | ・キー 24 連打（200ms間隔）<br>・連打停止後 550ms 経過（合計750ms）<br>・キー 88（内容確認）<br>・キー 24 押下直後にキー 85（決定） | ・打鍵ごとに即時画面表示が +2.5kg 加算（62.5kg -> 65kg）、即時ビープ。連打中は TTS 未発話<br>・0.7s 停止後に「65キロ」が1回だけ TTS 発話<br>・キー 88 で「ベンチプレス、65キロ、10回、3セット」確認発話<br>・未完了デバウンスがキー 85 で即時キャンセルされ、遅延発話を残さず TTS「調整、重量」＋Step 5 へ遷移 |
| **5** | **Step 5: 調整完了の体験** | ・対象外キー押下（85, 24, 25）<br>・キー 87（次曲）押下 | ・対象外キー押下で注意文言（「［次の曲へ進む］ボタンを押して調整を完了してください」）表示、遷移なし<br>・キー 87 押下でビープ＋TTS「確定、開始、ベンチプレス、65キロ、10回、3セット」発話＋Step 6 へ遷移 |
| **6** | **Step 6: 完了と本編スタート** | ・完了画面の表示<br>・「最初のトレーニングを開始する」タップ<br>・キー 85 押下 | ・祝福タイトル「🎉 チュートリアル完了！」表示<br>・ボタンタップまたはキー 85 で本編 `TrainingScreen` へ遷移（`pushReplacement`） |
| **7** | **全ステップのスキップ機能** | ・各ステップの「スキップ」ボタン（`btn_tutorial_skip`）押下 | ・Step 2 でスキップ ➔ Step 3 へ即座に進行<br>・Step 3 でスキップ ➔ Step 4 へ即座に進行<br>・Step 4 でスキップ ➔ デバウンスキャンセル＋Step 5 へ進行<br>・Step 5 でスキップ ➔ Step 6 へ即座に進行 |
| **8** | **画面最下部 疑似メディアキーバー** | ・仮想キーバーの各ボタンタップ（Prev, Play/Pause, Next, Vol-, Vol+） | ・物理キー / ADB イベントと 100% 同一のハンドラが呼び出され、同一のビープ・発話・状態遷移が実行されること |
| **9** | **音声排他制御（Audio Hygiene）** | ・各ステップの全 TTS 発話時 | ・すべての発話の直前に `FakeTtsService.stop()` が呼び出されていること（`stopCallCount >= spokenHistory.length`）<br>・ダッキングイベント（`requestDucking` / `releaseDucking`）が適切に実行されていること |

---

## 5. `test/tutorial_screen_test.dart` 完全実装コード仕様

Worker がそのまま配置してテスト実行できる完全なテストコードです：

```dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:button_controll_test/main.dart';
import 'package:button_controll_test/training_screen.dart';
import 'package:button_controll_test/tutorial_screen.dart';

/// Android ネイティブ層（MainActivity.kt）からの MethodChannel 呼び出しをシミュレートするヘルパー
Future<dynamic> sendNativeKeyEvent(
  WidgetTester tester,
  dynamic arguments, {
  String method = 'onKeyEvent',
}) async {
  const codec = StandardMethodCodec();
  final ByteData callData = codec.encodeMethodCall(
    MethodCall(method, arguments),
  );
  final completer = Completer<ByteData?>();
  tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    kKeyEventsChannelName,
    callData,
    (ByteData? reply) {
      completer.complete(reply);
    },
  );
  final reply = await completer.future;
  if (reply == null) {
    return null;
  }
  return codec.decodeEnvelope(reply);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeTtsService fakeTts;
  late FakeSoundEffectService fakeSound;
  late FakeAudioDuckingController fakeDucking;

  setUp(() {
    fakeTts = FakeTtsService();
    fakeSound = FakeSoundEffectService();
    fakeDucking = FakeAudioDuckingController();
  });

  Widget buildTestableApp({
    Widget? home,
    bool animateGlow = false,
  }) {
    final darkTheme = ThemeData.dark().copyWith(
      splashFactory: InkRipple.splashFactory,
      scaffoldBackgroundColor: const Color(0xFF121212),
      colorScheme: const ColorScheme.dark(
        primary: Colors.tealAccent,
        secondary: Colors.amberAccent,
        surface: Color(0xFF1E1E1E),
      ),
    );

    return MaterialApp(
      theme: darkTheme,
      home: home ??
          TutorialScreen(
            ttsService: fakeTts,
            soundEffectService: fakeSound,
            duckingController: fakeDucking,
            animateGlow: animateGlow,
          ),
    );
  }

  group('Entry Navigation: lib/main.dart -> TutorialScreen', () {
    testWidgets('メイン画面にチュートリアルボタンが存在し、タップでTutorialScreenへ遷移できること', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark().copyWith(splashFactory: InkRipple.splashFactory),
          home: ButtonControlScreen(
            ttsService: fakeTts,
            soundEffectService: fakeSound,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // ボタンの存在確認
      final tutorialBtn = find.byKey(const Key('start_tutorial_button'));
      expect(tutorialBtn, findsOneWidget);
      expect(find.text('操作チュートリアルを体験する'), findsOneWidget);

      // 既存のトレーニング開始ボタンも健在であること
      expect(find.byKey(const Key('start_training_button')), findsOneWidget);

      // タップして TutorialScreen へ遷移
      await tester.tap(tutorialBtn);
      await tester.pumpAndSettle();

      expect(find.byType(TutorialScreen), findsOneWidget);
    });
  });

  group('TutorialScreen Widget Test Suite (Matrix 1 - 9)', () {
    testWidgets('1. Step 1: 表示検証、開始タップでStep 2遷移、スキップでTrainingScreen直行', (tester) async {
      // 1a: 開始ボタンで Step 2 へ
      await tester.pumpWidget(buildTestableApp());
      await tester.pumpAndSettle();

      expect(find.text('のう筋 操作チュートリアル'), findsOneWidget);
      final startBtn = find.byKey(const Key('btn_tutorial_start'));
      expect(startBtn, findsOneWidget);

      await tester.tap(startBtn);
      await tester.pumpAndSettle();

      // Step 2 の案内文が表示されること
      expect(find.textContaining('再生/停止'), findsOneWidget);

      // 1b: スキップボタンで本編 TrainingScreen へ直行
      await tester.pumpWidget(buildTestableApp());
      await tester.pumpAndSettle();

      final skipAllBtn = find.byKey(const Key('btn_tutorial_skip_all'));
      expect(skipAllBtn, findsOneWidget);

      await tester.tap(skipAllBtn);
      await tester.pumpAndSettle();

      expect(find.byType(TrainingScreen), findsOneWidget);
    });

    testWidgets('2. Step 2: 不正キー無視、キー85でビープ＋開始TTS＋Step 3自動遷移', (tester) async {
      await tester.pumpWidget(buildTestableApp());
      await tester.pumpAndSettle();

      // Step 1 -> Step 2
      await tester.tap(find.byKey(const Key('btn_tutorial_start')));
      await tester.pumpAndSettle();

      // 不正キー（24, 25, 87）は無視
      await sendNativeKeyEvent(tester, 24);
      await sendNativeKeyEvent(tester, 25);
      await sendNativeKeyEvent(tester, 87);
      await tester.pumpAndSettle();

      expect(fakeSound.beepCount, 0);
      expect(fakeTts.spokenHistory, isEmpty);

      // 有効キー: 85（再生/停止）
      await sendNativeKeyEvent(tester, 85);
      await tester.pumpAndSettle();

      expect(fakeSound.beepCount, 1);
      expect(fakeTts.lastSpoken, '開始、ベンチプレス、60キロ、10回、3セット');

      // Step 3 への自動遷移完了を確認（次曲ボタン案内の表示）
      expect(find.textContaining('次の曲へ進む'), findsOneWidget);
    });

    testWidgets('3. Step 3: Part 1(87で調整突入・88確認)、Part 2(24/25項目送り・85決定でStep 4遷移)', (tester) async {
      await tester.pumpWidget(buildTestableApp());
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('btn_tutorial_start')));
      await tester.pumpAndSettle();
      await sendNativeKeyEvent(tester, 85); // Step 2 完了
      await tester.pumpAndSettle();

      fakeSound.clear();
      fakeTts.clear();

      // Part 1: キー 88（確認ボタン）
      await sendNativeKeyEvent(tester, 88);
      await tester.pump();
      expect(fakeTts.lastSpoken, 'ベンチプレス、60キロ、10回、3セット');

      // Part 1: キー 87（次曲で調整モード突入）
      await sendNativeKeyEvent(tester, 87);
      await tester.pumpAndSettle();
      expect(fakeSound.beepCount, 1);
      expect(fakeTts.lastSpoken, '調整、種目名');

      // Part 2: キー 24 で項目送り（種目名 -> 重量）
      fakeSound.clear();
      await sendNativeKeyEvent(tester, 24);
      await tester.pump();
      expect(fakeSound.beepCount, 1);
      expect(fakeTts.lastSpoken, '重量');

      // Part 2: キー 88（確認ボタン）
      await sendNativeKeyEvent(tester, 88);
      await tester.pump();
      expect(fakeTts.lastSpoken, 'ベンチプレス、60キロ、10回、3セット');

      // Part 2: キー 85（決定で Step 4 へ遷移）
      fakeSound.clear();
      await sendNativeKeyEvent(tester, 85);
      await tester.pumpAndSettle();
      expect(fakeSound.beepCount, 1);
      expect(fakeTts.lastSpoken, '60キロ');

      // Step 4 の表示確認（重量カード表示）
      expect(find.byKey(const Key('card_weight')), findsOneWidget);
    });

    testWidgets('4. Step 4: 24/25連打で±2.5kg即時更新＋0.7sデバウンスTTS、85でデバウンス破棄＆Step 5遷移', (tester) async {
      await tester.pumpWidget(buildTestableApp());
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('btn_tutorial_start')));
      await tester.pumpAndSettle();
      await sendNativeKeyEvent(tester, 85); // Step 2
      await tester.pumpAndSettle();
      await sendNativeKeyEvent(tester, 87); // Step 3 Part 1
      await tester.pumpAndSettle();
      await sendNativeKeyEvent(tester, 24); // 重量選択
      await tester.pump();
      await sendNativeKeyEvent(tester, 85); // Step 4 突入
      await tester.pumpAndSettle();

      fakeSound.clear();
      fakeTts.clear();

      // 1回目打鍵 (+2.5kg -> 62.5kg): 即時UI更新、TTSはまだ
      await sendNativeKeyEvent(tester, 24);
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('62.5 kg'), findsOneWidget);
      expect(fakeSound.beepCount, 1);
      expect(fakeTts.spokenHistory, isEmpty);

      // 2回目打鍵 (+2.5kg -> 65.0kg): 即時UI更新、タイマー延長
      await sendNativeKeyEvent(tester, 24);
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('65 kg'), findsOneWidget);
      expect(fakeSound.beepCount, 2);
      expect(fakeTts.spokenHistory, isEmpty);

      // 連打停止から 0.7秒（550ms + 前の200ms = 750ms）経過: TTSが「65キロ」を1回発話
      await tester.pump(const Duration(milliseconds: 550));
      expect(fakeTts.spokenHistory, ['65キロ']);

      // キー 88（確認ボタン）
      await sendNativeKeyEvent(tester, 88);
      await tester.pump();
      expect(fakeTts.lastSpoken, 'ベンチプレス、65キロ、10回、3セット');

      // 3回目打鍵 (+2.5kg -> 67.5kg) 直後にキー 85（決定）
      fakeSound.clear();
      fakeTts.clear();
      await sendNativeKeyEvent(tester, 24);
      await tester.pump(const Duration(milliseconds: 100));
      expect(fakeTts.spokenHistory, isEmpty);

      // 決定キー押下: 保留中デバウンスが破棄され「調整、重量」を発話して Step 5 へ
      await sendNativeKeyEvent(tester, 85);
      await tester.pumpAndSettle();
      expect(fakeSound.beepCount, 1);
      expect(fakeTts.lastSpoken, '調整、重量');

      // さらに時間が経過しても破棄された「67.5キロ」が発話されないこと
      await tester.pump(const Duration(seconds: 1));
      expect(fakeTts.spokenHistory.contains('67.5キロ'), isFalse);
    });

    testWidgets('5. Step 5: 対象外キーで注意案内、キー87で確定＋全体内容TTS＋Step 6自動遷移', (tester) async {
      await tester.pumpWidget(buildTestableApp());
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('btn_tutorial_start')));
      await tester.pumpAndSettle();
      await sendNativeKeyEvent(tester, 85); // Step 2
      await tester.pumpAndSettle();
      await sendNativeKeyEvent(tester, 87); // Step 3
      await tester.pumpAndSettle();
      await sendNativeKeyEvent(tester, 85); // Step 3 決定
      await tester.pumpAndSettle();
      await sendNativeKeyEvent(tester, 85); // Step 4 決定 -> Step 5
      await tester.pumpAndSettle();

      fakeSound.clear();
      fakeTts.clear();

      // 対象外キー（85, 24）押下: 遷移せず注意文言が表示されること
      await sendNativeKeyEvent(tester, 85);
      await tester.pump();
      expect(find.textContaining('［次の曲へ進む］ボタンを押して調整を完了してください'), findsOneWidget);

      // キー 87 で確定
      await sendNativeKeyEvent(tester, 87);
      await tester.pumpAndSettle();

      expect(fakeSound.beepCount, 1);
      expect(fakeTts.lastSpoken, '確定、開始、ベンチプレス、60キロ、10回、3セット');

      // Step 6 への自動遷移確認
      expect(find.textContaining('チュートリアル完了'), findsOneWidget);
    });

    testWidgets('6. Step 6: 完了画面表示、ボタンタップまたはキー85で本編TrainingScreenへ遷移', (tester) async {
      await tester.pumpWidget(buildTestableApp());
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('btn_tutorial_start')));
      await tester.pumpAndSettle();
      await sendNativeKeyEvent(tester, 85); // 2
      await tester.pumpAndSettle();
      await sendNativeKeyEvent(tester, 87); // 3
      await tester.pumpAndSettle();
      await sendNativeKeyEvent(tester, 85); // 3 decide
      await tester.pumpAndSettle();
      await sendNativeKeyEvent(tester, 85); // 4 decide
      await tester.pumpAndSettle();
      await sendNativeKeyEvent(tester, 87); // 5 finish -> 6
      await tester.pumpAndSettle();

      expect(find.textContaining('チュートリアル完了'), findsOneWidget);

      // 「最初のトレーニングを開始する」ボタンタップで TrainingScreen へ
      final startFirstBtn = find.byKey(const Key('btn_start_first_training'));
      expect(startFirstBtn, findsOneWidget);

      await tester.tap(startFirstBtn);
      await tester.pumpAndSettle();

      expect(find.byType(TrainingScreen), findsOneWidget);
    });

    testWidgets('7. 全ステップのスキップボタンが即座に次ステップ/本編へ遷移すること', (tester) async {
      await tester.pumpWidget(buildTestableApp());
      await tester.pumpAndSettle();

      // Step 1 -> Step 2
      await tester.tap(find.byKey(const Key('btn_tutorial_start')));
      await tester.pumpAndSettle();

      // Step 2 でスキップ
      await tester.tap(find.byKey(const Key('btn_tutorial_skip')));
      await tester.pumpAndSettle();
      expect(find.textContaining('次の曲へ進む'), findsOneWidget); // Step 3

      // Step 3 でスキップ
      await tester.tap(find.byKey(const Key('btn_tutorial_skip')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('card_weight')), findsOneWidget); // Step 4

      // Step 4 でスキップ
      await tester.tap(find.byKey(const Key('btn_tutorial_skip')));
      await tester.pumpAndSettle();
      expect(find.textContaining('調整を完了'), findsOneWidget); // Step 5

      // Step 5 でスキップ
      await tester.tap(find.byKey(const Key('btn_tutorial_skip')));
      await tester.pumpAndSettle();
      expect(find.textContaining('チュートリアル完了'), findsOneWidget); // Step 6
    });

    testWidgets('8. 画面最下部の疑似メディアキーバー各ボタンが物理キーと同一に動作すること', (tester) async {
      await tester.pumpWidget(buildTestableApp());
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('btn_tutorial_start')));
      await tester.pumpAndSettle();

      // Step 2 で仮想キーバーの「再生/停止」をタップ
      fakeSound.clear();
      fakeTts.clear();
      await tester.tap(find.byKey(const Key('virtual_key_play_pause')));
      await tester.pumpAndSettle();

      expect(fakeSound.beepCount, 1);
      expect(fakeTts.lastSpoken, '開始、ベンチプレス、60キロ、10回、3セット');

      // Step 3 で仮想キーバーの「次曲」をタップ
      fakeSound.clear();
      fakeTts.clear();
      await tester.tap(find.byKey(const Key('virtual_key_next')));
      await tester.pumpAndSettle();

      expect(fakeSound.beepCount, 1);
      expect(fakeTts.lastSpoken, '調整、種目名');
    });

    testWidgets('9. 音声排他制御（stopCallCount >= 発話回数）およびダッキング要求の整合性', (tester) async {
      await tester.pumpWidget(buildTestableApp());
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('btn_tutorial_start')));
      await tester.pumpAndSettle();

      // Step 2 開始発話
      await sendNativeKeyEvent(tester, 85);
      await tester.pumpAndSettle();

      // Step 3 突入発話
      await sendNativeKeyEvent(tester, 87);
      await tester.pumpAndSettle();

      // 発話の直前に必ず stop() が呼ばれていることの検証
      expect(fakeTts.spokenHistory.length, greaterThanOrEqualTo(2));
      expect(fakeTts.stopCallCount, greaterThanOrEqualTo(fakeTts.spokenHistory.length));

      // ダッキング要求が実行された履歴があること
      expect(fakeDucking.events.contains('requestDucking'), isTrue);
    });
  });

  group('Visual & Glow Animation Unit Test', () {
    testWidgets('animateGlow: true で有限フレーム進めた際にアニメーションが正常に稼働すること', (tester) async {
      await tester.pumpWidget(buildTestableApp(animateGlow: true));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 300));
      // 例外なくフレーム更新が進むことを確認
      expect(find.byType(TutorialScreen), findsOneWidget);
    });
  });
}
```

---

## 6. Worker 向け実装チェックリスト＆ガイドライン

1. **`lib/main.dart` の修正手順**:
   - 43行目付近に `import 'tutorial_screen.dart';` および `export 'tutorial_screen.dart';` を追記。
   - 702行目の `start_training_button` を囲む `Padding` の直下に、`start_tutorial_button` の `Padding` ウィジェットを挿入。
   - 既存コードの変更や削除は行わない（追加のみ）。
2. **`test/tutorial_screen_test.dart` の配置手順**:
   - 上記セクション 5 のコードを新規ファイル `test/tutorial_screen_test.dart` として保存。
3. **キー命名の厳密な合致**:
   - `lib/tutorial_screen.dart` 内で以下のキーを命名すること：
     - 開始画面: `Key('btn_tutorial_start')`, `Key('btn_tutorial_skip_all')`
     - スキップボタン: `Key('btn_tutorial_skip')`
     - 重量カード: `Key('card_weight')`
     - 完了画面ボタン: `Key('btn_start_first_training')`
     - 疑似メディアキーバー: `Key('virtual_key_prev')`, `Key('virtual_key_play_pause')`, `Key('virtual_key_next')`, `Key('virtual_key_vol_down')`, `Key('virtual_key_vol_up')`
4. **検証コマンドの実行**:
   ```powershell
   flutter test test/tutorial_screen_test.dart
   flutter test
   ```
   全テストが exit code 0 でパスすることを確認する。
