import 'package:flutter/widgets.dart';

import '../../navigation/app_router.dart';

/// What a flow coordinator may ask of the widget that hosts it.
///
/// Coordinators own flow state and gateway calls; the host owns the widget
/// lifecycle, the route stack and transient UI such as snack bars.
abstract interface class FlowHost {
  bool get mounted;

  BuildContext get context;

  AppRouter get router;

  /// Applies [update] inside `setState` so dependent screens rebuild.
  void refresh(VoidCallback update);

  void showFeedback(String message);

  /// The in-app back action, including sensory-flow and debug handling.
  void back();
}
