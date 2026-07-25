import 'package:flutter/material.dart';
import 'package:vayug/core/design/colors.dart';
import 'package:vayug/core/design/spacing.dart';
import 'package:vayug/core/design/typography.dart';
import 'package:vayug/features/video/core/data/models/video_model.dart';
import 'package:vayug/shared/widgets/app_button.dart';
import 'package:vayug/shared/widgets/vayu_snackbar.dart';
import 'package:hugeicons/hugeicons.dart';

class CreateQuizScreen extends StatefulWidget {
  final List<QuizModel> initialQuizzes;
  final double videoDurationInSeconds;

  const CreateQuizScreen({
    super.key,
    required this.initialQuizzes,
    required this.videoDurationInSeconds,
  });

  @override
  State<CreateQuizScreen> createState() => _CreateQuizScreenState();
}

class _CreateQuizScreenState extends State<CreateQuizScreen> {
  late List<QuizModel> _quizzes;
  final _scrollController = ScrollController();

  int get _maxAllowedQuizzes {
    final duration = widget.videoDurationInSeconds;
    return duration > 0 ? (duration / 5).floor().clamp(1, 99) : 99;
  }

  @override
  void initState() {
    super.initState();
    _quizzes = List.from(widget.initialQuizzes);
  }

  void _addQuiz() {
    // Density check: 1 quiz per 5 seconds. When the duration is unknown
    // (metadata probe failed), don't block quiz creation on a bogus limit.
    final maxAllowedCount = _maxAllowedQuizzes;

    if (_quizzes.length >= maxAllowedCount) {
      VayuSnackBar.showError(
        context,
        'Quiz limit reached — this video fits up to $maxAllowedCount ${maxAllowedCount == 1 ? 'quiz' : 'quizzes'} (one every 5 seconds).',
      );
      return;
    }

    setState(() {
      _quizzes.add(QuizModel(
        timestamp: widget.videoDurationInSeconds > 10 ? 10 : widget.videoDurationInSeconds / 2,
        question: '',
        options: ['', ''],
        correctIndex: 0,
      ));
    });
    
    // Scroll to bottom after adding
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
  }

  void _removeQuiz(int index) {
    setState(() {
      _quizzes.removeAt(index);
    });
  }

  void _updateQuiz(int index, QuizModel updated) {
    setState(() {
      _quizzes[index] = updated;
    });
  }

  void _saveAndExit() {
    // Basic validation
    for (int i = 0; i < _quizzes.length; i++) {
      final q = _quizzes[i];
      if (q.question.trim().isEmpty) {
        VayuSnackBar.showError(
            context, 'Please enter a question for Quiz #${i + 1}');
        return;
      }
      if (q.options.any((opt) => opt.trim().isEmpty)) {
        VayuSnackBar.showError(
            context, 'All options in Quiz #${i + 1} must be filled');
        return;
      }
    }

    Navigator.pop(context, _quizzes);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      body: CustomScrollView(
        controller: _scrollController,
        slivers: [
          SliverAppBar(
            title: const Text('Manage Quizzes', style: TextStyle(fontWeight: FontWeight.bold)),
            backgroundColor: AppColors.backgroundPrimary,
            floating: true,
            snap: true,
            elevation: 0,
            centerTitle: true,
            leading: IconButton(
              icon: const Icon(Icons.close_rounded),
              onPressed: () => Navigator.pop(context),
            ),
            actions: [
              TextButton(
                onPressed: _saveAndExit,
                child: const Text('SAVE', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          SliverToBoxAdapter(child: _buildInfoBanner()),
          if (_quizzes.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _buildEmptyState(),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) => _buildQuizRow(index, _quizzes[index]),
                  childCount: _quizzes.length,
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addQuiz,
        backgroundColor: AppColors.primary,
        icon: const Icon(Icons.add_rounded, color: Colors.white),
        label: const Text('Add Quiz', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildInfoBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.1)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded, color: AppColors.primary, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              widget.videoDurationInSeconds > 0
                  ? 'Add interactive quizzes at specific times. ${_quizzes.length}/$_maxAllowedQuizzes used for this ${widget.videoDurationInSeconds.toStringAsFixed(0)}s video.'
                  : 'Add interactive quizzes at specific times to engage your audience.',
              style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.backgroundSecondary.withValues(alpha: 0.5),
              shape: BoxShape.circle,
            ),
            child: const HugeIcon(icon: HugeIcons.strokeRoundedHelpCircle, size: 64, color: AppColors.textTertiary),
          ),
          const SizedBox(height: 16),
          Text(
            'No quizzes added yet',
            style: AppTypography.titleMedium.copyWith(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildQuizRow(int index, QuizModel quiz) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
      leading: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.backgroundSecondary.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.quiz_rounded, color: AppColors.textPrimary, size: 20),
      ),
        title: Text(
          quiz.question.isEmpty ? 'New Question' : quiz.question,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: quiz.question.isEmpty ? AppColors.textSecondary : AppColors.textPrimary,
          ),
        ),
        subtitle: Text(
          'Appears at ${quiz.timestamp.toStringAsFixed(1)}s • ${quiz.options.length} options',
          style: const TextStyle(fontSize: 12),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.edit_rounded, size: 18, color: AppColors.textTertiary),
            AppSpacing.hSpace8,
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded, color: AppColors.error, size: 20),
              onPressed: () => _removeQuiz(index),
            ),
          ],
        ),
        onTap: () => _showQuizEditor(index),
      );
  }

  void _showQuizEditor(int index) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _QuizBottomSheetEditor(
        quiz: _quizzes[index],
        index: index,
        maxDuration: widget.videoDurationInSeconds,
        onChanged: (updated) => _updateQuiz(index, updated),
      ),
    );
  }
}

