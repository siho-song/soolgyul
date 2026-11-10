import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../design/app_layout.dart';
import '../../../design/app_tokens.dart';
import '../../../design/app_typography.dart';
import '../../../widgets/app_text_field.dart';
import '../../catalog/data/catalog_drink.dart';
import '../../catalog/data/catalog_search_gateway.dart';
import '../../catalog/data/discovery_events.dart';
import '../../recording/presentation/widgets/drink_search_results.dart';
import '../../recording/presentation/widgets/selected_drink_card.dart';
import '../../catalog/data/suggested_drinks.dart';
import '../data/label_photo_picker.dart';
import '../data/label_text_recognizer.dart';
import '../data/taste_fit_gateway.dart';
import '../data/catalog_search_session.dart';
import '../data/taste_fit_verdict.dart';
import 'widgets/label_photo_flow.dart';
import 'widgets/label_scan_button.dart';
import 'widgets/taste_fit_badge.dart';
import 'widgets/taste_fit_headline.dart';

export 'widgets/label_photo_flow.dart'
    show
        tasteFitLabelButtonLabel,
        tasteFitLabelNoMatchHint,
        tasteFitLabelReadingHint,
        tasteFitLabelUnreadableHint;

/// The row the reader tapped, with the verdict shown next to it.
/// A tapped row: the drink, its verdict when one came, and whether the
/// fit call for it has answered ([judged] false when the row was tapped
/// before its badge arrived).
typedef TasteFitSelection = ({
  CatalogDrink drink,
  TasteFitVerdict? verdict,
  bool hasCards,
  bool judged,
});

const String tasteFitNoCardsHint = '첫 기록을 남기면 나와 잘 맞는지 확인할 수 있어요.';
const String tasteFitSuggestionsTitle = '많이 기록하는 술';

/// Catalog search whose result rows carry the reader's fit badge. A label
/// photo can stand in for typing: its lines are read on the device and
/// searched as one, and the reader picks the drink from the candidates.
class TasteFitSearchScreen extends StatefulWidget {
  const TasteFitSearchScreen({
    required this.onSelect,
    this.catalogSearchGateway,
    this.tasteFitGateway,
    this.discoveryEvents,
    this.labelTextRecognizer,
    this.pickLabelPhoto,
    this.scanLabelOnOpen = false,
    this.suggestedDrinkNames = const <String>[],
    super.key,
  });

  final ValueChanged<TasteFitSelection> onSelect;
  final CatalogSearchGateway? catalogSearchGateway;
  final TasteFitGateway? tasteFitGateway;

  /// Told about empty searches, label reads, picks and every fit opened.
  final DiscoveryEventGateway? discoveryEvents;

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
  late final CatalogSearchSession _results = CatalogSearchSession(
    () => widget.catalogSearchGateway,
    onPage: _judge,
    events: () => widget.discoveryEvents,
    surface: DiscoverySurface.tasteFit,
  )..addListener(_rebuild);

  /// Verdicts for the search results, gathered page by page.
  TasteFitResponse? _fit;

  /// The results the fit call has answered for, with or without a verdict.
  final Set<String> _judged = <String>{};

  /// The results whose fit call is on the wire.
  final Set<String> _judging = <String>{};

  /// Shown before any search, and their verdicts.
  List<CatalogDrink> _suggested = const <CatalogDrink>[];
  TasteFitResponse? _suggestedFit;

  String get _query => _searchController.text.trim();

  bool get _hasResultsContext =>
      _query.isNotEmpty || _results.labelQueries.isNotEmpty;

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

