import 'package:flutter/material.dart';

import '../../../../design/app_tokens.dart';
import '../../../../design/app_typography.dart';
import '../../../../widgets/app_icon.dart';
import '../../../../widgets/app_text_field.dart';
import '../../../../widgets/app_sheet.dart';

/// Opens the aroma search above the question so the keyboard never covers
/// the results. An aroma found is the question's own chip and is touched
/// the same way, so what is chosen here is what the question holds.
Future<void> showAromaSearchSheet(
  BuildContext context, {
  required List<String> Function(String query) search,
  required Widget guide,
  required Widget Function(String key, VoidCallback onPressed) chip,
  required void Function(String key) cycle,
}) => showAppSheet<void>(
  context: context,
  tall: true,
  builder: (context) =>
      AromaSearchSheet(search: search, guide: guide, chip: chip, cycle: cycle),
);

class AromaSearchSheet extends StatefulWidget {
  const AromaSearchSheet({
    required this.search,
    required this.guide,
    required this.chip,
    required this.cycle,
    super.key,
  });

  final List<String> Function(String query) search;

  /// The line that says what a tap does, as the question shows it.
  final Widget guide;

  /// The question's chip of an aroma, as it stands now, touched through
  /// [onPressed].
  final Widget Function(String key, VoidCallback onPressed) chip;

  /// Takes the aroma one tap on, as its chip in the question does: liked,
  /// then a burden, then off.
  final void Function(String key) cycle;

  @override
  State<AromaSearchSheet> createState() => _AromaSearchSheetState();
}

class _AromaSearchSheetState extends State<AromaSearchSheet>
    with FocusWhenSheetOpens {
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  void _cycle(String key) => setState(() => widget.cycle(key));

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
              TextButton(
                key: const ValueKey('aroma-search:done'),
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('완료'),
              ),
            ],
          ),
          widget.guide,
          const SizedBox(height: AppSpacing.md),
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
                : SingleChildScrollView(
                    key: const ValueKey('aroma-search-results'),
                    padding: const EdgeInsets.only(
                      top: AppSpacing.sm,
                      bottom: AppSpacing.lg,
                    ),
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    child: Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      children: [
                        for (final key in results)
                          widget.chip(key, () => _cycle(key)),
                      ],
                    ),
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
