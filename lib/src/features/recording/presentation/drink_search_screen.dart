import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../../design/app_layout.dart';
import '../../../design/app_tokens.dart';
import '../../../design/app_typography.dart';
import '../../catalog/data/catalog_drink.dart';
import '../../catalog/data/catalog_search_gateway.dart';
import '../../catalog/data/discovery_events.dart';
import '../../catalog/data/suggested_drinks.dart';
import '../../onboarding/presentation/widgets/onboarding_layout.dart';
import '../../taste_fit/data/label_photo_picker.dart';
import '../../taste_fit/data/label_text_recognizer.dart';
import '../../taste_fit/data/catalog_search_session.dart';
import '../../taste_fit/presentation/widgets/label_photo_flow.dart';
import '../../taste_fit/presentation/widgets/label_scan_button.dart';
import '../../../widgets/app_icon.dart';
import '../../../widgets/app_text_field.dart';
import 'widgets/drink_search_results.dart';
import 'widgets/selected_drink_card.dart';

class RecordDrinkSearchScreen extends StatefulWidget {
  const RecordDrinkSearchScreen({
    this.onDrinkSelected,
    this.onDrinkSelection,
    this.initialDrinkName,
    this.catalogDrinks,
    this.catalogSearchGateway,
    this.discoveryEvents,
    this.title = '술 이름이 기억나나요?',
    this.description = '찾은 술의 특징까지 반영해\n내 취향을 더 섬세하게 분석해드려요.',
    this.searchHintText = '술 이름이나 브랜드를 검색해 보세요',
    this.topContentBuilder,
    this.suggestedDrinkNames = const <String>[],
    this.suggestionsTitle = '자주 찾는 술',
    this.labelTextRecognizer,
    this.pickLabelPhoto,
    super.key,
  }) : assert(onDrinkSelected != null || onDrinkSelection != null);

  final ValueChanged<String>? onDrinkSelected;
  final ValueChanged<DrinkSelection>? onDrinkSelection;
  final String? initialDrinkName;
  final List<CatalogDrink>? catalogDrinks;
  final CatalogSearchGateway? catalogSearchGateway;

  /// Told about empty searches, label reads and the drink submitted.
  final DiscoveryEventGateway? discoveryEvents;
  final String title;
  final String description;
  final String searchHintText;

  /// Shown above the question until the visitor starts typing.
  final OnboardingContentBuilder? topContentBuilder;

  /// Exact catalog names listed under the field while nothing is typed.
  /// Tapping one selects it the same way a search result does.
  final List<String> suggestedDrinkNames;
  final String suggestionsTitle;

  /// With a recognizer the field carries the label camera button: the
  /// photo's lines are read on the device and searched as one, and the
  /// candidates show in the ordinary result list. Without one there is no
  /// button (the web has no recognizer).
  final LabelTextRecognizer? labelTextRecognizer;
  final LabelPhotoPicker? pickLabelPhoto;

  @override
  State<RecordDrinkSearchScreen> createState() =>
      _RecordDrinkSearchScreenState();
}

class _RecordDrinkSearchScreenState extends State<RecordDrinkSearchScreen> {
  late final TextEditingController _searchController;
  late final FocusNode _searchFocusNode;
  DrinkSelection? _selectedDrink;
  late final CatalogSearchSession _results = CatalogSearchSession(
    () => widget.catalogSearchGateway,
    events: () => widget.discoveryEvents,
  )..addListener(_rebuild);

  /// The words typed when [_selectedDrink] was chosen from the results;
  /// `null` for a suggestion or a label's candidate.
  String? _pickQuery;
  List<CatalogDrink> _suggestedDrinks = const <CatalogDrink>[];

  String get _searchQuery => _searchController.text.trim();

  bool get _hasResultsContext =>
      _searchQuery.isNotEmpty || _results.labelQueries.isNotEmpty;

