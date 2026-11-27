import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/errors/error_report.dart';
import '../../../core/format/korean_particles.dart';
import '../../../widgets/app_button.dart';
import '../../../widgets/app_dialog.dart';
import '../../../widgets/app_snack_bar.dart';
import '../../../widgets/app_top_bar.dart';
import '../../catalog/data/catalog_drink.dart';
import '../../catalog/data/catalog_search_gateway.dart';
import '../../catalog/data/discovery_events.dart';
import '../data/label_photo_finder.dart';
import '../data/label_text_recognizer.dart';
import '../data/saved_drinks_gateway.dart';
import '../data/taste_fit_gateway.dart';
import '../data/taste_fit_verdict.dart';
import 'label_camera_screen.dart';
import 'label_results_screen.dart';
import 'taste_fit_search_screen.dart';
import 'widgets/label_reading_screen.dart';
import 'widgets/label_shots_review_screen.dart';

/// How long after the list is asked for it opens with the photos answered
/// by then, the rest still being checked; and how long after the asking a
/// photo's answer may still join it.
const Duration labelListWait = Duration(seconds: 3);
const Duration labelLateWait = Duration(seconds: 15);

const String labelCameraLeaveTitle = '촬영을 닫을까요?';
const String labelCameraLeaveBody = '닫으면 찍은 사진이 사라져요.';
const String labelCameraStayLabel = '계속 찍기';
const String labelResultsLeaveTitle = '결과를 닫을까요?';
const String labelResultsLeaveBody = '닫으면 찍은 사진과 찾은 술 목록이 사라져요.';
const String labelResultsStayLabel = '계속 보기';
const String labelLeaveLabel = '닫기';
const String labelSearchTitle = '내게 맞는 술 찾기';
const String labelSearchListedNotice = '이미 목록에 있어요.';
String labelSearchAddedNotice(String name) =>
    '$name${endsOnConsonant(name) ? '을' : '를'} 목록에 넣었어요.';

enum _Stage { camera, reading, results }

/// Finding drinks by their labels, from the camera to the list: photos are
/// taken one after another, read together on a screen that says how far
/// the reading is, and the drinks they surely show are listed best fit
/// first. A photo whose answer is slow does not hold the others back: the
/// list opens without it, says how many bottles are still being checked,
/// and takes its drinks in when the answer comes. From the list 더 찍기 returns to the camera with an empty stack and
/// adds what the new photos show; 검색 adds a drink by its name. Closing the
/// camera with photos taken, or the list, asks first.
class LabelScanFlow extends StatefulWidget {
  const LabelScanFlow({
    required this.catalogSearchGateway,
    required this.recognizer,
    required this.onSelect,
    this.tasteFitGateway,
    this.savedDrinks,
    this.discoveryEvents,
    super.key,
  });

  final CatalogSearchGateway catalogSearchGateway;
  final LabelTextRecognizer recognizer;

  /// Opens a listed drink's fit page.
  final ValueChanged<TasteFitSelection> onSelect;
  final TasteFitGateway? tasteFitGateway;

  /// Tells which finds are among 저장한 술; without it no row wears a heart.
  final SavedDrinksGateway? savedDrinks;
  final DiscoveryEventGateway? discoveryEvents;

  @override
  State<LabelScanFlow> createState() => LabelScanFlowState();
}

/// What looking at one photo came to: what it shows, or that its search
/// failed ([unsearched]) or something broke.
typedef _Looked = ({LabelPhotoFound? found, bool unsearched, bool broke});

/// Drinks not listed yet, with what is known of them.
typedef _Known = ({
  List<CatalogDrink> drinks,
  TasteFitResponse? fit,
  Set<String> saved,
});

/// One photo being read and searched.
class _Looking {
  /// Whether the phone has read it.
  bool read = false;

  /// What was read, with the one bottle's photo for the judge.
  LabelPhotoRead? photoRead;
  late final Future<_Looked> looked;

  /// [looked] once it has ended.
  _Looked? ended;

