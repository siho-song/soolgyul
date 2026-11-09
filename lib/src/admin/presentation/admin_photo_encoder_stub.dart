import 'admin_dropped_file.dart';

/// Without a browser canvas the photo is uploaded as it was picked.
Future<AdminDroppedFile> encodePhotoForUpload(AdminDroppedFile file) async =>
    file;
