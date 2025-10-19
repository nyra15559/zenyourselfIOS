package ch.zenyourself.app

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Bundle
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.util.Locale

class MainActivity : FlutterActivity() {

    private val METHOD_CHANNEL = "zen.whisper"
    private val EVENT_CHANNEL  = "zen.whisper/events"
    private val REQ_MIC = 1337

    private var eventSink: EventChannel.EventSink? = null
    private var speechRecognizer: SpeechRecognizer? = null
    private var recognizerIntent: Intent? = null
    private var isListening = false
    private var isPaused = false
    private var locale: Locale = Locale.forLanguageTag("de-DE")

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val methodChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            METHOD_CHANNEL
        )
        val eventChannel = EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            EVENT_CHANNEL
        )

        eventChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(args: Any?, sink: EventChannel.EventSink?) {
                eventSink = sink
            }

            override fun onCancel(args: Any?) {
                eventSink = null
            }
        })

        methodChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    val loc = call.argument<String>("locale") ?: "de-DE"
                    locale = Locale.forLanguageTag(loc)
                    startListening()
                    result.success(null)
                }
                "pause" -> {
                    pauseListening()
                    result.success(null)
                }
                "resume" -> {
                    resumeListening()
                    result.success(null)
                }
                "stop" -> {
                    stopListening()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    // ──────────────────────────────────────────────────────────────────────────
    // SpeechRecognizer-Steuerung
    // ──────────────────────────────────────────────────────────────────────────

    private fun ensurePermission(): Boolean {
        val ok = ContextCompat.checkSelfPermission(
            this, Manifest.permission.RECORD_AUDIO
        ) == PackageManager.PERMISSION_GRANTED

        if (!ok) {
            ActivityCompat.requestPermissions(
                this,
                arrayOf(Manifest.permission.RECORD_AUDIO),
                REQ_MIC
            )
        }
        return ok
    }

    private fun startListening() {
        if (isListening) return
        if (!ensurePermission()) {
            sendError("no_permission")
            return
        }
        if (!SpeechRecognizer.isRecognitionAvailable(this)) {
            sendError("no_recognizer")
            return
        }

        speechRecognizer = SpeechRecognizer.createSpeechRecognizer(this)
        speechRecognizer?.setRecognitionListener(object : RecognitionListener {
            override fun onReadyForSpeech(params: Bundle?) {
                isListening = true
                isPaused = false
            }

            override fun onRmsChanged(rmsdB: Float) {
                // Pegel ca. 0..1 normalisieren
                val level = ((rmsdB + 2f) / 10f).coerceIn(0f, 1f)
                sendLevel(level.toDouble())
            }

            override fun onPartialResults(partialResults: Bundle?) {
                val list = partialResults?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                val text = list?.firstOrNull() ?: return
                if (text.isNotBlank()) sendPartial(text)
            }

            override fun onResults(results: Bundle?) {
                val list = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                val text = list?.firstOrNull() ?: ""
                if (text.isNotBlank()) sendFinal(text)
                stopListening()
            }

            override fun onError(error: Int) {
                sendError("error:$error")
                stopListening()
            }

            override fun onBeginningOfSpeech() {}
            override fun onBufferReceived(buffer: ByteArray?) {}
            override fun onEndOfSpeech() {}
            override fun onEvent(eventType: Int, params: Bundle?) {}
        })

        recognizerIntent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(
                RecognizerIntent.EXTRA_LANGUAGE_MODEL,
                RecognizerIntent.LANGUAGE_MODEL_FREE_FORM
            )
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, locale.toLanguageTag())
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
            putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
        }

        speechRecognizer?.startListening(recognizerIntent)
    }

    private fun pauseListening() {
        if (!isListening || isPaused) return
        isPaused = true
        // Es gibt kein echtes Pause-API → wir stoppen; Resume startet neu.
        try {
            speechRecognizer?.stopListening()
        } catch (_: Exception) { }
    }

    private fun resumeListening() {
        if (!isListening || !isPaused) return
        isPaused = false
        try {
            speechRecognizer?.startListening(recognizerIntent)
        } catch (_: Exception) { }
    }

    private fun stopListening() {
        isPaused = false
        isListening = false
        try {
            speechRecognizer?.stopListening()
            speechRecognizer?.cancel()
        } catch (_: Exception) { }
        speechRecognizer?.destroy()
        speechRecognizer = null
    }

    // ──────────────────────────────────────────────────────────────────────────
    // Event-Helfer
    // ──────────────────────────────────────────────────────────────────────────

    private fun sendPartial(text: String) {
        eventSink?.success(mapOf("type" to "partial", "value" to text))
    }

    private fun sendFinal(text: String) {
        eventSink?.success(mapOf("type" to "final", "value" to text))
    }

    private fun sendLevel(v: Double) {
        eventSink?.success(mapOf("type" to "level", "value" to v))
    }

    private fun sendError(msg: String) {
        eventSink?.error("whisper_error", msg, null)
    }

    // (Optional) Nur für Vollständigkeit – Verhalten ändert sich nicht.
    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQ_MIC && grantResults.isNotEmpty()) {
            // Benutzeraktion wurde behandelt; der nächste "start" versucht es erneut.
        }
    }

    override fun onDestroy() {
        stopListening()
        super.onDestroy()
    }
}