  /// What the judge left of [looked], once asked.
  Future<LabelPhotoFound>? judged;
}

@visibleForTesting
class LabelScanFlowState extends State<LabelScanFlow> {
  _Stage _stage = _Stage.camera;

  /// The photos taken and not read yet, oldest first.
  List<XFile> _shots = const <XFile>[];
  bool _reviewing = false;

  /// What was wrong with the last photo taken.
  String? _notice;

  /// Each photo's bottles inside what the viewfinder showed, being found
  /// from the moment it is taken, when it shows several: the one nearest
  /// the middle is read. `null` when the phone could not look for them,
  /// and the photo is read whole.
  final Map<String, Future<List<BottleBox>?>> _bottles =
      <String, Future<List<BottleBox>?>>{};

  /// What each photo shows, being read and searched from the moment it is
  /// taken, so most of the waiting is over when the member asks for the
  /// list. The phone reads one photo at a time ([_phoneRead] ends with the
  /// last one asked for) while their searches run side by side. A bottle's
  /// photo goes to the judge only when the list is asked for: a photo taken
  /// out before that is never sent.
  final Map<String, _Looking> _looking = <String, _Looking>{};
  Future<void> _phoneRead = Future<void>.value();

  /// The photos whose answer the open list still waits for.
  final Set<String> _checked = <String>{};
  final Set<Timer> _timers = <Timer>{};

  /// The drinks listed, in the order found, and what is known of them.
  List<CatalogDrink> _finds = const <CatalogDrink>[];
  TasteFitResponse? _fit;
  Set<String> _saved = const <String>{};

  /// Whether a list stands behind the camera (더 찍기).
  bool _listed = false;

  /// How many of the photos being read the phone has read.
  int get _readCount =>
      _shots.where((shot) => _looking[shot.path]?.read ?? false).length;
  bool _failed = false;

  /// Found on the photos and not listed yet: their verdicts did not come.
  List<CatalogDrink>? _unlisted;

  /// Goes up with every reading, so a reading left behind lists nothing.
  int _run = 0;

  /// The find whose fit page is open; its heart is asked for again on the
  /// way back.
  String? _opened;
  bool _wasCurrent = true;

  @override
  void dispose() {
    for (final timer in _timers) {
      timer.cancel();
    }
    super.dispose();
  }

  /// Calls [then] after [wait], unless the screen is gone by then.
  Timer _after(Duration wait, VoidCallback then) {
    late final Timer timer;
    timer = Timer(wait, () {
      _timers.remove(timer);
      then();
    });
    _timers.add(timer);
    return timer;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final current = ModalRoute.of(context)?.isCurrent ?? true;
    if (current && !_wasCurrent) {
      final opened = _opened;
      _opened = null;
      if (opened != null) unawaited(_refreshSaved(opened));
    }
    _wasCurrent = current;
  }

  /// Adds a photo as the camera would.
  @visibleForTesting
  void addShot(LabelShot shot) => _shot(shot);

  void _shot(LabelShot shot) {
    if (_shots.length >= labelCameraShotsMax) return;
    final path = shot.file.path;
    _bottles[path] = _findBottles(shot);
    _looking[path] = _look(path);
    setState(() {
      _shots = <XFile>[..._shots, shot.file];
      _notice = null;
    });
    unawaited(
      _bottles[path]!.then((bottles) {
        if (!mounted || bottles == null || bottles.length < 2) return;
        if (_shots.lastOrNull?.path != path) return;
        setState(() => _notice = labelCameraSeveralHint);
      }),
    );
  }

  Future<List<BottleBox>?> _findBottles(LabelShot shot) async {
    final LabelBottleReader reader;
    if (widget.recognizer case final LabelBottleReader found) {
      reader = found;
    } else {
      return null;
    }
    try {
      final bottles = await reader.findBottles(shot.file.path);
      return <BottleBox>[
        for (final bottle in bottles)
          if (shot.shown.contains(
            Offset(
              (bottle.left + bottle.right) / 2,
              (bottle.top + bottle.bottom) / 2,
            ),
          ))
            bottle,
      ];
    } on LabelTextRecognitionException {
      return null;
    }
  }

