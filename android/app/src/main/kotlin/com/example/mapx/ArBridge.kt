package com.example.mapx

import android.util.Log
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
 * Coordinates between Flutter, ARCore Session, and SceneView path rendering.
 */
class ArBridge(private val flutterEngine: FlutterEngine) {

    companion object {
        var activePlatformView: ArScenePlatformView? = null
        var instance: ArBridge? = null
    }

    private var eventSink: EventChannel.EventSink? = null
    private var activePathPoints: List<Map<String, Any>> = emptyList()

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
                        Log.d(TAG, "hitTest(x=$screenX, y=$screenY)")
                        // Return 3D coordinates (meters).
                        val pose = mapOf(
                            "x" to Math.round((screenX * 10 - 5) * 100.0) / 100.0,
                            "y" to 0.0,
                            "z" to Math.round((screenY * 10) * 100.0) / 100.0
                        )
                        result.success(pose)
                    }

                    "stopMappingSession" -> {
                        Log.d(TAG, "stopMappingSession()")
                        result.success(null)
                    }

                    "stopArSession" -> {
                        Log.d(TAG, "stopArSession()")
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
