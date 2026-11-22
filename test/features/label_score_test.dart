import 'package:flutter_test/flutter_test.dart';
import 'package:soolgyul/src/features/catalog/data/catalog_drink.dart';
import 'package:soolgyul/src/features/taste_fit/data/label_score.dart';
import 'package:soolgyul/src/features/taste_fit/data/label_words.dart';

CatalogDrink _drink(
  String name,
  String nameEn, {
  DrinkLabelFacts? facts,
  double? abv,
}) => CatalogDrink(
  id: name,
  displayName: name,
  nameEn: nameEn,
  category: DrinkCategory.redWine,
  abvPercent: abv,
  labelFacts: facts,
);

const List<String> _colchagua = <String>['콜차구아 밸리', 'Colchagua Valley'];
const List<String> _casablanca = <String>['카사블랑카 밸리', 'Casablanca Valley'];
const List<String> _chile = <String>['칠레', 'Chile'];

List<String> _names(LabelRanking ranking) =>
    ranking.matches.map((drink) => drink.displayName).toList();

void main() {
  group('label words', () {
    test('a word few names hold weighs more than one many hold, and a kind '
        'word least', () {
      expect(labelWordWeight('glenfarclas'), 1);
      expect(labelWordWeight('black'), inExclusiveRange(0.5, 1));
      expect(labelWordWeight('sauvignon'), 0.5);
      expect(labelWordWeight('whisky'), 0.25);
    });

    test('a drink\'s own words are not its kind, its grape, its age, nor a '
        'word of its name that the most names hold', () {
      expect(isOwnWord('montes'), isTrue);
      expect(isOwnWord('black'), isTrue);
      expect(isOwnWord('1865'), isTrue);
      expect(isOwnWord('muller'), isTrue, reason: 'De Muller is a producer');
      for (final word in <String>['whisky', 'syrah', '쉬라즈', 'chablis', '12']) {
        expect(isNameWord(word), isFalse, reason: word);
        expect(isOwnWord(word), isFalse, reason: word);
      }
      for (final word in <String>['chateau', '샤또', 'domaine', 'reserva']) {
        expect(isNameWord(word), isTrue, reason: word);
        expect(isOwnWord(word), isFalse, reason: word);
      }
    });

    test('"Chateau" read alone names no drink', () {
      final ranking = rankLabelCandidates(
        <List<CatalogDrink>>[
          <CatalogDrink>[
            _drink('샤또 마고', 'Chateau Margaux'),
            _drink('샤또 팔머', 'Chateau Palmer'),
          ],
        ],
        labelLines: <String>['Chateau'],
      );

      expect(ranking.matches, isEmpty);
    });
  });

  group('rankLabelCandidates', () {
    final syrah = _drink(
      '몬테스 알파 시라',
      'Montes Alpha Syrah',
      facts: const DrinkLabelFacts(
        regions: <List<String>>[_colchagua, _chile],
        known: true,
        staple: true,
      ),
    );
    final m = _drink(
      '몬테스 알파 M 2021',
      'Montes Alpha M',
      facts: const DrinkLabelFacts(
        vintageYear: 2021,
        regions: <List<String>>[_colchagua, _chile],
        known: true,
      ),
    );
    final chardonnay = _drink(
      '몬테스 알파 샤르도네',
      'Montes Alpha Chardonnay',
      facts: const DrinkLabelFacts(
        regions: <List<String>>[_casablanca, _chile],
        known: true,
        staple: true,
      ),
    );
    final cabernet = _drink(
      '몬테스 알파 까베르네 소비뇽 2016',
      'Montes Alpha Cabernet Sauvignon 2016',
      facts: const DrinkLabelFacts(
        vintageYear: 2016,
        known: true,
        staple: true,
      ),
    );
    final cabernet2015 = _drink(
      '몬테스 알파 까베르네 소비뇽 2015',
      'Montes Alpha Cabernet Sauvignon 2015',
      facts: const DrinkLabelFacts(vintageYear: 2015),
    );
    final brand = <List<CatalogDrink>>[
      <CatalogDrink>[m, syrah, chardonnay, cabernet, cabernet2015],
    ];

    test('a brand read without the bottle is tied, a producer\'s everyday '
        'bottles before the others, each drink once', () {
      final ranking = rankLabelCandidates(
        brand,
        labelLines: <String>['MONTES ALPHA'],
      );

      expect(ranking.tied, isTrue);
      expect(ranking.sure, isFalse);
      expect(_names(ranking).last, m.displayName);
      expect(_names(ranking), hasLength(4), reason: 'two years are one drink');
    });

    test('the place a label names puts the bottles from there first, and a '
        'bottle whose place is not on record between them and the rest', () {
      final ranking = rankLabelCandidates(
        brand,
        labelLines: <String>['MONTES ALPHA', 'D.O. VALLE DE COLCHAGUA'],
      );

      expect(_names(ranking), <String>[
        syrah.displayName,
        m.displayName,
        cabernet.displayName,
        chardonnay.displayName,
      ]);
      expect(ranking.tied, isTrue);
      final scores = <String, LabelScore>{
        for (final score in ranking.scores) score.drink.displayName: score,
      };
      double place(CatalogDrink drink) => scores[drink.displayName]!.items
          .where((item) => item.name == 'place')
          .fold(0, (sum, item) => sum + item.value);
      expect(place(syrah), greaterThan(0));
      expect(place(cabernet), 0.5 * place(syrah));
      expect(place(chardonnay), 0);
    });

    test('the bottle read is that bottle, and its year on the label comes '
        'first of its years', () {
      final ranking = rankLabelCandidates(
        brand,
        labelLines: <String>['MONTES ALPHA', 'CABERNET SAUVIGNON', '2015'],
      );

      expect(ranking.sure, isTrue);
      expect(ranking.tied, isFalse);
      expect(_names(ranking).take(2), <String>[
        cabernet2015.displayName,
        cabernet.displayName,
      ]);
    });

    test('a word the bottle\'s place accounts for counts as one in its '
        'name', () {
      // The catalog's English name of the Pinot Noir leaves Monterey out.
      final pinot = _drink(
        '카멜 로드 몬테레이 피노 누아',
        'Carmel Road Pinot Noir',
        facts: const DrinkLabelFacts(
          regions: <List<String>>[
            <String>['몬터레이', 'Monterey'],
          ],
        ),
      );
      final chardonnay = _drink(
        '카멜 로드 몬테레이 샤르도네',
        'Carmel Road Monterey Chardonnay',
      );
      final ranking = rankLabelCandidates(
        <List<CatalogDrink>>[
          <CatalogDrink>[chardonnay, pinot],
        ],
        labelLines: <String>['CARMEL ROAD', 'MONTEREY'],
      );

      expect(ranking.tied, isTrue, reason: 'the grape was not read');
      expect(ranking.sure, isFalse);
    });

    test('the bottle\'s own place says more than a place it lies in', () {
      const california = <String>['캘리포니아', 'California'];
      final cabernet = _drink(
        '한 까베르네 소비뇽',
        'Hahn Cabernet Sauvignon',
        facts: const DrinkLabelFacts(regions: <List<String>>[california]),
      );
      final merlot = _drink(
        '한 메를로',
        'Hahn Merlot',
        facts: const DrinkLabelFacts(
          regions: <List<String>>[
            <String>['센트럴 코스트', 'Central Coast'],
            california,
          ],
        ),
      );
      final ranking = rankLabelCandidates(
        <List<CatalogDrink>>[
          <CatalogDrink>[merlot, cabernet],
        ],
        labelLines: <String>['HAHN', 'CALIFORNIA'],
      );

      expect(_names(ranking), <String>[
        cabernet.displayName,
        merlot.displayName,
      ]);
      expect(ranking.tied, isTrue);
    });

    test('the strength a label states says for the bottle of that '
        'strength', () {
      final light = _drink('머루팩', 'Meoru Pack', abv: 12);
      final strong = _drink('다래팩', 'Darae Pack', abv: 15);
      final ranking = rankLabelCandidates(
        <List<CatalogDrink>>[
          <CatalogDrink>[strong, light],
        ],
        labelLines: <String>['Pack', 'ALC 12%'],
      );

      expect(_names(ranking).first, light.displayName);
    });

    test('two names shown whole and as well are tied', () {
      final plain = _drink('도멘 로랑 부르고뉴', 'Laurent Bourgogne');
      final other = _drink('도멘 룰로 부르고뉴', 'Laurent Bourgogne');
      final ranking = rankLabelCandidates(
        <List<CatalogDrink>>[
          <CatalogDrink>[plain, other],
        ],
        labelLines: <String>['LAURENT', 'BOURGOGNE'],
      );

      expect(ranking.tied, isTrue);
      expect(ranking.sure, isFalse);
    });

    test('a result says why each drink stands where it does, and why a '
        'drink found is no candidate', () {
      final other = _drink(
        '산타 리타 120 까베르네 소비뇽',
        'Santa Rita 120 Cabernet Sauvignon',
      );
      final ranking = rankLabelCandidates(
        <List<CatalogDrink>>[
          <CatalogDrink>[syrah, other],
        ],
        labelLines: <String>['MONTES ALPHA', 'CABERNET SAUVIGNON'],
      );

      expect(
        ranking.scores.single.explain(),
        '1.46 몬테스 알파 시라 (Montes Alpha Syrah) | name +1.81 (montes alpha)'
        ' | unseen -0.60 (syrah) | known +0.10 | staple +0.15',
      );
      expect(ranking.passedOver, <String>[
        '산타 리타 120 까베르네 소비뇽: cabernet sauvignon 40%, no word of its own',
      ]);
    });

    test('the bottle\'s place read alone is not enough to list it without '
        'asking', () {
      const estephe = <String>['생떼스테프', 'Saint-Estephe'];
      final placed = _drink(
        '생떼스테프 루즈',
        'Saint-Estephe Rouge',
        facts: const DrinkLabelFacts(regions: <List<String>>[estephe]),
      );
      final unplaced = _drink('생떼스테프 루즈', 'Saint-Estephe Rouge');
      final lines = <String>['SAINT-ESTEPHE', 'ROUGE'];

      expect(
        rankLabelCandidates(<List<CatalogDrink>>[
          <CatalogDrink>[placed],
        ], labelLines: lines).sure,
        isFalse,
      );
      expect(
        rankLabelCandidates(<List<CatalogDrink>>[
          <CatalogDrink>[unplaced],
        ], labelLines: lines).sure,
        isTrue,
      );
    });

    test('the "since" of a house\'s year names no drink', () {
      expect(isNameWord('since'), isFalse);
      final ranking = rankLabelCandidates(
        <List<CatalogDrink>>[
          <CatalogDrink>[_drink('신스 1974', 'Since 1974')],
        ],
        labelLines: <String>['SINCE 1892'],
      );

      expect(ranking.matches, isEmpty);
    });

    test('a name the bottle goes by in its own script names it, run '
        'together on the label, and its producer\'s name still counts', () {
      const masumi = <String>['마스미', 'Masumi', '真澄'];
      final ginsen = _drink(
        '마스미 긴센',
        'Masumi Ginsen',
        facts: const DrinkLabelFacts(
          names: <String>['真澄 銀撰'],
          producer: masumi,
        ),
      );
      final kuro = _drink(
        '마스미 쿠로',
        'Masumi Kuro',
        facts: const DrinkLabelFacts(producer: masumi),
      );
      final ranking = rankLabelCandidates(
        <List<CatalogDrink>>[
          <CatalogDrink>[kuro, ginsen],
        ],
        labelLines: <String>['銀撰真澄'],
      );

      expect(_names(ranking).first, '마스미 긴센');
      expect(ranking.sure, isTrue);
      expect(isNameWord('特撰'), isFalse, reason: 'a grade, on many bottles');
    });

    test('a grape the label shows that the bottle lacks counts against it', () {
      final merlot = _drink(
        '도멘 피에르',
        'Domaine Pierre',
        facts: const DrinkLabelFacts(grapes: <String>['merlot']),
      );
      final chardonnay = _drink(
        '도멘 피에르 화이트',
        'Domaine Pierre White',
        facts: const DrinkLabelFacts(grapes: <String>['chardonnay']),
      );
      final ranking = rankLabelCandidates(
        <List<CatalogDrink>>[
          <CatalogDrink>[merlot, chardonnay],
        ],
        labelLines: <String>['DOMAINE PIERRE', 'CHARDONNAY'],
      );

      final against = ranking.scores
          .singleWhere((score) => score.drink == merlot)
          .items
          .where((item) => item.name == 'grape');
      expect(against.single.value, lessThan(0));
      expect(ranking.matches.first, chardonnay);
    });
  });
}
