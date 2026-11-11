import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import '../../catalog/data/catalog_drink.dart';
import '../../catalog/data/catalog_search_gateway.dart';
import '../../catalog/data/discovery_events.dart';
import '../presentation/widgets/label_photo_flow.dart';
import 'label_catalog_search.dart';
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
  /// it answers; [isCurrent] tells whether that search still stands.
  final void Function(List<CatalogDrink> page, int search)? onPage;

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
  bool labelScanning = false;
  String? labelHint;

  Timer? _debounce;
  int _search = 0;
  bool _disposed = false;

  bool isCurrent(int search) => !_disposed && search == _search;

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
    labelHint = null;
    labelScanning = false;
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
          onPage?.call(found, search);
        } catch (_) {
          if (!isCurrent(search)) return;
          matches = const <CatalogDrink>[];
          searching = false;
          requestInFlight = false;
          failed = true;
          _update();
        }
      },
    );
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
    matches = List<CatalogDrink>.unmodifiable(<CatalogDrink>[
      ...matches,
      ...added,
    ]);
    hasMore = page.length == catalogSearchPageSize;
    loadingMore = false;
    _update();
    onPage?.call(added, search);
  }

  /// Reads [photo]'s label with [recognizer] and searches the lines it
  /// finds; an unreadable label leaves a hint instead.
  Future<void> scanLabel(LabelTextRecognizer recognizer, XFile photo) async {
    final gateway = _gateway();
    if (gateway == null) return;
    _debounce?.cancel();
    final search = ++_search;
    _drop();
    labelScanning = true;
    _update();
    try {
      final queries = labelSearchQueries(
        await recognizer.recognizeLines(photo.path),
      );
      if (!isCurrent(search)) return;
      if (queries.isEmpty) {
        labelScanning = false;
        labelHint = tasteFitLabelUnreadableHint;
        _update();
        return;
      }
      final found = await searchCatalogByLabel(gateway, queries);
      if (!isCurrent(search)) return;
      labelScanning = false;
      labelQueries = queries;
      matches = found;
      _update();
      final sink = events?.call();
      if (found.firstOrNull case final best?) {
        sink?.record(DiscoveryEvent.labelMatch, surface, drinkId: best.id);
      } else {
        sink?.record(
          DiscoveryEvent.labelMiss,
          surface,
          query: queries.join(' '),
        );
      }
      onPage?.call(found, search);
    } on CatalogSearchException {
      if (!isCurrent(search)) return;
      labelScanning = false;
      failed = true;
      _update();
    } catch (_) {
      if (!isCurrent(search)) return;
      labelScanning = false;
      labelHint = tasteFitLabelUnreadableHint;
      _update();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    super.dispose();
  }
}
