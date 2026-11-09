import 'package:flutter_test/flutter_test.dart';
import 'package:soolgyul/src/admin/presentation/admin_dropped_file.dart';
import 'package:soolgyul/src/admin/presentation/admin_photo_encoder.dart';

void main() {
  test('an encoded photo is named after the original with .jpg', () {
    expect(
      jpegFileName('KakaoTalk_Photo_2026-11-07 001.png'),
      'KakaoTalk_Photo_2026-11-07 001.jpg',
    );
    expect(jpegFileName('glass.jpeg'), 'glass.jpg');
    expect(jpegFileName('noext'), 'noext.jpg');
  });

  test('off the web the photo passes through untouched', () async {
    const file = AdminDroppedFile(name: 'a.png', bytes: <int>[1, 2, 3]);
    expect(identical(await encodePhotoForUpload(file), file), isTrue);
  });
}
