package com.example.button_controll_test

import android.media.AudioManager
import android.media.ToneGenerator
import android.view.KeyEvent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "com.example.noukin/key_events"

        // 横取り対象の6種類のキーコード
        private val TARGET_KEY_CODES = setOf(
            KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE, // 85
            KeyEvent.KEYCODE_HEADSETHOOK,      // 79
            KeyEvent.KEYCODE_VOLUME_UP,        // 24
            KeyEvent.KEYCODE_VOLUME_DOWN,      // 25
            KeyEvent.KEYCODE_MEDIA_NEXT,       // 87
            KeyEvent.KEYCODE_MEDIA_PREVIOUS    // 88
        )
    }

    private var methodChannel: MethodChannel? = null
    private var toneGenerator: ToneGenerator? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        try {
            toneGenerator = ToneGenerator(AudioManager.STREAM_MUSIC, 80)
        } catch (_: Exception) {
            toneGenerator = null
        }

        methodChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "playBeep" -> {
                        try {
                            toneGenerator?.startTone(ToneGenerator.TONE_PROP_BEEP, 45)
                            result.success(true)
                        } catch (e: Exception) {
                            result.success(false)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        methodChannel?.setMethodCallHandler(null)
        methodChannel = null
        try {
            toneGenerator?.release()
        } catch (_: Exception) {
        }
        toneGenerator = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        val keyCode = event.keyCode
        if (keyCode in TARGET_KEY_CODES) {
            // 初回押し込み時のみ Flutter 側へキーコードを通知（長押しリピートや離した時は通知しない）
            if (event.action == KeyEvent.ACTION_DOWN && event.repeatCount == 0) {
                methodChannel?.invokeMethod("onKeyEvent", keyCode)
            }
            // OS デフォルトの処理（音量バー表示や標準メディア操作等）を完全にブロック
            return true
        }
        return super.dispatchKeyEvent(event)
    }
}
