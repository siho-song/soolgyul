/// The four taste letters shown on the home tab, read from `taste_letters`
/// and `taste_letter_changes`. The server recomputes them after every card;
/// the app only reads and words them.
enum TasteLetterAxis {
  aroma(
    'aroma',
    'F',
    'R',
    '향',
    '향 (아로마)',
    '코끝에 먼저 닿는 향의 취향은 아직 비밀이에요.\n다음 술에서 어떤 향이 났는지 기록하면\n이 조각이 열려요.',
  ),
  sweetness(
    'sweetness',
    'D',
    'S',
    '단맛',
    '단맛 (당도)',
    '단맛을 어디까지 반기는지는 아직 비밀이에요.\n다음 술에서 단맛이 어땠는지 기록하면\n이 조각이 열려요.',
  ),
  weight(
    'weight',
    'L',
    'H',
    '무게',
    '무게 (바디감)',
    '입안에서 느껴지는 무게감은 아직 비밀이에요.\n다음 술에서 목넘김과 무게감을 기록하면\n이 조각이 열려요.',
  ),
  finish(
    'finish',
    'C',
    'P',
    '여운',
    '여운 (피니시)',
    '삼킨 뒤 남는 여운의 취향은 아직 비밀이에요.\n다음 술에서 마무리가 어땠는지 기록하면\n이 조각이 열려요.',
  );

  const TasteLetterAxis(
    this.key,
    this.leftLetter,
    this.rightLetter,
    this.label,
    this.hiddenCaption,
    this.hiddenBody,
  );

  final String key;
  final String leftLetter;
  final String rightLetter;
  final String label;

  /// Under the closed tile (무게 (바디감)).
  final String hiddenCaption;

  /// The three lines inside the closed panel.
  final String hiddenBody;

  /// The Korean glyph shown for the left letter (산 for F).
  String get leftGlyph => TasteLetterPole.glyphOf(leftLetter);
  String get rightGlyph => TasteLetterPole.glyphOf(rightLetter);

  static TasteLetterAxis? fromKey(String? key) {
    for (final axis in values) {
      if (axis.key == key) return axis;
    }
    return null;
  }
}

/// What one letter means, in the docent's words. The server stores the
/// Latin letter; the app shows its Korean [glyph] everywhere.
class TasteLetterPole {
  const TasteLetterPole({
    required this.letter,
    required this.glyph,
    required this.label,
    required this.shareName,
    required this.axisPhrase,
    required this.body,
    required this.phrase,
  });

  final String letter;

  /// The one-syllable glyph on the tile (산, 드, 가, 깔).
  final String glyph;

  /// Short name used in the home summary and as the meaning card's title
  /// (산뜻한 향, 드라이, 깔끔한 여운).
  final String label;

  /// The side as a noun with its English word, on the share gauge
  /// (산뜻함 (Fresh) 75%).
  final String shareName;

  /// The side with its axis word, for the change moments
  /// (산뜻한 향 쪽으로 기울었어요 / 드라이한 맛 축이 처음 열렸어요).
  final String axisPhrase;
  final String body;

  /// Predicate piece for the overview sentence (산뜻한 향이 나고).
  final String phrase;

