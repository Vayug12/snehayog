import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:vayug/core/design/colors.dart';
import 'package:vayug/features/video/core/data/models/video_model.dart';
import 'package:vayug/features/video/upload/domain/models/episode_draft.dart';
import 'package:vayug/shared/widgets/app_button.dart';
import 'package:vayug/features/video/quiz/presentation/screens/create_quiz_screen.dart';
import 'package:vayug/shared/utils/app_logger.dart';
import 'package:vayug/features/video/upload/presentation/screens/subscriber_selection_screen.dart';

class UploadAdvancedSettingsScreen extends StatefulWidget {
  final TextEditingController linkController;
  final TextEditingController tagInputController;
  final ValueNotifier<List<String>> tags;
  final void Function(String) onAddTag;
  final void Function(String) onRemoveTag;

  /// Episodes 2..N of the series draft. Episode 1 is the video already picked
  /// in the main flow, so this being empty means "not a series".
  final ValueNotifier<List<EpisodeDraft>> seriesEpisodes;
  final VoidCallback onEditSeries;
  final ValueNotifier<List<QuizModel>> quizzes;
  final ValueNotifier<List<String>> selectedPlatforms;
  final ValueNotifier<List<String>> selectedSubscribers;
  final ValueNotifier<File?> selectedThumbnail;
  final double videoDuration;
  final double videoAspectRatio;

  const UploadAdvancedSettingsScreen({
    super.key,
    required this.linkController,
    required this.tagInputController,
    required this.tags,
    required this.onAddTag,
    required this.onRemoveTag,
    required this.seriesEpisodes,
    required this.onEditSeries,
    required this.quizzes,
    required this.selectedPlatforms,
    required this.selectedSubscribers,
    required this.selectedThumbnail,
    this.videoDuration = 0.0,
    this.videoAspectRatio = 9/16,
  });

  @override
  State<UploadAdvancedSettingsScreen> createState() => _UploadAdvancedSettingsScreenState();
}

