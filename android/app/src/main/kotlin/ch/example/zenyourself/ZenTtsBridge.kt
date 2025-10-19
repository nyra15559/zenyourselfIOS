// android/app/src/main/kotlin/ch/example/zenyourself/ZenTtsBridge.kt
package ch.zenyourself.app

import android.content.Context
import android.os.Build
import android.os.Bundle
import android.speech.tts.TextToSpeech
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.HashMap
import java.util.Locale

/**
 * Einfache TTS-Bridge für Flutter.
 * MethodChannel: "zen.tts"
 *  - speak(text, lang?, pitch?, rate?)
 *  - stop()
 *  - shutdown()
 */
class ZenTtsBridge private constructor(private val appContext: Context) :
  MethodChannel.MethodCallHandler, TextToSpeech.OnInitListener {

  companion object {
    private const val CHANNEL = "zen.tts"

    fun register(context: Context, messenger: BinaryMessenger): ZenTtsBridge {
      val bridge = ZenTtsBridge(context.applicationContext)
      bridge.channel = MethodChannel(messenger, CHANNEL)
      bridge.channel.setMethodCallHandler(bridge)
      return bridge
    }
  }

  private lateinit var channel: MethodChannel
  private var tts: TextToSpeech? = null
  private var ready = false

  override fun onInit(status: Int) {
    ready = status == TextToSpeech.SUCCESS
    if (!ready) {
      channel.invokeMethod("onError", mapOf("code" to "init_failed"))
    }
  }

  override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
    when (call.method) {
      "speak" -> {
        val text = call.argument<String>("text").orEmpty()
        val lang = call.argument<String>("lang") ?: "de-DE"
        val pitch = (call.argument<Double>("pitch") ?: 1.0).toFloat()
        val rate  = (call.argument<Double>("rate")  ?: 1.0).toFloat()

        if (tts == null) tts = TextToSpeech(appContext, this)
        tts?.language = Locale.forLanguageTag(lang)
        tts?.setPitch(pitch)
        tts?.setSpeechRate(rate)

        speak(text)
        result.success(true)
      }
      "stop" -> { tts?.stop(); result.success(true) }
      "shutdown" -> { tts?.shutdown(); tts = null; result.success(true) }
      else -> result.notImplemented()
    }
  }

  private fun speak(text: String) {
    val engine = tts ?: return
    val utteranceId = "zen_${System.currentTimeMillis()}"

    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
      // Neue Überladung: 4 Parameter, 3. Param = Bundle
      val params = Bundle().apply {
        putFloat(TextToSpeech.Engine.KEY_PARAM_VOLUME, 1.0f)
      }
      engine.speak(text, TextToSpeech.QUEUE_FLUSH, params, utteranceId)
    } else {
      // Legacy-Überladung: 3 Parameter, 3. Param = HashMap<String, String>
      @Suppress("DEPRECATION")
      val legacyParams = HashMap<String, String>().apply {
        put(TextToSpeech.Engine.KEY_PARAM_UTTERANCE_ID, utteranceId)
        // Lautstärke nur ab Lollipop als Bundle verfügbar
      }
      @Suppress("DEPRECATION")
      engine.speak(text, TextToSpeech.QUEUE_FLUSH, legacyParams)
    }
  }
}
