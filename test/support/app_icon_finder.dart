import 'package:flutter_test/flutter_test.dart';
import 'package:soolgyul/src/widgets/app_icon.dart';

/// Finds the app's line icon drawn from [icon]'s file.
Finder findAppIcon(AppIconAsset icon) => find.byWidgetPredicate(
  (widget) => widget is AppIcon && widget.icon == icon,
  description: 'AppIcon(${icon.fileName})',
);
