import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../design/app_layout.dart';
import '../../../design/app_tokens.dart';
import '../../../design/app_typography.dart';
import '../../../widgets/app_text_field.dart';
import '../../catalog/data/catalog_drink.dart';
import '../../catalog/data/catalog_search_gateway.dart';
import '../../catalog/data/discovery_events.dart';
import '../../recording/presentation/widgets/drink_search_results.dart';
import '../../recording/presentation/widgets/drink_search_note.dart';
import '../../catalog/data/suggested_drinks.dart';
import '../data/label_text_recognizer.dart';
import '../data/saved_drinks_gateway.dart';
import '../data/taste_fit_gateway.dart';
import '../data/catalog_search_session.dart';
import '../data/taste_fit_verdict.dart';
import 'widgets/label_photo_flow.dart';
import 'widgets/label_scan_button.dart';
import 'widgets/taste_fit_badge.dart';
import '../../../widgets/app_state_view.dart';

export 'widgets/label_photo_flow.dart' show tasteFitLabelButtonLabel;

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
const String tasteFitJudgeFailedMessage = '나와 잘 맞는지 확인하지 못했어요.';
const String tasteFitSuggestionsTitle = '많이 기록하는 술';

/// Catalog search whose result rows carry the reader's fit badge. The
/// camera button in its field opens the label camera, which lists what its
/// photos show on screens of its own ([LabelScanFlow]).
class TasteFitSearchScreen extends StatefulWidget {
  const TasteFitSearchScreen({
    required this.onSelect,
    this.catalogSearchGateway,
    this.tasteFitGateway,
    this.savedDrinksGateway,
    this.discoveryEvents,
    this.labelTextRecognizer,
    this.scanLabelOnOpen = false,
    this.onCloseOpeningScan,
    this.suggestedDrinkNames = const <String>[],
    this.revision = 0,
    super.key,
  });

  final ValueChanged<TasteFitSelection> onSelect;
  final CatalogSearchGateway? catalogSearchGateway;
  final TasteFitGateway? tasteFitGateway;

  /// Tells the label camera's list which of its drinks are saved.
  final SavedDrinksGateway? savedDrinksGateway;

  /// Told about empty searches, label reads, picks and every fit opened.
  final DiscoveryEventGateway? discoveryEvents;

  /// Without one there is no label button.
  final LabelTextRecognizer? labelTextRecognizer;

  /// Asks for the label photo as soon as the screen opens (the home camera
  /// button); the search field then waits instead of taking focus.
  final bool scanLabelOnOpen;

  /// Leaves the screen when the camera it opened with ([scanLabelOnOpen])
  /// is closed, with or without drinks found, so the reader is back where
  /// they pressed the camera, not on a search they never saw. `null` stays.
  final VoidCallback? onCloseOpeningScan;

  /// Exact catalog names listed, with their badges, while nothing has been
  /// searched yet; the same list the record search shows.
  final List<String> suggestedDrinkNames;

  /// Changes when a record was saved. The faces are drawn from the reader's
  /// cards, so the rows on screen ask for theirs again.
  final int revision;

  @override
  State<TasteFitSearchScreen> createState() => _TasteFitSearchScreenState();
}

class _TasteFitSearchScreenState extends State<TasteFitSearchScreen> {
  /// How long a list waits for its faces before it shows without them; the
  /// faces then fill in as they arrive.
  static const _faceWait = Duration(seconds: 1);

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

  /// Whether the reader has saved cards, as the last fit call answered;
  /// null before any answer.
  bool? _hasCards;

  /// A list waits for its faces unless there can be none: no fit call, or
  /// a reader already known to have no cards.
  bool get _waitsForFaces =>
      widget.tasteFitGateway != null && _hasCards != false;

  String get _query => _searchController.text.trim();

  bool get _hasResultsContext => _query.isNotEmpty;

  @override
  void initState() {
    super.initState();
    if (widget.scanLabelOnOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_scanLabel(opening: true));
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
    if (oldWidget.revision != widget.revision) _judgeAgain();
  }

  /// Asks again for the faces of the rows on screen, the suggestions and
  /// the results; the old ones stay until the new arrive.
  void _judgeAgain() {
    final suggested = _suggested;
    if (suggested.isNotEmpty) {
      unawaited(
        _judgeSuggestions(suggested)?.then((fit) {
          if (!mounted || fit == null || !identical(suggested, _suggested)) {
            return;
          }
          setState(() => _suggestedFit = fit);
        }),
      );
    }
    final matches = _results.matches;
    if (matches.isNotEmpty) unawaited(_judgeRows(matches, _results.current));
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
    final judged = _judgeSuggestions(drinks);
    // The list waits a moment so its faces come with it.
    final fit = judged == null || !_waitsForFaces
        ? null
        : await judged.timeout(_faceWait, onTimeout: () => null);
    if (stale()) return;
    setState(() {
      _suggested = drinks;
      _suggestedFit = fit;
    });
    if (judged == null || fit != null) return;
    final late = await judged;
    if (!stale() && late != null) setState(() => _suggestedFit = late);
  }

