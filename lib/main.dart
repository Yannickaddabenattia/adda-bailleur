import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'core/storage/local_database.dart';
import 'services/linux_bootstrap.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarContrastEnforced: false,
  ));
  await LocalDatabase.init();
  // Auto-enregistre les associations `.adlb` / `.adlr` / `.adli` côté Linux.
  // Sans effet sur les autres OS (gérés par leur manifest natif).
  await LinuxBootstrap.ensureRegistered();
  runApp(const AddaLocationApp());
}
