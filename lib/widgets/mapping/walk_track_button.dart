import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Circular Walk & Path Tracking button with press-and-hold and flick-to-lock gestures.
///
/// Designed to be positioned centrally on the mapping screen.
///
/// Interaction:
/// - **Press & Hold**: Knob activates immediately upon touch down and records footsteps/distance
///   while walking to count as an edge.
/// - **Swipe / Flick Upward**: Sliding the knob upward past the lock threshold snaps it
///   into locked hands-free path recording mode.
/// - **Release**: When released while holding (not locked), knob springs back to bottom,
///   pauses tracking, and commits the walked path as an edge.
/// - **Tap when Locked**: Unlocks and pauses tracking, committing the walked path as an edge.
class WalkTrackButton extends StatefulWidget {
  const WalkTrackButton({
    super.key,
    required this.isRecording,
    required this.isLocked,
    required this.onRecordingChanged,
    required this.onLockChanged,
    this.onWalkFinished,
    this.distanceTraversedMeters,
  });

  final bool isRecording;
  final bool isLocked;
  final ValueChanged<bool> onRecordingChanged;
  final ValueChanged<bool> onLockChanged;
  final VoidCallback? onWalkFinished;
  final double? distanceTraversedMeters;

  @override
  State<WalkTrackButton> createState() => _WalkTrackButtonState();
}

