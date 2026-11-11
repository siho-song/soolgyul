import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'src/admin/admin_app.dart';
import 'src/admin/data/supabase_admin_editorial_gateway.dart';
import 'src/app/app_start.dart';
import 'src/config/app_config.dart';
import 'src/core/errors/error_report.dart';
import 'src/core/supabase/time_limited_client.dart';

Future<void> main() => runWithErrorReporting(
  dsn: AppConfig.sentryDsn,
  environment: AppConfig.environment,
  // The bindings start where the app runs; see `lib/main.dart`.
  start: () {
    WidgetsFlutterBinding.ensureInitialized();
    if (kReleaseMode) ErrorWidget.builder = brokenView;
    runApp(const AppStart(start: _startAdmin));
  },
);

Future<Widget> _startAdmin() async {
  AppConfig.validateSupabase();

  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    publishableKey: AppConfig.supabasePublishableKey,
    httpClient: TimeLimitedClient(),
    authOptions: const FlutterAuthClientOptions(
      authFlowType: AuthFlowType.pkce,
    ),
  );

  return AdminApp(
    gateway: SupabaseAdminEditorialGateway(Supabase.instance.client),
  );
}
