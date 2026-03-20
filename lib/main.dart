import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'app.dart';
import 'data/services/supabase_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('es', null); // needed for DateFormat locale "es"
  await SupabaseService.initialize(); // no-op if not compiled with credentials
  runApp(
    const ProviderScope(
      child: InertiaXApp(),
    ),
  );
}
