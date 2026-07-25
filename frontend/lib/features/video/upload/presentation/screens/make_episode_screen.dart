import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vayug/core/providers/navigation_providers.dart';
import 'package:vayug/core/providers/profile_providers.dart';
import 'package:vayug/features/video/core/data/services/video_service.dart';
import 'package:vayug/shared/utils/app_logger.dart';
import 'package:video_player/video_player.dart';
import 'package:vayug/shared/widgets/app_button.dart';
import 'package:vayug/shared/widgets/vayu_snackbar.dart';

// Helper class to store episode details
class EpisodeItem {
  final File file;
  String title;

  EpisodeItem({required this.file, required this.title});
}

class MakeEpisodeScreen extends ConsumerStatefulWidget {
  final File? initialFile;
  const MakeEpisodeScreen({super.key, this.initialFile});

  @override
  ConsumerState<MakeEpisodeScreen> createState() => _MakeEpisodeScreenState();
}

class _MakeEpisodeScreenState extends ConsumerState<MakeEpisodeScreen> {
  final VideoService _videoService = VideoService();
  final List<EpisodeItem> _selectedEpisodes = [];
  bool _isUploading = false;

  String _currentStatus = '';
  int _currentUploadIndex = 0;

  @override
  void initState() {
    super.initState();
    if (widget.initialFile != null) {
      final file = widget.initialFile!;
      final defaultTitle = file.path.split('/').last.split('.').first;
      _selectedEpisodes.add(EpisodeItem(file: file, title: defaultTitle));
    }
  }

