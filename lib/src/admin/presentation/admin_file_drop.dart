import 'package:flutter/material.dart';

import '../../design/app_tokens.dart';
import '../../design/app_typography.dart';
import 'admin_dropped_file.dart';
import 'admin_file_drop_stub.dart'
    if (dart.library.js_interop) 'admin_file_drop_web.dart'
    as platform;

export 'admin_dropped_file.dart';

/// On the web, files dropped anywhere on the page while this widget is on
/// screen reach [onFiles], and a veil over [child] says so while dragging.
/// Elsewhere it is just [child].
class AdminFileDrop extends StatefulWidget {
  const AdminFileDrop({
    required this.child,
    required this.onFiles,
    this.enabled = true,
    super.key,
  });

  final Widget child;
  final ValueChanged<List<AdminDroppedFile>> onFiles;
  final bool enabled;

  @override
  State<AdminFileDrop> createState() => _AdminFileDropState();
}

class _AdminFileDropState extends State<AdminFileDrop> {
  platform.FileDropSubscription? _subscription;
  bool _hovering = false;

  @override
  void initState() {
    super.initState();
    _subscription = platform.listenForFiles(
      onHover: (hovering) {
        if (mounted && hovering != _hovering) {
          setState(() => _hovering = hovering);
        }
      },
      onFiles: (files) {
        if (widget.enabled && files.isNotEmpty) widget.onFiles(files);
      },
    );
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    children: <Widget>[
      widget.child,
      if (_hovering && widget.enabled)
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.actionPrimary.withValues(alpha: .08),
                borderRadius: BorderRadius.circular(AppRadii.card),
                border: Border.all(color: AppColors.actionPrimary, width: 2),
              ),
              child: Center(
                child: Text(
                  '여기에 놓으면 사진이 올라가요',
                  style: AppTextStyles.sectionTitleMd.copyWith(
                    color: AppColors.actionPrimary,
                  ),
                ),
              ),
            ),
          ),
        ),
    ],
  );
}
