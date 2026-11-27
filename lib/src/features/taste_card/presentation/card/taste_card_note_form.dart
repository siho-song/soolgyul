part of '../taste_card_screen.dart';

// 테이스팅 노트 in edit mode: one form for the whole note, kept at once on
// the header's 완료. The draft holds what the form shows; the boxes are
// drawn in 기본 정보 and the look's choices in 상세 기록.

/// The keys of the form's boxes, by which each is found, scrolled to and
/// focused.
abstract final class _DraftBox {
  static const rating = TastingNoteField.rating;
  static const purchasedOn = TastingNoteField.purchasedOn;
  static const companionPlace = TastingNoteField.companionPlace;
  static const pairing = TastingNoteField.pairing;
  static const price = 'price';
  static const place = 'purchase-place';
  static const overall = 'overall';

  static const days = <String>[purchasedOn];

  /// In the order they stand on the page.
  static const all = <String>[
    rating,
    purchasedOn,
    price,
    place,
    companionPlace,
    pairing,
    overall,
  ];
}

/// What the note's form holds while it is written: the words of each box,
/// the ways it was drunk, the look chosen, and the record's answers (재음용
/// 의사, the aromas, the gauges) in a questionnaire flow. It knows what was stored when
/// it opened, so it can say whether anything changed, and 완료 sends only
/// what did.
class _NoteDraft extends ChangeNotifier {
  _NoteDraft({
    required this.entries,
    required this.price,
    required this.memo,
    required this.opener,
    this.answers,
    this.flow,
  }) {
    if (flow case final flow?) {
      _openingAnswers = answers!.questions!.registry.readAnswers(flow);
    }
    final stored = price?.price;
    final opening = <String, String>{
      _DraftBox.rating: switch (double.tryParse(
        entries.valueOf(TastingNoteField.rating) ?? '',
      )) {
        final stars? => stars.toStringAsFixed(1),
        null => '',
      },
      _DraftBox.purchasedOn: _shownDay(
        entries.valueOf(TastingNoteField.purchasedOn),
      ),
      _DraftBox.companionPlace:
          entries.valueOf(TastingNoteField.companionPlace) ?? '',
      _DraftBox.pairing: entries.valueOf(TastingNoteField.pairing) ?? '',
      _DraftBox.price: switch (stored?.amount) {
        final won? => groupWon(won),
        null => '',
      },
      _DraftBox.place: stored?.place ?? '',
      _DraftBox.overall: memo?.memo ?? '',
    };
    for (final key in _DraftBox.all) {
      final box = _Box(opening[key]!);
      _boxes[key] = box;
      var last = box.text;
      box.controller.addListener(() {
        // Writing in a box marked wrong takes the mark away.
        if (box.text != last && _wrong.remove(key)) notifyListeners();
        last = box.text;
        _changed();
      });
    }
    _opening = opening;
    servings = List<String>.of(entries.servings);
    appearance = entries.valueOf(TastingNoteField.appearance);
    texture = entries.valueOf(TastingNoteField.appearanceTexture);
  }

  final TastingNoteEditor entries;
  final RecordPriceEditor? price;
  final RecordMemoEditor? memo;
  final TasteCardNoteOpener opener;

  /// The record's answers, which 완료 corrects; null where they cannot be.
  final TasteCardAnswersEditor? answers;

  /// The answers as the form holds them; null where they cannot be changed.
  final SensoryQuestionFlow? flow;
  Map<String, List<String>>? _openingAnswers;

  /// Where 향 stands, which the page is brought to when nothing sensed is
  /// left.
  final sensesKey = GlobalKey();

  /// The mark of 향, 맛 and 여운 left with nothing sensed.
  static const senses = 'senses';

  final _boxes = <String, _Box>{};
  late final Map<String, String> _opening;
  final _wrong = <String>{};
  late List<String> servings;

  String? appearance;
  String? texture;

  _Box box(String key) => _boxes[key]!;
  String text(String key) => _boxes[key]!.text;
  bool isWrong(String key) => _wrong.contains(key);

  static String _shownDay(String? stored) =>
      switch (TastingNoteField.dayOf(stored)) {
        final day? => dotDay(day),
        null => '',
      };

  Map<String, List<String>>? get _answered => switch (flow) {
    final flow? => answers!.questions!.registry.readAnswers(flow),
    null => null,
  };

  bool get _answersChanged {
    final now = _answered;
    final opening = _openingAnswers;
    if (now == null || opening == null) return false;
    return now.entries.any(
      (entry) => !listEquals(entry.value, opening[entry.key] ?? const []),
    );
  }

