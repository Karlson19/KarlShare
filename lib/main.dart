import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app.dart';
import 'providers/storage_provider.dart';
import 'providers/theme_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // SharedPreferences — small flags (theme, profile, first-run).
  final prefs = await SharedPreferences.getInstance();

  // Hive — persisted transfer history.
  await Hive.initFlutter();
  final transfersBox =
      await Hive.openBox<Map<dynamic, dynamic>>(HiveBoxes.transfers);

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        transfersBoxProvider.overrideWithValue(transfersBox),
      ],
      child: const KarlshareApp(),
    ),
  );
}
