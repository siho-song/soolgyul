import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/format/dates.dart';
import '../../../../design/app_layout.dart';
import '../../../../design/app_tokens.dart';
import '../../../../widgets/app_state_view.dart';
import '../../../../widgets/app_text_field.dart';
import '../../../catalog/data/catalog_drink.dart';
import '../../../recording/presentation/widgets/drink_search_results.dart';
import '../../data/preference_history_content.dart';
import '../../data/preference_history_providers.dart';

/// 기록 검색: every record of the account, newest first, narrowed to the
/// ones whose drink's name holds what is typed. A row opens the record's
/// card, and this page stays under it with what was typed.
class HistorySearchScreen extends ConsumerStatefulWidget {
  const HistorySearchScreen({required this.onOpenCard, super.key});

  /// Opens the saved card with this result id.
  final ValueChanged<String> onOpenCard;

  @override
  ConsumerState<HistorySearchScreen> createState() =>
      _HistorySearchScreenState();
}

class _HistorySearchScreenState extends ConsumerState<HistorySearchScreen> {
  final _controller = TextEditingController();
  final _focus = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// A name as it is compared: letter case and spaces do not count.
  static String _plain(String text) =>
      text.toLowerCase().replaceAll(RegExp(r'\s'), '');

  void _clear() {
    setState(_controller.clear);
    // The keyboard comes back for the next name.
    _focus.requestFocus();
  }

  /// A record as a search row draws it: the photo, the drink's name, and
  /// its kind and day on the line a bottle's style takes. The row hands
  /// back the id, here the card's.
  static DrinkSelection _row(HistoryRecord record) =>
      DrinkSelection.catalogMatch(
        CatalogDrink(
          id: record.resultId,
          displayName: record.title,
          category: DrinkCategory.other,
          styleLabel:
              '${record.categoryLabel} · ${formatDotDate(record.recordedAt)}',
          photoUrl: record.imageUrl,
        ),
      );

  Widget _results() {
    final all = ref.watch(historyAllProvider);
    final records = all.value;
    if (records == null) {
      return all.hasError
          ? Center(
              child: AppErrorView(
                title: '기록을 불러오지 못했어요',
                error: all.error,
                onRetry: () => ref.invalidate(historyAllProvider),
              ),
            )
          : const Center(
              child: AppLoadingView(
                key: ValueKey<String>('history-search-loading'),
              ),
            );
    }
    if (records.isEmpty) {
      return const Center(child: AppEmptyView(message: '아직 남긴 기록이 없어요.'));
    }
    final typed = _plain(_controller.text);
    final matches = <DrinkSelection>[
      for (final record in records)
        if (_plain(record.title).contains(typed)) _row(record),
    ];
    if (matches.isEmpty) {
      return const AppEmptyView(message: '검색 결과가 없어요.');
    }
    return DrinkSearchResults(
      key: const ValueKey<String>('history-search-list'),
      drinks: matches,
      selectedDrink: null,
      onDrinkSelected: (row) => widget.onOpenCard(row.catalogId),
      scrollable: true,
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (!AppLayout.isViewportReady(constraints)) {
        return const SizedBox.shrink();
      }
      final horizontalPadding = AppScreenLayout.fromConstraints(
        constraints,
      ).horizontalPadding;
      return Padding(
        padding: EdgeInsets.fromLTRB(
          horizontalPadding,
          AppSpacing.md,
          horizontalPadding,
          AppSpacing.sm,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            AppTextField(
              key: const ValueKey<String>('history-search-field'),
              controller: _controller,
              focusNode: _focus,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              textInputAction: TextInputAction.search,
              hintText: '술 이름으로 검색',
              variant: AppTextFieldVariant.search,
              onClear: _controller.text.isEmpty ? null : _clear,
            ),
            const SizedBox(height: AppSpacing.md),
            Expanded(child: _results()),
          ],
        ),
      );
    },
  );
}