  /// A change to the answers: an aroma picked or unpicked, a step chosen,
  /// 재음용 의사 chosen. Something sensed again takes 향's mark away.
  void answer(void Function(SensoryQuestionFlow flow) change) {
    final flow = this.flow;
    if (flow == null) return;
    change(flow);
    if (flow.hasSensation) _wrong.remove(senses);
    _changed();
  }

  bool get dirty =>
      _answersChanged ||
      _DraftBox.all.any((key) => text(key).trim() != _opening[key]) ||
      !listEquals(servings, entries.servings) ||
      appearance != entries.valueOf(TastingNoteField.appearance) ||
      texture != entries.valueOf(TastingNoteField.appearanceTexture);

  void _changed() {
    opener.markDirty(dirty);
    notifyListeners();
  }

  void setServings(List<String> ways) {
    servings = ways;
    _changed();
  }

  void setAppearance(String field, String? key) {
    if (field == TastingNoteField.appearance) {
      appearance = key;
    } else {
      texture = key;
    }
    _changed();
  }

  /// Whether a day box holds a day, or nothing; a day is written out as
  /// 2020.01.05.
  bool _checkDay(String key) {
    final box = this.box(key);
    final typed = box.text.trim();
    if (typed.isEmpty) return true;
    final day = normalizeDay(typed);
    if (day == null) return false;
    if (box.text != day) box.controller.text = day;
    return true;
  }

  /// Whether the 평점 box holds stars in halves from 0.5 to 5, or nothing;
  /// they are written out as 3.5.
  bool _checkRating() {
    final box = this.box(_DraftBox.rating);
    if (box.text.trim().isEmpty) return true;
    final stars = parseRating(box.text);
    if (stars == null) return false;
    final shown = stars.toStringAsFixed(1);
    if (box.text != shown) box.controller.text = shown;
    return true;
  }

  /// The stored form of a day box: YYYY-MM-DD, or null for blank.
  String? _storedDay(String key) => switch (dayOfDot(text(key).trim())) {
    final day? => TastingNoteField.storedDay(day),
    null => null,
  };

  static String? _words(String text) {
    final trimmed = text.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  /// 완료: checks every box, then keeps every change at once. With any box
  /// wrong nothing is kept: each wrong one is edged in red, the page brings
  /// the topmost to its top and focuses it, and one notice says so. Says
  /// what was kept or what went wrong.
  Future<bool> commit(BuildContext context) async {
    _wrong
      ..clear()
      ..addAll([
        if (!_checkRating()) _DraftBox.rating,
        for (final key in _DraftBox.days)
          if (!_checkDay(key)) key,
        // The questionnaire keeps no record without something sensed.
        if (flow?.hasSensation == false) senses,
      ]);
    if (_wrong.isNotEmpty) {
      notifyListeners();
      if (context.mounted) showAppSnackBar(context, '정보를 올바르게 입력해 주세요.');
      // The boxes stand in [_DraftBox.all]'s order on the page, and 향
      // under them all.
      final firstBox = _DraftBox.all.where(_wrong.contains).firstOrNull;
      final first = firstBox == null ? null : box(firstBox);
      first?.focus.requestFocus();
      if ((first?.key ?? sensesKey).currentContext case final target?) {
        await Scrollable.ensureVisible(target, duration: AppDurations.standard);
      }
      return false;
    }
    final patch = <String, String?>{
      if (text(_DraftBox.purchasedOn).trim() != _opening[_DraftBox.purchasedOn])
        TastingNoteField.purchasedOn: _storedDay(_DraftBox.purchasedOn),
      for (final key in [_DraftBox.companionPlace, _DraftBox.pairing])
        if (text(key).trim() != _opening[key]) key: _words(text(key)),
      if (text(_DraftBox.rating).trim() != _opening[_DraftBox.rating])
        TastingNoteField.rating: switch (parseRating(text(_DraftBox.rating))) {
          final stars? => _NoteStars.wordOf(stars),
          null => null,
        },
      if (!listEquals(servings, entries.servings))
        TastingNoteField.serving: servings.isEmpty
            ? null
            : servings.join(TastingNoteField.servingSeparator),
      if (appearance != entries.valueOf(TastingNoteField.appearance))
        TastingNoteField.appearance: appearance,
      if (texture != entries.valueOf(TastingNoteField.appearanceTexture))
        TastingNoteField.appearanceTexture: texture,
    };
    final failures = <String?>[
      await entries.saveAll(patch),
      await price?.save(
        amount: parseWon(text(_DraftBox.price)),
        place: _words(text(_DraftBox.place)),
      ),
      await memo?.saveText(text(_DraftBox.overall)),
    ];
    final failure = failures.nonNulls.firstOrNull;
    // The answers are kept as corrections, which the card is written again
    // from when it is shown or left.
    if (failure == null && _answersChanged) answers!.keep(_answered!);
    if (context.mounted) {
      failure == null
          ? showAppSnackBar(context, '수정한 내용을 저장했어요.', success: true)
          : showAppSnackBar(context, failure);
    }
    return failure == null;
  }

  @override
  void dispose() {
    for (final box in _boxes.values) {
      box.dispose();
    }
    super.dispose();
  }
}

/// A box's text, focus and place on the page.
class _Box {
  _Box(String text) : controller = TextEditingController(text: text);

