import 'package:flutter/material.dart';
import 'package:vayug/core/design/colors.dart';
import 'package:vayug/shared/services/report_service.dart';
import 'package:vayug/shared/widgets/app_button.dart';
import 'package:vayug/shared/widgets/vayu_snackbar.dart';

class ReportDialogWidget extends StatefulWidget {
  final String targetType;
  final String targetId;

  const ReportDialogWidget({
    super.key,
    required this.targetType,
    required this.targetId,
  });

  @override
  State<ReportDialogWidget> createState() => _ReportDialogWidgetState();
}

class _ReportDialogWidgetState extends State<ReportDialogWidget> {
  final _formKey = GlobalKey<FormState>();
  final _detailsController = TextEditingController();
  final _reportService = ReportService();

  String _selectedReason = 'spam';
  bool _submitting = false;

  final List<String> _reasons = [
    'spam',
    'abusive',
    'nudity',
    'copyright',
    'misinformation',
    'other',
  ];

  @override
  void dispose() {
    _detailsController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);

    final success = await _reportService.submitReport(
      targetType: widget.targetType,
      targetId: widget.targetId,
      reason: _selectedReason,
      details: _detailsController.text.trim().isEmpty
          ? null
          : _detailsController.text.trim(),
    );

    if (!mounted) return;

    if (success) {
      Navigator.of(context).pop(true);
      VayuSnackBar.showSuccess(context, 'Report submitted. Thank you.');
    } else {
      VayuSnackBar.showError(context, 'Failed to submit report.');
    }

    if (mounted) setState(() => _submitting = false);
  }

  @override
  Widget build(BuildContext context) {
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'What is the issue?',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w600,
              fontSize: isLandscape ? 12.0 : 13.0,
            ),
          ),
          SizedBox(height: isLandscape ? 6 : 10),
          Wrap(
            spacing: isLandscape ? 6 : 8,
            runSpacing: isLandscape ? 6 : 8,
            children: _reasons.map((reason) {
              final isSelected = _selectedReason == reason;
              return ChoiceChip(
                label: Text(
                  reason[0].toUpperCase() + reason.substring(1),
                  style: TextStyle(
                    color: isSelected ? Colors.white : AppColors.textSecondary,
                    fontWeight:
                        isSelected ? FontWeight.w600 : FontWeight.w500,
                    fontSize: isLandscape ? 11.5 : 12.5,
                  ),
                ),
                selected: isSelected,
                onSelected: (selected) {
                  if (selected) setState(() => _selectedReason = reason);
                },
                selectedColor: AppColors.primary,
                backgroundColor: AppColors.backgroundSecondary,
                checkmarkColor: Colors.white,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: isLandscape
                    ? const VisualDensity(horizontal: -3, vertical: -3)
                    : VisualDensity.compact,
                padding: EdgeInsets.symmetric(
                  horizontal: isLandscape ? 8 : 10,
                  vertical: isLandscape ? 2 : 4,
                ),
                labelPadding: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(100),
                  side: BorderSide(
                    color: isSelected
                        ? AppColors.primary
                        : AppColors.borderPrimary,
                    width: 1,
                  ),
                ),
              );
            }).toList(),
          ),
          SizedBox(height: isLandscape ? 10 : 16),
          Text(
            'Actionable details (optional)',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w600,
              fontSize: isLandscape ? 12.0 : 13.0,
            ),
          ),
          SizedBox(height: isLandscape ? 4 : 8),
          TextFormField(
            controller: _detailsController,
            minLines: isLandscape ? 1 : 2,
            maxLines: isLandscape ? 2 : 4,
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: isLandscape ? 12.0 : 14.0,
            ),
            decoration: InputDecoration(
              hintText: 'Describe the problem...',
              hintStyle: TextStyle(
                color: AppColors.textTertiary,
                fontSize: isLandscape ? 12.0 : 14.0,
              ),
              filled: true,
              fillColor: AppColors.backgroundSecondary,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
              contentPadding: EdgeInsets.symmetric(
                horizontal: 12,
                vertical: isLandscape ? 8 : 12,
              ),
            ),
          ),
          SizedBox(height: isLandscape ? 10 : 18),
          AppButton(
            onPressed: _submitting ? null : _submit,
            label: 'Submit Report',
            variant: AppButtonVariant.primary,
            size: isLandscape ? AppButtonSize.small : AppButtonSize.medium,
            fontSize: isLandscape ? 12.5 : 14.0,
            isLoading: _submitting,
            isFullWidth: true,
          ),
        ],
      ),
    );
  }
}
