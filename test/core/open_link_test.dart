import 'package:flutter_test/flutter_test.dart';
import 'package:soolgyul/src/core/open_link.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('what is not an address, or cannot be opened here, is answered '
      'with false instead of thrown', () async {
    expect(await openLink('인스타그램 @soolgyul'), isFalse);
    expect(await openLink(''), isFalse);
    expect(await openLink('http://[broken'), isFalse);
    // No platform is there to open it in a test: the failure is caught.
    expect(await openLink('https://www.instagram.com/soolgyul'), isFalse);
  });
}
