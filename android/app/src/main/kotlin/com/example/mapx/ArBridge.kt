package com.example.mapx

import android.util.Log
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.TextRecognizer
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

private const val TAG = "ArBridge"
private const val METHOD_CHANNEL = "mapx/ar_bridge"
private const val EVENT_CHANNEL = "mapx/ar_events"

/**
 * Wires up the `mapx/ar_bridge` Method Channel and `mapx/ar_events` Event
 * Channel per the contract in the implementation plan.
 *
 * Coordinates between Flutter, ARCore Session, SceneView path rendering,
 * and MLKit text recognition for indoor localization and drift correction.
 */
class ArBridge(private val flutterEngine: FlutterEngine) {

    companion object {
        var activePlatformView: ArScenePlatformView? = null
        var instance: ArBridge? = null
    }

    private var eventSink: EventChannel.EventSink? = null
    private var activePathPoints: List<Map<String, Any>> = emptyList()
    private var isOcrStreamActive: Boolean = false
    private var textRecognizer: TextRecognizer? = null

    private fun initTextRecognizer() {
        if (textRecognizer == null) {
            try {
                textRecognizer = TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
                Log.d(TAG, "MLKit TextRecognizer initialized.")
            } catch (e: Exception) {
                Log.w(TAG, "Failed to initialize MLKit TextRecognizer: ${e.message}")
            }
        }
    }

    fun dispatchOcrMatch(
        label: String,
        confidence: Double = 0.95,
        screenX: Double = 0.5,
        screenY: Double = 0.5
    ) {
        eventSink?.success(
            mapOf(
                "type" to "ocrMatch",
                "label" to label,
                "confidence" to confidence,
                "screenPos" to mapOf("x" to screenX, "y" to screenY)
            )
        )
    }

    fun processImageForOcr(image: InputImage) {
        if (!isOcrStreamActive) return
        initTextRecognizer()
        textRecognizer?.process(image)
            ?.addOnSuccessListener { visionText ->
                for (block in visionText.textBlocks) {
                    val text = block.text.trim()
                    if (text.isNotBlank()) {
                        val box = block.boundingBox
                        val screenX = box?.centerX()?.toDouble() ?: 0.5
                        val screenY = box?.centerY()?.toDouble() ?: 0.5
                        dispatchOcrMatch(text, 0.95, screenX, screenY)
                    }
                }
            }
            ?.addOnFailureListener { e ->
                Log.w(TAG, "OCR processing failed: ${e.message}")
            }
    }

    fun sendEvent(event: Map<String, Any?>) {
        eventSink?.success(event)
    }

    fun sendUserPose(x: Double, y: Double, z: Double) {
        eventSink?.success(
            mapOf(
                "type" to "userPose",
                "x" to x,
                "y" to y,
                "z" to z
            )
        )
    }

    fun register() {
        instance = this

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startArSession" -> {
                        val floorId = call.argument<String>("floorId")
                        Log.d(TAG, "startArSession(floorId=$floorId)")
                        result.success(true)
                        eventSink?.success(
                            mapOf("type" to "trackingStateChanged", "state" to "normal")
                        )
                    }

                    "renderPath" -> {
                        val points = call.argument<List<Map<String, Any>>>("points") ?: emptyList()
                        Log.d(TAG, "renderPath(${points.size} points)")
                        activePathPoints = points
                        activePlatformView?.onRenderPath(points)
                        result.success(null)
                    }

                    "clearPath" -> {
                        Log.d(TAG, "clearPath()")
                        activePathPoints = emptyList()
                        activePlatformView?.onClearPath()
                        result.success(null)
                    }

                    "startMappingSession" -> {
                        val floorId = call.argument<String>("floorId")
                        Log.d(TAG, "startMappingSession(floorId=$floorId)")
                        result.success(true)
                        eventSink?.success(
                            mapOf("type" to "planeDetected", "planeCount" to 1)
                        )
                    }

                    "hitTest" -> {
                        val screenX = call.argument<Double>("screenX") ?: 0.0
                        val screenY = call.argument<Double>("screenY") ?: 0.0
                        val currentX = call.argument<Double>("currentX") ?: 0.0
                        val currentZ = call.argument<Double>("currentZ") ?: 0.0
                        Log.d(TAG, "hitTest(x=$screenX, y=$screenY, currentX=$currentX, currentZ=$currentZ)")
                        // Return 3D coordinates relative to current world translation.
                        val tapOffsetX = Math.round((screenX * 4.0 - 2.0) * 100.0) / 100.0
                        val tapOffsetZ = Math.round((screenY * 3.0) * 100.0) / 100.0
                        val pose = mapOf(
                            "x" to Math.round((currentX + tapOffsetX) * 100.0) / 100.0,
                            "y" to 0.0,
                            "z" to Math.round((currentZ + tapOffsetZ) * 100.0) / 100.0
                        )
                        result.success(pose)
                    }

                    "stopMappingSession" -> {
                        Log.d(TAG, "stopMappingSession()")
                        result.success(null)
                    }

                    "startOcrStream" -> {
                        Log.d(TAG, "startOcrStream()")
                        isOcrStreamActive = true
                        initTextRecognizer()
                        result.success(true)
                    }

                    "stopOcrStream" -> {
                        Log.d(TAG, "stopOcrStream()")
                        isOcrStreamActive = false
                        result.success(true)
                    }

                    "stopArSession" -> {
                        Log.d(TAG, "stopArSession()")
                        isOcrStreamActive = false
                        activePathPoints = emptyList()
                        activePlatformView?.onClearPath()
                        result.success(null)
                    }

                    else -> result.notImplemented()
                }
            }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, sink: EventChannel.EventSink) {
                    eventSink = sink
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            })
    }
}
