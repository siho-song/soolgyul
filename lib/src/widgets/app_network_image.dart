import 'package:flutter/widgets.dart';

/// How the app turns an image address into an image. It starts as a plain
/// download, kept in memory for the session; on a phone `main` swaps in a
/// loader that also keeps the file on the device, so a photo downloads once
/// and later launches read it from disk. A browser keeps files by itself.
ImageProvider Function(String url) networkImageProvider = _download;

ImageProvider _download(String url) => NetworkImage(url);