  List<DrinkSelection> get _visibleDrinks {
    if (!_hasResultsContext) {
      return const <DrinkSelection>[];
    }
    final normalizedQuery = _searchQuery.toLowerCase();
    // The gateway already matched the query and pages it; the local list is
    // matched here and stops at one page.
    final fromCatalog =
        widget.catalogSearchGateway != null || _results.labelQueries.isNotEmpty;
    final candidates = fromCatalog
        ? _results.matches
        : (widget.catalogDrinks ?? const <CatalogDrink>[]).where(
            (drink) =>
                drink.displayName.toLowerCase().contains(normalizedQuery),
          );
    final drinks = candidates.map(DrinkSelection.catalogMatch);
    return List<DrinkSelection>.unmodifiable(
      fromCatalog ? drinks : drinks.take(catalogSearchPageSize),
    );
  }

  @override
  void initState() {
    super.initState();
    final initialDrinkName = widget.initialDrinkName?.trim();
    if (initialDrinkName != null && initialDrinkName.isNotEmpty) {
      final catalogMatches = widget.catalogDrinks
          ?.where((drink) => drink.displayName == initialDrinkName)
          .toList(growable: false);
      _selectedDrink = catalogMatches != null && catalogMatches.isNotEmpty
          ? DrinkSelection.catalogMatch(catalogMatches.first)
          : null;
    }
    _searchController = TextEditingController(
      text: widget.initialDrinkName ?? '',
    );
    _searchFocusNode = FocusNode()..addListener(_handleFocusChanged);
    if (widget.catalogSearchGateway != null && _searchQuery.isNotEmpty) {
      _results.search(_searchQuery, immediate: true, keepShown: true);
    }
    unawaited(_loadSuggestedDrinks());
  }

  @override
  void reassemble() {
    super.reassemble();
    // Hot reload keeps this state; pick up an edited suggestion list.
    unawaited(_loadSuggestedDrinks());
  }

  Future<void> _loadSuggestedDrinks() async {
    final names = widget.suggestedDrinkNames;
    if (names.isEmpty) {
      return;
    }
    final gateway = widget.catalogSearchGateway;
    if (gateway == null) {
      final local = widget.catalogDrinks ?? const <CatalogDrink>[];
      _suggestedDrinks = <CatalogDrink>[
        for (final name in names)
          ...local.where((drink) => drink.displayName == name).take(1),
      ];
      return;
    }
    // Usually prefetched on the page before, so this is already in memory.
    final cached = SuggestedDrinks.cached(names);
    if (cached != null) {
      _suggestedDrinks = cached;
      return;
    }
    final resolved = await SuggestedDrinks.load(gateway, names);
    if (!mounted) {
      return;
    }
    setState(() => _suggestedDrinks = resolved);
  }

  List<DrinkSelection> get _visibleSuggestions =>
      !_hasResultsContext && _selectedDrink == null
      ? List<DrinkSelection>.unmodifiable(
          _suggestedDrinks.map(DrinkSelection.catalogMatch),
        )
      : const <DrinkSelection>[];

  Widget _buildSuggestions(
    List<DrinkSelection> suggestions, {
    bool scrollable = false,
  }) {
    final list = DrinkSearchResults(
      key: const ValueKey<String>('drink-search-suggestions'),
      drinks: suggestions,
      selectedDrink: _selectedDrink,
      onDrinkSelected: _selectDrink,
      scrollable: scrollable,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: scrollable ? MainAxisSize.max : MainAxisSize.min,
      children: <Widget>[
        Text(widget.suggestionsTitle, style: AppTextStyles.sectionTitle),
        const SizedBox(height: AppSpacing.sm),
        if (scrollable) Expanded(child: list) else list,
      ],
    );
  }

  @override
  void dispose() {
    _results.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _handleFocusChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  /// Typing keeps the results shown until the new ones come, and drops the
  /// label results; a running scan is left to finish and discarded.
  void _handleSearchChanged(String value) {
    setState(() => _selectedDrink = null);
    if (widget.catalogSearchGateway == null) return;
    _results.search(_searchQuery, keepShown: true);
  }

  void _clearSearch() {
    _searchController.clear();
    _selectedDrink = null;
    _results.clear();
  }

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
    _searchFocusNode.unfocus();
    _selectedDrink = null;
    await _results.scanLabel(recognizer, photo);
    // The likeliest bottle is chosen at once and asked about on the card;
    // the other candidates stay listed under it.
    if (!mounted || _results.labelQueries.isEmpty) return;
    if (_results.matches.firstOrNull case final best?) {
      _selectDrink(DrinkSelection.catalogMatch(best));
    }
  }