  @override
  void didUpdateWidget(covariant TasteFitSearchScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The member's gender can arrive after the screen opens.
    if (!listEquals(
      oldWidget.suggestedDrinkNames,
      widget.suggestedDrinkNames,
    )) {
      unawaited(_loadSuggestions());
    }
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  Future<void> _loadSuggestions() async {
    final names = widget.suggestedDrinkNames;
    final gateway = widget.catalogSearchGateway;
    if (names.isEmpty || gateway == null) return;
    final drinks =
        SuggestedDrinks.cached(names) ??
        await SuggestedDrinks.load(gateway, names);
    // A list asked for before the member's gender arrived is dropped.
    bool stale() => !mounted || !identical(names, widget.suggestedDrinkNames);
    if (stale() || drinks.isEmpty) return;
    setState(() {
      _suggested = drinks;
      _suggestedFit = null;
    });
    final fitGateway = widget.tasteFitGateway;
    if (fitGateway == null) return;
    try {
      final response = await fitGateway.judge(
        drinks.map((drink) => drink.id).toList(growable: false),
      );
      if (!stale()) setState(() => _suggestedFit = response);
    } on TasteFitGatewayException {
      // The list stays useful without badges.
    }
  }

  @override
  void dispose() {
    _results.dispose();
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _clearSearch() {
    _searchController.clear();
    _fit = null;
    _judged.clear();
    _judging.clear();
    _results.clear();
  }

  /// Typing keeps the rows and their badges on screen until the new
  /// results come, as the record search does.
  void _typed(String _) => _results.search(_query, keepShown: true);

  void _loadMore() => unawaited(_results.loadMore(_query));

  Future<void> _scanLabel() async {
    final recognizer = widget.labelTextRecognizer;
    if (recognizer == null ||
        widget.catalogSearchGateway == null ||
        _results.labelScanning) {
      return;
    }
    final photo = await _pickLabelPhoto();
    if (photo == null || !mounted) return;
    _searchController.clear();
    _fit = null;
    _judged.clear();
    _judging.clear();
    await _results.scanLabel(recognizer, photo);
  }

  /// Tests hand over a photo directly; the app opens the camera screen.
  Future<XFile?> _pickLabelPhoto() {
    final injected = widget.pickLabelPhoto;
    if (injected != null) return injected();
    return takeLabelPhoto(context, onTypeInstead: _searchFocus.requestFocus);
  }

  /// One fit call per page of results, added to the verdicts already shown;
  /// a failed call leaves those rows unbadged.
  Future<void> _judge(List<CatalogDrink> matches, int search) async {
    final gateway = widget.tasteFitGateway;
    if (gateway == null || matches.isEmpty) return;
    final ids = matches.map((drink) => drink.id).toList(growable: false);
    _judging.addAll(ids);
    try {
      final response = await gateway.judge(ids);
      if (!mounted) return;
      if (!_results.isCurrent(search)) {
        setState(() => _judging.removeAll(ids));
        return;
      }
      setState(() {
        _judging.removeAll(ids);
        _fit = TasteFitResponse(
          hasCards: response.hasCards,
          verdicts: Map<String, TasteFitVerdict>.unmodifiable(
            <String, TasteFitVerdict>{...?_fit?.verdicts, ...response.verdicts},
          ),
        );
        _judged.addAll(matches.map((drink) => drink.id));
      });
    } on TasteFitGatewayException {
      // Results stay useful without badges.
      if (mounted) setState(() => _judging.removeAll(ids));
    }
  }

  /// The verdicts behind the list on screen: the search results, or the
  /// suggestions before any search.
  TasteFitResponse? get _shownFit => _hasResultsContext ? _fit : _suggestedFit;

  void _select(DrinkSelection selection) {
    final drink = selection.catalogDrink;
    final fit = _shownFit;
    final events = widget.discoveryEvents;
    if (_query.isNotEmpty && _results.labelQueries.isEmpty) {
      events?.record(
        DiscoveryEvent.searchPick,
        DiscoverySurface.tasteFit,
        drinkId: drink.id,
        query: _query,
      );
    }
    events?.record(
      DiscoveryEvent.fitView,
      DiscoverySurface.tasteFit,
      drinkId: drink.id,
    );
    widget.onSelect((
      drink: drink,
      verdict: fit?.verdictFor(drink.id),
      hasCards: fit?.hasCards ?? true,
      judged: _hasResultsContext
          ? _judged.contains(drink.id)
          : _suggestedFit != null,
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
                onChanged: _typed,
                textInputAction: TextInputAction.search,
                hintText: '술 이름이나 브랜드 검색',
                variant: AppTextFieldVariant.search,
                onClear: _hasResultsContext ? _clearSearch : null,
                trailing: widget.labelTextRecognizer == null
                    ? null
                    : LabelScanButton(
                        key: const ValueKey<String>('taste-fit-label-button'),
                        label: tasteFitLabelButtonLabel,
                        onPressed: _results.labelScanning ? null : _scanLabel,
                      ),
              ),
              if (_results.searching ||
                  _results.labelScanning) ...const <Widget>[
                SizedBox(height: AppSpacing.sm),
                Center(
                  child: SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ],
              if (_results.labelScanning) ...const <Widget>[
                SizedBox(height: AppSpacing.xs),
                Text(tasteFitLabelReadingHint, style: AppTextStyles.modalBody),
              ],
              if (_results.failed) ...const <Widget>[
                SizedBox(height: AppSpacing.xs),
                Text(
                  '검색 서버 연결이 원활하지 않아요. 잠시 후 다시 시도해 주세요.',
                  style: AppTextStyles.modalBody,
                ),
              ],
              if (_results.labelHint case final hint?) ...<Widget>[
                const SizedBox(height: AppSpacing.sm),
                Text(hint, style: AppTextStyles.modalBody),
              ],
              if (_fit case TasteFitResponse(
                hasCards: false,
              ) when _results.matches.isNotEmpty) ...const <Widget>[
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

  /// A label's likeliest bottle on the card that asks 이 제품이 맞나요?,
  /// with its verdict, then the other candidates with their badges.
  Widget _buildLabelMatches(List<CatalogDrink> matches) {
    final best = matches.first;
    final others = <DrinkSelection>[
      for (final drink in matches.skip(1)) DrinkSelection.catalogMatch(drink),
    ];
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SelectedDrinkCard(
            key: const ValueKey<String>('label-best-candidate'),
            drink: best,
            verdict: _cardVerdict(best),
            onTap: () => _select(DrinkSelection.catalogMatch(best)),
          ),
          if (others.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.xl),
            const Text(otherCandidatesTitle, style: AppTextStyles.sectionTitle),
            const SizedBox(height: AppSpacing.sm),
            DrinkSearchResults(
              key: const ValueKey<String>('label-other-candidates'),
              drinks: others,
              selectedDrink: null,
              onDrinkSelected: _select,
              trailingBuilder: _badgeFor,
            ),
          ],
        ],
      ),
    );
  }

  /// The card's verdict line: the detail's headline, a spinner while the
  /// fit call is on the wire, or nothing (no verdict, no saved cards).
  Widget? _cardVerdict(CatalogDrink drink) {
    if (_judging.contains(drink.id)) {
      return const SizedBox.square(
        key: ValueKey<String>('label-best-judging'),
        dimension: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    final fit = _fit;
    final verdict = fit?.verdictFor(drink.id);
    if (fit == null || !fit.hasCards || verdict == null) return null;
    return TasteFitHeadline(verdict: verdict);
  }

  Widget _buildResults() {
    if (!_hasResultsContext) {
      if (_suggested.isEmpty) {
        return const Center(
          child: Text('찾으시는 술의 이름을 검색해 보세요.', style: AppTextStyles.modalBody),
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const SizedBox(height: AppSpacing.sm),
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
    if (_results.matches.isNotEmpty && _results.labelQueries.isNotEmpty) {
      return _buildLabelMatches(_results.matches);
    }
    if (_results.matches.isNotEmpty) {
      return DrinkSearchResults(
        drinks: List<DrinkSelection>.unmodifiable(
          _results.matches.map(DrinkSelection.catalogMatch),
        ),
        selectedDrink: null,
        onDrinkSelected: _select,
        scrollable: true,
        trailingBuilder: _badgeFor,
        onEndReached: _results.hasMore ? _loadMore : null,
        loadingMore: _results.loadingMore,
      );
    }
    if (_results.searching || _results.failed) {
      return const SizedBox.shrink();
    }
    return Text(
      _results.labelQueries.isNotEmpty
          ? tasteFitLabelNoMatchHint
          : '일치하는 술이 없어요. 다른 이름으로 검색해 보세요.',
      style: AppTextStyles.modalBody,
    );
  }
}