  final TextEditingController controller;
  final focus = FocusNode();
  final key = GlobalKey();

  String get text => controller.text;

  void dispose() {
    controller.dispose();
    focus.dispose();
  }
}

/// 기본 정보's form in edit mode: 평점 | 구입 날짜, 가격 (KRW) | 구입처, then
/// across the line 재음용 의사, 음용 방식, 누구와 어디서, 페어링 and 총평. The day is
/// typed (2020.01.05, 20200105 or 200105) and written out on 완료; the price
/// shows its commas as it is typed. 음용 방식 and 재음용 의사 open their
/// choices.
class _NoteEditForm extends StatelessWidget {
  const _NoteEditForm({
    required this.draft,
    required this.serving,
    required this.revisit,
  });

  final _NoteDraft draft;

  /// The kind's ways of drinking; null for a kind with none.
  final TasteCardNoteChoiceViewData? serving;

  /// 재음용 의사 as the card has it, shown where the answers cannot be
  /// changed.
  final String? revisit;

  /// 재음용 의사 as the form holds it: the questionnaire's short answer, a
  /// skipped question as 애매해요, the same as the note reads it.
  String _revisitShown() {
    final flow = draft.flow;
    if (flow == null) return revisit ?? '';
    return switch (flow.revisit) {
      final intent? => RevisitQuestion.recordLabel(intent),
      null => '',
    };
  }

  Widget _text(
    String key,
    String label,
    String hint, {
    TextInputType keyboard = TextInputType.text,
    List<TextInputFormatter>? formatters,
    int maxLength = 100,
    int maxLines = 1,
  }) {
    final box = draft.box(key);
    final wrong = draft.isWrong(key);
    return _NoteFormField(
      key: box.key,
      label: label,
      child: AppTextField(
        key: ValueKey<String>('taste-card-note-$key'),
        controller: box.controller,
        focusNode: box.focus,
        hintText: hint,
        size: AppTextFieldSize.compact,
        maxLength: maxLength,
        maxLines: maxLines,
        minLines: maxLines > 1 ? 3 : null,
        keyboardType: maxLines > 1 ? TextInputType.multiline : keyboard,
        inputFormatters: formatters,
        hasError: wrong,
        textInputAction: maxLines > 1
            ? TextInputAction.newline
            : TextInputAction.done,
        onFieldSubmitted: (_) => box.focus.unfocus(),
      ),
    );
  }

