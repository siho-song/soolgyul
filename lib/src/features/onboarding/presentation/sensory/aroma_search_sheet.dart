import 'package:flutter/material.dart';

import '../../../../design/app_tokens.dart';
import '../../../../design/app_typography.dart';
import '../../../../widgets/app_icon.dart';
import '../../../../widgets/app_text_field.dart';
import '../../../../widgets/app_sheet.dart';
import '../../adaptive/direct_aroma_choices.dart';
import '../../adaptive/onboarding_aroma_menu.dart';

/// Opens the aroma search above the question so the keyboard never covers
/// the results. It stays open while aromas are picked and closes by 완료.
/// Its bar of picked aromas and its chips are the question's own and are
/// touched the same way, so what is chosen here is what the question holds.
Future<void> showAromaSearchSheet(
  BuildContext context, {
  required DirectAromaChoiceEngine engine,
  required OnboardingAromaMenu menu,
  required List<OnboardingAromaChip> frequent,
  required Listenable changes,
  required Widget? Function() pickedBar,
  required Widget Function(String key, String label) chip,
}) => showAppSheet<void>(
  context: context,
  tall: true,
  builder: (context) => AromaSearchSheet(
    engine: engine,
    menu: menu,
    frequent: frequent,
    changes: changes,
    pickedBar: pickedBar,
    chip: chip,
  ),
);

class AromaSearchSheet extends StatefulWidget {
  const AromaSearchSheet({
    required this.engine,
    required this.menu,
    required this.frequent,
    required this.changes,
    required this.pickedBar,
    required this.chip,
    super.key,
  });

  /// Searches the whole public aroma dictionary.
  final DirectAromaChoiceEngine engine;

  /// The menu of the question the sheet was opened from.
  final OnboardingAromaMenu menu;

  /// Chips the menu keeps behind its headings, offered before anything is
  /// typed.
  final List<OnboardingAromaChip> frequent;

  /// Rings when the question's picks change.
  final Listenable changes;

  /// The question's bar of picked aromas, or `null` while none is picked.
  final Widget? Function() pickedBar;

  /// The question's chip of an aroma, as it stands now, under the label
  /// given.
  final Widget Function(String key, String label) chip;

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

  Widget _scrolling({Key? key, required List<Widget> children}) =>
      SingleChildScrollView(
        key: key,
        padding: const EdgeInsets.only(
          top: AppSpacing.sm,
          bottom: AppSpacing.lg,
        ),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      );

  Widget _chips(List<Widget> chips) => Padding(
    padding: const EdgeInsets.only(top: AppSpacing.xs),
    child: Wrap(spacing: AppSpacing.sm, children: chips),
  );

  /// Before anything is typed: aromas the menu keeps behind its headings.
  Widget _suggestions() => _scrolling(
    children: [
      if (widget.frequent.isNotEmpty) ...[
        Text(
          '자주 찾는 ${widget.menu.label} 향',
          style: AppTextStyles.sectionTitleSm,
        ),
        _chips([
          for (final chip in widget.frequent)
            widget.chip(chip.key, '${chip.emoji} ${chip.label}'),
        ]),
      ],
    ],
  );

  Widget _body() {
    final query = _query.text.trim();
    if (query.isEmpty) return _suggestions();
    final results = widget.engine.search(query);
    if (results.isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(top: AppSpacing.lg),
        child: Text(
          '일치하는 향을 찾지 못했어요.\n다른 단어로 검색해 보세요.',
          style: AppTextStyles.modalBody,
          textAlign: TextAlign.center,
        ),
      );
    }
    // The aromas found as chips, several to a row, the best match first.
    return _scrolling(
      key: const ValueKey('aroma-search-results'),
      children: [
        _chips([
          for (final result in results) widget.chip(result.key, result.label),
        ]),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      AppSpacing.sheetX,
      AppSpacing.sm,
      AppSpacing.sheetX,
      MediaQuery.viewInsetsOf(context).bottom,
    ),
    child: ListenableBuilder(
      listenable: Listenable.merge([_query, widget.changes]),
      builder: (context, _) {
        final pickedBar = widget.pickedBar();
        return Column(
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
            const SizedBox(height: AppSpacing.md),
            AppTextField(
              key: const ValueKey('sensory-aroma-search'),
              controller: _query,
              focusNode: sheetFocus,
              hintText: aromaSearchHint,
              variant: AppTextFieldVariant.search,
              textInputAction: TextInputAction.search,
              onClear: _query.text.trim().isEmpty ? null : _query.clear,
            ),
            if (pickedBar != null) ...[
              const SizedBox(height: AppSpacing.sm),
              pickedBar,
            ],
            const SizedBox(height: AppSpacing.sm),
            Expanded(child: _body()),
          ],
        );
      },
    ),
  );
}

/// What the search box says while empty, on the question and in the sheet:
/// an aroma is found by its name, its family or an everyday word.
const aromaSearchHint = '향·계열로 검색 (예: 곡물, 달콤)';

/// Looks like the search field it opens, so the visitor knows to tap it.
class AromaSearchEntry extends StatelessWidget {
  const AromaSearchEntry({required this.onPressed, super.key});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: aromaSearchHint,
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
                // On the narrowest phones the hint ends in an ellipsis
                // rather than running past the box.
                Expanded(
                  child: Text(
                    aromaSearchHint,
                    style: AppTextStyles.textFieldHint,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
