import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../design/app_layout.dart';
import '../../../design/app_tokens.dart';
import '../../../design/app_typography.dart';
import '../../../widgets/app_text_field.dart';
import '../../catalog/catalog_drink.dart';
import '../../catalog/data/catalog_search_gateway.dart';
import '../../recording/presentation/drink_search_results.dart';
import '../../recording/presentation/drink_search_screen.dart'
    show SuggestedDrinks;
import '../data/label_photo_picker.dart';
import '../data/label_text_recognizer.dart';
import '../data/taste_fit_gateway.dart';
import '../label_catalog_search.dart';
import '../taste_fit_verdict.dart';
import 'label_photo_flow.dart';
import 'label_scan_button.dart';
import 'taste_fit_badge.dart';

export 'label_photo_flow.dart'
    show
        tasteFitLabelButtonLabel,
        tasteFitLabelNoMatchHint,
        tasteFitLabelReadingHint,
        tasteFitLabelUnreadableHint;

/// The row the reader tapped, with the verdict shown next to it.
typedef TasteFitSelection = ({
  CatalogDrink drink,
  TasteFitVerdict? verdict,
  bool hasCards,
});

const String tasteFitNoCardsHint = '술결을 남기면 이 술이 나와 맞는지 표시돼요';
const String tasteFitSuggestionsTitle = '자주 찾는 술';

/// Catalog search whose result rows carry the reader's fit badge. A label
/// photo can stand in for typing: its lines are read on the device and
/// searched as one, and the reader picks the drink from the candidates.
class TasteFitSearchScreen extends StatefulWidget {
  const TasteFitSearchScreen({
    required this.onSelect,
    this.catalogSearchGateway,
    this.tasteFitGateway,
    this.labelTextRecognizer,
    this.pickLabelPhoto,
    this.scanLabelOnOpen = false,
    this.suggestedDrinkNames = const <String>[],
    super.key,
  });

  final ValueChanged<TasteFitSelection> onSelect;
  final CatalogSearchGateway? catalogSearchGateway;
  final TasteFitGateway? tasteFitGateway;

  /// Without one there is no label button.
  final LabelTextRecognizer? labelTextRecognizer;
  final LabelPhotoPicker? pickLabelPhoto;

  /// Asks for the label photo as soon as the screen opens (the home camera
  /// button); the search field then waits instead of taking focus.
  final bool scanLabelOnOpen;

  /// Exact catalog names listed, with their badges, while nothing has been
  /// searched yet; the same list the record search shows.
  final List<String> suggestedDrinkNames;

  @override
  State<TasteFitSearchScreen> createState() => _TasteFitSearchScreenState();
}

