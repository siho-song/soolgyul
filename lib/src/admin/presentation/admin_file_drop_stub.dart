import 'package:flutter/foundation.dart';

import 'admin_dropped_file.dart';

/// Desktop drag-and-drop exists only on the web; elsewhere nothing listens.
class FileDropSubscription {
  const FileDropSubscription();

  void cancel() {}
}

FileDropSubscription? listenForFiles({
  required ValueChanged<bool> onHover,
  required ValueChanged<List<AdminDroppedFile>> onFiles,
}) => null;
