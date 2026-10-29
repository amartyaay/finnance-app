package com.amartyaay.finnance_app

import com.google.mlkit.genai.common.FeatureStatus
import com.google.mlkit.genai.prompt.Generation
import com.google.mlkit.genai.prompt.TextPart
import com.google.mlkit.genai.prompt.generateContentRequest
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

/**
 * Gemini Nano through Android AICore (ML Kit GenAI Prompt API), as an
 * optional, user-started second opinion. AICore only answers while the app
 * is the top foreground app, so this is never used by the SMS receiver or the
 * 10 pm job. Everything stays on the phone.
 */
object GeminiNano {
    const val CHANNEL = "finnance_app/nano"
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private val model by lazy { Generation.getClient() }

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "status" -> scope.launch {
                try {
                    val status = when (model.checkStatus()) {
                        FeatureStatus.AVAILABLE -> "available"
                        FeatureStatus.DOWNLOADABLE -> "downloadable"
                        FeatureStatus.DOWNLOADING -> "downloading"
                        else -> "unavailable"
                    }
                    result.success(mapOf("status" to status))
                } catch (error: Throwable) {
                    result.success(mapOf("status" to "unavailable", "error" to (error.message ?: error.javaClass.simpleName)))
                }
            }
            "download" -> scope.launch {
                try {
                    model.download().collect { }
                    result.success(true)
                } catch (error: Throwable) {
                    result.error("download_failed", error.message, null)
                }
            }
            "prompt" -> scope.launch {
                try {
                    val text = call.argument<String>("text") ?: ""
                    val response = model.generateContent(
                        generateContentRequest(TextPart(text)) {
                            temperature = 0.0f
                            topK = 1
                            maxOutputTokens = call.argument<Int>("maxTokens") ?: 64
                        },
                    )
                    result.success(response.candidates.firstOrNull()?.text ?: "")
                } catch (error: Throwable) {
                    result.error("prompt_failed", error.message ?: error.javaClass.simpleName, null)
                }
            }
            else -> result.notImplemented()
        }
    }
}