class _UploadAdvancedSettingsScreenState extends State<UploadAdvancedSettingsScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      body: CustomScrollView(
        slivers: [
          const SliverAppBar(
            title: Text('Advanced Settings', style: TextStyle(fontWeight: FontWeight.bold)),
            centerTitle: true,
            backgroundColor: AppColors.backgroundPrimary,
            floating: true,
            snap: true,
            elevation: 0,
          ),
          SliverList(
            delegate: SliverChildListDelegate([
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    _buildThumbnailRow(),

                    _buildSettingRow(
                      icon: Icons.help_outline_rounded,
                      title: 'Quizzes',
                      subtitle: 'Add interactive questions',
                      trailing: ValueListenableBuilder<List<QuizModel>>(
                        valueListenable: widget.quizzes,
                        builder: (context, current, _) {
                          return Text(
                            current.isEmpty ? 'None' : '${current.length} added',
                            style: TextStyle(
                              color: current.isEmpty ? AppColors.textTertiary : AppColors.primary,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          );
                        },
                      ),
                      onTap: () async {
                        final List<QuizModel>? result = await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => CreateQuizScreen(
                              initialQuizzes: widget.quizzes.value,
                              videoDurationInSeconds: widget.videoDuration,
                            ),
                          ),
                        );
                        if (result != null) widget.quizzes.value = result;
                      },
                    ),

                    _buildSettingRow(
                      icon: Icons.tag_rounded,
                      title: 'Discovery Tags',
                      subtitle: 'Help people find your video',
                      trailing: ValueListenableBuilder<List<String>>(
                        valueListenable: widget.tags,
                        builder: (context, current, _) {
                          return Text(
                            current.isEmpty ? 'Add' : '${current.length} tags',
                            style: TextStyle(
                              color: current.isEmpty ? AppColors.textTertiary : AppColors.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          );
                        },
                      ),
                      onTap: () => _showAddTagsBottomSheet(context),
                    ),
                    
                    _buildSettingRow(
                      icon: Icons.link_rounded,
                      title: 'Promotional Link',
                      subtitle: 'Website or purchase link',
                      trailing: AnimatedBuilder(
                        animation: widget.linkController,
                        builder: (context, _) {
                          final hasLink = widget.linkController.text.isNotEmpty;
                          return Text(
                            hasLink ? 'Added' : 'None',
                            style: TextStyle(
                              color: !hasLink ? AppColors.textTertiary : AppColors.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          );
                        },
                      ),
                      onTap: () => _showLinkEditor(context),
                    ),

                    _buildSeriesRow(),

                    _buildSubscriberOnlyTile(),
                    
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ]),
          ),
        ],
      ),
      // Pinned so the primary action is visible without scrolling
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.backgroundPrimary,
        border: Border(
          top: BorderSide(color: AppColors.borderPrimary.withValues(alpha: 0.4)),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: AppButton(
            onPressed: () => Navigator.pop(context),
            label: 'Done',
            variant: AppButtonVariant.primary,
            isFullWidth: true,
          ),
        ),
      ),
    );
  }

  /// Behaves like every other row here: it edits the draft and comes back.
  /// The upload itself only ever starts from the main upload screen.
  Widget _buildSeriesRow() {
    return ValueListenableBuilder<List<EpisodeDraft>>(
      valueListenable: widget.seriesEpisodes,
      builder: (context, episodes, _) {
        final isSeries = episodes.isNotEmpty;
        return _buildSettingRow(
          icon: Icons.video_collection_outlined,
          title: 'Series',
          subtitle: 'Upload this as a numbered multi-episode series',
          trailing: Text(
            isSeries ? '${episodes.length + 1} episodes' : 'Off',
            style: TextStyle(
              color: isSeries ? AppColors.primary : AppColors.textTertiary,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
          onTap: widget.onEditSeries,
        );
      },
    );
  }

  Widget _buildSettingRow({
    required IconData icon,
    required String title,
    String? subtitle,
    Widget? trailing,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 4),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.backgroundSecondary.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 22, color: AppColors.textPrimary),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle,
                      style: const TextStyle(color: AppColors.textTertiary, fontSize: 12),
                    ),
                ],
              ),
            ),
            if (trailing != null) ...[
              trailing,
              const SizedBox(width: 8),
            ],
            const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: AppColors.textTertiary),
          ],
        ),
      ),
    );
  }

  void _showLinkEditor(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.backgroundPrimary,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
          left: 24, right: 24, top: 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Promotional Link', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
            const SizedBox(height: 8),
            const Text('Add a website or product link to your video details.', style: TextStyle(color: AppColors.textTertiary, fontSize: 13)),
            const SizedBox(height: 24),
            TextField(
              controller: widget.linkController,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'https://...',
                prefixIcon: const Icon(Icons.link),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 24),
            AppButton(onPressed: () => Navigator.pop(context), label: 'Save Link', variant: AppButtonVariant.primary, isFullWidth: true),
          ],
        ),
      ),
    );
  }

  void _showAddTagsBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.backgroundPrimary,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
            left: 20,
            right: 20,
            top: 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Search Tags',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: widget.tagInputController,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Type tag and press Add',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.add_box_rounded, color: AppColors.primary),
                    onPressed: () {
                      if (widget.tagInputController.text.isNotEmpty) {
                        widget.onAddTag(widget.tagInputController.text);
                        widget.tagInputController.clear();
                      }
                    },
                  ),
                ),
                onSubmitted: (value) {
                  if (value.isNotEmpty) {
                    widget.onAddTag(value);
                    widget.tagInputController.clear();
                  }
                },
              ),
              const SizedBox(height: 20),
              ValueListenableBuilder<List<String>>(
                valueListenable: widget.tags,
                builder: (context, currentTags, _) {
                  if (currentTags.isEmpty) {
                    return Container(
                      height: 100,
                      decoration: BoxDecoration(
                        color: AppColors.backgroundSecondary,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Center(child: Text('No tags added yet')),
                    );
                  }
                  return Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: currentTags
                        .map((tag) => Chip(
                              label: Text(tag),
                              backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                              side: BorderSide.none,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              onDeleted: () => widget.onRemoveTag(tag),
                              deleteIcon: const Icon(Icons.cancel, size: 16),
                            ))
                        .toList(),
                  );
                },
              ),
              const SizedBox(height: 24),
              AppButton(
                onPressed: () => Navigator.pop(context),
                label: 'Done',
                variant: AppButtonVariant.primary,
                isFullWidth: true,
              ),
              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSubscriberOnlyTile() {
    return ValueListenableBuilder<List<String>>(
      valueListenable: widget.selectedSubscribers,
      builder: (context, selected, _) {
        return _buildSettingRow(
          icon: Icons.lock_person,
          title: 'End-to-end encrypted',
          subtitle: selected.isEmpty
              ? 'End-to-end encrypted video'
              : '${selected.length} subscriber${selected.length == 1 ? '' : 's'} selected',
          trailing: selected.isEmpty
              ? null
              : Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${selected.length}',
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
          onTap: () => _navigateToSubscriberSelection(context),
        );
      },
    );
  }

  void _navigateToSubscriberSelection(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SubscriberSelectionScreen(
          selectedSubscribers: widget.selectedSubscribers,
        ),
      ),
    );
  }

  Widget _buildThumbnailRow() {
    return ValueListenableBuilder<File?>(
      valueListenable: widget.selectedThumbnail,
      builder: (context, file, _) {
        return Column(
          children: [
            _buildSettingRow(
              icon: Icons.image_rounded,
              title: 'Custom Thumbnail',
              subtitle: file == null ? 'Select a cover image' : 'Custom image selected',
              trailing: file != null 
                ? IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20, color: Colors.redAccent),
                    onPressed: () => widget.selectedThumbnail.value = null,
                  )
                : null,
              onTap: _pickThumbnail,
            ),
            if (file != null) _buildThumbnailPreview(file),
          ],
        );
      },
    );
  }

  Widget _buildThumbnailPreview(File file) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Preview',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: AppColors.textTertiary,
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.6,
                maxHeight: 300,
              ),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.primary.withValues(alpha: 0.3), width: 2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: AspectRatio(
                aspectRatio: widget.videoAspectRatio,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.file(file, fit: BoxFit.cover),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Center(
            child: Text(
              'Thumbnail aspect ratio matches your video (${widget.videoAspectRatio > 1 ? "Horizontal" : "Vertical"})',
              style: const TextStyle(fontSize: 10, color: AppColors.textTertiary),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickThumbnail() async {
    try {
      // Use standard file picker for images
      final result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => Scaffold(
            appBar: AppBar(title: const Text('Select Thumbnail')),
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.image_search, size: 64, color: AppColors.textTertiary),
                  const SizedBox(height: 16),
                  const Text('Pick a thumbnail image from gallery'),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (widget.selectedThumbnail.value != null)
                        Padding(
                          padding: const EdgeInsets.only(right: 12),
                          child: AppButton(
                            onPressed: () {
                              widget.selectedThumbnail.value = null;
                              Navigator.pop(context);
                            },
                            label: 'Remove',
                            variant: AppButtonVariant.secondary,
                          ),
                        ),
                      AppButton(
                        onPressed: () async {
                          // Note: In a real app we'd use a file picker service, 
                          // but for this task I'll assume we can use a basic implementation
                          // or the user will provide one.
                          // Let's use the provided file picker if available.
                          Navigator.pop(context, 'pick');
                        },
                        label: 'Pick Image',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      if (result == 'pick') {
         // Assuming we can use something like ImagePicker or FilePicker here.
         // Since I don't want to add new dependencies or guess the exact service name,
         // I'll use a placeholder that the user can adapt if they have a specific service.
         // However, I see 'file_picker' is imported in upload_screen.dart.
         // Let's use the same logic.
         // For now, I'll ask the user to provide the logic or I'll try to find a picker service.
         AppLogger.log('Thumbnail pick requested');
         _pickFile();
      }
    } catch (e) {
      AppLogger.log('Error picking thumbnail: $e');
    }
  }

  void _pickFile() async {
     try {
       final result = await FilePicker.platform.pickFiles(
         type: FileType.image,
         allowMultiple: false,
       );

       if (result != null && result.files.single.path != null) {
         widget.selectedThumbnail.value = File(result.files.single.path!);
       }
     } catch (e) {
       AppLogger.log('❌ Error picking thumbnail file: $e');
     }
  }
}

