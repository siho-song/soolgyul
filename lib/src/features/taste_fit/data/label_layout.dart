import 'dart:math' as math;

/// One line the device read off a photo, with where it sits: fractions of
/// the photo's width and height, measured from its top left corner.
class ReadLine {
  const ReadLine({
    required this.text,
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    this.confidence = 1,
  });

  final String text;
  final double left;
  final double top;
  final double width;
  final double height;

  /// How sure the reader was of the text, 0 to 1.
  final double confidence;

  double get right => left + width;
  double get bottom => top + height;

  /// A line as the label channel sends it: `text`, `left`, `top`, `width`,
  /// `height` and `confidence`. `null` for anything else.
  static ReadLine? fromChannel(Object? value) {
    if (value is! Map) return null;
    final text = value['text'];
    final left = value['left'];
    final top = value['top'];
    final width = value['width'];
    final height = value['height'];
    final confidence = value['confidence'];
    if (text is! String ||
        left is! num ||
        top is! num ||
        width is! num ||
        height is! num) {
      return null;
    }
    return ReadLine(
      text: text,
      left: left.toDouble(),
      top: top.toDouble(),
      width: width.toDouble(),
      height: height.toDouble(),
      confidence: confidence is num ? confidence.toDouble() : 1,
    );
  }
}

/// Lines that belong together in the photo: one bottle's label, or one
/// entry of a menu or a cart.
class LabelGroup {
  const LabelGroup({required this.lines, this.listEntry = false});

  /// In reading order, top first.
  final List<ReadLine> lines;

  /// One line of a list (a menu, a cart screenshot), which names a drink
  /// by itself; a label's lines name one drink together.
  final bool listEntry;

  double get top => lines.map((line) => line.top).reduce(math.min);
  double get left => lines.map((line) => line.left).reduce(math.min);
  double get right => lines.map((line) => line.right).reduce(math.max);

  double get bottom => lines.map((line) => line.bottom).reduce(math.max);

  /// How far the group's middle is from the middle of the photo.
  double get offCentre {
    final across = (left + right) / 2 - 0.5;
    final down = (top + bottom) / 2 - 0.5;
    return math.sqrt(across * across + down * down);
  }

  /// Where a label prints its name: the lines in its largest letters (at
  /// least half as tall as its tallest), then those with the next largest
  /// added, for a label whose largest print is an emblem or was misread.
  List<List<ReadLine>> get nameTiers {
    List<ReadLine> atLeastHalf(double tallest) => lines
        .where((line) => 2 * line.height >= tallest)
        .toList(growable: false);
    final tallest = lines.map((line) => line.height).reduce(math.max);
    final first = atLeastHalf(tallest);
    final rest = lines.where((line) => !first.contains(line));
    if (rest.isEmpty) return <List<ReadLine>>[first];
    return <List<ReadLine>>[
      first,
      atLeastHalf(rest.map((line) => line.height).reduce(math.max)),
    ];
  }

  /// The label's lines, largest letters first: a label prints the name
  /// larger than anything else on it.
  List<ReadLine> get largestFirst =>
      lines.toList()..sort((a, b) => b.height.compareTo(a.height));
}

/// Two reads of the same place (a second scan in another language) are one
/// line: the surer read stays, and both stay when they are as sure as each
/// other and differ ("MONDAM", "MONDAVI"), since either may be the name.
List<ReadLine> withoutRepeats(List<ReadLine> lines) {
  final kept = <ReadLine>[];
  for (final line in lines) {
    if (line.text.trim().isEmpty || line.width <= 0 || line.height <= 0) {
      continue;
    }
    final rivals = kept.where((other) => _samePlace(other, line)).toList();
    if (rivals.any(
      (other) => other.confidence > line.confidence || other.text == line.text,
    )) {
      continue;
    }
    kept
      ..removeWhere(
        (other) => rivals.contains(other) && other.confidence < line.confidence,
      )
      ..add(line);
  }
  return kept;
}

bool _samePlace(ReadLine a, ReadLine b) {
  final across = math.min(a.right, b.right) - math.max(a.left, b.left);
  final down = math.min(a.bottom, b.bottom) - math.max(a.top, b.top);
  if (across <= 0 || down <= 0) return false;
  final smaller = math.min(a.width * a.height, b.width * b.height);
  return across * down > 0.5 * smaller;
}

/// A list needs this many lines starting at one left edge, that many of
/// them in letters of one size, running across the page; a label centres
/// its lines, prints each in a size of its own and is no wider than its
/// bottle.
const int _listAligned = 5;
const double _sameEdge = 0.03;
const double _sameSize = 1.3;
const double _listWidth = 0.25;

/// How far below a line the next line of its label can be, in heights of
/// the taller of the two: a label leaves room under its name.
const double _labelReach = 4;