  LabelPhotoFinder get _finder =>
      LabelPhotoFinder(widget.catalogSearchGateway, judgesAsFound: false);

  /// Starts reading the photo at [path] and finding its drinks, after the
  /// photos asked for before it are read.
  _Looking _look(String path) {
    final looking = _Looking();
    final before = _phoneRead;
    final read = Completer<void>();
    _phoneRead = read.future;
    final bottles = _bottles[path] ?? Future<List<BottleBox>?>.value();
    looking.looked = () async {
      try {
        final found = await bottles;
        await before;
        return (
          found: await _finder.readAndFind(
            widget.recognizer,
            path,
            current: () => mounted && identical(_looking[path], looking),
            onRead: (read) => looking.photoRead = read,
            bottles: found,
            onPhotoRead: () {
              if (!read.isCompleted) read.complete();
              looking.read = true;
              if (mounted && _stage == _Stage.reading) setState(() {});
            },
          ),
          unsearched: false,
          broke: false,
        );
      } on CatalogSearchException {
        return (found: null, unsearched: true, broke: false);
      } on LabelTextRecognitionException {
        // A photo that cannot be read shows no drink.
        return (found: null, unsearched: false, broke: false);
      } catch (error, stack) {
        reportError(error, stack, where: 'label scan');
        return (found: null, unsearched: false, broke: true);
      } finally {
        if (!read.isCompleted) read.complete();
      }
    }();
    unawaited(looking.looked.then((looked) => looking.ended = looked));
    return looking;
  }

  /// What [looking] found, its one bottle put to the judge, once however
  /// often the list is asked for.
  Future<_Looked> _judged(_Looking looking) async {
    final looked = await looking.looked;
    final found = looked.found;
    final read = looking.photoRead;
    if (found == null || read == null) return looked;
    try {
      return (
        found: await (looking.judged ??= _finder.judged(found, read)),
        unsearched: looked.unsearched,
        broke: looked.broke,
      );
    } catch (error, stack) {
      reportError(error, stack, where: 'label scan');
      return (found: null, unsearched: false, broke: true);
    }
  }

  void _forget(Iterable<String> paths) {
    for (final path in paths) {
      _bottles.remove(path);
      _looking.remove(path);
    }
  }

  void _deleteShot(XFile shot) {
    _forget(<String>[shot.path]);
    setState(() {
      _shots = <XFile>[
        for (final other in _shots)
          if (other.path != shot.path) other,
      ];
      _notice = null;
      // The last photo gone, there is nothing to look at.
      if (_shots.isEmpty) _reviewing = false;
    });
  }

  bool _current(int run) => mounted && run == _run;

  /// Reads the photos taken and lists the drinks they surely show: all of
  /// them when every photo is answered within [labelListWait], and
  /// otherwise the ones answered by then, the rest as their answers come.
  Future<void> _read() async {
    final shots = _shots;
    if (shots.isEmpty) return;
    final run = ++_run;
    setState(() {
      _stage = _Stage.reading;
      _reviewing = false;
      _failed = false;
      _unlisted = null;
    });
    // A photo whose search failed while it was being taken is tried again.
    for (final shot in shots) {
      final ended = _looking[shot.path]?.ended;
      if (ended == null && _looking.containsKey(shot.path)) continue;
      if (ended == null || ended.unsearched || ended.broke) {
        _looking[shot.path] = _look(shot.path);
      }
    }
    try {
      final answers = <Future<_Looked>>[
        for (final shot in shots) _judged(_looking[shot.path]!),
      ];
      final answered = List<_Looked?>.filled(shots.length, null);
      for (final (index, answer) in answers.indexed) {
        unawaited(answer.then((looked) => answered[index] = looked));
      }
      final opens = Completer<void>();
      final waited = _after(labelListWait, () {
        if (!opens.isCompleted) opens.complete();
      });
      final late = Stopwatch()..start();
      unawaited(
        Future.wait(answers).then((_) {
          waited.cancel();
          _timers.remove(waited);
          if (!opens.isCompleted) opens.complete();
        }),
      );
      await opens.future;
      if (!_current(run)) return;
      final drinks = <CatalogDrink>[];
      var unsearched = 0;
      for (final photo in answered.nonNulls) {
        if (photo.broke) {
          setState(() => _failed = true);
          return;
        }
        if (photo.unsearched) unsearched += 1;
        if (photo.found case final found?) drinks.addAll(_sure(found));
      }
      if (unsearched == shots.length) {
        setState(() => _failed = true);
        return;
      }
      final slow = <String>[
        for (final (index, shot) in shots.indexed)
          if (answered[index] == null) shot.path,
      ];
      for (final (index, shot) in shots.indexed) {
        if (answered[index] != null) continue;
        _checked.add(shot.path);
        unawaited(_listLate(shot.path, answers[index]));
      }
      if (slow.isNotEmpty) {
        _after(labelLateWait - late.elapsed, () => _giveUp(slow));
      }
      await _list(drinks, run);
    } catch (error, stack) {
      reportError(error, stack, where: 'label scan');
      if (_current(run)) setState(() => _failed = true);
    }
  }

