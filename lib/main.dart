import 'package:flutter/material.dart';

import 'app.dart';
import 'config/supabase_config.dart';

export 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SupabaseConfig.initializeSupabaseIfConfigured();
  runApp(const NoukinApp());
}
