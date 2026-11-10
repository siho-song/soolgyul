import 'package:url_launcher/url_launcher.dart';

import 'errors/error_report.dart';

/// Opens [address] outside the app. `false` when it is not an address or
/// nothing on the device could open it, so the caller can say so.
Future<bool> openLink(
  String address, {
  LaunchMode mode = LaunchMode.externalApplication,
  String? webOnlyWindowName,
}) async {
  final uri = Uri.tryParse(address.trim());
  if (uri == null || !uri.hasScheme) return false;
  try {
    return await launchUrl(
      uri,
      mode: mode,
      webOnlyWindowName: webOnlyWindowName,
    );
  } catch (error, stack) {
    reportError(error, stack, where: 'link');
    return false;
  }
}
