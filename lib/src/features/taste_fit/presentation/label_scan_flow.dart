import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/errors/error_report.dart';
import '../../../core/format/korean_particles.dart';
import '../../../widgets/app_button.dart';
import '../../../widgets/app_dialog.dart';
import '../../../widgets/app_paper.dart';
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

/// The bottles of one photo that are read: the camera asks for this many
/// or fewer, and of a photo with more the largest are read.
const int labelBottlesPerPhoto = 4;

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
/// first. From the list 더 찍기 returns to the camera with an empty stack and
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

@visibleForTesting
class LabelScanFlowState extends State<LabelScanFlow> {
  _Stage _stage = _Stage.camera;

  /// The photos taken and not read yet, oldest first.
  List<XFile> _shots = const <XFile>[];
  bool _reviewing = false;

  /// What was wrong with the last photo taken.
  String? _notice;

  /// Each photo's bottles inside what the viewfinder showed, being found
  /// from the moment it is taken; `null` when the phone could not find
  /// any, and the photo is read whole.
  final Map<String, Future<List<BottleBox>?>> _bottles =
      <String, Future<List<BottleBox>?>>{};

  /// The drinks listed, in the order found, and what is known of them.
  List<CatalogDrink> _finds = const <CatalogDrink>[];
  TasteFitResponse? _fit;
  Set<String> _saved = const <String>{};

  /// Whether a list stands behind the camera (더 찍기).
  bool _listed = false;

  /// The bottles counted on the photos being read and how many are read.
  int _bottleCount = 0;
  int _readCount = 0;
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
    setState(() {
      _shots = <XFile>[..._shots, shot.file];
      _notice = null;
    });
    unawaited(
      _bottles[path]!.then((bottles) {
        if (!mounted || bottles == null) return;
        if (bottles.length <= labelBottlesPerPhoto) return;
        if (_shots.lastOrNull?.path != path) return;
        setState(() => _notice = labelCameraCrowdedHint);
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

  void _deleteShot(XFile shot) {
    _bottles.remove(shot.path);
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

  /// Reads the photos taken and lists the drinks they surely show.
  Future<void> _read() async {
    final shots = _shots;
    if (shots.isEmpty) return;
    final run = ++_run;
    setState(() {
      _stage = _Stage.reading;
      _reviewing = false;
      _failed = false;
      _unlisted = null;
      _bottleCount = 0;
      _readCount = 0;
    });
    try {
      final bottles = <List<BottleBox>?>[];
      var count = 0;
      for (final shot in shots) {
        final found = await _bottles[shot.path];
        if (!_current(run)) return;
        bottles.add(found);
        count += found == null
            ? 1
            : math.max(1, math.min(found.length, labelBottlesPerPhoto));
      }
      setState(() => _bottleCount = count);
      final finder = LabelPhotoFinder(
        widget.catalogSearchGateway,
        listsSeveral: true,
        mostRead: labelBottlesPerPhoto,
      );
      final drinks = <CatalogDrink>[];
      var unsearched = 0;
      for (final (index, shot) in shots.indexed) {
        try {
          final found = await finder.readAndFind(
            widget.recognizer,
            shot.path,
            current: () => _current(run),
            onRead: (_) {},
            bottles: bottles[index],
            onBottleRead: () {
              if (_current(run)) setState(() => _readCount += 1);
            },
          );
          if (!_current(run)) return;
          drinks.addAll(_sure(found));
        } on CatalogSearchException {
          unsearched += 1;
        } on LabelTextRecognitionException {
          // A photo that cannot be read shows no drink.
        }
        if (!_current(run)) return;
      }
      if (unsearched == shots.length) {
        setState(() => _failed = true);
        return;
      }
      await _list(drinks, run);
    } catch (error, stack) {
      reportError(error, stack, where: 'label scan');
      if (_current(run)) setState(() => _failed = true);
    }
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

  /// Lists [drinks] once their verdicts and hearts are known. A drink
  /// listed already stays where it is.
  Future<void> _list(List<CatalogDrink> drinks, int run) async {
    final listed = <String>{for (final drink in _finds) drink.id};
    final added = <CatalogDrink>[
      for (final drink in drinks)
        if (listed.add(drink.id)) drink,
    ];
    final ids = <String>[for (final drink in added) drink.id];
    var fit = _fit;
    var saved = _saved;
    if (ids.isNotEmpty) {
      if (widget.tasteFitGateway case final gateway?) {
        try {
          final judged = await gateway.judge(ids);
          fit = TasteFitResponse(
            hasCards: judged.hasCards,
            verdicts: Map<String, TasteFitVerdict>.unmodifiable(
              <String, TasteFitVerdict>{...?fit?.verdicts, ...judged.verdicts},
            ),
          );
        } on TasteFitGatewayException {
          if (!_current(run)) return;
          setState(() {
            _failed = true;
            _unlisted = drinks;
          });
          return;
        }
      }
      saved = <String>{...saved, ...await _savedAmong(ids)};
    }
    if (!_current(run)) return;
    for (final shot in _shots) {
      _bottles.remove(shot.path);
    }
    setState(() {
      _finds = <CatalogDrink>[..._finds, ...added];
      _fit = fit;
      _saved = saved;
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
        builder: (context) => AppPaperScaffold(
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
    _bottles.clear();
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
          bottles: _bottleCount,
          read: _readCount,
          failed: _failed,
          onBack: _backToCamera,
          onRetry: _retry,
        ),
        _Stage.results => LabelResultsScreen(
          finds: _finds,
          fit: _fit,
          saved: _saved,
          onMore: _more,
          onSearch: () => unawaited(_search()),
          onClose: () => unawaited(_leaveResults()),
          onSelect: _select,
        ),
      },
    );
  }
}
