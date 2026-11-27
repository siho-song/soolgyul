import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/errors/error_report.dart';
import '../../catalog/data/catalog_drink.dart';
import '../../catalog/data/catalog_search_gateway.dart';
import '../../catalog/data/discovery_events.dart';
import '../presentation/widgets/label_photo_flow.dart';
import 'label_catalog_search.dart';
import 'label_layout.dart';
import 'label_match.dart';
import 'label_text_recognizer.dart';

/// The catalog results of one search screen: a typed name searched after a
/// short pause and paged as the list nears its end, or the lines read off a
/// label photo. Every new search outdates the one before, and a late answer
/// to an outdated search is dropped. A search that finds nothing and every
/// label read are reported to [events] as seen from [surface].
class CatalogSearchSession extends ChangeNotifier {
  CatalogSearchSession(
    this._gateway, {
    this.onPage,
    this.events,
    this.surface = DiscoverySurface.record,
    this.listsSeveral = false,
  });

  final CatalogSearchGateway? Function() _gateway;
  final DiscoveryEventGateway? Function()? events;
  final DiscoverySurface surface;

  /// Whether a photo of several drinks (a shelf, a menu) answers with all
  /// of them, or only with the bottle it was taken of.
  final bool listsSeveral;

  /// Each page that arrives (the first, a label's, one more) with the search
  /// it answers; [isCurrent] tells whether that search still stands. When it
  /// returns a future, the page shows only once that has completed, so what
  /// it fetched for the page comes with it; the spinner stays meanwhile.
  final FutureOr<void> Function(List<CatalogDrink> page, int search)? onPage;

  List<CatalogDrink> matches = const <CatalogDrink>[];

  /// From the moment a name is typed until its results arrive.
  bool searching = false;

  /// Only while a request is on the wire, not during the typing pause, so a
  /// spinner does not flash on every key.
  bool requestInFlight = false;

  /// What the search failed with; null while it has not failed.
  Object? failure;
  bool get failed => failure != null;
  bool hasMore = false;

  /// The line to show with the answer on screen: see [catalogSearchNote].
  String? note;
  bool loadingMore = false;

  /// The label lines the matches came from; empty for a typed search.
  List<String> labelQueries = const <String>[];

  /// The drinks the label photo shows. One is a bottle whose candidates
  /// are [matches]; with more, [matches] is one drink of each, in reading
  /// order ([labelSeveral]), and every candidate of the one in
  /// [labelTiedFind]. Set as soon as the photo is searched, before [onPage]
  /// is asked about its drinks.
  List<LabelFind> labelFinds = const <LabelFind>[];

  bool get labelSeveral => labelFinds.length > 1;

  /// The label on the photo that names a brand and not which bottle of it:
  /// its candidates are that brand's bottles to choose from, none likelier
  /// than the next. `null` when every label named its drink.
  LabelFind? get labelTiedFind =>
      labelFinds.where((find) => find.search.tied).firstOrNull;

  /// The photo's one label is [labelTiedFind], so [matches] are its brand's
  /// bottles.
  bool get labelTied => !labelSeveral && labelTiedFind != null;
  bool labelScanning = false;
  String? labelHint;

  /// The last label read was a back label that named no drink found, so the
  /// reader is asked for the front instead of told the drink is missing.
  bool labelBackSide = false;

  /// What [retry] repeats: the name last typed, or the lines last read off a
  /// label when that came after it.
  String _lastQuery = '';
  List<ReadLine>? _lastLabelLines;

  Timer? _debounce;
  int _search = 0;
  bool _disposed = false;

  bool isCurrent(int search) => !_disposed && search == _search;

  /// The search the results on screen answer, as [onPage] is given it.
  int get current => _search;

  void _update() {
    if (!_disposed) notifyListeners();
  }

  void _drop() {
    matches = const <CatalogDrink>[];
    searching = false;
    requestInFlight = false;
    failure = null;
    hasMore = false;
    note = null;
    loadingMore = false;
    labelQueries = const <String>[];
    labelFinds = const <LabelFind>[];
    labelHint = null;
    labelScanning = false;
    labelBackSide = false;
  }

