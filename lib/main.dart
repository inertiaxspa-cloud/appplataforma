import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';
import 'data/services/supabase_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SupabaseService.initialize(); // no-op if not compiled with credentials
  runApp(
    const ProviderScope(
      child: InertiaXApp(),
    ),
  );
}
