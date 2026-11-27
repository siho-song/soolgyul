part of '../taste_card_screen.dart';

// 술결 카드 | 테이스팅 노트: the two tabs over a card that carries a note. A card without one has no tabs and is drawn
// as it always was.

enum _CardTab {
  card('술결 카드', 'taste-card-tab-card'),
  note('테이스팅 노트', 'taste-card-tab-note');

  const _CardTab(this.label, this.key);

  final String label;
  final String key;
}

/// A plain tab bar that stays put over the page while either tab scrolls
/// under it: the two names side by side at equal width on the page's own
/// background, the chosen one in the wine with a 2px line under it, the
/// other in grey, and a thin rule across the whole bar under both. While
/// the note is being written the bar is closed ([enabled] false): the names
/// are dimmed and take no tap, so the form is left by its own 완료 or back.
class _CardTabBar extends StatelessWidget {
  const _CardTabBar({
    required this.selected,
    required this.onSelect,
    this.enabled = true,
  });

  final _CardTab selected;
  final ValueChanged<_CardTab> onSelect;
  final bool enabled;

  static const _height = 48.0;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: AppColors.borderSubtle)),
    ),
    child: SizedBox(
      height: _height,
      child: Row(
        children: <Widget>[
          for (final tab in _CardTab.values)
            Expanded(
              child: _CardTabLabel(
                tab: tab,
                selected: tab == selected,
                onTap: enabled ? () => onSelect(tab) : null,
              ),
            ),
        ],
      ),
    ),
  );
}

/// A tab's name: the chosen one bold in the card's wine over a 2px wine
/// line, the other in grey. The whole half of the bar takes the tap.
/// Without [onTap] the name and its line are dimmed and nothing is taken.
class _CardTabLabel extends StatelessWidget {
  const _CardTabLabel({
    required this.tab,
    required this.selected,
    required this.onTap,
  });

  final _CardTab tab;
  final bool selected;
  final VoidCallback? onTap;

  static const _indicator = 2.0;

  static final _chosen = _TasteCardText.sectionLabel.copyWith(
    fontWeight: FontWeight.w700,
    color: _TasteCardColors.wineDeep,
  );
  static final _other = _TasteCardText.sectionLabel.copyWith(
    fontWeight: FontWeight.w400,
    color: PaperInk.grey,
  );

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    enabled: onTap != null,
    child: GestureDetector(
      key: ValueKey<String>(tab.key),
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        children: <Widget>[
          Expanded(
            child: Center(
              child: Text(
                tab.label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: onTap == null
                    ? (selected ? _chosen : _other).copyWith(
                        color: AppColors.controlInactive,
                      )
                    : selected
                    ? _chosen
                    : _other,
              ),
            ),
          ),
          SizedBox(
            height: _indicator,
            width: double.infinity,
            child: selected
                ? ColoredBox(
                    color: onTap == null
                        ? AppColors.controlInactive
                        : _TasteCardColors.wine,
                  )
                : null,
          ),
        ],
      ),
    ),
  );
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
  const _RewriteFailedDialog({this.error});

  /// What the write failed with: a connection failure is told as one.
  final Object? error;

  @override
  Widget build(BuildContext context) {
    final words = failureWords(error, title: '고친 답을 반영하지 못했어요.');
    return AppDialogBody(
      title: words.title,
      body: words.description,
      actions: _actions(context),
    );
  }

  List<Widget> _actions(BuildContext context) => <Widget>[
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
  ];
}
