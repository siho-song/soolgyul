import 'dart:async';
import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

import 'admin_dropped_file.dart';

/// Listens on the page for files dragged in from the desktop.
class FileDropSubscription {
  FileDropSubscription._(this._subscriptions);

  final List<StreamSubscription<web.MouseEvent>> _subscriptions;

  void cancel() {
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
  }
}

FileDropSubscription? listenForFiles({
  required ValueChanged<bool> onHover,
  required ValueChanged<List<AdminDroppedFile>> onFiles,
}) {
  final target = web.document.documentElement;
  if (target == null) return null;
  // Enter and leave fire for every element the drag crosses; the depth
  // tells when the pointer has really left the page.
  var depth = 0;
  return FileDropSubscription._(<StreamSubscription<web.MouseEvent>>[
    target.onDragEnter.listen((event) {
      event.preventDefault();
      depth += 1;
      onHover(true);
    }),
    target.onDragOver.listen((event) => event.preventDefault()),
    target.onDragLeave.listen((event) {
      depth -= 1;
      if (depth <= 0) {
        depth = 0;
        onHover(false);
      }
    }),
    target.onDrop.listen((event) {
      event.preventDefault();
      depth = 0;
      onHover(false);
      unawaited(_readFiles(event as web.DragEvent).then(onFiles));
    }),
  ]);
}

Future<List<AdminDroppedFile>> _readFiles(web.DragEvent event) async {
  final list = event.dataTransfer?.files;
  if (list == null) return const <AdminDroppedFile>[];
  final files = <AdminDroppedFile>[];
  for (var index = 0; index < list.length; index++) {
    final file = list.item(index);
    if (file == null) continue;
    final buffer = await file.arrayBuffer().toDart;
    files.add(
      AdminDroppedFile(name: file.name, bytes: buffer.toDart.asUint8List()),
    );
  }
  return files;
}