  /// Drops every result and outdates whatever is still running.
  void clear() {
    _debounce?.cancel();
    _search += 1;
    _drop();
    _update();
  }

  /// Searches [query] after a short pause, or at once when [immediate]. With
  /// [keepShown] the list on screen, and the spinner of a request still on
  /// the wire, stay until the new results come; otherwise the list empties.
  void search(String query, {bool immediate = false, bool keepShown = false}) {
    final gateway = _gateway();
    if (gateway == null || query.isEmpty) {
      clear();
      return;
    }
    _debounce?.cancel();
    _lastQuery = query;
    _lastLabelLines = null;
    final search = ++_search;
    final (shown, shownNote, onTheWire) = (matches, note, requestInFlight);
    _drop();
    if (keepShown) {
      matches = shown;
      note = shownNote;
      requestInFlight = onTheWire;
    }
    searching = true;
    _update();
    _debounce = Timer(
      immediate ? Duration.zero : const Duration(milliseconds: 250),
      () async {
        if (!isCurrent(search)) return;
        requestInFlight = true;
        _update();
        try {
          final found = await gateway.search(query);
          if (!isCurrent(search)) return;
          await _hold(found, search);
          if (!isCurrent(search)) return;
          matches = found;
          searching = false;
          requestInFlight = false;
          hasMore = found.length == catalogSearchPageSize;
          note = found is CatalogMatches
              ? catalogSearchNote(
                  notCarried: found.notCarried,
                  guesses: found.guesses,
                )
              : null;
          _update();
          if (found.isEmpty) {
            events?.call()?.record(
              DiscoveryEvent.searchEmpty,
              surface,
              query: query,
            );
          }
        } catch (error, stack) {
          if (!isCurrent(search)) return;
          if (error is! CatalogSearchException) {
            reportError(error, stack, where: 'catalog search');
          }
          matches = const <CatalogDrink>[];
          searching = false;
          requestInFlight = false;
          failure = error;
          _update();
        }
      },
    );
  }

  /// Repeats the search that failed: the label lines already read, so the
  /// reader is not sent back to the camera, or the typed name. Completes
  /// when a label's results are in, as [scanLabel] does.
  Future<void> retry() async {
    if (_lastLabelLines case final lines?) {
      await _searchLabel(() async => lines);
    } else {
      search(_lastQuery, immediate: true);
    }
  }

  /// Appends the next page of [query]'s matches; a failed page leaves the
  /// rows shown and the next scroll tries again.
  Future<void> loadMore(String query) async {
    final gateway = _gateway();
    if (gateway == null ||
        query.isEmpty ||
        !hasMore ||
        loadingMore ||
        searching) {
      return;
    }
    final search = _search;
    loadingMore = true;
    _update();
    List<CatalogDrink> page;
    try {
      page = await gateway.search(query, offset: matches.length);
    } catch (_) {
      if (isCurrent(search)) {
        loadingMore = false;
        _update();
      }
      return;
    }
    if (!isCurrent(search)) return;
    final shown = {for (final drink in matches) drink.id};
    final added = page.where((drink) => !shown.contains(drink.id)).toList();
    await _hold(added, search);
    if (!isCurrent(search)) return;
    matches = List<CatalogDrink>.unmodifiable(<CatalogDrink>[
      ...matches,
      ...added,
    ]);
    hasMore = page.length == catalogSearchPageSize;
    loadingMore = false;
    _update();
  }

  /// Reads [photo]'s label with [recognizer] and searches the lines it
  /// finds; an unreadable label leaves a hint instead.
  Future<void> scanLabel(LabelTextRecognizer recognizer, XFile photo) =>
      _searchLabel(() => recognizer.recognizeLines(photo.path));