class _QuizBottomSheetEditor extends StatefulWidget {
  final QuizModel quiz;
  final int index;
  final double maxDuration;
  final Function(QuizModel) onChanged;

  const _QuizBottomSheetEditor({
    required this.quiz,
    required this.index,
    required this.maxDuration,
    required this.onChanged,
  });

  @override
  State<_QuizBottomSheetEditor> createState() => _QuizBottomSheetEditorState();
}

class _QuizBottomSheetEditorState extends State<_QuizBottomSheetEditor> {
  late TextEditingController _questionController;
  late TextEditingController _timeController;
  late List<TextEditingController> _optionControllers;
  late QuizModel _localQuiz;

  @override
  void initState() {
    super.initState();
    _localQuiz = widget.quiz;
    _questionController = TextEditingController(text: _localQuiz.question);
    _timeController = TextEditingController(text: _localQuiz.timestamp.toStringAsFixed(1));
    _optionControllers = _localQuiz.options
        .map((opt) => TextEditingController(text: opt))
        .toList();
  }

  @override
  void dispose() {
    _questionController.dispose();
    _timeController.dispose();
    for (var c in _optionControllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _updateTimeFromText() {
    final val = double.tryParse(_timeController.text);
    if (val != null) {
      final clamped = val.clamp(0.0, widget.maxDuration);
      setState(() {
        _localQuiz = _localQuiz.copyWith(timestamp: clamped);
      });
      widget.onChanged(_localQuiz);
      if (clamped != val) {
        _timeController.text = clamped.toStringAsFixed(1);
      }
    }
  }

  void _onQuizContentChanged() {
    widget.onChanged(_localQuiz);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.backgroundPrimary,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        left: 24,
        right: 24,
        top: 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Edit Quiz #${widget.index + 1}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 22),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            AppSpacing.vSpace24,
            
            // Question Field
            const Text('Question', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 0.5)),
            AppSpacing.vSpace8,
            TextField(
              controller: _questionController,
              onChanged: (val) {
                setState(() {
                  _localQuiz = _localQuiz.copyWith(question: val);
                });
                _onQuizContentChanged();
              },
              maxLines: 2,
              decoration: InputDecoration(
                hintText: 'What is the capital of India?',
                filled: true,
                fillColor: AppColors.backgroundSecondary.withValues(alpha: 0.5),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.all(16),
              ),
            ),
            
            AppSpacing.vSpace24,
            
            // Timestamp Control
            Row(
              children: [
                const Icon(Icons.timer_outlined, size: 16, color: AppColors.primary),
                const SizedBox(width: 8),
                const Text('APPEARANCE TIME', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 0.5)),
                const Spacer(),
                Container(
                  width: 70,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: TextField(
                    controller: _timeController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.primary),
                    onSubmitted: (_) => _updateTimeFromText(),
                    decoration: const InputDecoration(isDense: true, border: InputBorder.none, suffixText: 's'),
                  ),
                ),
              ],
            ),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 4,
                activeTrackColor: AppColors.primary,
                inactiveTrackColor: AppColors.primary.withValues(alpha: 0.1),
                thumbColor: AppColors.primary,
                overlayColor: AppColors.primary.withValues(alpha: 0.1),
              ),
              child: Slider(
                value: _localQuiz.timestamp.clamp(0.0, widget.maxDuration),
                min: 0,
                max: widget.maxDuration > 0 ? widget.maxDuration : 1.0,
                onChanged: (val) {
                  setState(() {
                    _localQuiz = _localQuiz.copyWith(timestamp: val);
                    _timeController.text = val.toStringAsFixed(1);
                  });
                  _onQuizContentChanged();
                },
              ),
            ),

            AppSpacing.vSpace24,
            
            // Options List
            const Text('OPTIONS & CORRECT ANSWER', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 0.8)),
            AppSpacing.vSpace16,
            ...List.generate(_localQuiz.options.length, (optIndex) {
              final isCorrect = _localQuiz.correctIndex == optIndex;
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          _localQuiz = _localQuiz.copyWith(correctIndex: optIndex);
                        });
                        _onQuizContentChanged();
                      },
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: isCorrect ? AppColors.primary : AppColors.backgroundSecondary,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: isCorrect ? AppColors.primary : AppColors.borderPrimary.withValues(alpha: 0.5)),
                        ),
                        child: Icon(isCorrect ? Icons.check_circle_rounded : Icons.radio_button_off_rounded, color: isCorrect ? Colors.white : AppColors.textTertiary, size: 22),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _optionControllers[optIndex],
                        onChanged: (val) {
                          final newOptions = List<String>.from(_localQuiz.options);
                          newOptions[optIndex] = val;
                          setState(() {
                            _localQuiz = _localQuiz.copyWith(options: newOptions);
                          });
                          _onQuizContentChanged();
                        },
                        decoration: InputDecoration(
                          hintText: 'Option ${optIndex + 1}',
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                          filled: true,
                          fillColor: isCorrect ? AppColors.primary.withValues(alpha: 0.05) : AppColors.backgroundSecondary.withValues(alpha: 0.4),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14), 
                            borderSide: BorderSide(color: isCorrect ? AppColors.primary : Colors.transparent, width: 1.5),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14), 
                            borderSide: BorderSide(color: isCorrect ? AppColors.primary : Colors.transparent, width: 1.5),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14), 
                            borderSide: const BorderSide(color: AppColors.primary, width: 2),
                          ),
                        ),
                      ),
                    ),
                    if (_localQuiz.options.length > 2)
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline, size: 22, color: Colors.redAccent),
                        onPressed: () {
                          setState(() {
                            _optionControllers.removeAt(optIndex);
                            final newOptions = List<String>.from(_localQuiz.options);
                            newOptions.removeAt(optIndex);
                            _localQuiz = _localQuiz.copyWith(
                              options: newOptions,
                              correctIndex: _localQuiz.correctIndex >= newOptions.length ? 0 : _localQuiz.correctIndex,
                            );
                          });
                          _onQuizContentChanged();
                        },
                      ),
                  ],
                ),
              );
            }),
            
            TextButton.icon(
              onPressed: () {
                setState(() {
                  _optionControllers.add(TextEditingController());
                  final newOptions = List<String>.from(_localQuiz.options)..add('');
                  _localQuiz = _localQuiz.copyWith(options: newOptions);
                });
                _onQuizContentChanged();
              },
              icon: const Icon(Icons.add_circle_outline_rounded, size: 20),
              label: const Text('Add Option', style: TextStyle(fontWeight: FontWeight.bold)),
              style: TextButton.styleFrom(foregroundColor: AppColors.primary),
            ),
            
            AppSpacing.vSpace32,
            AppButton(
              onPressed: () => Navigator.pop(context),
              label: 'Done',
              variant: AppButtonVariant.primary,
              isFullWidth: true,
              size: AppButtonSize.large,
            ),
          ],
        ),
      ),
    );
  }
}