  static const _byLetter = <String, TasteLetterPole>{
    'F': TasteLetterPole(
      letter: 'F',
      glyph: '산',
      label: '산뜻한 향',
      shareName: '산뜻함 (Fresh)',
      axisPhrase: '산뜻한 향',
      body: '과일, 꽃, 허브처럼 맑고 화사하게 피어나는 향을 기분 좋게 즐겨요.',
      phrase: '산뜻한 향이 나고',
    ),
    'R': TasteLetterPole(
      letter: 'R',
      glyph: '풍',
      label: '풍부한 향',
      shareName: '풍부함 (Rich)',
      axisPhrase: '풍부한 향',
      body: '오크, 견과, 스모키처럼 깊고 두텁게 퍼지는 향에서 매력을 느껴요.',
      phrase: '풍부한 향이 깔리고',
    ),
    'D': TasteLetterPole(
      letter: 'D',
      glyph: '드',
      label: '드라이',
      shareName: '드라이 (Dry)',
      axisPhrase: '드라이한 맛',
      body: '단맛이 절제되어 담백하고 깔끔하게 떨어지는 맛을 편안하게 즐겨요.',
      phrase: '드라이하고',
    ),
    'S': TasteLetterPole(
      letter: 'S',
      glyph: '달',
      label: '달콤한',
      shareName: '달콤함 (Sweet)',
      axisPhrase: '달콤한 맛',
      body: '입안에 기분 좋게 퍼지는 은은하고 또렷한 단맛을 좋아해요.',
      phrase: '달콤하고',
    ),
    'L': TasteLetterPole(
      letter: 'L',
      glyph: '가',
      label: '가벼운',
      shareName: '가벼움 (Light)',
      axisPhrase: '가벼운 무게',
      body: '부담 없이 가볍고 부드럽게 넘어가는 목넘김을 편안해해요.',
      phrase: '가볍게 넘어가고',
    ),
    'H': TasteLetterPole(
      letter: 'H',
      glyph: '묵',
      label: '묵직한',
      shareName: '묵직함 (Heavy)',
      axisPhrase: '묵직한 무게',
      body: '입안을 묵직하게 채워주는 깊은 바디감과 따뜻한 온기를 즐겨요.',
      phrase: '묵직하게 받쳐 주고',
    ),
    'C': TasteLetterPole(
      letter: 'C',
      glyph: '깔',
      label: '깔끔한 여운',
      shareName: '깔끔함 (Clean)',
      axisPhrase: '깔끔한 여운',
      body: '뒤끝 없이 산뜻하고 개운하게 정돈되는 깔끔한 마무리를 좋아해요.',
      phrase: '깔끔하게 끝나는',
    ),
    'P': TasteLetterPole(
      letter: 'P',
      glyph: '길',
      label: '긴 여운',
      shareName: '긴 여운 (Persistent)',
      axisPhrase: '긴 여운',
      body: '잔을 내려놓은 뒤에도 향과 여운이 길게 이어지는 술을 좋아해요.',
      phrase: '길게 남는',
    ),
  };

  /// The pole for a letter; unknown letters have no pole.
  static TasteLetterPole? of(String? letter) => _byLetter[letter];

  /// The glyph for a stored letter; an unknown letter shows as it is.
  static String glyphOf(String letter) => _byLetter[letter]?.glyph ?? letter;
}

class TasteLetterAxisState {
  const TasteLetterAxisState({
    this.letter,
    this.leftShare = 0,
    this.rightShare = 0,
    this.voteCount = 0,
  });

  static const empty = TasteLetterAxisState();

  final String? letter;
  final int leftShare;
  final int rightShare;
  final int voteCount;

  bool get revealed => letter != null;

  factory TasteLetterAxisState.fromJson(Map<String, dynamic> json) =>
      TasteLetterAxisState(
        letter: json['letter'] as String?,
        leftShare: _int(json['left_share']),
        rightShare: _int(json['right_share']),
        voteCount: _int(json['vote_count']),
      );
}

class TasteLettersState {
  const TasteLettersState({
    required this.axes,
    this.recordCount = 0,
    this.updatedAt,
  });

  final Map<TasteLetterAxis, TasteLetterAxisState> axes;
  final int recordCount;
  final DateTime? updatedAt;

  factory TasteLettersState.fromRow(Map<String, dynamic> row) {
    final rawAxes = row['axes'];
    final axes = <TasteLetterAxis, TasteLetterAxisState>{};
    for (final axis in TasteLetterAxis.values) {
      final json = rawAxes is Map ? rawAxes[axis.key] : null;
      axes[axis] = json is Map
          ? TasteLetterAxisState.fromJson(Map<String, dynamic>.from(json))
          : TasteLetterAxisState.empty;
    }
    final updatedAt = row['updated_at'];
    return TasteLettersState(
      axes: axes,
      recordCount: _int(row['record_count']),
      updatedAt: updatedAt is String
          ? DateTime.tryParse(updatedAt)?.toLocal()
          : null,
    );
  }

