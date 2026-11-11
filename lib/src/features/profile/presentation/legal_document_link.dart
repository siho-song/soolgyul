import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../widgets/app_snack_bar.dart';

enum LegalDocument { terms, privacy, notice, faq }

/// Separate from APP_WEB_URL: the app host and public legal host may differ.
Uri legalDocumentUri(LegalDocument document) {
  const origin = String.fromEnvironment(
    'LEGAL_WEB_ORIGIN',
    defaultValue: 'https://soolgyul.com',
  );
  final uri = Uri.parse(origin);
  if (uri.scheme != 'https' ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment ||
      (uri.path.isNotEmpty && uri.path != '/')) {
    throw StateError('LEGAL_WEB_ORIGIN must be an HTTPS origin.');
  }
  // The page then hides its link to the site's home: from the app, the way
  // back is the browser's close button.
  return uri
      .resolve('/${document.name}/')
      .replace(queryParameters: const {'from': 'app'});
}

Future<void> openLegalDocument(
  BuildContext context,
  LegalDocument document,
) async {
  try {
    // No preflight await: web browsers require opening inside the click gesture.
    final uri = legalDocumentUri(document);
    var opened = await launchUrl(
      uri,
      mode: kIsWeb ? LaunchMode.platformDefault : LaunchMode.inAppBrowserView,
      webOnlyWindowName: '_blank',
    );
    if (!opened && !kIsWeb) {
      opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
    if (!opened) throw StateError('legal_document_not_opened');
  } catch (_) {
    if (context.mounted) {
      showAppSnackBar(context, '페이지를 불러오지 못했어요. 네트워크 연결을 확인해 주세요.');
    }
  }
}