  Future<void> _pickVideos() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.video,
        allowMultiple: true,
      );

      if (result != null) {
        List<File> files = result.paths.map((path) => File(path!)).toList();
        
        // Filter out videos shorter than 8 seconds
        List<EpisodeItem> validEpisodes = [];
        for (var file in files) {
           try {
            final controller = VideoPlayerController.file(file);
            await controller.initialize();
            if (controller.value.duration.inSeconds >= 8) {
              String defaultTitle = file.path.split('/').last.split('.').first;
              validEpisodes.add(EpisodeItem(file: file, title: defaultTitle));
            } else {
              AppLogger.log('Skipping video with invalid duration: ${file.path}');
            }
            await controller.dispose();
          } catch (e) {
            AppLogger.log('Error checking duration: $e');
            String defaultTitle = file.path.split('/').last.split('.').first;
            validEpisodes.add(EpisodeItem(file: file, title: defaultTitle));
          }
        }

        if (files.length != validEpisodes.length && mounted) {
          VayuSnackBar.showWarning(context,
              'Some episodes were skipped. Duration must be at least 8 seconds.');
        }

        setState(() {
          _selectedEpisodes.addAll(validEpisodes);
        });
      }
    } catch (e) {
      AppLogger.log('Error picking videos: $e');
    }
  }

  // **NEW: Edit Title Dialog**
  void _editTitle(int index) {
    if (_isUploading) return;
    
    TextEditingController controller = TextEditingController(text: _selectedEpisodes[index].title);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Episode Title'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Title',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          AppButton(
            onPressed: () => Navigator.pop(context),
            label: 'Cancel',
            variant: AppButtonVariant.text,
          ),
          AppButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                setState(() {
                  _selectedEpisodes[index].title = controller.text.trim();
                });
              }
              Navigator.pop(context);
            },
            label: 'Save',
            variant: AppButtonVariant.primary,
          ),
        ],
      ),
    );
  }

  Future<void> _uploadOneByOne() async {
    if (_selectedEpisodes.isEmpty) return;
    
    // Enforce minimum 2 videos for an episode
    if (_selectedEpisodes.length < 2) {
      if (mounted) {
        VayuSnackBar.showError(context,
            'You must select at least 2 episodes to create a series.');
      }
      return;
    }

    setState(() {
      _isUploading = true;
      _currentUploadIndex = 0;
    });

    // Generate a unique series ID for linking episodes
    final String seriesId = '${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(10000)}';

    for (int i = 0; i < _selectedEpisodes.length; i++) {
      setState(() {
        _currentUploadIndex = i;
        _currentStatus = 'Uploading episode ${i + 1} of ${_selectedEpisodes.length}...';
      });

      try {
        EpisodeItem episode = _selectedEpisodes[i];
        
        // Use the edited title
        String title = episode.title;
        
        // Call upload video with series metadata
        final result = await _videoService.uploadVideo(
          videoFile: episode.file,
          title: title,
          description: '',
          link: '',
          videoType: 'yog',
          category: 'Others',
          tags: <String>[],
          seriesId: seriesId,
          episodeNumber: i + 1,
        );

        if (result['video'] != null) {
          // Success for this video - Add to ProfileStateManager optimistically
          try {
            final profileManager = ref.read(profileStateManagerProvider);
            profileManager.addVideoOptimistically(result['video']);
            AppLogger.log('✅ Episode ${i + 1} added to profile state');
          } catch (e) {
            AppLogger.log('⚠️ Error adding episode to profile state: $e');
          }
        }

      } catch (e) {
        AppLogger.log('Error uploading video $i: $e');
        if (mounted) {
          VayuSnackBar.showError(
              context, 'Failed to upload episode ${i + 1}: $e');
        }
        setState(() {
          _isUploading = false;
        });
        return;
      }
    }

    setState(() {
      _isUploading = false;
      _currentStatus = 'All episodes uploaded successfully!';
      _selectedEpisodes.clear(); // Clear list on success
    });

    if (mounted) {
      showDialog(
        context: context,
        useRootNavigator: false, // **FIX: Ensure dialog is on the Tab Navigator**
        builder: (context) => AlertDialog(
          title: const Text('Uploads Completed'),
          content: const Text('All episodes have been queued for processing. They will be available shortly after processing is complete.'),
          actions: [
            AppButton(
              onPressed: () {
                // 1. Get the controller BEFORE popping current context
                final mainController = ref.read(mainControllerProvider);
                
                // 2. Pop both dialog and screen (within the Tab Navigator)
                Navigator.of(context).pop(); // Close dialog
                Navigator.of(context).pop(true); // Exit MakeEpisodeScreen with SUCCESS signal
                
                // 3. Switch to Account tab (Index 3 is Account/Profile)
                mainController.changeIndex(3);
              },
              label: 'OK',
              variant: AppButtonVariant.primary,
            ),
          ],
        ),
      );
    }
  }

  void _removeVideo(int index) {
    setState(() {
      _selectedEpisodes.removeAt(index);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          const SliverAppBar(
            title: Text('Make a Episode'),
            floating: true,
            snap: true,
          ),
          SliverToBoxAdapter(
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Create a Series',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Select multiple episodes to upload as a sequence.',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),
          ),
          // Video List
          if (_selectedEpisodes.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.video_library_outlined, size: 64, color: Colors.grey[300]),
                    const SizedBox(height: 16),
                    Text('No episodes selected', style: TextStyle(color: Colors.grey[500])),
                  ],
                ),
              ),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final episode = _selectedEpisodes[index];
                  final isUploadingThis = _isUploading && _currentUploadIndex == index;
                  final isCompleted = _isUploading && _currentUploadIndex > index;
                  
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: ListTile(
                      leading: Container(
                        width: 32,
                        height: 32,
                        decoration: const BoxDecoration(
                          color: Colors.black12,
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: isCompleted 
                          ? const Icon(Icons.check, color: Colors.green, size: 16)
                          : Text('${index + 1}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      ),
                      // **NEW: Editable title display**
                      title: Text(
                         episode.title,
                         style: const TextStyle(fontWeight: FontWeight.w600),
                         maxLines: 1,
                         overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text('Episode ${index + 1}'),
                      // **NEW: Edit button added to trailing**
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (!_isUploading)
                            IconButton(
                              icon: const Icon(Icons.edit, color: Colors.blue),
                              onPressed: () => _editTitle(index),
                              tooltip: 'Edit Title',
                            ),
                            
                          if (!_isUploading)
                            IconButton(
                              icon: const Icon(Icons.close, color: Colors.red, size: 20),
                              onPressed: () => _removeVideo(index),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            )
                          else if (isUploadingThis) 
                            const SizedBox(
                              width: 20, 
                              height: 20, 
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                        ],
                      ),
                    ),
                  );
                },
                childCount: _selectedEpisodes.length,
              ),
            ),
          // Bottom actions
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  if (_isUploading)
                    Column(
                      children: [
                         LinearProgressIndicator(value: _currentUploadIndex / _selectedEpisodes.length),
                         const SizedBox(height: 8),
                         Text(_currentStatus, style: const TextStyle(fontSize: 12)),
                         const SizedBox(height: 16),
                      ],
                    ),
                  // Actions
                  Row(
                    children: [
                      Expanded(
                        child: AppButton(
                          onPressed: _pickVideos,
                          isDisabled: _isUploading,
                          icon: const Icon(Icons.add_photo_alternate),
                          label: 'Select Episodes',
                          variant: AppButtonVariant.primary,
                          isFullWidth: true,
                        ),
                      ),
                      if (_selectedEpisodes.isNotEmpty) ...[
                        const SizedBox(width: 16),
                        Expanded(
                          child: AppButton(
                            onPressed: _uploadOneByOne,
                            isDisabled: _isUploading,
                            icon: const Icon(Icons.cloud_upload),
                            label: 'Upload All',
                            variant: AppButtonVariant.primary,
                            isFullWidth: true,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}