  /// Searches the label lines [readLines] gives and keeps them for [retry].
  Future<void> _searchLabel(Future<List<ReadLine>> Function() readLines) async {
    final gateway = _gateway();
    if (gateway == null) return;
    _debounce?.cancel();
    final search = ++_search;
    _drop();
    labelScanning = true;
    _update();
    try {
      final lines = await readLines();
      if (!isCurrent(search)) return;
      _lastLabelLines = lines;
      final photo = await searchCatalogByPhoto(gateway, lines);
      if (!isCurrent(search)) return;
      // A photo of one bottle is ranked by the label match; one of several
      // keeps one find a label until its bottles are cut out one by one.
      final finds = listsSeveral && photo.listed.length > 1
          ? photo.listed
          : <LabelFind>[?await _matchedMain(gateway, lines, photo)];
      if (!isCurrent(search)) return;
      final found = finds.length == 1
          ? finds.single.search.matches
          : <CatalogDrink>[
              for (final find in finds)
                if (find.search.tied) ...find.search.matches else find.drink,
            ];
      if (photo.queries.isNotEmpty) {
        labelFinds = finds;
        await _hold(found, search);
        if (!isCurrent(search)) return;
      }
      labelScanning = false;
      labelBackSide = photo.backSide && found.isEmpty;
      if (photo.queries.isEmpty) {
        labelHint = labelBackSide
            ? tasteFitLabelBackSideHint
            : tasteFitLabelUnreadableHint;
        _update();
        return;
      }
      labelQueries = photo.queries;
      matches = found;
      if (labelTied) labelHint = tasteFitLabelTiedHint;
      _update();
      final sink = events?.call();
      for (final find in finds) {
        sink?.record(
          DiscoveryEvent.labelMatch,
          surface,
          drinkId: find.drink.id,
          query: find.search.queries.join(' '),
        );
      }
      if (finds.isEmpty) {
        sink?.record(
          DiscoveryEvent.labelMiss,
          surface,
          query: labelQueries.join(' '),
        );
      }
    } on CatalogSearchException catch (error) {
      if (!isCurrent(search)) return;
      labelScanning = false;
      failure = error;
      _update();
    } catch (error, stack) {
      if (!isCurrent(search)) return;
      reportError(error, stack, where: 'label scan');
      labelScanning = false;
      labelHint = tasteFitLabelUnreadableHint;
      _update();
    }
  }

  /// The bottle the photo was taken of, its drinks as the label match ranks
  /// them ([matchLabelPhoto]); the line search's own answer when the
  /// catalog has no word search, it fails, or it finds nothing.
  Future<LabelFind?> _matchedMain(
    CatalogSearchGateway gateway,
    List<ReadLine> lines,
    PhotoSearch photo,
  ) async {
    final main = photo.main;
    if (gateway case final LabelWordSearch words) {
      final LabelMatch match;
      try {
        match = await matchLabelPhoto(words, lines, photo);
      } on CatalogSearchException {
        return main;
      }
      if (match.drinks.isNotEmpty) {
        return LabelFind(
          group: main?.group ?? LabelGroup(lines: lines),
          search: LabelSearch(
            queries: main?.search.queries ?? photo.queries,
            matches: match.drinks.take(20).toList(growable: false),
            sure: match.state == LabelMatchState.sure,
            tied: match.state == LabelMatchState.brand,
          ),
        );
      }
    }
    return main;
  }

  /// Hands [page] to [onPage] and waits for what it returns. A failure
  /// there is reported and the page still shows.
  Future<void> _hold(List<CatalogDrink> page, int search) async {
    try {
      await onPage?.call(page, search);
    } catch (error, stack) {
      reportError(error, stack, where: 'catalog search page');
    }
  }

  /// Reports [drinkId] as the drink the reader chose among what the label
  /// photo on screen found, with the lines that found it; nothing when no
  /// label is on screen.
  void recordLabelPick(String drinkId) {
    if (labelQueries.isEmpty) return;
    final find = labelFinds
        .where(
          (find) => find.search.matches.any((drink) => drink.id == drinkId),
        )
        .firstOrNull;
    events?.call()?.record(
      DiscoveryEvent.labelPick,
      surface,
      drinkId: drinkId,
      query: (find?.search.queries ?? labelQueries).join(' '),
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    super.dispose();
  }
}