  /// The label's candidates besides the one on the card.
  List<DrinkSelection> get _otherLabelCandidates => <DrinkSelection>[
    if (_results.labelQueries.isNotEmpty)
      for (final drink in _results.matches)
        if (drink.id != _selectedDrink?.catalogId)
          DrinkSelection.catalogMatch(drink),
  ];

  /// Tests hand over a photo directly; the app opens the camera screen.
  Future<XFile?> _pickLabelPhoto() {
    final injected = widget.pickLabelPhoto;
    if (injected != null) return injected();
    return takeLabelPhoto(
      context,
      onTypeInstead: _searchFocusNode.requestFocus,
    );
  }

  void _loadMoreCatalogMatches() => unawaited(_results.loadMore(_searchQuery));

  // The chosen name fills the field and the result list closes until the
  // visitor edits the name again.
  void _selectDrink(DrinkSelection drink) {
    _pickQuery = _searchQuery.isEmpty || _results.labelQueries.isNotEmpty
        ? null
        : _searchQuery;
    _searchController.value = TextEditingValue(
      text: drink.displayName,
      selection: TextSelection.collapsed(offset: drink.displayName.length),
    );
    setState(() => _selectedDrink = drink);
    _searchFocusNode.unfocus();
  }

  void _submitSelectedDrink() {
    final selectedDrink = _selectedDrink;
    if (selectedDrink != null) {
      widget.discoveryEvents?.record(
        DiscoveryEvent.searchPick,
        DiscoverySurface.record,
        drinkId: selectedDrink.catalogId,
        query: _pickQuery,
      );
      widget.onDrinkSelection?.call(selectedDrink);
      widget.onDrinkSelected?.call(selectedDrink.displayName);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (!AppLayout.isViewportReady(constraints)) {
          return const SizedBox.shrink();
        }

        final layout = AppScreenLayout.fromConstraints(constraints);
        final horizontalPadding = layout.horizontalPadding;
        final visibleDrinks = _visibleDrinks;
        final keyboardVisible = MediaQuery.viewInsetsOf(context).bottom > 0;

        if (!kIsWeb && (_searchFocusNode.hasFocus || keyboardVisible)) {
          return _buildFocusedSearch(
            horizontalPadding: horizontalPadding,
            visibleDrinks: visibleDrinks,
          );
        }

        final topContentBuilder = _searchQuery.isEmpty
            ? widget.topContentBuilder
            : null;
        final results = _hasResultsContext && _selectedDrink == null
            ? _buildResults(visibleDrinks)
            : null;
        final suggestions = _visibleSuggestions;
        // The results sit inside the page's own scroll here, so the page's
        // scroll asks for the next page.
        return NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if (results != null && isNearScrollEnd(notification)) {
              _loadMoreCatalogMatches();
            }
            return false;
          },
          child: OnboardingStepScaffold(
            topContentBuilder: topContentBuilder,
            topPadding: topContentBuilder == null
                ? AppSpacing.xxl
                : AppSpacing.sm,
            title: widget.title,
            description: widget.description,
            descriptionStyle: AppTextStyles.recordingQuestionDescription,
            childrenBuilder: (context, layout) => <Widget>[
              _buildSearchField(),
              ..._buildSearchStatus(),
              const SizedBox(height: AppSpacing.sm),
              const SizedBox(height: AppSpacing.md),
              if (results != null) ...<Widget>[
                results,
                const SizedBox(height: AppSpacing.xl),
              ],
              if (suggestions.isNotEmpty) ...<Widget>[
                _buildSuggestions(suggestions),
                const SizedBox(height: AppSpacing.xl),
              ],
              if (_selectedDrink case final selected?) ...<Widget>[
                SelectedDrinkCard(drink: selected.catalogDrink),
                if (_otherLabelCandidates case final others
                    when others.isNotEmpty) ...<Widget>[
                  const SizedBox(height: AppSpacing.xl),
                  const Text(
                    otherCandidatesTitle,
                    style: AppTextStyles.sectionTitle,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  DrinkSearchResults(
                    key: const ValueKey<String>('label-other-candidates'),
                    drinks: others,
                    selectedDrink: null,
                    onDrinkSelected: _selectDrink,
                  ),
                ],
              ],
            ],
            primaryAction: OnboardingStepAction(
              label: '다음',
              trailingIcon: AppIconAsset.next,
              onPressed: _selectedDrink == null ? null : _submitSelectedDrink,
            ),
          ),
        );
      },
    );
  }

  Widget _buildSearchField() {
    // The intro above the question leaves once typing starts, which shifts
    // the field's position; the key keeps the same field and its focus.
    return AppTextField(
      key: const ValueKey<String>('drink-search-field'),
      controller: _searchController,
      focusNode: _searchFocusNode,
      autofocus: false,
      onChanged: _handleSearchChanged,
      textInputAction: TextInputAction.search,
      hintText: widget.searchHintText,
      variant: AppTextFieldVariant.search,
      isLoading: _results.requestInFlight || _results.labelScanning,
      onClear: _hasResultsContext ? _clearSearch : null,
      // Once a drink is picked, only the clear button stays, so a wrong pick
      // is one tap away from a fresh search.
      trailing: widget.labelTextRecognizer == null || _selectedDrink != null
          ? null
          : LabelScanButton(
              key: const ValueKey<String>('drink-search-label-button'),
              label: tasteFitLabelButtonLabel,
              onPressed: _results.labelScanning ? null : _scanLabel,
            ),
    );
  }

  /// Notes under the field: a failed catalog search, and what the label
  /// scan is doing or read. Progress shows inside the field itself.
  List<Widget> _buildSearchStatus() {
    return <Widget>[
      if (_results.failed) ...const <Widget>[
        SizedBox(height: AppSpacing.xs),
        Text(
          '카탈로그 검색이 잠시 원활하지 않아요. 잠시 후 다시 찾아보세요.',
          style: AppTextStyles.modalBody,
        ),
      ],
      if (_results.labelScanning) ...const <Widget>[
        SizedBox(height: AppSpacing.xs),
        Text(tasteFitLabelReadingHint, style: AppTextStyles.modalBody),
      ],
      if (_results.labelHint case final hint?) ...<Widget>[
        const SizedBox(height: AppSpacing.xs),
        Text(hint, style: AppTextStyles.modalBody),
      ],
    ];
  }

  /// The matches, or one line when nothing matched.
  Widget _buildResults(
    List<DrinkSelection> visibleDrinks, {
    bool scrollable = false,
  }) {
    if (visibleDrinks.isNotEmpty) {
      return DrinkSearchResults(
        drinks: visibleDrinks,
        selectedDrink: _selectedDrink,
        onDrinkSelected: _selectDrink,
        scrollable: scrollable,
        onEndReached: _results.hasMore ? _loadMoreCatalogMatches : null,
        loadingMore: _results.loadingMore,
      );
    }
    if (_results.searching || _results.failed) {
      return const SizedBox.shrink();
    }
    return Text(
      _results.labelQueries.isNotEmpty
          ? tasteFitLabelNoMatchHint
          : '검색 결과가 없어요. 다른 이름으로 찾아보세요.',
      style: AppTextStyles.modalBody,
    );
  }

  Widget _buildFocusedSearch({
    required double horizontalPadding,
    required List<DrinkSelection> visibleDrinks,
  }) {
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
          _buildSearchField(),
          ..._buildSearchStatus(),
          const SizedBox(height: AppSpacing.sm),
          Expanded(
            child: !_hasResultsContext && _visibleSuggestions.isNotEmpty
                ? _buildSuggestions(_visibleSuggestions, scrollable: true)
                : !_hasResultsContext
                ? const Center(
                    child: Text(
                      '기억나는 술 이름을 검색해보세요',
                      style: AppTextStyles.modalBody,
                    ),
                  )
                : _buildResults(visibleDrinks, scrollable: true),
          ),
        ],
      ),
    );
  }
}
