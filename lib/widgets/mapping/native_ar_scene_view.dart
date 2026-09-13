import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

/// Renders the native Android ARSceneView (`mapx/ar_scene_view`) using
/// Hybrid Composition so that Android SurfaceView / ARCore gets a direct hardware
/// surface rather than failing inside a Virtual Display.
class NativeArSceneView extends StatelessWidget {
  const NativeArSceneView({super.key});

  @override
  Widget build(BuildContext context) {
    if (!Platform.isAndroid || Platform.environment.containsKey('FLUTTER_TEST')) {
      return const SizedBox.shrink();
    }

    const String viewType = 'mapx/ar_scene_view';

    return PlatformViewLink(
      viewType: viewType,
      surfaceFactory: (context, controller) {
        return AndroidViewSurface(
          controller: controller as AndroidViewController,
          gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{},
          hitTestBehavior: PlatformViewHitTestBehavior.opaque,
        );
      },
      onCreatePlatformView: (params) {
        return PlatformViewsService.initExpensiveAndroidView(
          id: params.id,
          viewType: viewType,
          layoutDirection: TextDirection.ltr,
          creationParams: const <String, dynamic>{},
          creationParamsCodec: const StandardMessageCodec(),
          onFocus: () {
            params.onFocusChanged(true);
          },
        )
          ..addOnPlatformViewCreatedListener(params.onPlatformViewCreated)
          ..create();
      },
    );
  }
}
