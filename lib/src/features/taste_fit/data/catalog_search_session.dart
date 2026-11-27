import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/errors/error_report.dart';
import '../../catalog/data/catalog_drink.dart';
import '../../catalog/data/catalog_search_gateway.dart';
import '../../catalog/data/discovery_events.dart';
import '../presentation/widgets/label_photo_flow.dart';
import 'label_catalog_search.dart';
import 'label_photo_finder.dart';
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
  });

  final CatalogSearchGateway? Function() _gateway;
  final DiscoveryEventGateway? Function()? events;
  final DiscoverySurface surface;

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
  bool failed = false;
  bool hasMore = false;

  /// The line to show with the answer on screen: see [catalogSearchNote].
  String? note;
  bool loadingMore = false;

  /// The label lines the matches came from; empty for a typed search.
  List<String> labelQueries = const <String>[];

  /// The bottle the label photo was taken of, whose candidates are
  /// [matches]; `null` when the photo named none.
  LabelFind? _labelFind;
  bool labelScanning = false;
  String? labelHint;

  /// The last label read was a back label that named no drink found, so the
  /// reader is asked for the front instead of told the drink is missing.
  bool labelBackSide = false;

  /// What [retry] repeats: the name last typed, or the lines last read off a
  /// label when that came after it.
  String _lastQuery = '';
  LabelPhotoRead? _lastLabelRead;

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
    failed = false;
    hasMore = false;
    note = null;
    loadingMore = false;
    labelQueries = const <String>[];
    _labelFind = null;
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
    _lastLabelRead = null;
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
          failed = true;
          _update();
        }
      },
    );
  }

  /// Repeats the search that failed: the label lines already read, so the
  /// reader is not sent back to the camera, or the typed name. Completes
  /// when a label's results are in, as [scanLabel] does.
  Future<void> retry() async {
    if (_lastLabelRead case final read?) {
      await _searchLabel((finder, _) => finder.find(read));
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

  /// Reads [photo]'s label with [recognizer] and finds its drinks
  /// ([LabelPhotoFinder]); an unreadable label leaves a hint instead.
  Future<void> scanLabel(LabelTextRecognizer recognizer, XFile photo) =>
      _searchLabel(
        (finder, current) => finder.readAndFind(
          recognizer,
          photo.path,
          current: current,
          onRead: (read) => _lastLabelRead = read,
        ),
      );

  /// Finds a label's drinks with [find] and shows them.
  Future<void> _searchLabel(
    Future<LabelPhotoFound> Function(
      LabelPhotoFinder finder,
      bool Function() current,
    )
    find,
  ) async {
    final gateway = _gateway();
    if (gateway == null) return;
    final finder = LabelPhotoFinder(gateway);
    _debounce?.cancel();
    final search = ++_search;
    _drop();
    labelScanning = true;
    _update();
    try {
      final (:finds, :queries, :backSide) = await find(
        finder,
        () => isCurrent(search),
      );
      if (!isCurrent(search)) return;
      // The bottle the photo was taken of, or none.
      final bottle = finds.firstOrNull;
      final found = bottle?.search.matches ?? const <CatalogDrink>[];
      if (queries.isNotEmpty) {
        _labelFind = bottle;
        await _hold(found, search);
        if (!isCurrent(search)) return;
      }
      labelScanning = false;
      labelBackSide = backSide && found.isEmpty;
      if (queries.isEmpty) {
        labelHint = labelBackSide
            ? tasteFitLabelBackSideHint
            : tasteFitLabelUnreadableHint;
        _update();
        return;
      }
      labelQueries = queries;
      matches = found;
      // The label names a brand and not which bottle of it.
      if (bottle != null && bottle.search.tied) {
        labelHint = tasteFitLabelTiedHint;
      }
      _update();
      final sink = events?.call();
      if (bottle != null) {
        sink?.record(
          DiscoveryEvent.labelMatch,
          surface,
          drinkId: bottle.drink.id,
          query: bottle.search.queries.join(' '),
        );
      } else {
        sink?.record(
          DiscoveryEvent.labelMiss,
          surface,
          query: labelQueries.join(' '),
        );
      }
    } on CatalogSearchException {
      if (!isCurrent(search)) return;
      labelScanning = false;
      failed = true;
      _update();
    } catch (error, stack) {
      if (!isCurrent(search)) return;
      reportError(error, stack, where: 'label scan');
      labelScanning = false;
      labelHint = tasteFitLabelUnreadableHint;
      _update();
    }
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
    final find = _labelFind;
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
