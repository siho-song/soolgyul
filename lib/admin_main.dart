import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'src/admin/admin_app.dart';
import 'src/admin/data/supabase_admin_editorial_gateway.dart';
import 'src/config/app_config.dart';
import 'src/core/supabase/time_limited_client.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AppConfig.validateSupabase();

  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    publishableKey: AppConfig.supabasePublishableKey,
    httpClient: TimeLimitedClient(),
    authOptions: const FlutterAuthClientOptions(
      authFlowType: AuthFlowType.pkce,
    ),
  );

  runApp(
    AdminApp(gateway: SupabaseAdminEditorialGateway(Supabase.instance.client)),
  );
}
