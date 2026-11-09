import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

web.HTMLElement? _safeAreaProbe;

// Flutter writes its own viewport tag without viewport-fit=cover, so the
// browser reports no notch or home indicator until the page asks for them.
void enableBrowserSafeArea() {
  final viewport = web.document.querySelector('meta[name="viewport"]');
  if (viewport == null) return;
  final content = viewport.getAttribute('content') ?? '';
  if (content.contains('viewport-fit')) return;
  viewport.setAttribute('content', '$content, viewport-fit=cover');
}

// The browser exposes the insets only to CSS, so a hidden element padded by
// env(safe-area-inset-*) carries them back as computed pixels.
EdgeInsets readBrowserSafeArea() {
  final probe = _safeAreaProbe ??= _createSafeAreaProbe();
  final style = web.window.getComputedStyle(probe);
  double inset(String side) =>
      double.tryParse(
        style.getPropertyValue('padding-$side').replaceAll('px', ''),
      ) ??
      0;
  return EdgeInsets.fromLTRB(
    inset('left'),
    inset('top'),
    inset('right'),
    inset('bottom'),
  );
}

web.HTMLElement _createSafeAreaProbe() {
  final probe = web.document.createElement('div') as web.HTMLElement;
  probe.style.cssText =
      'position: fixed; visibility: hidden; pointer-events: none; '
      'padding: env(safe-area-inset-top) env(safe-area-inset-right) '
      'env(safe-area-inset-bottom) env(safe-area-inset-left);';
  web.document.body!.append(probe);
  return probe;
}
