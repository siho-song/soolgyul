import 'package:flutter/material.dart';

import '../../../../design/app_tokens.dart';
import '../../../../design/app_typography.dart';
import '../../../../widgets/app_icon.dart';
import '../../../../widgets/app_text_field.dart';
import '../widgets/onboarding_choice_controls.dart';
import '../../../../widgets/app_sheet.dart';

const maxAromaSelections = 5;

/// Opens the aroma search above the question so the keyboard never covers
/// the results; choices made here land in the question's own chip list.
Future<void> showAromaSearchSheet(
  BuildContext context, {
  required List<String> Function(String query) search,
  required String Function(String key) label,
  required bool Function(String key) isSelected,
  required int Function() selectedCount,
  required bool Function(String key) toggle,
}) => showAppSheet<void>(
  context: context,
  tall: true,
  builder: (context) => AromaSearchSheet(
    search: search,
    label: label,
    isSelected: isSelected,
    selectedCount: selectedCount,
    toggle: toggle,
  ),
);

class AromaSearchSheet extends StatefulWidget {
  const AromaSearchSheet({
    required this.search,
    required this.label,
    required this.isSelected,
    required this.selectedCount,
    required this.toggle,
    super.key,
  });

  final List<String> Function(String query) search;
  final String Function(String key) label;
  final bool Function(String key) isSelected;
  final int Function() selectedCount;

  /// Returns false when the selection limit kept the aroma out.
  final bool Function(String key) toggle;

  @override
  State<AromaSearchSheet> createState() => _AromaSearchSheetState();
}

class _AromaSearchSheetState extends State<AromaSearchSheet>
    with FocusWhenSheetOpens {
  final _query = TextEditingController();
  bool _limitReached = false;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  void _toggle(String key) {
    final accepted = widget.toggle(key);
    setState(() => _limitReached = !accepted);
  }

  @override
  Widget build(BuildContext context) {
    final query = _query.text.trim();
    final results = query.isEmpty ? const <String>[] : widget.search(query);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.sheetX,
        AppSpacing.sm,
        AppSpacing.sheetX,
        MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('향 검색', style: AppTextStyles.sectionTitle),
              ),
              Text(
                '${widget.selectedCount()}/$maxAromaSelections',
                style: AppTextStyles.modalBody,
              ),
              TextButton(
                key: const ValueKey('aroma-search:done'),
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('완료'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          AppTextField(
            key: const ValueKey('sensory-aroma-search'),
            controller: _query,
            focusNode: sheetFocus,
            hintText: '찾으시는 향을 입력해 보세요',
            variant: AppTextFieldVariant.search,
            textInputAction: TextInputAction.search,
            onChanged: (_) => setState(() {}),
            onClear: query.isEmpty ? null : () => setState(_query.clear),
          ),
          if (_limitReached)
            const Padding(
              padding: EdgeInsets.only(top: AppSpacing.sm),
              child: Text(
                '향은 최대 $maxAromaSelections개까지 선택할 수 있어요.',
                style: AppTextStyles.modalBody,
              ),
            ),
          const SizedBox(height: AppSpacing.sm),
          Expanded(
            child: query.isEmpty || results.isEmpty
                ? Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.lg),
                    child: Text(
                      query.isEmpty
                          ? '기억나는 향을 검색창에 적어 보세요.'
                          : '일치하는 향을 찾지 못했어요.\n다른 단어로 검색해 보세요.',
                      style: AppTextStyles.modalBody,
                      textAlign: TextAlign.center,
                    ),
                  )
                : ListView(
                    key: const ValueKey('aroma-search-results'),
                    padding: EdgeInsets.zero,
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    children: [
                      for (final key in results)
                        OnboardingLargeOption(
                          key: ValueKey('search:aroma:$key'),
                          label: widget.label(key),
                          selected: widget.isSelected(key),
                          onPressed: () => _toggle(key),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

/// Looks like the search field it opens, so the visitor knows to tap it.
class AromaSearchEntry extends StatelessWidget {
  const AromaSearchEntry({required this.onPressed, super.key});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: '찾으시는 향을 입력해 보세요',
    child: Material(
      color: Colors.white.withValues(alpha: .72),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.control),
        side: const BorderSide(
          color: AppColors.actionPrimaryStrong,
          width: 1.3,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: const SizedBox(
          height: 50,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: Row(
              children: [
                AppIcon(
                  AppIconAsset.search,
                  size: AppSizes.iconLg,
                  color: AppColors.actionPrimaryStrong,
                ),
                SizedBox(width: AppSpacing.md),
                Text('찾으시는 향을 입력해 보세요', style: AppTextStyles.textFieldHint),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
