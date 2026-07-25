import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:vayug/features/video/core/data/models/video_model.dart';
import 'package:vayug/features/video/core/data/services/video_service.dart';
import 'package:vayug/core/design/colors.dart';
import 'package:vayug/core/design/typography.dart';
import 'package:vayug/core/design/spacing.dart';
import 'package:vayug/shared/utils/app_logger.dart';

import 'package:vayug/features/video/quiz/presentation/screens/create_quiz_screen.dart';
import 'package:vayug/shared/widgets/app_button.dart';

class EditVideoDetails extends StatefulWidget {
  final VideoModel video;
  const EditVideoDetails({super.key, required this.video});

  @override
  State<EditVideoDetails> createState() => _EditVideoDetailsState();
}

class _EditVideoDetailsState extends State<EditVideoDetails> {
  late TextEditingController _titleController;
  late TextEditingController _linkController;
  late TextEditingController _tagsController;
  late List<Map<String, dynamic>> _episodes;
  late List<QuizModel> _quizzes;
  String? _seriesId;
  final VideoService _videoService = VideoService();
  bool _isSaving = false;
  String? _error;
  File? _selectedThumbnail;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.video.videoName);
    _linkController = TextEditingController(text: widget.video.link ?? '');
    _tagsController = TextEditingController(text: widget.video.tags?.join(', ') ?? '');
    
    _quizzes = widget.video.quizzes != null ? List<QuizModel>.from(widget.video.quizzes!) : [];
    
    // Initialize episodes and ensure the current video is IN the list
    final episodesFromVideo = widget.video.episodes ?? [];
    _episodes = List<Map<String, dynamic>>.from(episodesFromVideo);
    
    // If the current video isn't in its own episodes list (happens for new series), add it!
    final bool currentIncluded = _episodes.any((e) => e['id'] == widget.video.id || e['_id'] == widget.video.id);
    if (!currentIncluded) {
      _episodes.insert(0, {
        'id': widget.video.id,
        'videoName': widget.video.videoName,
        'thumbnailUrl': widget.video.thumbnailUrl,
      });
    }
    
    _seriesId = widget.video.seriesId;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _linkController.dispose();
    _tagsController.dispose();
    super.dispose();
  }

  Future<void> _saveChanges() async {
    final newTitle = _titleController.text.trim();
    final newLink = _linkController.text.trim();
    final newTagsStr = _tagsController.text.trim();
    
    if (newTitle.isEmpty) {
      setState(() => _error = 'Video title cannot be empty');
      return;
    }

    final List<String> newTags = newTagsStr
        .split(',')
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList();

    setState(() {
      _isSaving = true;
      _error = null;
    });

    try {
      // 1. Update main video basic metadata (title, link, tags)
      final updatedMainVideo = await _videoService.updateVideoMetadata(
        widget.video.id, 
        newTitle,
        link: newLink,
        tags: newTags,
        quizzes: _quizzes,
        thumbnailFile: _selectedThumbnail,
      );

      // 2. Handle Series Linking (Bulk Update)
      if (_episodes.length > 1) {
        final List<String> episodeIds = _episodes
            .map((e) => (e['id'] ?? e['_id']).toString())
            .toList();
            
        final seriesResult = await _videoService.updateVideoSeries(
          widget.video.id, 
          episodeIds,
          seriesId: _seriesId,
        );
        
        // Update local state with the returned episodes from the refined bulk update
        if (mounted) {
          setState(() => _isSaving = false);
          Navigator.of(context).pop({
            'videoName': updatedMainVideo.videoName,
            'link': updatedMainVideo.link,
            'tags': updatedMainVideo.tags,
            'quizzes': updatedMainVideo.quizzes,
            'episodes': seriesResult['episodes'], // Full list from backend
            'seriesId': seriesResult['seriesId'],
          });
        }
      } else {
        // Not a series anymore OR never was. 
        // If it was a series before (widget.video.seriesId != null), we must explicitly unlink it.
        VideoModel finalVideo = updatedMainVideo;
        
        if (widget.video.seriesId != null && widget.video.seriesId!.isNotEmpty) {
          AppLogger.log('🔄 EditVideoDetails: Unlinking video from series...');
          finalVideo = await _videoService.updateVideoMetadata(
            widget.video.id, 
            newTitle,
            link: newLink,
            tags: newTags,
            seriesId: '', // Explicitly clear
            episodeNumber: 0, // Explicitly clear
            quizzes: _quizzes,
            thumbnailFile: _selectedThumbnail,
          );
        }

        if (mounted) {
          setState(() => _isSaving = false);
          Navigator.of(context).pop({
            'videoName': finalVideo.videoName,
            'link': finalVideo.link,
            'tags': finalVideo.tags,
            'quizzes': finalVideo.quizzes,
            'episodes': finalVideo.episodes,
            'seriesId': finalVideo.seriesId,
          });
        }
      }
    } catch (e) {
      AppLogger.log('❌ EditVideoDetails: Failed to save changes: $e');
      if (mounted) {
        setState(() {
          _isSaving = false;
          _error = e.toString().contains('Exception: ') 
              ? e.toString().split('Exception: ').last 
              : e.toString();
        });
      }
    }
  }



  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            title: Text(
              'Edit Video Details',
              style: TextStyle(
                fontSize: AppTypography.fontSizeLG,
                fontWeight: AppTypography.weightSemiBold,
              ),
            ),
            backgroundColor: AppColors.backgroundPrimary,
            foregroundColor: AppColors.textPrimary,
            floating: true,
            snap: true,
            elevation: 0,
            centerTitle: true,
            leading: IconButton(
              icon: const Icon(Icons.close_rounded),
              onPressed: () => Navigator.of(context).pop(),
            ),
            actions: [
              if (_isSaving)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16.0),
                    child: SizedBox(
                       width: 20,
                       height: 20,
                       child: CircularProgressIndicator(
                         strokeWidth: 2,
                         color: AppColors.primary,
                       ),
                    ),
                  ),
                )
              else
                TextButton(
                  onPressed: _saveChanges,
                  child: const Text(
                    'SAVE',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontWeight: AppTypography.weightBold,
                    ),
                  ),
                ),
            ],
          ),
          SliverList(
            delegate: SliverChildListDelegate([
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0),
                child: Column(
                  children: [
                    // Video Main Info Section
                    _buildSettingRow(
                      icon: Icons.info_outline_rounded,
                      title: 'Basic Information',
                      subtitle: _titleController.text.isNotEmpty 
                          ? _titleController.text 
                          : 'Title, Link, and Tags',
                      onTap: _showDetailsEditor,
                    ),

                    AppSpacing.vSpace8,

                    _buildThumbnailEditor(),
                    if (_selectedThumbnail != null) _buildThumbnailPreview(_selectedThumbnail!),
                    
                    AppSpacing.vSpace8,

                    // Series / Episodes Section
                    _buildSettingRow(
                      icon: Icons.layers_rounded,
                      title: 'Series & Episodes',
                      subtitle: _seriesId != null && _seriesId!.isNotEmpty
                          ? 'Part of a series • ${_episodes.length} episodes'
                          : 'Manage series and episodes',
                      onTap: _showSeriesEditor,
                    ),

                    AppSpacing.vSpace8,

                    // Quiz Management (Separate Screen as requested)
                    _buildSettingRow(
                      icon: Icons.add_task_rounded,
                      title: 'Interactive Quizzes',
                      subtitle: _quizzes.isEmpty 
                          ? 'Add questions to the video' 
                          : '${_quizzes.length} quizzes added',
                      onTap: () async {
                        final List<QuizModel>? result = await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => CreateQuizScreen(
                              initialQuizzes: _quizzes,
                              videoDurationInSeconds: widget.video.duration.inSeconds.toDouble(),
                            ),
                          ),
                        );
                        if (result != null) {
                          setState(() {
                            _quizzes = result;
                          });
                        }
                      },
                    ),
                    
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 24.0, left: 4.0),
                        child: Text(
                          '⚠️ $_error',
                          style: const TextStyle(color: Colors.red, fontSize: 13, fontWeight: FontWeight.w500),
                        ),
                      ),                   
                    AppSpacing.vSpace32,
                  ],
                ),
              ),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingRow({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      leading: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.backgroundSecondary.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: AppColors.textPrimary, size: 22),
      ),
      title: Text(
        title,
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 15,
          color: AppColors.textPrimary,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(
          fontSize: 13,
          color: AppColors.textSecondary,
          height: 1.4,
        ),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: const Icon(
        Icons.arrow_forward_ios_rounded,
        size: 14,
        color: AppColors.textTertiary,
      ),
      onTap: onTap,
    );
  }

  Widget _buildThumbnailEditor() {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      leading: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.backgroundSecondary.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.image_rounded, color: AppColors.textPrimary, size: 22),
      ),
      title: const Text(
        'Custom Thumbnail',
        style: TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 15,
          color: AppColors.textPrimary,
        ),
      ),
      subtitle: Text(
        _selectedThumbnail != null ? 'New thumbnail selected' : 'Change video cover image',
        style: const TextStyle(
          fontSize: 13,
          color: AppColors.textSecondary,
        ),
      ),
      trailing: Container(
        width: 60,
        height: 40,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: AppColors.backgroundSecondary,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: _selectedThumbnail != null 
            ? Image.file(_selectedThumbnail!, fit: BoxFit.cover)
            : Image.network(widget.video.thumbnailUrl, fit: BoxFit.cover),
        ),
      ),
      onTap: _pickThumbnail,
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
                aspectRatio: widget.video.aspectRatio,
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
              'Thumbnail aspect ratio matches your video (${widget.video.aspectRatio > 1 ? "Horizontal" : "Vertical"})',
              style: const TextStyle(fontSize: 10, color: AppColors.textTertiary),
            ),
          ),
        ],
      ),
    );
  }

  void _pickThumbnail() async {
    // We'll use a simple modal to ask for pick or remove
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.backgroundPrimary,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Change Thumbnail', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            AppSpacing.vSpace24,
            ListTile(
              leading: const Icon(Icons.photo_library_rounded),
              title: const Text('Pick from Gallery'),
              onTap: () => Navigator.pop(context, 'pick'),
            ),
            if (_selectedThumbnail != null)
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
                title: const Text('Remove Selected', style: TextStyle(color: Colors.redAccent)),
                onTap: () => Navigator.pop(context, 'remove'),
              ),
            AppSpacing.vSpace16,
          ],
        ),
      ),
    );

    if (action == 'pick') {
      try {
        final result = await FilePicker.platform.pickFiles(
          type: FileType.image,
          allowMultiple: false,
        );

        if (result != null && result.files.single.path != null) {
          setState(() {
            _selectedThumbnail = File(result.files.single.path!);
          });
        }
      } catch (e) {
        AppLogger.log('❌ EditVideoDetails: Error picking thumbnail: $e');
      }
    } else if (action == 'remove') {
      setState(() {
        _selectedThumbnail = null;
      });
    }
  }

  void _showDetailsEditor() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          decoration: const BoxDecoration(
            color: AppColors.backgroundPrimary,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom + 24,
            left: 24,
            right: 24,
            top: 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Basic Information',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
              ),
              AppSpacing.vSpace24,
              _buildSectionHeader('Video Title', Icons.title_rounded),
              AppSpacing.vSpace8,
              _buildTextField(
                controller: _titleController,
                hintText: 'Give your video a catchy title',
                maxLines: 2,
                onChanged: (_) { setState(() {}); setModalState(() {}); },
              ),
              AppSpacing.vSpace24,
              _buildSectionHeader('CTA Link', Icons.link_rounded),
              AppSpacing.vSpace8,
              _buildTextField(
                controller: _linkController,
                hintText: 'https://example.com',
                keyboardType: TextInputType.url,
                onChanged: (_) { setState(() {}); setModalState(() {}); },
              ),
              AppSpacing.vSpace24,
              _buildSectionHeader('Tags', Icons.tag_rounded),
              AppSpacing.vSpace8,
              _buildTextField(
                controller: _tagsController,
                hintText: 'Add tags...',
                maxLines: 3,
                onChanged: (_) { setState(() {}); setModalState(() {}); },
              ),
              AppSpacing.vSpace24,
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
      ),
    );
  }

  void _showSeriesEditor() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          decoration: const BoxDecoration(
            color: AppColors.backgroundPrimary,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom + 24,
            left: 24,
            right: 24,
            top: 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Series & Episodes',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
              ),
              AppSpacing.vSpace12,
              const Text(
                'Manage how this video is linked with others in a series.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
              AppSpacing.vSpace24,
              _buildEpisodeManager(setModalState),
              AppSpacing.vSpace24,
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
      ),
    );
  }

  Widget _buildEpisodeManager([StateSetter? setModalState]) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.backgroundSecondary.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderPrimary.withValues(alpha: 0.5)),
      ),
      child: Column(
        children: [
          if (_episodes.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Column(
                children: [
                   const Icon(Icons.layers_clear_rounded, color: AppColors.textTertiary, size: 32),
                  AppSpacing.vSpace8,
                  Text('No episodes linked.', style: AppTypography.bodySmall.copyWith(color: AppColors.textTertiary)),
                ],
              ),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _episodes.length,
              itemBuilder: (context, index) {
                final ep = _episodes[index];
                final bool isCurrent = ep['id'] == widget.video.id || ep['_id'] == widget.video.id;
                
                return ListTile(
                  dense: true,
                  leading: CircleAvatar(
                    radius: 12,
                    backgroundColor: isCurrent ? AppColors.primary : AppColors.backgroundTertiary,
                    child: Text(
                      '${index + 1}', 
                      style: TextStyle(
                        fontSize: 10, 
                        color: isCurrent ? Colors.white : AppColors.textSecondary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  title: Text(
                    ep['videoName'] ?? 'Untitled', 
                    style: AppTypography.bodySmall.copyWith(
                      color: isCurrent ? AppColors.textPrimary : AppColors.textSecondary, 
                      fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                    ), 
                    maxLines: 1, 
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: isCurrent 
                    ? Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), 
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.1), 
                          borderRadius: BorderRadius.circular(6),
                        ), 
                        child: const Text(
                          'CURRENT', 
                          style: TextStyle(color: AppColors.primary, fontSize: 9, fontWeight: FontWeight.bold),
                        ),
                      )
                    : IconButton(
                        icon: const Icon(Icons.remove_circle_outline_rounded, size: 20, color: Colors.redAccent), 
                        onPressed: () {
                          setState(() => _episodes.removeAt(index));
                          if (setModalState != null) setModalState(() {});
                        },
                      ),
                );
              },
            ),
          const Divider(height: 1, color: AppColors.divider),
          TextButton.icon(
            onPressed: () => _showVideoPicker(setModalState),
            icon: const Icon(Icons.add_rounded, size: 20),
            label: const Text('Add Existing Video'),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.primary,
              textStyle: const TextStyle(fontWeight: FontWeight.bold),
              padding: const EdgeInsets.symmetric(vertical: 16),
              minimumSize: const Size(double.infinity, 48),
            ),
          ),
        ],
      ),
    );
  }

  void _showVideoPicker([StateSetter? setModalState]) async {
    // Show a bottom sheet to pick videos
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.backgroundPrimary,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) => _VideoPickerSheet(
        videoType: widget.video.videoType,
        videoService: _videoService,
        currentUserId: widget.video.uploader.id,
        onSelected: (video) {
          Navigator.pop(context);
          setState(() {
            // Check if already in episodes
            if (!_episodes.any((e) => e['id'] == video.id || e['_id'] == video.id)) {
               _episodes.add({
                 'id': video.id,
                 'videoName': video.videoName,
                 'thumbnailUrl': video.thumbnailUrl,
               });
            }
          });
          if (setModalState != null) {
            setModalState(() {});
          }
        },
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppColors.primary),
        AppSpacing.hSpace8,
        Text(
          title,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 12,
            fontWeight: AppTypography.weightSemiBold,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hintText,
    int? maxLines = 1,
    TextInputType? keyboardType,
    Function(String)? onChanged,
  }) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      style: TextStyle(
        color: AppColors.textPrimary,
        fontSize: AppTypography.fontSizeBase,
      ),
      maxLines: maxLines,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: TextStyle(color: AppColors.textSecondary.withValues(alpha: 0.4)),
        filled: true,
        fillColor: AppColors.backgroundSecondary.withValues(alpha: 0.5),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
      ),
    );
  }
}

