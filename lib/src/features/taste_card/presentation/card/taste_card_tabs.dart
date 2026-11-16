part of '../taste_card_screen.dart';

// 술결 카드 | 테이스팅 노트: the two index tabs, as of a paper folder, over
// a card that carries a note. A card without one has no tabs and is drawn
// as it always was.

enum _CardTab {
  card('술결 카드', 'taste-card-tab-card'),
  note('테이스팅 노트', 'taste-card-tab-note');

  const _CardTab(this.label, this.key);

  final String label;
  final String key;
}

/// The tabs of a paper folder, which stay put over the page while either
/// tab scrolls under them. They stand on a band of deeper paper; the chosen
/// one is the page's own sheet, so it and the page read as one, and the
/// other stands behind it in a muted tan.
class _CardTabBar extends StatelessWidget {
  const _CardTabBar({required this.selected, required this.onSelect});

  final _CardTab selected;
  final ValueChanged<_CardTab> onSelect;

  static const _height = 50.0;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: _height,
    child: CustomPaint(
      painter: _FolderTabsPainter(chosen: selected.index),
      child: Padding(
        padding: const EdgeInsets.only(
          left: _FolderTabsPainter.sideInset,
          right: _FolderTabsPainter.sideInset,
          top: _FolderTabsPainter.topInset,
        ),
        child: Row(
          children: <Widget>[
            for (final tab in _CardTab.values)
              Expanded(
                child: _CardTabLabel(
                  tab: tab,
                  selected: tab == selected,
                  onTap: () => onSelect(tab),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

/// A tab's name on its tab: the chosen one bold in the card's wine, the
/// other in grey ink. The whole tab takes the tap.
class _CardTabLabel extends StatelessWidget {
  const _CardTabLabel({
    required this.tab,
    required this.selected,
    required this.onTap,
  });

  final _CardTab tab;
  final bool selected;
  final VoidCallback onTap;

  static final _chosen = _TasteCardText.sectionLabel.copyWith(
    fontWeight: FontWeight.w700,
    color: _TasteCardColors.wine,
  );
  static final _other = _TasteCardText.sectionLabel.copyWith(
    fontWeight: FontWeight.w400,
    color: PaperInk.grey,
  );

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    child: GestureDetector(
      key: ValueKey<String>(tab.key),
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Center(
        child: Text(
          tab.label,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: selected ? _chosen : _other,
        ),
      ),
    ),
  );
}

/// The band and the two tabs. The band is painted around the chosen tab
/// and around the page's rounded top, so the screen's own paper shows
/// through both as one sheet with no line between them; the page's top
/// corners are painted just under the bar, over the edge of what scrolls
/// there.
class _FolderTabsPainter extends CustomPainter {
  const _FolderTabsPainter({required this.chosen});

  /// The index of the tab in front.
  final int chosen;

  /// How far a tab's side stands in from the page's side at its foot.
  static const sideInset = 22.0;

  /// The band left over the tabs.
  static const topInset = 8.0;

  /// The page's top corners where no tab stands, and a tab's own top ones.
  static const _corner = 14.0;

  /// How far a tab's foot curves out into the page's edge.
  static const _foot = 8.0;

  /// How much narrower a tab is at its top than at its foot, each side.
  static const _slant = 4.0;

  /// How far the tabs reach over each other where they meet.
  static const _overlap = 10.0;

  static const _band = TasteCardGuideColors.ticketLine;
  static final _behind = Color.lerp(_band, _TasteCardColors.canvas, 0.4)!;

  /// A folder tab from [left] to [right] at its foot, standing on [base]:
  /// rounded top corners, sides a little aslant, and feet that curve out
  /// into the page's edge.
  static Path _tab(double left, double right, double base) {
    Offset along(Offset from, Offset to, double length) =>
        from + (to - from) / (to - from).distance * length;
    final footLeft = Offset(left, base);
    final topLeft = Offset(left + _slant, topInset);
    final topRight = Offset(right - _slant, topInset);
    final footRight = Offset(right, base);
    final upLeft = along(footLeft, topLeft, _foot);
    final underLeft = along(topLeft, footLeft, _corner);
    final underRight = along(topRight, footRight, _corner);
    final upRight = along(footRight, topRight, _foot);
    return Path()
      ..moveTo(left - _foot, base)
      ..quadraticBezierTo(footLeft.dx, footLeft.dy, upLeft.dx, upLeft.dy)
      ..lineTo(underLeft.dx, underLeft.dy)
      ..quadraticBezierTo(
        topLeft.dx,
        topLeft.dy,
        topLeft.dx + _corner,
        topInset,
      )
      ..lineTo(topRight.dx - _corner, topInset)
      ..quadraticBezierTo(
        topRight.dx,
        topRight.dy,
        underRight.dx,
        underRight.dy,
      )
      ..lineTo(upRight.dx, upRight.dy)
      ..quadraticBezierTo(footRight.dx, footRight.dy, right + _foot, base)
      ..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final base = size.height;
    final middle = size.width / 2;
    final tabs = <Path>[
      _tab(sideInset, middle + _overlap / 2, base),
      _tab(middle - _overlap / 2, size.width - sideInset, base),
    ];
    final front = tabs[chosen];
    final back = tabs[1 - chosen];
    final page = Path()
      ..addRRect(
        RRect.fromLTRBAndCorners(
          0,
          base,
          size.width,
          base + _corner * 2,
          topLeft: const Radius.circular(_corner),
          topRight: const Radius.circular(_corner),
        ),
      );
    final over = Rect.fromLTRB(0, 0, size.width, base);
    final sheet = Path.combine(PathOperation.union, page, front);
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        // Down to the foot of the page's corners, just under the bar.
        Path()..addRect(Rect.fromLTRB(0, 0, size.width, base + _corner)),
        sheet,
      ),
      Paint()..color = _band,
    );
    // Over the band alone: a tab's shadow falls beside it and over it,
    // never along its foot or on the sheet in front.
    canvas
      ..save()
      ..clipPath(
        Path.combine(PathOperation.difference, Path()..addRect(over), front),
      );
    final shadow = Paint()
      ..color = _TasteCardColors.ink.withValues(alpha: 0.16)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    canvas
      ..drawPath(back, shadow)
      ..drawPath(back, Paint()..color = _behind)
      ..drawPath(front, shadow)
      ..restore();
  }

  @override
  bool shouldRepaint(_FolderTabsPainter oldDelegate) =>
      oldDelegate.chosen != chosen;
}

/// One tab's page. Both tabs stay alive so each keeps its place, and the
/// route's scroll controller, which a tap on the iOS status bar scrolls to
/// the top, goes to the tab on screen alone; the other holds one of its own
/// meanwhile.
class _TabPage extends StatefulWidget {
  const _TabPage({required this.active, required this.child});

  final bool active;
  final Widget child;

  @override
  State<_TabPage> createState() => _TabPageState();
}

class _TabPageState extends State<_TabPage> {
  final _idle = ScrollController();

  @override
  void dispose() {
    _idle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final route = PrimaryScrollController.maybeOf(context);
    return PrimaryScrollController(
      controller: widget.active && route != null ? route : _idle,
      child: widget.child,
    );
  }
}

/// The 술결 카드 tab while the card is written again from the answers
/// corrected on the note.
class _CardRewriting extends StatelessWidget {
  const _CardRewriting();

  @override
  Widget build(BuildContext context) => Padding(
    key: const ValueKey<String>('taste-card-rewriting'),
    padding: const EdgeInsets.symmetric(horizontal: 28),
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Padding(
            padding: EdgeInsets.only(bottom: 28),
            child: CircularProgressIndicator(color: _TasteCardColors.wine),
          ),
          KeptText(
            '수정한 내용으로\n술결 카드를 다시 쓰고 있어요',
            textAlign: TextAlign.center,
            style: _TasteCardText.headline,
          ),
          const SizedBox(height: AppSpacing.s14),
          KeptText(
            '고친 답에 맞춰 내용을 새로 정리하는 중이에요. 잠시만 기다려 주세요.',
            textAlign: TextAlign.center,
            style: _TasteCardText.body,
          ),
        ],
      ),
    ),
  );
}

/// Over the screen while leaving it waits for the card to be written
/// again: a small spinner, and nothing under it takes a tap.
class _LeaveHeld extends StatelessWidget {
  const _LeaveHeld();

  @override
  Widget build(BuildContext context) => const AbsorbPointer(
    key: ValueKey<String>('taste-card-leave-held'),
    child: Center(
      child: SizedBox.square(
        dimension: AppSizes.iconLg,
        child: CircularProgressIndicator(
          strokeWidth: 2.5,
          color: _TasteCardColors.wine,
        ),
      ),
    ),
  );
}

/// Asks, when leaving found the corrected answers could not be sent,
/// whether to try again (true) or to leave without them (false).
class _RewriteFailedDialog extends StatelessWidget {
  const _RewriteFailedDialog();

  @override
  Widget build(BuildContext context) => AppDialogBody(
    title: '고친 답을 반영하지 못했어요.',
    actions: <Widget>[
      AppButton(
        key: const ValueKey<String>('taste-card-rewrite-leave'),
        label: '나가기',
        variant: AppButtonVariant.neutral,
        size: AppButtonSize.popup,
        onPressed: () => Navigator.of(context).pop(false),
      ),
      AppButton(
        key: const ValueKey<String>('taste-card-rewrite-retry'),
        label: '다시 시도',
        size: AppButtonSize.popup,
        onPressed: () => Navigator.of(context).pop(true),
      ),
    ],
  );
}