  /// A box that is chosen, not typed: the chosen words, or 선택해 주세요,
  /// and a chevron; touched, it opens the choices.
  Widget _choice(String key, String label, String shown, VoidCallback? onTap) =>
      _NoteFormField(
        label: label,
        child: Semantics(
          button: true,
          label: label,
          value: shown,
          child: GestureDetector(
            key: ValueKey<String>('taste-card-note-$key'),
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.surfacePrimary,
                borderRadius: BorderRadius.circular(AppRadii.control),
                border: Border.all(color: AppColors.borderSubtle),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.md,
                  AppSpacing.sm,
                  AppSpacing.md,
                ),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        shown.isEmpty ? '선택해 주세요' : shown,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.body.copyWith(
                          color: shown.isEmpty
                              ? AppColors.textTertiary
                              : AppColors.textPrimary,
                        ),
                      ),
                    ),
                    const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: AppSizes.iconLg,
                      color: AppColors.textTertiary,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: draft,
    builder: (context, _) {
      Widget pair(Widget left, Widget? right) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(child: left),
          const SizedBox(width: AppSpacing.md),
          Expanded(child: right ?? const SizedBox.shrink()),
        ],
      );
      final serving = this.serving;
      final servingBox = serving == null
          ? null
          : _choice(
              'serving',
              serving.label,
              <String>[
                for (final option in serving.options)
                  if (draft.servings.contains(option.key)) option.chosenLabel,
              ].join(' · '),
              () async {
                final ways = await _showNoteServingSheet(
                  context,
                  serving,
                  draft.servings,
                );
                if (ways != null) draft.setServings(ways);
              },
            );
      final revisitBox = _choice(
        'revisit',
        '재음용 의사',
        _revisitShown(),
        draft.flow == null
            ? null
            : () async {
                // A skipped question opens on 애매해요, as the form shows it.
                final shown = switch (draft.flow!.revisit) {
                  final intent? => RevisitQuestion.recordAnswer(intent),
                  null => null,
                };
                final chosen = await _showNoteRevisitSheet(
                  context,
                  shown == null ? null : 'revisit:${shown.name}',
                );
                final intent = RevisitIntent.values
                    .asNameMap()[chosen?.substring('revisit:'.length)];
                // The answer shown, kept: nothing was answered again, and a
                // skipped question stays the skipped one it is stored as.
                if (intent != null && intent != shown) {
                  draft.answer((flow) => flow.setRevisit(intent));
                }
              },
      );
      const gap = SizedBox(height: AppSpacing.md);
      return Column(
        key: const ValueKey<String>('taste-card-note-form'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          pair(
            _text(
              _DraftBox.rating,
              '평점',
              '예) 3.5',
              keyboard: const TextInputType.numberWithOptions(decimal: true),
              maxLength: 4,
            ),
            _text(
              _DraftBox.purchasedOn,
              '구입 날짜',
              '예) 2026.09.01',
              keyboard: TextInputType.datetime,
              maxLength: 10,
            ),
          ),
          gap,
          pair(
            _text(
              _DraftBox.price,
              '가격 (KRW)',
              '예) 50,000',
              keyboard: TextInputType.number,
              formatters: const <TextInputFormatter>[_WonFormatter()],
              maxLength: 10,
            ),
            _text(_DraftBox.place, '구입처', '예) 와인샵'),
          ),
          gap,
          revisitBox,
          gap,
          if (servingBox != null) ...<Widget>[servingBox, gap],
          _text(_DraftBox.companionPlace, '누구와 어디서', '예) 친구와 집에서'),
          gap,
          _text(_DraftBox.pairing, '페어링', '예) 스테이크, 치즈'),
          gap,
          _text(
            _DraftBox.overall,
            '총평',
            '이 술을 한 줄로 남겨 보세요',
            maxLength: 2000,
            maxLines: 5,
          ),
        ],
      );
    },
  );
}

/// A box's name in small grey over the box.
class _NoteFormField extends StatelessWidget {
  const _NoteFormField({required this.label, required this.child, super.key});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      Text(label, style: _NoteText.muted),
      const SizedBox(height: AppSpacing.xs),
      child,
    ],
  );
}

/// Keeps the digits of a price and writes them with commas as they are
/// typed: 80000 shows as 80,000, the cursor kept after the same digit.
class _WonFormatter extends TextInputFormatter {
  const _WonFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp('[^0-9]'), '');
    if (digits.isEmpty) return const TextEditingValue();
    final won = int.parse(digits);
    if (won > maxWon) return oldValue;
    final text = groupWon(won);
    // The digits before the cursor stay before it.
    final cursor = newValue.selection.baseOffset.clamp(0, newValue.text.length);
    final before = newValue.text
        .substring(0, cursor)
        .replaceAll(RegExp('[^0-9]'), '')
        .length;
    var offset = 0;
    for (var seen = 0; offset < text.length && seen < before; offset++) {
      if (text[offset] != ',') seen++;
    }
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: offset),
    );
  }
}

/// The member's stars, only read: [rating] of five filled in the card's
/// wine, a half star for a half, the rest as light grey outlines.
class _NoteStars extends StatelessWidget {
  const _NoteStars({required this.rating, required this.size});

  final double rating;
  final double size;

  static const _count = 5;

  /// 4.0 as 4, a half as 4.5: as the note keeps it.
  static String wordOf(double stars) =>
      stars % 1 == 0 ? '${stars.toInt()}' : '$stars';

  IconData _iconOf(int star) {
    if (rating >= star) return Icons.star_rounded;
    if (rating >= star - .5) return Icons.star_half_rounded;
    return Icons.star_outline_rounded;
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: '평점 ${wordOf(rating)}점',
    child: Row(
      key: const ValueKey<String>('taste-card-note-rating'),
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (var star = 1; star <= _count; star++)
          Icon(
            _iconOf(star),
            size: size,
            color: _iconOf(star) == Icons.star_outline_rounded
                ? AppColors.borderStrong
                : _TasteCardColors.wine,
          ),
      ],
    ),
  );
}