class _WalkTrackButtonState extends State<WalkTrackButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _springController;
  late Animation<double> _knobAnimation;

  double _dragOffset = 0.0; // 0.0 (bottom) to -48.0 (top lock)
  static const double _maxDragUp = -48.0;
  static const double _lockThreshold = -26.0;

  double _pointerDownY = 0.0;
  DateTime _pointerDownTime = DateTime.now();
  bool _wasLockedOnDown = false;
  bool _didLockInCurrentGesture = false;

  @override
  void initState() {
    super.initState();
    _springController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
    )..addListener(() {
        setState(() {
          _dragOffset = _knobAnimation.value;
        });
      });

    if (widget.isLocked) {
      _dragOffset = _maxDragUp;
    }
  }

  @override
  void didUpdateWidget(covariant WalkTrackButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isLocked && !oldWidget.isLocked) {
      _animateTo(_maxDragUp);
    } else if (!widget.isLocked && oldWidget.isLocked) {
      _animateTo(0.0);
    }
  }

  @override
  void dispose() {
    _springController.dispose();
    super.dispose();
  }

  void _animateTo(double target) {
    _knobAnimation = Tween<double>(
      begin: _dragOffset,
      end: target,
    ).animate(
      CurvedAnimation(parent: _springController, curve: Curves.easeOutBack),
    );
    _springController.forward(from: 0.0);
  }

  void _onPointerDown(PointerDownEvent event) {
    _pointerDownY = event.position.dy;
    _pointerDownTime = DateTime.now();
    _springController.stop();

    if (widget.isLocked) {
      _wasLockedOnDown = true;
      _didLockInCurrentGesture = false;
    } else {
      _wasLockedOnDown = false;
      _didLockInCurrentGesture = false;
      HapticFeedback.selectionClick();
      widget.onRecordingChanged(true);
    }
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (_wasLockedOnDown && !_didLockInCurrentGesture) return;

    final dy = event.position.dy - _pointerDownY;
    if (dy < 0) {
      // Swiping / dragging upwards towards the lock icon
      final target = dy.clamp(_maxDragUp, 0.0);
      setState(() {
        _dragOffset = target;
      });

      if (_dragOffset <= _lockThreshold && !_didLockInCurrentGesture) {
        _didLockInCurrentGesture = true;
        HapticFeedback.heavyImpact();
        _animateTo(_maxDragUp);
        widget.onLockChanged(true);
      }
    } else if (!_didLockInCurrentGesture) {
      setState(() {
        _dragOffset = 0.0;
      });
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    final now = DateTime.now();
    final elapsedMs = now.difference(_pointerDownTime).inMilliseconds;
    final totalDistY = (event.position.dy - _pointerDownY);

    if (_wasLockedOnDown) {
      // Tap on locked knob to unlock
      if (totalDistY.abs() < 24.0) {
        HapticFeedback.mediumImpact();
        _animateTo(0.0);
        widget.onLockChanged(false);
        widget.onWalkFinished?.call();
      }
      _wasLockedOnDown = false;
      return;
    }

    if (_didLockInCurrentGesture) {
      // Swiped up and locked: stays locked hands-free!
      _didLockInCurrentGesture = false;
      return;
    }

    // Quick upward flick detection
    if (totalDistY < -15.0 && elapsedMs < 300) {
      HapticFeedback.heavyImpact();
      _animateTo(_maxDragUp);
      widget.onLockChanged(true);
      return;
    }

    // Released while holding: spring back to bottom & pause recording
    HapticFeedback.lightImpact();
    _animateTo(0.0);
    widget.onRecordingChanged(false);
    widget.onWalkFinished?.call();
  }

  void _onPointerCancel(PointerCancelEvent event) {
    if (!_didLockInCurrentGesture && !widget.isLocked) {
      _animateTo(0.0);
      widget.onRecordingChanged(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLocked = widget.isLocked;
    final isRecording = widget.isRecording || isLocked;
    final distText = widget.distanceTraversedMeters != null
        ? '+${widget.distanceTraversedMeters!.toStringAsFixed(1)}m'
        : '';

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Centered Status Guidance / Distance Counter Pill
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: isRecording
                ? const Color(0xFF059669).withValues(alpha: 0.94)
                : Colors.black.withValues(alpha: 0.82),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isRecording ? const Color(0xFF34D399) : Colors.white24,
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: isRecording
                    ? const Color(0xFF10B981).withValues(alpha: 0.45)
                    : Colors.black54,
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isRecording ? Colors.white : Colors.amberAccent,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                isLocked
                    ? '🔒 LOCKED $distText • Tap knob to pause'
                    : isRecording
                        ? '● WALKING $distText • Flick ↑ to Lock'
                        : 'Hold to Walk • Flick ↑ to Lock',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),

        // Vertical Pill Track with Circular Knob
        Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: _onPointerDown,
          onPointerMove: _onPointerMove,
          onPointerUp: _onPointerUp,
          onPointerCancel: _onPointerCancel,
          child: Container(
            width: 62,
            height: 116,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.78),
              borderRadius: BorderRadius.circular(31),
              border: Border.all(
                color: isLocked
                    ? const Color(0xFF10B981)
                    : (isRecording ? const Color(0xFF38BDF8) : Colors.white24),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: isLocked
                      ? const Color(0xFF10B981).withValues(alpha: 0.4)
                      : Colors.black54,
                  blurRadius: 14,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: Stack(
              alignment: Alignment.bottomCenter,
              children: [
                // Top Lock Anchor & Direction Chevrons
                Positioned(
                  top: 10,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isLocked
                            ? CupertinoIcons.lock_fill
                            : CupertinoIcons.lock_open,
                        size: 16,
                        color: isLocked ? const Color(0xFF10B981) : Colors.white54,
                      ),
                      const SizedBox(height: 2),
                      Icon(
                        CupertinoIcons.chevron_compact_up,
                        size: 14,
                        color: isLocked
                            ? const Color(0xFF10B981).withValues(alpha: 0.8)
                            : Colors.white30,
                      ),
                      Icon(
                        CupertinoIcons.chevron_compact_up,
                        size: 12,
                        color: isLocked
                            ? const Color(0xFF10B981).withValues(alpha: 0.4)
                            : Colors.white24,
                      ),
                    ],
                  ),
                ),

                // Sliding Round Knob
                Positioned(
                  bottom: 4,
                  child: Transform.translate(
                    offset: Offset(0, _dragOffset),
                    child: Container(
                      width: 54,
                      height: 54,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: isLocked
                              ? [const Color(0xFF10B981), const Color(0xFF047857)]
                              : (isRecording
                                  ? [const Color(0xFF0284C7), const Color(0xFF0369A1)]
                                  : [const Color(0xFF27272A), const Color(0xFF18181B)]),
                        ),
                        border: Border.all(
                          color: isLocked
                              ? Colors.white
                              : (isRecording ? const Color(0xFF38BDF8) : Colors.white38),
                          width: 2.2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: isLocked
                                ? const Color(0xFF10B981).withValues(alpha: 0.6)
                                : (isRecording
                                    ? const Color(0xFF0284C7).withValues(alpha: 0.5)
                                    : Colors.black.withValues(alpha: 0.6)),
                            blurRadius: 10,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                      child: Center(
                        child: Icon(
                          isLocked
                              ? CupertinoIcons.lock_fill
                              : (isRecording ? CupertinoIcons.recordingtape : Icons.directions_walk),
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
