import 'dart:async';
import 'dart:js_interop';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'admin_dropped_file.dart';
import 'admin_photo_encoder.dart';

/// Decodes the photo with the browser (which also applies its EXIF
/// rotation), scales it down to fit the page size if it is larger, and
/// exports JPEG. Transparent areas end up white, as JPEG has no alpha.
Future<AdminDroppedFile> encodePhotoForUpload(AdminDroppedFile file) async {
  try {
    final bytes = Uint8List.fromList(file.bytes);
    final source = web.Blob(<web.BlobPart>[bytes.toJS].toJS);
    final bitmap = await web.window.createImageBitmap(source).toDart;
    final scale = math.min(
      1.0,
      math.min(
        uploadPhotoMaxWidth / bitmap.width,
        uploadPhotoMaxHeight / bitmap.height,
      ),
    );
    final width = math.max(1, (bitmap.width * scale).round());
    final height = math.max(1, (bitmap.height * scale).round());

    final canvas = web.HTMLCanvasElement()
      ..width = width
      ..height = height;
    final context = canvas.getContext('2d') as web.CanvasRenderingContext2D;
    context.fillStyle = '#ffffff'.toJS;
    context.fillRect(0, 0, width, height);
    context.drawImage(bitmap, 0, 0, width, height);
    bitmap.close();

    final encoded = Completer<web.Blob?>();
    canvas.toBlob(
      ((web.Blob? blob) => encoded.complete(blob)).toJS,
      'image/jpeg',
      uploadPhotoJpegQuality.toJS,
    );
    final jpeg = await encoded.future;
    if (jpeg == null) return file;
    final buffer = await jpeg.arrayBuffer().toDart;
    return AdminDroppedFile(
      name: jpegFileName(file.name),
      bytes: buffer.toDart.asUint8List(),
    );
  } catch (_) {
    return file;
  }
}
