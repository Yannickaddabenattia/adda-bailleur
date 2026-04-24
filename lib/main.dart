import 'package:flutter/material.dart';

import 'app.dart';
import 'core/storage/local_database.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LocalDatabase.init();
  runApp(const AddaLocationApp());
}