class _VideoPickerSheet extends StatefulWidget {
  final String videoType;
  final VideoService videoService;
  final String currentUserId;
  final Function(VideoModel) onSelected;

  const _VideoPickerSheet({
    required this.videoType,
    required this.videoService,
    required this.currentUserId,
    required this.onSelected,
  });

  @override
  State<_VideoPickerSheet> createState() => _VideoPickerSheetState();
}

class _VideoPickerSheetState extends State<_VideoPickerSheet> {
  List<VideoModel>? _videos;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadVideos();
  }

  void _loadVideos() async {
    try {
      final allVideos = await widget.videoService.getUserVideos(
        widget.currentUserId,
        videoType: widget.videoType, // Server-side filtering
        limit: 50, // Fetch a larger batch for the picker
        forceRefresh: true, // Always get latest for picker
      );
      
      setState(() {
        _videos = allVideos;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      padding: EdgeInsets.all(AppSpacing.spacing4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Select a ${widget.videoType.toUpperCase()} video',
                style: AppTypography.titleLarge.copyWith(fontWeight: FontWeight.bold),
              ),
              IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(context)),
            ],
          ),
          AppSpacing.vSpace12,
          Expanded(
            child: _isLoading 
              ? const Center(child: CircularProgressIndicator())
              : _videos == null || _videos!.isEmpty
                ? const Center(child: Text('No videos found.'))
                : ListView.separated(
                    itemCount: _videos!.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final v = _videos![index];
                      return ListTile(
                        onTap: () => widget.onSelected(v),
                        leading: Container(width: 60, height: 40, decoration: BoxDecoration(borderRadius: BorderRadius.circular(4), color: AppColors.backgroundSecondary), child: ClipRRect(borderRadius: BorderRadius.circular(4), child: v.thumbnailUrl.isNotEmpty ? Image.network(v.thumbnailUrl, fit: BoxFit.cover) : const Icon(Icons.videocam_rounded))),
                        title: Text(v.videoName, style: AppTypography.bodyMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(v.videoType.toUpperCase(), style: AppTypography.labelSmall),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