  /// The suggestions' verdicts, or null when there is no fit call or it
  /// failed (the list stays useful without badges).
  Future<TasteFitResponse?>? _judgeSuggestions(List<CatalogDrink> drinks) {
    final gateway = widget.tasteFitGateway;
    if (gateway == null) return null;
    return gateway
        .judge(drinks.map((drink) => drink.id).toList(growable: false))
        .then<TasteFitResponse?>((response) {
          _hasCards = response.hasCards;
          return response;
        })
        .catchError(
          (Object _) => null,
          test: (error) => error is TasteFitGatewayException,
        );
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
    // The keyboard comes back for the next name.
    _searchFocus.requestFocus();
  }

  /// Typing keeps the rows and their badges on screen until the new
  /// results come, as the record search does.
  void _typed(String _) => _results.search(_query, keepShown: true);

  void _loadMore() => unawaited(_results.loadMore(_query));

  /// Whether the label camera is open over this screen.
  bool _cameraOpen = false;

  Future<void> _scanLabel({bool opening = false}) async {
    final recognizer = widget.labelTextRecognizer;
    final catalog = widget.catalogSearchGateway;
    if (recognizer == null || catalog == null || _cameraOpen) return;
    _cameraOpen = true;
    // The camera lists what it finds on its own screens.
    await openLabelScanFlow(
      context,
      catalogSearchGateway: catalog,
      recognizer: recognizer,
      tasteFitGateway: widget.tasteFitGateway,
      savedDrinks: widget.savedDrinksGateway,
      discoveryEvents: widget.discoveryEvents,
      onSelect: widget.onSelect,
    );
    _cameraOpen = false;
    if (opening && mounted) widget.onCloseOpeningScan?.call();
  }

  /// The verdicts of a page of results, added to those already shown; a
  /// failed call leaves those rows unbadged. The page waits for it, up to
  /// [_faceWait], so its rows and faces show together.
  FutureOr<void> _judge(List<CatalogDrink> matches, int search) {
    if (widget.tasteFitGateway == null || matches.isEmpty) return null;
    final judged = _judgeRows(matches, search);
    if (!_waitsForFaces) return null;
    return judged.timeout(_faceWait, onTimeout: () {});
  }

  Future<void> _judgeRows(List<CatalogDrink> matches, int search) async {
    final gateway = widget.tasteFitGateway!;
    final ids = matches.map((drink) => drink.id).toList(growable: false);
    _judging.addAll(ids);
    try {
      final response = await gateway.judge(ids);
      if (!mounted) return;
      _hasCards = response.hasCards;
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
    if (_query.isNotEmpty) {
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
                // Progress shows inside the field, so the rows under it
                // stay where they are.
                isLoading: _results.requestInFlight,
                onClear: _hasResultsContext ? _clearSearch : null,
                trailing: widget.labelTextRecognizer == null
                    ? null
                    : LabelScanButton(
                        key: const ValueKey<String>('taste-fit-label-button'),
                        label: tasteFitLabelButtonLabel,
                        onPressed: _scanLabel,
                      ),
              ),
              if (_results.failed) ...<Widget>[
                const SizedBox(height: AppSpacing.lg),
                AppCardError(
                  message: '검색 서버 연결이 원활하지 않아요.',
                  error: _results.failure,
                  onRetry: () => unawaited(_results.retry()),
                ),
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

  Widget _buildResults() {
    if (!_hasResultsContext) {
      if (_suggested.isEmpty) {
        return const Center(
          child: AppEmptyView(message: '찾으시는 술의 이름을 검색해 보세요.'),
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
    if (_results.matches.isNotEmpty) {
      return DrinkSearchNoted(
        note: _results.note,
        scrollable: true,
        child: DrinkSearchResults(
          drinks: List<DrinkSelection>.unmodifiable(
            _results.matches.map(DrinkSelection.catalogMatch),
          ),
          selectedDrink: null,
          onDrinkSelected: _select,
          scrollable: true,
          trailingBuilder: _badgeFor,
          onEndReached: _results.hasMore ? _loadMore : null,
          loadingMore: _results.loadingMore,
        ),
      );
    }
    if (_results.failed) return const SizedBox.shrink();
    // No rows to keep on screen yet, so the list's place says a search is
    // running, as the record search does.
    if (_results.searching) {
      return const Align(
        alignment: Alignment.topCenter,
        child: AppLoadingView(compact: true),
      );
    }
    return AppEmptyView(
      message: _results.note ?? '일치하는 술이 없어요. 다른 이름으로 검색해 보세요.',
    );
  }
}