  TasteLetterAxisState of(TasteLetterAxis axis) =>
      axes[axis] ?? TasteLetterAxisState.empty;

  String? letterOf(TasteLetterAxis axis) => of(axis).letter;

  /// Glyphs in axis order, '·' for an empty slot (e.g. '산드·깔').
  String get code => [
    for (final axis in TasteLetterAxis.values)
      switch (letterOf(axis)) {
        final letter? => TasteLetterPole.glyphOf(letter),
        null => '·',
      },
  ].join();

  /// Axes that already have a letter, in display order.
  List<TasteLetterAxis> get revealed => [
    for (final axis in TasteLetterAxis.values)
      if (of(axis).revealed) axis,
  ];

  List<TasteLetterAxis> get hidden => [
    for (final axis in TasteLetterAxis.values)
      if (!of(axis).revealed) axis,
  ];

  List<TasteLetterPole> get revealedPoles => [
    for (final axis in revealed) ?TasteLetterPole.of(letterOf(axis)),
  ];

  /// The sentence under the home strip and at the top of the detail screen.
  String get overviewStatement {
    final poles = revealedPoles;
    if (poles.isEmpty) return '첫 술결을 남기면 취향 조각이 드러나요.';
    return '${poles.map((pole) => pole.phrase).join(' ')} 술이 편해요.';
  }
}

class TasteLetterChange {
  const TasteLetterChange({
    required this.axis,
    required this.toLetter,
    required this.changedAt,
    this.fromLetter,
    this.leftShare = 0,
    this.rightShare = 0,
    this.productName = '',
    this.resultId,
  });

  final TasteLetterAxis axis;
  final String? fromLetter;
  final String toLetter;
  final int leftShare;
  final int rightShare;
  final String productName;
  final DateTime changedAt;

  /// The saved card of the record that tipped it; null once that record is
  /// deleted, and then the row does not open anything.
  final String? resultId;

  bool get isFirstReveal => fromLetter == null;

  /// Rows whose axis is unknown are skipped by the caller.
  static TasteLetterChange? fromRow(
    Map<String, dynamic> row, {
    String? resultId,
  }) {
    final axis = TasteLetterAxis.fromKey(row['axis'] as String?);
    final toLetter = row['to_letter'] as String?;
    final changedAt = row['changed_at'];
    if (axis == null || toLetter == null || changedAt is! String) return null;
    return TasteLetterChange(
      axis: axis,
      fromLetter: row['from_letter'] as String?,
      toLetter: toLetter,
      leftShare: _int(row['left_share']),
      rightShare: _int(row['right_share']),
      productName: (row['product_name'] as String?) ?? '',
      changedAt: DateTime.parse(changedAt).toLocal(),
      resultId: resultId,
    );
  }

  /// The small tag on the row: 첫 발견 / 향 변화.
  String get kindLabel => isFirstReveal ? '첫 발견' : '${axis.label} 변화';

  /// The quoted line next to the tiles.
  String get quote {
    final phrase = TasteLetterPole.of(toLetter)?.axisPhrase ?? toLetter;
    return isFirstReveal ? '$phrase 축이 처음 열렸어요' : '$phrase 쪽으로 기울었어요';
  }
}

class TasteLettersSnapshot {
  const TasteLettersSnapshot({this.state, this.changes = const []});

  /// `null` when the user has no letters row yet.
  final TasteLettersState? state;

  /// Oldest first.
  final List<TasteLetterChange> changes;
}

abstract interface class TasteLettersGateway {
  Future<TasteLettersSnapshot> load();
}

int _int(Object? value) => switch (value) {
  int v => v,
  num v => v.toInt(),
  String v => int.tryParse(v) ?? 0,
  _ => 0,
};