  /// Takes the drinks of a photo answered after the list opened into it,
  /// unless its time was over first ([_giveUp]). A late photo that shows
  /// no drink, or whose verdicts do not come, only stops being waited for.
  Future<void> _listLate(String path, Future<_Looked> answer) async {
    final looked = await answer;
    if (!mounted || !_checked.contains(path)) return;
    final drinks = switch (looked.found) {
      final found? => _sure(found),
      null => const <CatalogDrink>[],
    };
    final known = await _knownOf(drinks);
    if (!mounted || !_checked.contains(path)) return;
    _forget(<String>[path]);
    setState(() {
      _checked.remove(path);
      if (known != null) _add(known);
    });
  }

  /// Stops waiting for the answers of the photos at [paths].
  void _giveUp(List<String> paths) {
    if (!mounted || !paths.any(_checked.contains)) return;
    _forget(paths);
    setState(() => paths.forEach(_checked.remove));
  }

  /// The drinks a photo surely shows; the rest of what it found is left
  /// out, and reported as read with no drink when there is none.
  List<CatalogDrink> _sure(LabelPhotoFound found) {
    final events = widget.discoveryEvents;
    final sure = <CatalogDrink>[];
    for (final find in found.finds) {
      if (!find.search.sure) continue;
      sure.add(find.drink);
      events?.record(
        DiscoveryEvent.labelMatch,
        DiscoverySurface.tasteFit,
        drinkId: find.drink.id,
        query: find.search.queries.join(' '),
      );
    }
    if (sure.isEmpty && found.queries.isNotEmpty) {
      events?.record(
        DiscoveryEvent.labelMiss,
        DiscoverySurface.tasteFit,
        query: found.queries.join(' '),
      );
    }
    return sure;
  }

  /// The drinks of [drinks] not listed yet with their verdicts and hearts;
  /// `null` when the verdicts did not come.
  Future<_Known?> _knownOf(List<CatalogDrink> drinks) async {
    final listed = <String>{for (final drink in _finds) drink.id};
    final added = <CatalogDrink>[
      for (final drink in drinks)
        if (listed.add(drink.id)) drink,
    ];
    if (added.isEmpty) {
      return (drinks: added, fit: null, saved: const <String>{});
    }
    final ids = <String>[for (final drink in added) drink.id];
    TasteFitResponse? fit;
    if (widget.tasteFitGateway case final gateway?) {
      try {
        fit = await gateway.judge(ids);
      } on TasteFitGatewayException {
        return null;
      }
    }
    return (drinks: added, fit: fit, saved: await _savedAmong(ids));
  }