class _TasteFitSearchScreenState extends State<TasteFitSearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  Timer? _searchDebounce;
  int _searchRevision = 0;
  List<CatalogDrink> _matches = const <CatalogDrink>[];
  bool _searchInProgress = false;
  bool _hasMoreMatches = false;
  bool _loadingMoreMatches = false;
  bool _searchFailed = false;

  /// The label lines the current results came from; empty for a typed search.
  List<String> _labelQueries = const <String>[];
  bool _labelScanInProgress = false;
  String? _labelHint;

  /// Verdicts of the current matches; `null` while loading or after a failure.
  TasteFitResponse? _fit;

  List<CatalogDrink> _suggested = const <CatalogDrink>[];

  /// Verdicts of the suggested drinks, judged once when they arrive.
  TasteFitResponse? _suggestedFit;

  String get _query => _searchController.text.trim();

  bool get _hasResultsContext => _query.isNotEmpty || _labelQueries.isNotEmpty;

  @override
  void initState() {
    super.initState();
    if (widget.scanLabelOnOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_scanLabel());
      });
    }
    unawaited(_loadSuggestions());
  }

  Future<void> _loadSuggestions() async {
    final names = widget.suggestedDrinkNames;
    final gateway = widget.catalogSearchGateway;
    if (names.isEmpty || gateway == null) return;
    final drinks =
        SuggestedDrinks.cached(names) ??
        await SuggestedDrinks.load(gateway, names);
    if (!mounted || drinks.isEmpty) return;
    setState(() => _suggested = drinks);
    final fitGateway = widget.tasteFitGateway;
    if (fitGateway == null) return;
    try {
      final response = await fitGateway.judge(
        drinks.map((drink) => drink.id).toList(growable: false),
      );
      if (mounted) setState(() => _suggestedFit = response);
    } on TasteFitGatewayException {
      // The list stays useful without badges.
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _clearSearch() {
    _searchDebounce?.cancel();
    _searchRevision += 1;
    _searchController.clear();
    setState(_resetResults);
  }

  void _resetResults() {
    _matches = const <CatalogDrink>[];
    _searchInProgress = false;
    _hasMoreMatches = false;
    _loadingMoreMatches = false;
    _searchFailed = false;
    _labelQueries = const <String>[];
    _labelHint = null;
    _fit = null;
  }

  void _scheduleSearch(String _) {
    final gateway = widget.catalogSearchGateway;
    _searchDebounce?.cancel();
    final query = _query;
    final revision = ++_searchRevision;
    if (gateway == null || query.isEmpty) {
      setState(_resetResults);
      return;
    }
    setState(() {
      _resetResults();
      _searchInProgress = true;
    });
    _searchDebounce = Timer(const Duration(milliseconds: 250), () async {
      List<CatalogDrink> matches;
      try {
        matches = await gateway.search(query);
      } catch (_) {
        if (!mounted || revision != _searchRevision) return;
        setState(() {
          _matches = const <CatalogDrink>[];
          _searchInProgress = false;
          _searchFailed = true;
          _fit = null;
        });
        return;
      }
      if (!mounted || revision != _searchRevision) return;
      setState(() {
        _matches = matches;
        _searchInProgress = false;
        _hasMoreMatches = matches.length == catalogSearchPageSize;
        _fit = null;
      });
      unawaited(_judge(matches, revision));
    });
  }

  /// Appends the next page of name matches once the list nears its end.
  Future<void> _loadMoreMatches() async {
    final gateway = widget.catalogSearchGateway;
    final query = _query;
    if (gateway == null ||
        query.isEmpty ||
        !_hasMoreMatches ||
        _loadingMoreMatches ||
        _searchInProgress) {
      return;
    }
    final revision = _searchRevision;
    setState(() => _loadingMoreMatches = true);
    List<CatalogDrink> page;
    try {
      page = await gateway.search(query, offset: _matches.length);
    } catch (_) {
      // The rows already shown stay; the next scroll tries again.
      if (mounted && revision == _searchRevision) {
        setState(() => _loadingMoreMatches = false);
      }
      return;
    }
    if (!mounted || revision != _searchRevision) return;
    final shown = {for (final drink in _matches) drink.id};
    final added = page.where((drink) => !shown.contains(drink.id)).toList();
    setState(() {
      _matches = List<CatalogDrink>.unmodifiable(<CatalogDrink>[
        ..._matches,
        ...added,
      ]);
      _hasMoreMatches = page.length == catalogSearchPageSize;
      _loadingMoreMatches = false;
    });
    unawaited(_judge(added, revision));
  }

  Future<void> _scanLabel() async {
    final recognizer = widget.labelTextRecognizer;
    final gateway = widget.catalogSearchGateway;
    if (recognizer == null || gateway == null || _labelScanInProgress) return;
    final photo = await _pickLabelPhoto();
    if (photo == null || !mounted) return;

    _searchDebounce?.cancel();
    final revision = ++_searchRevision;
    _searchController.clear();
    setState(() {
      _resetResults();
      _labelScanInProgress = true;
    });
    try {
      final queries = labelSearchQueries(
        await recognizer.recognizeLines(photo.path),
      );
      if (queries.isEmpty) {
        if (!mounted || revision != _searchRevision) return;
        setState(() {
          _labelScanInProgress = false;
          _labelHint = tasteFitLabelUnreadableHint;
        });
        return;
      }
      final matches = await searchCatalogByLabel(gateway, queries);
      if (!mounted || revision != _searchRevision) return;
      setState(() {
        _labelScanInProgress = false;
        _labelQueries = queries;
        _matches = matches;
      });
      unawaited(_judge(matches, revision));
    } on CatalogSearchException {
      if (!mounted || revision != _searchRevision) return;
      setState(() {
        _labelScanInProgress = false;
        _searchFailed = true;
      });
    } catch (_) {
      if (!mounted || revision != _searchRevision) return;
      setState(() {
        _labelScanInProgress = false;
        _labelHint = tasteFitLabelUnreadableHint;
      });
    }
  }

  /// Tests hand over a photo directly; the app opens the camera screen.
  Future<XFile?> _pickLabelPhoto() {
    final injected = widget.pickLabelPhoto;
    if (injected != null) return injected();
    return takeLabelPhoto(context, onTypeInstead: _searchFocus.requestFocus);
  }

  /// One fit call per page of results, added to the verdicts already shown;
  /// a failed call leaves those rows unbadged.
  Future<void> _judge(List<CatalogDrink> matches, int revision) async {
    final gateway = widget.tasteFitGateway;
    if (gateway == null || matches.isEmpty) return;
    try {
      final response = await gateway.judge(
        matches.map((drink) => drink.id).toList(growable: false),
      );
      if (!mounted || revision != _searchRevision) return;
      setState(
        () => _fit = TasteFitResponse(
          hasCards: response.hasCards,
          verdicts: Map<String, TasteFitVerdict>.unmodifiable(
            <String, TasteFitVerdict>{...?_fit?.verdicts, ...response.verdicts},
          ),
        ),
      );
    } on TasteFitGatewayException {
      // Results stay useful without badges.
    }
  }

  /// The verdicts behind the list on screen: the search results, or the
  /// suggestions before any search.
  TasteFitResponse? get _shownFit => _hasResultsContext ? _fit : _suggestedFit;

  void _select(DrinkSelection selection) {
    final drink = selection.catalogDrink;
    final fit = _shownFit;
    widget.onSelect((
      drink: drink,
      verdict: fit?.verdictFor(drink.id),
      hasCards: fit?.hasCards ?? true,
    ));
  }

  Widget _badgeFor(CatalogDrink drink) {
    final fit = _shownFit;
    if (fit == null || !fit.hasCards) return const SizedBox.shrink();
    final verdict = fit.verdictFor(drink.id);
    if (verdict == null) return const SizedBox.shrink();
    return TasteFitRowBadge(verdict.badge);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
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
                key: const ValueKey<String>('taste-fit-search-field'),
                controller: _searchController,
                focusNode: _searchFocus,
                autofocus: !widget.scanLabelOnOpen,
                onChanged: _scheduleSearch,
                textInputAction: TextInputAction.search,
                hintText: '술 이름, 와이너리 검색',
                variant: AppTextFieldVariant.search,
                onClear: _hasResultsContext ? _clearSearch : null,
                trailing: widget.labelTextRecognizer == null
                    ? null
                    : LabelScanButton(
                        key: const ValueKey<String>('taste-fit-label-button'),
                        label: tasteFitLabelButtonLabel,
                        onPressed: _labelScanInProgress ? null : _scanLabel,
                      ),
              ),
              if (_searchInProgress || _labelScanInProgress) ...const <Widget>[
                SizedBox(height: AppSpacing.xs),
                LinearProgressIndicator(),
              ],
              if (_labelScanInProgress) ...const <Widget>[
                SizedBox(height: AppSpacing.xs),
                Text(tasteFitLabelReadingHint, style: AppTextStyles.modalBody),
              ],
              if (_searchFailed) ...const <Widget>[
                SizedBox(height: AppSpacing.xs),
                Text(
                  '카탈로그 검색이 잠시 원활하지 않아요. 잠시 후 다시 찾아보세요.',
                  style: AppTextStyles.modalBody,
                ),
              ],
              if (_labelHint case final hint?) ...<Widget>[
                const SizedBox(height: AppSpacing.sm),
                Text(hint, style: AppTextStyles.modalBody),
              ],
              if (_labelQueries.isNotEmpty) ...<Widget>[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  '라벨에서 읽은 글자: ${_labelQueries.join(' · ')}',
                  style: AppTextStyles.modalBody,
                ),
              ],
              if (_fit case TasteFitResponse(
                hasCards: false,
              ) when _matches.isNotEmpty) ...const <Widget>[
                SizedBox(height: AppSpacing.sm),
                Text(tasteFitNoCardsHint, style: AppTextStyles.modalBody),
              ],
              const SizedBox(height: AppSpacing.sm),
              Expanded(child: _buildResults()),
            ],
          ),
        );
      },
    );
  }

  Widget _buildResults() {
    if (!_hasResultsContext) {
      if (_suggested.isEmpty) {
        return const Center(
          child: Text('술 이름을 검색해보세요', style: AppTextStyles.modalBody),
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const Text(
            tasteFitSuggestionsTitle,
            style: AppTextStyles.sectionTitle,
          ),
          const SizedBox(height: AppSpacing.sm),
          Expanded(
            child: DrinkSearchResults(
              key: const ValueKey<String>('taste-fit-suggestions'),
              drinks: List<DrinkSelection>.unmodifiable(
                _suggested.map(DrinkSelection.catalogMatch),
              ),
              selectedDrink: null,
              onDrinkSelected: _select,
              scrollable: true,
              trailingBuilder: _badgeFor,
            ),
          ),
        ],
      );
    }
    if (_matches.isNotEmpty) {
      return DrinkSearchResults(
        drinks: List<DrinkSelection>.unmodifiable(
          _matches.map(DrinkSelection.catalogMatch),
        ),
        selectedDrink: null,
        onDrinkSelected: _select,
        scrollable: true,
        trailingBuilder: _badgeFor,
        onEndReached: _hasMoreMatches ? _loadMoreMatches : null,
        loadingMore: _loadingMoreMatches,
      );
    }
    if (_searchInProgress || _searchFailed) {
      return const SizedBox.shrink();
    }
    return Text(
      _labelQueries.isNotEmpty
          ? tasteFitLabelNoMatchHint
          : '검색 결과가 없어요. 다른 이름으로 찾아보세요.',
      style: AppTextStyles.modalBody,
    );
  }
}
