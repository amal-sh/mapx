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
 * Channel per the contract in the implementation plan (Sec. 5).
 *
 * Every handler here is a stub: no ARCore Session, SceneView rendering, or
 * MLKit OCR yet. Those land in Phases 2/4/7. This class is the seam they
 * plug into so the Dart side (lib/native/ar_bridge.dart) and the screens
 * that use it don't need to change when the real implementations arrive.
 */
class ArBridge(private val flutterEngine: FlutterEngine) {

    private var eventSink: EventChannel.EventSink? = null

    fun register() {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startArSession" -> {
                        val floorId = call.argument<String>("floorId")
                        Log.d(TAG, "startArSession(floorId=$floorId) [stub]")
                        // TODO(Phase 2/4): start a real ARCore Session for floorId.
                        result.success(true)
                        // Proves the Event Channel round-trip works end-to-end
                        // ahead of real tracking-state updates landing in Phase 4.
                        eventSink?.success(
                            mapOf("type" to "trackingStateChanged", "state" to "normal")
                        )
                    }

                    "renderPath" -> {
                        val points = call.argument<List<*>>("points")
                        Log.d(TAG, "renderPath(${points?.size ?: 0} points) [stub]")
                        // TODO(Phase 4): hand smoothed path points to SceneView.
                        result.success(null)
                    }

                    "startMappingMode" -> {
                        val buildingId = call.argument<String>("buildingId")
                        val floorId = call.argument<String>("floorId")
                        Log.d(TAG, "startMappingMode(building=$buildingId, floor=$floorId) [stub]")
                        // TODO(Phase 7): admin mapping mode.
                        result.success(null)
                    }

                    "dropNode" -> {
                        val label = call.argument<String>("label")
                        Log.d(TAG, "dropNode(label=$label) [stub]")
                        // TODO(Phase 7): ARCore hit-test anchor drop for mapping mode.
                        result.success(null)
                    }

                    "stopArSession" -> {
                        Log.d(TAG, "stopArSession() [stub]")
                        // TODO(Phase 2/4): tear down the ARCore Session.
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
