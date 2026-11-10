import 'package:flutter_test/flutter_test.dart';
import 'package:soolgyul/src/features/editorial/data/editorial_article.dart';
import 'package:soolgyul/src/features/editorial/data/editorial_article_link.dart';
import 'package:soolgyul/src/features/editorial/editorial_share.dart';

EditorialArticle _article(String body) => EditorialArticle(
  id: 'a',
  body: body,
  publishedAt: DateTime.utc(2026, 11, 10),
  mediaAssets: const [],
  interestKeys: const [],
);

void main() {
  test(
    'a post link carries the id and reads back with or without the slash',
    () {
      final link = EditorialArticleLink.build('https://soolgyul.com', 'p1');
      expect(link.toString(), 'https://soolgyul.com/article?id=p1');
      expect(EditorialArticleLink.parse(link), 'p1');
      expect(
        EditorialArticleLink.parse(
          Uri.parse('https://soolgyul.com/article/?id=p1'),
        ),
        'p1',
      );
      expect(
        EditorialArticleLink.parse(
          Uri.parse('https://soolgyul.com/claim?id=p1'),
        ),
        isNull,
      );
      expect(
        EditorialArticleLink.parse(Uri.parse('https://soolgyul.com/article')),
        isNull,
      );
    },
  );

  test('a shared post is its first line and the app link of the post', () {
    expect(
      editorialShareText(_article('\n  가을에 어울리는 막걸리  \n둘째 줄')),
      '가을에 어울리는 막걸리\n\n술결 앱에서 보기 https://soolgyul.com/article?id=a',
    );
  });

  test('a post without text shares the link alone', () {
    expect(
      editorialShareText(_article('  \n')),
      '술결 앱에서 보기 https://soolgyul.com/article?id=a',
    );
  });
}
