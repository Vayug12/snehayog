import 'package:flutter/material.dart';
import 'package:vayug/shared/services/feedback_service.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:vayug/shared/widgets/app_button.dart';
import 'package:vayug/shared/widgets/vayu_snackbar.dart';

class FeedbackFormWidget extends StatefulWidget {
  const FeedbackFormWidget({Key? key}) : super(key: key);

  @override
  State<FeedbackFormWidget> createState() => _FeedbackFormWidgetState();
}

class _FeedbackFormWidgetState extends State<FeedbackFormWidget> {
  final _formKey = GlobalKey<FormState>();
  final _messageController = TextEditingController();
  final _feedbackService = FeedbackService();

  String _selectedType = 'general';
  int _rating = 5;
  bool _isSubmitting = false;

  final List<String> _feedbackTypes = [
    'general',
    'bug',
    'feature',
    'performance',
    'ui',
    'other'
  ];

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _submitFeedback() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSubmitting = true;
    });

    try {
      // Get device info
      final deviceInfo = DeviceInfoPlugin();

      if (Theme.of(context).platform == TargetPlatform.android) {
        final androidInfo = await deviceInfo.androidInfo;
      } else if (Theme.of(context).platform == TargetPlatform.iOS) {
        final iosInfo = await deviceInfo.iosInfo;
      }

      final success = await _feedbackService.submitFeedback(
        rating: _rating,
        comments: _messageController.text,
        type: _selectedType,
      );

      if (success) {
        if (mounted) {
          VayuSnackBar.showSuccess(context, 'Feedback submitted successfully!');
          _messageController.clear();
          setState(() {
            _rating = 5;
            _selectedType = 'general';
          });
        }
      } else {
        if (mounted) {
          VayuSnackBar.showError(
              context, 'Failed to submit feedback. Please try again.');
        }
      }
    } catch (e) {
      if (mounted) {
        VayuSnackBar.showError(context, 'Error: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Send Feedback'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Feedback Type
              const Text('Feedback Type',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _selectedType,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                ),
                items: _feedbackTypes.map((type) {
                  return DropdownMenuItem(
                    value: type,
                    child: Text(type.toUpperCase()),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedType = value!;
                  });
                },
              ),
              const SizedBox(height: 16),

              // Rating
              const Text('Rating',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Row(
                children: List.generate(5, (index) {
                  return IconButton(
                    icon: Icon(
                      index < _rating ? Icons.star : Icons.star_border,
                      color: Colors.amber,
                    ),
                    onPressed: () {
                      setState(() {
                        _rating = index + 1;
                      });
                    },
                  );
                }),
              ),
              const SizedBox(height: 16),

              // Message
              const Text('Message',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              TextFormField(
                controller: _messageController,
                maxLines: 5,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'Please describe your feedback...',
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter your feedback message';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 24),

              // Submit Button
              AppButton(
                onPressed: _isSubmitting ? null : _submitFeedback,
                label: 'Submit Feedback',
                variant: AppButtonVariant.primary,
                isLoading: _isSubmitting,
                isFullWidth: true,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
