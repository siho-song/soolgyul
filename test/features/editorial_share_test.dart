import 'package:flutter_test/flutter_test.dart';
import 'package:soolgyul/src/features/editorial/data/editorial_article.dart';
import 'package:soolgyul/src/features/editorial/editorial_share.dart';

EditorialArticle _article(String body) => EditorialArticle(
  id: 'a',
  body: body,
  publishedAt: DateTime.utc(2026, 11, 10),
  mediaAssets: const [],
  interestKeys: const [],
);

void main() {
  test('a shared post is its first line and the 술결 link', () {
    expect(
      editorialShareText(_article('\n  가을에 어울리는 막걸리  \n둘째 줄')),
      '가을에 어울리는 막걸리\n\n술결에서 보기 https://soolgyul.com',
    );
  });

  test('a post without text shares the link alone', () {
    expect(
      editorialShareText(_article('  \n')),
      '술결에서 보기 https://soolgyul.com',
    );
  });
}
