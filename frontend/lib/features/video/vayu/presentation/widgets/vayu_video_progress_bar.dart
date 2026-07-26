import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:vayug/core/design/colors.dart';

class VayuVideoProgressBar extends StatefulWidget {
  final VideoPlayerController controller;
  final double height;
  final double? barCenterOffset;
  final double barHeight;
  final double activeBarHeight;
  final double thumbRadius;
  final VoidCallback? onDragStart;
  final VoidCallback? onDragEnd;
  final Future<void> Function() onResumeAfterSeek;
  final VoidCallback? onSeekStarted;
  final void Function(double relative, Duration position)? onProgressUpdate;

  const VayuVideoProgressBar({
    super.key,
    required this.controller,
    this.height = 20.0,
    this.barCenterOffset,
    this.barHeight = 2.0, // Ultra-thin idle state
    this.activeBarHeight = 8.0, // Substantial interaction state
    this.thumbRadius = 6.0,
    this.onDragStart,
    this.onDragEnd,
    required this.onResumeAfterSeek,
    this.onSeekStarted,
    this.onProgressUpdate,
  });

  @override
  State<VayuVideoProgressBar> createState() => _VayuVideoProgressBarState();
}

class _VayuVideoProgressBarState extends State<VayuVideoProgressBar> with TickerProviderStateMixin {
  late ValueNotifier<double> _dragPosition;
  late AnimationController _expansionController;
  late Animation<double> _barScaleAnimation;

  bool _isDragging = false;
  bool _wasPlayingBeforeDrag = false;
  late double _currentRelative;
  double _lastVibrateProgress = 0.0; // **YUG MATCH: Track last haptic position**
  DateTime _lastUpdate = DateTime.now();
  DateTime? _lastSeekTime; // Track last seek to prevent "jump-back"
  static const Duration _updateInterval = Duration(milliseconds: 33); // ~30fps

  @override
  void initState() {
    super.initState();
    _currentRelative = _getVideoRelative();
    _dragPosition = ValueNotifier<double>(_currentRelative);

    _expansionController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );

    _barScaleAnimation = CurvedAnimation(
      parent: _expansionController,
      curve: Curves.easeOutCubic,
    );

