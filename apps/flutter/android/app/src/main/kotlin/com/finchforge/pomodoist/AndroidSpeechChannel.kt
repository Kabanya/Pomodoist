package com.finchforge.pomodoist

import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

internal class AndroidSpeechChannel(
    private val context: Context,
    messenger: BinaryMessenger,
) : EventChannel.StreamHandler {
    private val commands = MethodChannel(messenger, "pomodoist/android_speech")
    private val events = EventChannel(messenger, "pomodoist/android_speech/events")
    private val handler = Handler(Looper.getMainLooper())
    private var active: Session? = null

    init {
        events.setStreamHandler(this)
        commands.setMethodCallHandler { call, result ->
            when (call.method) {
                "stop" -> {
                    active?.stop()
                    result.success(null)
                }
                "cancel" -> {
                    active?.finish()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onListen(locale: Any?, sink: EventChannel.EventSink) {
        active?.finish()
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
            !SpeechRecognizer.isOnDeviceRecognitionAvailable(context)
        ) {
            sink.error("speech_system_unavailable", null, null)
            sink.endOfStream()
            return
        }
        try {
            val recognizer = SpeechRecognizer.createOnDeviceSpeechRecognizer(context)
            val session = Session(recognizer, sink)
            active = session
            session.start(locale as? String)
        } catch (_: RuntimeException) {
            active?.finish(error = "speech_system_unavailable") ?: run {
                sink.error("speech_system_unavailable", null, null)
                sink.endOfStream()
            }
        }
    }

    override fun onCancel(arguments: Any?) {
        active?.finish()
    }

    fun dispose() {
        active?.finish()
        events.setStreamHandler(null)
        commands.setMethodCallHandler(null)
    }

    private inner class Session(
        private val recognizer: SpeechRecognizer,
        private val sink: EventChannel.EventSink,
    ) : RecognitionListener {
        private var processing = false
        private val timeout = Runnable { finish(error = "speech_recognition_failed") }

        fun start(locale: String?) {
            recognizer.setRecognitionListener(this)
            val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH)
                .putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                .putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
            if (!locale.isNullOrBlank()) intent.putExtra(RecognizerIntent.EXTRA_LANGUAGE, locale)
            handler.postDelayed(timeout, 10_000)
            recognizer.startListening(intent)
        }

        fun stop() {
            if (processing) return
            onEndOfSpeech()
            try {
                recognizer.stopListening()
            } catch (_: RuntimeException) {
                finish(error = "speech_recognition_failed")
            }
        }

        fun finish(text: String? = null, error: String? = null) {
            if (active !== this) return
            active = null
            handler.removeCallbacks(timeout)
            recognizer.destroy()
            if (error != null) sink.error(error, null, null)
            if (text != null) sink.success(mapOf("text" to text))
            sink.endOfStream()
        }

        override fun onReadyForSpeech(params: Bundle?) {
            if (active !== this || processing) return
            handler.removeCallbacks(timeout)
            sink.success("recording")
        }

        override fun onRmsChanged(rmsdB: Float) {
            if (active === this && !processing) sink.success(rmsdB.toDouble())
        }

        override fun onEndOfSpeech() {
            if (active !== this || processing) return
            processing = true
            sink.success("transcribing")
            handler.removeCallbacks(timeout)
            handler.postDelayed(timeout, 10_000)
        }

        override fun onResults(results: Bundle?) {
            val text = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                ?.firstOrNull()?.trim()
            if (text.isNullOrEmpty()) finish(error = "speech_recognition_failed")
            else finish(text = text)
        }

        override fun onError(error: Int) = finish(error = when (error) {
            SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> "microphone_denied"
            SpeechRecognizer.ERROR_LANGUAGE_NOT_SUPPORTED,
            SpeechRecognizer.ERROR_LANGUAGE_UNAVAILABLE -> "speech_locale_unsupported"
            else -> "speech_recognition_failed"
        })

        override fun onBeginningOfSpeech() = Unit
        override fun onBufferReceived(buffer: ByteArray?) = Unit
        override fun onPartialResults(partialResults: Bundle?) = Unit
        override fun onEvent(eventType: Int, params: Bundle?) = Unit
    }
}
