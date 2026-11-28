import 'package:flutter/material.dart';
import '../../../../design/app_tokens.dart';
import '../../../../widgets/app_icon.dart';
import '../../../../widgets/app_list_row.dart';

/// The rows of one part of the 내 정보 tab, on the page itself with no box
/// around them. A line parts one row from the next, from the icon's left
/// edge to the arrow's right, dark enough to be seen on the page.
class ProfileMenuList extends StatelessWidget {
  const ProfileMenuList({super.key, required this.items});

  final List<ProfileMenuItem> items;

  @override
  Widget build(BuildContext context) => Column(
    children: <Widget>[
      for (final (index, item) in items.indexed) ...<Widget>[
        if (index > 0)
          const ColoredBox(
            color: AppColors.borderStrong,
            child: SizedBox(height: 1, width: double.infinity),
          ),
        _ProfileMenuRow(item: item),
      ],
    ],
  );
}

class _ProfileMenuRow extends StatelessWidget {
  const _ProfileMenuRow({required this.item});

  final ProfileMenuItem item;

  static const _iconSize = 28.0;

  @override
  Widget build(BuildContext context) => AppListRow(
    key: item.key,
    title: item.title,
    // The row's own coloured tile, with nothing drawn behind it.
    leading: Image.asset(
      item.icon.asset,
      width: _iconSize,
      height: _iconSize,
      filterQuality: FilterQuality.medium,
      excludeFromSemantics: true,
    ),
    trailing: const AppIcon(
      AppIconAsset.next,
      size: AppSizes.iconMd,
      color: AppColors.textTertiary,
    ),
    onPressed: item.onPressed,
    density: AppListRowDensity.compact,
    inset: AppListRowInset.none,
    // The list draws the lines: a row's own is cut short by its corners.
    showDivider: false,
  );
}

class ProfileMenuItem {
  const ProfileMenuItem({
    required this.title,
    required this.onPressed,
    required this.icon,
    this.key,
  });

  final Key? key;

  final ProfileMenuIcon icon;
  final String title;
  final VoidCallback onPressed;
}

/// The coloured tile a row of 내 정보 leads with, one picture each.
enum ProfileMenuIcon {
  nickname,
  interests,
  savedDrinks('saved_drinks'),
  glossary,
  policy,
  notice,
  inquiry;

  const ProfileMenuIcon([this._file]);

  final String? _file;

  String get asset => 'assets/icons/profile/${_file ?? name}.webp';
}
