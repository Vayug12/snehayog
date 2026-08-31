import 'package:flutter/material.dart';
import 'package:vayug/core/design/colors.dart';
import 'package:vayug/core/design/spacing.dart';
import 'package:vayug/core/design/typography.dart';
import 'package:vayug/shared/models/profession.dart';
import 'package:vayug/shared/services/profession_catalog_service.dart';
import 'package:vayug/shared/utils/app_text.dart';
import 'package:vayug/shared/widgets/app_button.dart';
import 'package:vayug/shared/widgets/vayu_bottom_sheet.dart';

class ProfessionPickerSheet {
  const ProfessionPickerSheet._();

  static Future<List<String>?> show({
    required BuildContext context,
    required Iterable<String> initialSelection,
    required bool multiSelect,
    String? title,
    String? emptySelectionLabel,
  }) {
    return VayuBottomSheet.show<List<String>>(
      context: context,
      title: title ??
          AppText.get('profession_picker_title', fallback: 'Choose profession'),
      icon: Icons.work_outline_rounded,
      useDraggable: true,
      initialChildSize: 0.78,
      minChildSize: 0.55,
      maxChildSize: 0.92,
      builder: (context, scrollController) => _ProfessionPickerBody(
        initialSelection: initialSelection.toSet(),
        multiSelect: multiSelect,
        emptySelectionLabel: emptySelectionLabel ??
            AppText.get('profession_everyone', fallback: 'Everyone'),
        scrollController: scrollController,
      ),
    );
  }
}

class _ProfessionPickerBody extends StatefulWidget {
  final Set<String> initialSelection;
  final bool multiSelect;
  final String emptySelectionLabel;
  final ScrollController? scrollController;

  const _ProfessionPickerBody({
    required this.initialSelection,
    required this.multiSelect,
    required this.emptySelectionLabel,
    this.scrollController,
  });

  @override
  State<_ProfessionPickerBody> createState() => _ProfessionPickerBodyState();
}

class _ProfessionPickerBodyState extends State<_ProfessionPickerBody> {
  final TextEditingController _searchController = TextEditingController();
  late final Set<String> _selected = {...widget.initialSelection};

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_refresh);
  }

  @override
  void dispose() {
    _searchController
      ..removeListener(_refresh)
      ..dispose();
    super.dispose();
  }

  void _refresh() => setState(() {});

  void _select(Profession profession) {
    if (!widget.multiSelect) {
      Navigator.pop(context, <String>[profession.id]);
      return;
    }
    setState(() {
      if (!_selected.add(profession.id)) _selected.remove(profession.id);
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Profession>>(
      future: ProfessionCatalogService.instance.getProfessions(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError || snapshot.data == null) {
          return Center(
            child: Padding(
              padding: AppSpacing.edgeInsetsAll24,
              child: Text(
                AppText.get(
                  'profession_load_error',
                  fallback: 'Could not load professions. Please try again.',
                ),
                textAlign: TextAlign.center,
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          );
        }

        final query = _searchController.text;
        final professions = snapshot.data!
            .where((profession) => profession.matches(query))
            .toList(growable: false);

        return Column(
          children: [
            Padding(
              padding: EdgeInsets.symmetric(horizontal: AppSpacing.spacing4),
              child: TextField(
                controller: _searchController,
                autofocus: false,
                decoration: InputDecoration(
                  hintText: AppText.get(
                    'profession_search_hint',
                    fallback: 'Search profession',
                  ),
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: query.isEmpty
                      ? null
                      : IconButton(
                          onPressed: _searchController.clear,
                          icon: const Icon(Icons.close_rounded),
                        ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppSpacing.spacing3),
                  ),
                ),
              ),
            ),
            AppSpacing.vSpace8,
            Expanded(
              child: ListView.builder(
                controller: widget.scrollController,
                itemCount: professions.length + 1,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return ListTile(
                      onTap: () => Navigator.pop(context, <String>[]),
                      leading: const Icon(Icons.public_rounded),
                      title: Text(widget.emptySelectionLabel),
                      trailing: _selected.isEmpty
                          ? const Icon(Icons.check_circle_rounded,
                              color: AppColors.primary)
                          : null,
                    );
                  }
                  final profession = professions[index - 1];
                  final selected = _selected.contains(profession.id);
                  return ListTile(
                    onTap: () => _select(profession),
                    title: Text(profession.label),
                    trailing: selected
                        ? const Icon(Icons.check_circle_rounded,
                            color: AppColors.primary)
                        : const Icon(Icons.circle_outlined,
                            color: AppColors.textTertiary),
                  );
                },
              ),
            ),
            if (widget.multiSelect)
              SafeArea(
                top: false,
                child: Padding(
                  padding: AppSpacing.edgeInsetsAll16,
                  child: AppButton(
                    onPressed: () => Navigator.pop(context, _selected.toList()),
                    label: AppText.get('btn_done', fallback: 'Done'),
                    variant: AppButtonVariant.primary,
                    isFullWidth: true,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