    widget.controller.addListener(_videoListener);
  }

  @override
  void didUpdateWidget(VayuVideoProgressBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_videoListener);
      widget.controller.addListener(_videoListener);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_videoListener);
    _dragPosition.dispose();
    _expansionController.dispose();
    super.dispose();
  }

  void _videoListener() {
    if (_isDragging || !widget.controller.value.isInitialized) return; // **YUG MATCH: Pause updates while dragging**
    
    // **NEW: Seek Stability - Ignore updates for 300ms after a seek/drag end**
    if (_lastSeekTime != null && DateTime.now().difference(_lastSeekTime!) < const Duration(milliseconds: 300)) {
      return;
    }

    final now = DateTime.now();
    if (now.difference(_lastUpdate) >= _updateInterval) {
      final relative = _getVideoRelative();
      if ((relative - _dragPosition.value).abs() > 0.001) {
        _dragPosition.value = relative;
      }
      _lastUpdate = now;
    }
  }

  double _getVideoRelative() {
    if (!widget.controller.value.isInitialized || widget.controller.value.duration == Duration.zero) {
      return 0.0;
    }
    return widget.controller.value.position.inMilliseconds /
        widget.controller.value.duration.inMilliseconds;
  }

  // Tap-to-seek removed to prevent accidental jump when interacting with controls

  void _handleDragStart(DragStartDetails details) {
    if (!widget.controller.value.isInitialized) return;

    _isDragging = true;
    _wasPlayingBeforeDrag = widget.controller.value.isPlaying;
    
    if (_wasPlayingBeforeDrag) {
      widget.controller.pause();
    }

    _expansionController.forward();
    widget.onDragStart?.call();
    HapticFeedback.mediumImpact();
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    if (!_isDragging || !widget.controller.value.isInitialized) return;

    final width = context.size?.width ?? 1.0;
    
    // **YUG MATCH: Direct Linear Seeking**
    // Using localPosition.dx directly for instantaneous response
    final newRelative = (details.localPosition.dx / width).clamp(0.0, 1.0);
    
    if ((newRelative - _dragPosition.value).abs() > 0.0001) {
      _dragPosition.value = newRelative;
      
      if (widget.onProgressUpdate != null) {
        final position = Duration(milliseconds: (widget.controller.value.duration.inMilliseconds * newRelative).toInt());
        widget.onProgressUpdate!(newRelative, position);
      }

      // **YUG MATCH: Granular Haptic Notches & End-of-bar Vibration**
      if (newRelative <= 0.0 || newRelative >= 1.0) {
        if ((newRelative - _lastVibrateProgress).abs() > 0.01) {
          HapticFeedback.vibrate(); // Distinc vibration at ends
          _lastVibrateProgress = newRelative;
        }
      } else if ((newRelative - _lastVibrateProgress).abs() >= 0.02) {
        HapticFeedback.lightImpact(); // Subtle "notches" while dragging
        _lastVibrateProgress = newRelative;
      }
    }
  }

  void _handleDragEnd(DragEndDetails details) {
    if (!_isDragging) return;

    _isDragging = false;
    _lastSeekTime = DateTime.now(); // Mark seeking start
    widget.onSeekStarted?.call();
    _seekTo(_dragPosition.value);

    if (_wasPlayingBeforeDrag) {
      widget.onResumeAfterSeek();
    }

    _expansionController.reverse();
    widget.onDragEnd?.call();
    HapticFeedback.lightImpact();
  }

  void _seekTo(double relative) {
    final duration = widget.controller.value.duration.inMilliseconds;
    final target = Duration(milliseconds: (duration * relative).toInt());
    widget.controller.seekTo(target);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // onTapDown removed to disable tap-to-seek (prevent accidental seeks)
      onHorizontalDragStart: _handleDragStart,
      onHorizontalDragUpdate: _handleDragUpdate,
      onHorizontalDragEnd: _handleDragEnd,
      onHorizontalDragCancel: () => _handleDragEnd(DragEndDetails()),
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        height: widget.height,
        width: double.infinity,
        child: ValueListenableBuilder<double>(
          valueListenable: _dragPosition,
          builder: (context, relative, _) {
            // Re-fetch buffered values to show background progress
            final buffered = widget.controller.value.buffered;
            
            return AnimatedBuilder(
              animation: _barScaleAnimation,
              builder: (context, child) {
                return CustomPaint(
                  painter: _ProgressBarPainter(
                    relative: relative,
                    buffered: buffered,
                    duration: widget.controller.value.duration,
                    isDragging: _isDragging,
                    expansion: _barScaleAnimation.value,
                    barCenterOffset: widget.barCenterOffset,
                    barHeight: widget.barHeight,
                    activeBarHeight: widget.activeBarHeight,
                    thumbRadius: widget.thumbRadius,
                    primaryColor: AppColors.primary,
                    bufferedColor: AppColors.white.withValues(alpha: 0.3),
                    backgroundColor: AppColors.backgroundSecondary.withValues(alpha: 0.5),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _ProgressBarPainter extends CustomPainter {
  final double relative;
  final List<DurationRange> buffered;
  final Duration duration;
  final bool isDragging;
  final double expansion;
  final double? barCenterOffset;
  final double barHeight;
  final double activeBarHeight;
  final double thumbRadius;
  final Color primaryColor;
  final Color bufferedColor;
  final Color backgroundColor;

  _ProgressBarPainter({
    required this.relative,
    required this.buffered,
    required this.duration,
    required this.isDragging,
    required this.expansion,
    this.barCenterOffset,
    required this.barHeight,
    required this.activeBarHeight,
    required this.thumbRadius,
    required this.primaryColor,
    required this.bufferedColor,
    required this.backgroundColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final currentBarHeight = barHeight + (activeBarHeight - barHeight) * expansion;
    // **FIX: Draw bar at the vertical center (default) or overridden offset**
    final centerY = barCenterOffset ?? size.height / 2;
    
    final bgPaint = Paint()..color = backgroundColor;
    final buffPaint = Paint()..color = bufferedColor;
    final playPaint = Paint()..color = primaryColor;
    final thumbPaint = Paint()..color = Colors.white;

    // Background bar
    canvas.drawRRect(
      RRect.fromLTRBR(0, centerY - currentBarHeight / 2, size.width,
          centerY + currentBarHeight / 2, Radius.circular(currentBarHeight / 2)),
      bgPaint,
    );

    // Buffered areas
    if (duration.inMilliseconds > 0) {
      for (final range in buffered) {
        final startRelative = range.start.inMilliseconds / duration.inMilliseconds;
        final endRelative = range.end.inMilliseconds / duration.inMilliseconds;
        
        canvas.drawRRect(
          RRect.fromLTRBR(
            size.width * startRelative,
            centerY - currentBarHeight / 2,
            size.width * endRelative,
            centerY + currentBarHeight / 2,
            Radius.circular(currentBarHeight / 2),
          ),
          buffPaint,
        );
      }
    }

    // Played bar (with glow effect during interaction)
    if (expansion > 0.05) {
      final glowPaint = Paint()
        ..color = primaryColor.withValues(alpha: 0.3 * expansion)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
      canvas.drawRRect(
        RRect.fromLTRBR(
          0,
          centerY - (currentBarHeight + 2 * expansion) / 2,
          size.width * relative,
          centerY + (currentBarHeight + 2 * expansion) / 2,
          Radius.circular(currentBarHeight / 2),
        ),
        glowPaint,
      );
    }

    canvas.drawRRect(
      RRect.fromLTRBR(
        0,
        centerY - currentBarHeight / 2,
        size.width * relative,
        centerY + currentBarHeight / 2,
        Radius.circular(currentBarHeight / 2),
      ),
      playPaint,
    );

    // Thumb
    if (expansion > 0.01) {
      final thumbX = size.width * relative;
      final currentThumbRadius = thumbRadius * expansion;
      
      // Shadow for thumb
      canvas.drawCircle(
        Offset(thumbX, centerY),
        currentThumbRadius + 1,
        Paint()
          ..color = Colors.black26
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
      );
      
      canvas.drawCircle(
        Offset(thumbX, centerY),
        currentThumbRadius,
        thumbPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_ProgressBarPainter oldDelegate) {
    return oldDelegate.relative != relative ||
        oldDelegate.isDragging != isDragging ||
        oldDelegate.expansion != expansion ||
        oldDelegate.buffered.length != buffered.length;
  }
}
