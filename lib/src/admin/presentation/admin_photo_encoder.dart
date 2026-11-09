import 'admin_dropped_file.dart';
import 'admin_photo_encoder_stub.dart'
    if (dart.library.js_interop) 'admin_photo_encoder_web.dart'
    as platform;

/// Post photos go up as JPEG at this quality, no larger than the app's
/// 3:4 page (1080×1440). A 2MB PNG becomes ~100KB with no visible loss, so
/// a post with six photos opens in a moment instead of pulling 12MB.
const uploadPhotoMaxWidth = 1080;
const uploadPhotoMaxHeight = 1440;
const uploadPhotoJpegQuality = 0.8;

/// Re-encodes a picked photo for upload. On the web this draws the photo on
/// a canvas, fitting it inside [uploadPhotoMaxWidth]×[uploadPhotoMaxHeight],
/// and exports JPEG; elsewhere (tests) the file passes through unchanged. A
/// photo the browser cannot decode also passes through, so the upload still
/// happens and the server's type check has the last word.
Future<AdminDroppedFile> encodePhotoForUpload(AdminDroppedFile file) =>
    platform.encodePhotoForUpload(file);

/// The upload name of an encoded photo: the original name with `.jpg`.
String jpegFileName(String original) =>
    '${original.replaceFirst(RegExp(r'\.[^.]*$'), '')}.jpg';
