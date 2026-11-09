import 'package:image_picker/image_picker.dart';

/// Hands over the label photo; tests and probes inject one in place of the
/// camera screen.
typedef LabelPhotoPicker = Future<XFile?> Function();