/// Splits what was read into the labels and list entries of the photo, in
/// reading order.
///
/// Lines stacked closely over each other, or side by side on one row, are
/// one block. A block whose lines start at one left edge is a list, and
/// each of its lines is an entry; any other block is one label.
List<LabelGroup> groupLines(List<ReadLine> read) {
  final lines = withoutRepeats(read);
  final parent = List<int>.generate(lines.length, (i) => i);
  int root(int i) {
    while (parent[i] != i) {
      parent[i] = parent[parent[i]];
      i = parent[i];
    }
    return i;
  }

  for (var i = 0; i < lines.length; i++) {
    for (var j = i + 1; j < lines.length; j++) {
      if (_together(lines[i], lines[j])) parent[root(i)] = root(j);
    }
  }
  final byRoot = <int, List<ReadLine>>{};
  for (var i = 0; i < lines.length; i++) {
    byRoot.putIfAbsent(root(i), () => <ReadLine>[]).add(lines[i]);
  }
  final blocks = _joinedDownward(byRoot.values.toList());
  final groups = <LabelGroup>[];
  for (final block in blocks) {
    block.sort(_readingOrder);
    if (_isList(block)) {
      groups.addAll(
        block.map(
          (line) => LabelGroup(lines: <ReadLine>[line], listEntry: true),
        ),
      );
    } else {
      groups.add(LabelGroup(lines: block));
    }
  }
  if (_oneBottle(groups)) {
    return <LabelGroup>[
      LabelGroup(
        lines: <ReadLine>[for (final group in groups) ...group.lines]
          ..sort(_readingOrder),
      ),
    ];
  }
  return groups..sort((a, b) {
    final down = a.top.compareTo(b.top);
    return down != 0 ? down : a.left.compareTo(b.left);
  });
}

/// A bottle stands upright, so its neck band, label and back strip are
/// over one another: when every block lies within the width of the widest,
/// the photo shows one bottle and they are all its label.
bool _oneBottle(List<LabelGroup> groups) {
  if (groups.length < 2 || groups.any((group) => group.listEntry)) {
    return false;
  }
  final widest = groups.reduce(
    (a, b) => b.right - b.left > a.right - a.left ? b : a,
  );
  return groups.every((group) {
    final shared =
        math.min(group.right, widest.right) - math.max(group.left, widest.left);
    return shared >= 0.5 * (group.right - group.left);
  });
}

/// A label's small print can sit further under its name than two small
/// lines reach: a block right under another, within the reach of the
/// upper block's tallest line, is the same label.
List<List<ReadLine>> _joinedDownward(List<List<ReadLine>> blocks) {
  final joined = <List<ReadLine>>[...blocks];
  var changed = true;
  while (changed) {
    changed = false;
    for (var i = 0; i < joined.length && !changed; i++) {
      for (var j = 0; j < joined.length && !changed; j++) {
        if (i == j || !_under(joined[i], joined[j])) continue;
        joined[i].addAll(joined[j]);
        joined.removeAt(j);
        changed = true;
      }
    }
  }
  return joined;
}

bool _under(List<ReadLine> upper, List<ReadLine> lower) {
  double least(List<ReadLine> block, double Function(ReadLine) of) =>
      block.map(of).reduce(math.min);
  double most(List<ReadLine> block, double Function(ReadLine) of) =>
      block.map(of).reduce(math.max);
  final gap =
      least(lower, (line) => line.top) - most(upper, (line) => line.bottom);
  if (gap < 0 || gap > _labelReach * most(upper, (line) => line.height)) {
    return false;
  }
  final left = math.max(
    least(upper, (line) => line.left),
    least(lower, (line) => line.left),
  );
  final right = math.min(
    most(upper, (line) => line.right),
    most(lower, (line) => line.right),
  );
  final narrower = math.min(
    most(upper, (line) => line.right) - least(upper, (line) => line.left),
    most(lower, (line) => line.right) - least(lower, (line) => line.left),
  );
  return right - left >= 0.5 * narrower;
}

int _readingOrder(ReadLine a, ReadLine b) {
  final down = a.top.compareTo(b.top);
  return down != 0 ? down : a.left.compareTo(b.left);
}

/// Whether two lines are parts of one block: one over the other with their
/// widths overlapping and within [_labelReach] of each other, or side by
/// side on one row a letter or two apart.
bool _together(ReadLine a, ReadLine b) {
  final taller = math.max(a.height, b.height);
  final across = math.min(a.right, b.right) - math.max(a.left, b.left);
  final down = math.min(a.bottom, b.bottom) - math.max(a.top, b.top);
  if (across >= 0.3 * math.min(a.width, b.width)) {
    return -down <= _labelReach * taller;
  }
  if (down >= 0.5 * math.min(a.height, b.height)) {
    return -across <= 0.5 * taller;
  }
  return false;
}

bool _isList(List<ReadLine> block) {
  for (final line in block) {
    final sharing = block
        .where((other) => (other.left - line.left).abs() <= _sameEdge)
        .toList(growable: false);
    if (sharing.length < _listAligned || 2 * sharing.length < block.length) {
      continue;
    }
    final heights = sharing.map((other) => other.height).toList()..sort();
    var sameSize = 0;
    for (var from = 0, to = 0; to < heights.length; to++) {
      while (heights[to] > _sameSize * heights[from]) {
        from++;
      }
      sameSize = math.max(sameSize, to - from + 1);
    }
    if (sameSize < _listAligned) continue;
    final widths = sharing.map((other) => other.width).toList()..sort();
    if (widths[widths.length ~/ 2] < _listWidth) continue;
    double spread(double Function(ReadLine) of) =>
        sharing.map(of).reduce(math.max) - sharing.map(of).reduce(math.min);
    // Lines of different lengths from one edge end at different places;
    // centred lines share their middle instead.
    if (spread((other) => other.left + other.width / 2) >
        spread((other) => other.left)) {
      return true;
    }
  }
  return false;
}
