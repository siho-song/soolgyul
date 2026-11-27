import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../design/app_tokens.dart';
import '../../../../design/app_typography.dart';
import '../../../../widgets/app_icon.dart';
import '../label_camera_screen.dart';

const String labelShotsDeleteLabel = '사진 지우기';
const String labelShotsBackLabel = '카메라로 돌아가기';

final TextStyle _backStyle = AppTextStyles.itemTitle.copyWith(
  color: Colors.white,
);

/// The photos taken and not read yet, one at a time: to look at them and
/// take out one that came out wrong before they are read. The ✕ on a small
/// photo takes it out without asking.
class LabelShotsReviewScreen extends StatefulWidget {
  const LabelShotsReviewScreen({
    required this.shots,
    required this.onDelete,
    required this.onClose,
    super.key,
  });

  /// Oldest first.
  final List<XFile> shots;
  final ValueChanged<XFile> onDelete;
  final VoidCallback onClose;

  @override
  State<LabelShotsReviewScreen> createState() => _LabelShotsReviewScreenState();
}

class _LabelShotsReviewScreenState extends State<LabelShotsReviewScreen> {
  /// Opens on the newest photo, the one on top of the camera's stack.
  late int _shown = widget.shots.length - 1;
  late final PageController _pages = PageController(initialPage: _shown);

  @override
  void didUpdateWidget(covariant LabelShotsReviewScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final last = widget.shots.length - 1;
    if (_shown > last) _shown = last < 0 ? 0 : last;
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _show(int index) {
    setState(() => _shown = index);
    if (_pages.hasClients && _pages.page?.round() != index) {
      _pages.jumpToPage(index);
    }
  }

  @override
  Widget build(BuildContext context) {
    final shots = widget.shots;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            SizedBox(
              height: 48,
              child: Row(
                children: <Widget>[
                  const SizedBox(width: AppSpacing.md),
                  // The way back says where it goes: the photos are read
                  // from the camera, not from here.
                  GestureDetector(
                    key: const ValueKey<String>('label-shots-back'),
                    behavior: HitTestBehavior.opaque,
                    onTap: widget.onClose,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        const AppIcon(
                          AppIconAsset.previous,
                          size: AppSizes.iconLg,
                          color: Colors.white,
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Text(labelShotsBackLabel, style: _backStyle),
                      ],
                    ),
                  ),
                  const Spacer(),
                  if (shots.isNotEmpty)
                    Text(
                      '${_shown + 1} / ${shots.length}',
                      style: AppTextStyles.itemTitle.copyWith(
                        color: Colors.white70,
                      ),
                    ),
                  const SizedBox(width: AppSpacing.lg),
                ],
              ),
            ),
            Expanded(
              child: PageView(
                controller: _pages,
                onPageChanged: (index) => setState(() => _shown = index),
                children: <Widget>[
                  for (final shot in shots)
                    LabelShotImage(
                      shot,
                      key: ValueKey<String>(shot.path),
                      fit: BoxFit.contain,
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  for (final (index, shot) in shots.indexed)
                    _Thumb(
                      key: ValueKey<String>(shot.path),
                      shot: shot,
                      shown: index == _shown,
                      onShow: () => _show(index),
                      onDelete: () => widget.onDelete(shot),
                      deleteKey: ValueKey<String>('label-shot-delete-$index'),
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
          ],
        ),
      ),
    );
  }
}

/// One photo small, with the ✕ at its corner that takes it out.
class _Thumb extends StatelessWidget {
  const _Thumb({
    required this.shot,
    required this.shown,
    required this.onShow,
    required this.onDelete,
    required this.deleteKey,
    super.key,
  });

  final XFile shot;
  final bool shown;
  final VoidCallback onShow;
  final VoidCallback onDelete;
  final Key deleteKey;

  static const double _x = 24;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s6),
      child: SizedBox(
        width: 66 + _x / 2,
        height: 88 + _x / 2,
        child: Stack(
          children: <Widget>[
            Positioned(
              left: 0,
              bottom: 0,
              child: GestureDetector(
                onTap: onShow,
                child: Container(
                  width: 66,
                  height: 88,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppRadii.sm),
                  ),
                  foregroundDecoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppRadii.sm),
                    border: Border.all(
                      color: shown ? Colors.white : Colors.white24,
                      width: 2,
                    ),
                  ),
                  child: LabelShotImage(shot),
                ),
              ),
            ),
            Positioned(
              right: 0,
              top: 0,
              child: GestureDetector(
                key: deleteKey,
                behavior: HitTestBehavior.opaque,
                onTap: onDelete,
                child: Container(
                  width: _x,
                  height: _x,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: const AppIcon(
                    AppIconAsset.close,
                    size: 16,
                    color: Colors.black,
                    semanticLabel: labelShotsDeleteLabel,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