  /// Puts [known] at the end of the list; called while the state is set.
  /// A drink listed since it was asked about stays where it is.
  void _add(_Known known) {
    final listed = <String>{for (final drink in _finds) drink.id};
    _finds = <CatalogDrink>[
      ..._finds,
      for (final drink in known.drinks)
        if (listed.add(drink.id)) drink,
    ];
    if (known.fit case final judged?) {
      _fit = TasteFitResponse(
        hasCards: judged.hasCards,
        verdicts: Map<String, TasteFitVerdict>.unmodifiable(
          <String, TasteFitVerdict>{...?_fit?.verdicts, ...judged.verdicts},
        ),
      );
    }
    _saved = <String>{..._saved, ...known.saved};
  }

  /// Lists [drinks] once their verdicts and hearts are known. A drink
  /// listed already stays where it is.
  Future<void> _list(List<CatalogDrink> drinks, int run) async {
    final known = await _knownOf(drinks);
    if (!_current(run)) return;
    if (known == null) {
      setState(() {
        _failed = true;
        _unlisted = drinks;
      });
      return;
    }
    // A photo still being checked is read on.
    _forget(<String>[
      for (final shot in _shots)
        if (!_checked.contains(shot.path)) shot.path,
    ]);
    setState(() {
      _add(known);
      _shots = const <XFile>[];
      _notice = null;
      _unlisted = null;
      _listed = true;
      _stage = _Stage.results;
    });
  }

  Future<Set<String>> _savedAmong(List<String> ids) async {
    final gateway = widget.savedDrinks;
    if (gateway == null) return const <String>{};
    final saved = await Future.wait(<Future<bool>>[
      for (final id in ids) gateway.isSaved(id).catchError((Object _) => false),
    ]);
    return <String>{
      for (final (index, id) in ids.indexed)
        if (saved[index]) id,
    };
  }

  Future<void> _refreshSaved(String id) async {
    final gateway = widget.savedDrinks;
    if (gateway == null) return;
    final bool saved;
    try {
      saved = await gateway.isSaved(id);
    } catch (_) {
      return;
    }
    if (!mounted || saved == _saved.contains(id)) return;
    setState(() {
      _saved = saved
          ? <String>{..._saved, id}
          : <String>{
              for (final other in _saved)
                if (other != id) other,
            };
    });
  }

  void _retry() {
    final unlisted = _unlisted;
    if (unlisted == null) {
      unawaited(_read());
      return;
    }
    final run = ++_run;
    setState(() => _failed = false);
    unawaited(_list(unlisted, run));
  }

  /// From the reading back to the camera, the photos kept.
  void _backToCamera() {
    _run += 1;
    setState(() {
      _stage = _Stage.camera;
      _failed = false;
      _unlisted = null;
    });
  }

  void _select(CatalogDrink drink) {
    final fit = _fit;
    final events = widget.discoveryEvents;
    events?.record(
      DiscoveryEvent.labelPick,
      DiscoverySurface.tasteFit,
      drinkId: drink.id,
    );
    events?.record(
      DiscoveryEvent.fitView,
      DiscoverySurface.tasteFit,
      drinkId: drink.id,
    );
    _opened = drink.id;
    widget.onSelect((
      drink: drink,
      verdict: fit?.verdictFor(drink.id),
      hasCards: fit?.hasCards ?? true,
      judged: fit != null,
    ));
  }

  /// The name search over the list: the drink chosen there joins the list
  /// at its place by fit; leaving it adds nothing.
  Future<void> _search() async {
    final chosen = await Navigator.of(context).push<TasteFitSelection>(
      MaterialPageRoute<TasteFitSelection>(
        builder: (context) => Scaffold(
          appBar: AppTopBar.back(
            onPressed: () => Navigator.of(context).pop(),
            title: labelSearchTitle,
          ),
          body: SafeArea(
            top: false,
            child: TasteFitSearchScreen(
              catalogSearchGateway: widget.catalogSearchGateway,
              tasteFitGateway: widget.tasteFitGateway,
              discoveryEvents: widget.discoveryEvents,
              onSelect: (selection) => Navigator.of(context).pop(selection),
            ),
          ),
        ),
      ),
    );
    if (chosen == null || !mounted) return;
    final drink = chosen.drink;
    if (_finds.any((find) => find.id == drink.id)) {
      showAppSnackBar(context, labelSearchListedNotice);
      return;
    }
    final run = ++_run;
    await _list(<CatalogDrink>[drink], run);
    if (!mounted) return;
    if (_finds.any((find) => find.id == drink.id)) {
      showAppSnackBar(context, labelSearchAddedNotice(drink.displayName));
    } else {
      // Its verdict did not come; the list stays as it was.
      setState(() {
        _failed = false;
        _unlisted = null;
      });
      showAppSnackBar(context, tasteFitJudgeFailedMessage);
    }
  }

