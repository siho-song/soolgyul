import 'package:flutter_test/flutter_test.dart';
import 'package:soolgyul/src/features/taste_fit/data/label_layout.dart';

ReadLine _line(
  String text,
  double left,
  double top, {
  double width = 0.3,
  double height = 0.02,
  double confidence = 1,
}) => ReadLine(
  text: text,
  left: left,
  top: top,
  width: width,
  height: height,
  confidence: confidence,
);

List<List<String>> _texts(List<LabelGroup> groups) => <List<String>>[
  for (final group in groups) group.lines.map((line) => line.text).toList(),
];

void main() {
  test('a neck sticker over a label is the same bottle, its name in the '
      'largest letters', () {
    final groups = groupLines(<ReadLine>[
      _line('JAMESSUCKLING.COM', 0.40, 0.10, width: 0.2, height: 0.012),
      _line('VIU MANENT', 0.30, 0.40, width: 0.4, height: 0.06),
      _line('SINGLE VINEYARD', 0.36, 0.50, width: 0.28, height: 0.02),
      _line('CABERNET SAUVIGNON', 0.34, 0.54, width: 0.32, height: 0.02),
    ]);

    expect(_texts(groups), <List<String>>[
      <String>[
        'JAMESSUCKLING.COM',
        'VIU MANENT',
        'SINGLE VINEYARD',
        'CABERNET SAUVIGNON',
      ],
    ]);
    final label = groups.single;
    expect(label.listEntry, isFalse);
    expect(label.nameTiers.first.map((line) => line.text), <String>[
      'VIU MANENT',
    ]);
    expect(label.nameTiers.last, hasLength(4));
    expect(label.largestFirst.first.text, 'VIU MANENT');
  });

  test('bottles side by side are groups of their own', () {
    final groups = groupLines(<ReadLine>[
      _line('four seasons', 0.05, 0.40, width: 0.35, height: 0.05),
      _line('Cabernet Sauvignon', 0.08, 0.48, width: 0.3),
      _line('Cono Sur', 0.60, 0.38, width: 0.35, height: 0.05),
      _line('BICICLETA', 0.62, 0.46, width: 0.3),
    ]);

    expect(_texts(groups), <List<String>>[
      <String>['Cono Sur', 'BICICLETA'],
      <String>['four seasons', 'Cabernet Sauvignon'],
    ]);
  });

  test('small print far under the name is still the same label', () {
    final groups = groupLines(<ReadLine>[
      _line('Cono Sur', 0.30, 0.18, width: 0.4, height: 0.06),
      _line('BICICLETA', 0.35, 0.26, width: 0.3),
      _line('CABERNET SAUVIGNON', 0.33, 0.48, width: 0.34),
    ]);

    expect(_texts(groups), <List<String>>[
      <String>['Cono Sur', 'BICICLETA', 'CABERNET SAUVIGNON'],
    ]);
  });

  test('lines starting at one edge in one size are a list, one entry '
      'a line', () {
    final groups = groupLines(<ReadLine>[
      _line('WINE LIST', 0.35, 0.10, height: 0.04),
      for (final (index, name) in <String>[
        '- 덕혼 디코이 까베르네 소비뇽',
        'Duckhorn Decoy Cabernet Sauvignon, 미국)',
        '- 서브미션 까베르네 소비뇽',
        'Submission Cabernet Sauvignon, 미국)',
        '- 오이스터 베이 쇼비뇽 블랑',
        'Oyster Bay Sauvignon Blanc, 뉴질랜드)',
      ].indexed)
        _line(
          name,
          index.isEven ? 0.21 : 0.23,
          0.20 + index * 0.03,
          width: 0.012 * name.length,
        ),
      _line('B 89.0', 0.72, 0.20, width: 0.06),
    ]);

    final entries = groups.where((group) => group.listEntry).toList();
    expect(entries, hasLength(7));
    expect(entries.every((entry) => entry.lines.length == 1), isTrue);
    // The price column is not part of the list of names.
    expect(
      groups.where((group) => !group.listEntry).single.lines.single.text,
      'B 89.0',
    );
  });

  test('centred lines that happen to share an edge are a label', () {
    final groups = groupLines(<ReadLine>[
      _line('ROBERT MONDAVI', 0.39, 0.53, width: 0.22, height: 0.036),
      _line('PRIVATE SELECTION', 0.41, 0.56, width: 0.19, height: 0.031),
      _line('BOURBON', 0.45, 0.61, width: 0.10),
      _line('BARREL-AGED', 0.44, 0.62, width: 0.13),
      _line('CABERNET SAUVIGNON', 0.41, 0.64, width: 0.20, height: 0.028),
      _line('CALIFORNIA 2021', 0.45, 0.67, width: 0.11),
    ]);

    expect(groups.single.listEntry, isFalse);
    expect(groups.single.lines, hasLength(6));
  });

  test('a label whose lines start at one edge in sizes of their own is a '
      'label', () {
    final groups = groupLines(<ReadLine>[
      _line('CAPILLA', 0.305, 0.38, width: 0.14, height: 0.035),
      _line('VIU MANENT.', 0.30, 0.61, width: 0.34, height: 0.055),
      _line('SINGLE VINEYARD', 0.33, 0.67, width: 0.24, height: 0.028),
      _line('CABERNET SAUVIGNON', 0.30, 0.75, width: 0.33, height: 0.04),
      _line('VALLE DE COLCHAGUA', 0.305, 0.80, width: 0.29, height: 0.05),
    ]);

    expect(groups.single.listEntry, isFalse);
    expect(groups.single.lines, hasLength(5));
  });

  test('two reads of one place that are as sure both stay', () {
    final lines = withoutRepeats(<ReadLine>[
      _line('ROBERT MONDAM', 0.3, 0.5),
      _line('ROBERT MONDAVI', 0.3, 0.5),
      _line('ROBERT MONDAVI', 0.3, 0.5),
    ]);

    expect(lines.map((line) => line.text), <String>[
      'ROBERT MONDAM',
      'ROBERT MONDAVI',
    ]);
  });

  test('a second read of the same place keeps the surer text', () {
    final lines = withoutRepeats(<ReadLine>[
      _line('EwMark', 0.3, 0.5, confidence: 0.3),
      _line('Mark', 0.31, 0.5, confidence: 1),
      _line('WHISKY', 0.3, 0.6),
      _line('  ', 0.3, 0.7),
    ]);

    expect(lines.map((line) => line.text), <String>['Mark', 'WHISKY']);
  });

  test('a channel line needs its text and box', () {
    final line = ReadLine.fromChannel(<Object?, Object?>{
      'text': 'HAHN',
      'left': 0.1,
      'top': 0.2,
      'width': 0.3,
      'height': 0.05,
      'confidence': 0.5,
    });
    expect(line?.text, 'HAHN');
    expect(line?.bottom, closeTo(0.25, 1e-9));
    expect(line?.confidence, 0.5);
    expect(ReadLine.fromChannel(<Object?, Object?>{'text': 'HAHN'}), isNull);
    expect(ReadLine.fromChannel('HAHN'), isNull);
  });
}
