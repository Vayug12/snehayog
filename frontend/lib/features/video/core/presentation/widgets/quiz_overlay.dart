import 'package:flutter/material.dart';
import 'package:vayug/core/design/spacing.dart';
import 'package:vayug/features/video/core/data/models/video_model.dart';
import 'dart:ui';

class QuizOverlay extends StatefulWidget {
  final QuizModel quiz;
  final VoidCallback onDismiss;
  final VoidCallback? onBack;
  final Function(int) onAnswered;
  final bool isCompact;
  final AlignmentGeometry? alignment;
  final EdgeInsetsGeometry? outerPadding;
  final double? maxWidth;

  const QuizOverlay({
    super.key,
    required this.quiz,
    required this.onDismiss,
    this.onBack,
    required this.onAnswered,
    this.isCompact = false,
    this.alignment,
    this.outerPadding,
    this.maxWidth,
  });

  @override
  State<QuizOverlay> createState() => _QuizOverlayState();
}

class _QuizOverlayState extends State<QuizOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _offsetAnimation;
  int? _selectedOption;
  bool _showResult = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _offsetAnimation = Tween<Offset>(
      begin: const Offset(0.0, 0.2),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    ));
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleOptionSelect(int index) {
    if (_showResult) return;
    if (mounted) {
      setState(() {
        _selectedOption = index;
        _showResult = true;
      });
    }
    widget.onAnswered(index);
    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted) _dismiss();
    });
  }

  void _dismiss() {
    if (mounted) {
      _controller.reverse().then((_) {
        if (mounted) widget.onDismiss();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final resolvedAlignment = widget.alignment ??
        (isLandscape ? Alignment.centerLeft : Alignment.center);
    final resolvedOuterPadding = widget.outerPadding ??
        EdgeInsets.symmetric(
          horizontal: isLandscape ? 48 : 0,
          vertical: isLandscape ? 20 : 0,
        );
    final resolvedMaxWidth =
        widget.maxWidth ?? (isLandscape ? (size.width * 0.35) : size.width);
    final optionColumnCount = resolvedMaxWidth < 280 ? 1 : 2;

    return FadeTransition(
      opacity: _controller,
      child: Align(
        alignment: resolvedAlignment,
        child: Padding(
          padding: resolvedOuterPadding,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: resolvedMaxWidth,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(widget.isCompact ? 12 : 16),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: EdgeInsets.symmetric(
                    horizontal: widget.isCompact ? 12.0 : AppSpacing.spacing4,
                    vertical: widget.isCompact ? 8.0 : AppSpacing.spacing3,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.45),
                    borderRadius:
                        BorderRadius.circular(widget.isCompact ? 12 : 16),
                    border:
                        Border.all(color: Colors.white.withValues(alpha: 0.15)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.2),
                        blurRadius: 20,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          if (widget.onBack != null)
                            Padding(
                              padding: const EdgeInsets.only(right: 8.0),
                              child: GestureDetector(
                                onTap: widget.onBack,
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.1),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(Icons.arrow_back_rounded,
                                      size: widget.isCompact ? 11 : 14,
                                      color: Colors.white),
                                ),
                              ),
                            ),
                          Expanded(
                            child: Text(
                              widget.quiz.question,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: widget.isCompact ? 12 : 14,
                                fontWeight: FontWeight.bold,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: _dismiss,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.1),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(Icons.close,
                                  size: widget.isCompact ? 11 : 14,
                                  color: Colors.white),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: widget.isCompact ? 6 : 10),
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        padding: EdgeInsets.zero,
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: optionColumnCount,
                          crossAxisSpacing: widget.isCompact ? 6 : 8,
                          mainAxisSpacing: widget.isCompact ? 6 : 8,
                          childAspectRatio: optionColumnCount == 1
                              ? (widget.isCompact ? 4.2 : 4)
                              : isLandscape
                                  ? 2.2
                                  : (widget.isCompact ? 3.4 : 3.2),
                        ),
                        itemCount: widget.quiz.options.length,
                        itemBuilder: (context, index) {
                          bool isCorrect = index == widget.quiz.correctIndex;
                          bool isSelected = index == _selectedOption;
                          Color borderColor =
                              Colors.white.withValues(alpha: 0.1);
                          Color textColor = Colors.white.withValues(alpha: 0.8);

                          if (_showResult) {
                            if (isCorrect) {
                              borderColor = Colors.green.withValues(alpha: 0.6);
                              textColor = Colors.greenAccent;
                            } else if (isSelected && !isCorrect) {
                              borderColor = Colors.red.withValues(alpha: 0.6);
                              textColor = Colors.redAccent;
                            }
                          }

                          return GestureDetector(
                            onTap: () => _handleOptionSelect(index),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: EdgeInsets.symmetric(
                                  horizontal: widget.isCompact ? 6 : 8,
                                  vertical: widget.isCompact ? 2 : 4),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? Colors.white.withValues(alpha: 0.1)
                                    : Colors.white.withValues(alpha: 0.05),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: borderColor),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      widget.quiz.options[index],
                                      style: TextStyle(
                                        color: textColor,
                                        fontSize: widget.isCompact ? 9.5 : 11,
                                        fontWeight: isSelected
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 1,
                                    ),
                                  ),
                                  if (_showResult && isCorrect)
                                    Icon(Icons.check_circle,
                                        color: Colors.green,
                                        size: widget.isCompact ? 8 : 10),
                                  if (_showResult && isSelected && !isCorrect)
                                    Icon(Icons.cancel,
                                        color: Colors.red,
                                        size: widget.isCompact ? 8 : 10),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