  void _more() => setState(() => _stage = _Stage.camera);

  Future<bool> _ask({
    required String title,
    required String body,
    required String stay,
  }) async {
    final leave = await showAppDialog<bool>(
      context: context,
      builder: (context) => AppDialogBody(
        title: title,
        body: body,
        actions: <Widget>[
          AppButton(
            label: stay,
            onPressed: () => Navigator.of(context).pop(false),
            variant: AppButtonVariant.neutral,
            size: AppButtonSize.popup,
          ),
          AppButton(
            key: const ValueKey<String>('label-leave'),
            label: labelLeaveLabel,
            onPressed: () => Navigator.of(context).pop(true),
            size: AppButtonSize.popup,
          ),
        ],
      ),
    );
    return leave ?? false;
  }

  /// The camera's top left, and the system back on it: photos taken and
  /// not read are asked about once before they are dropped.
  Future<void> _leaveCamera() async {
    if (_shots.isNotEmpty &&
        !await _ask(
          title: labelCameraLeaveTitle,
          body: labelCameraLeaveBody,
          stay: labelCameraStayLabel,
        )) {
      return;
    }
    if (!mounted) return;
    if (!_listed) {
      Navigator.of(context).pop();
      return;
    }
    // The photos the list still waits for are read on.
    _forget(<String>[for (final shot in _shots) shot.path]);
    setState(() {
      _shots = const <XFile>[];
      _notice = null;
      _stage = _Stage.results;
    });
  }

  Future<void> _leaveResults() async {
    if (!await _ask(
      title: labelResultsLeaveTitle,
      body: labelResultsLeaveBody,
      stay: labelResultsStayLabel,
    )) {
      return;
    }
    if (mounted) Navigator.of(context).pop();
  }

  /// The system back.
  void _back() {
    if (_reviewing) {
      setState(() => _reviewing = false);
      return;
    }
    switch (_stage) {
      case _Stage.camera:
        unawaited(_leaveCamera());
      case _Stage.reading:
        _backToCamera();
      case _Stage.results:
        unawaited(_leaveResults());
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: switch (_stage) {
        _Stage.camera => Stack(
          fit: StackFit.expand,
          children: <Widget>[
            LabelCameraScreen(
              shots: _shots,
              notice: _notice,
              onShot: _shot,
              onClose: () => unawaited(_leaveCamera()),
              onBackToResults: _listed ? () => unawaited(_leaveCamera()) : null,
              onReviewShots: () => setState(() => _reviewing = true),
              onResults: () => unawaited(_read()),
            ),
            // Over the camera, which stays up under it for the next shot.
            if (_reviewing)
              LabelShotsReviewScreen(
                shots: _shots,
                onDelete: _deleteShot,
                onClose: () => setState(() => _reviewing = false),
              ),
          ],
        ),
        _Stage.reading => LabelReadingScreen(
          shots: _shots,
          read: _readCount,
          failed: _failed,
          onBack: _backToCamera,
          onRetry: _retry,
        ),
        _Stage.results => LabelResultsScreen(
          finds: _finds,
          fit: _fit,
          saved: _saved,
          checking: _checked.length,
          onMore: _more,
          onSearch: () => unawaited(_search()),
          onClose: () => unawaited(_leaveResults()),
          onSelect: _select,
        ),
      },
    );
  }
}
