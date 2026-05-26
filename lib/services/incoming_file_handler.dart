import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../screens/share/incoming_file_screen.dart';

/// Reçoit les fichiers `.adls` / `.adlb` ouverts depuis l'extérieur
/// (AirDrop, Fichiers, Partage Android…) via un MethodChannel natif.
///
/// Cycle :
/// 1. [start] met en place le MethodChannel et récupère un fichier qui
///    aurait lancé l'app à froid. Les chemins sont mis en file d'attente.
/// 2. Tant que [markReady] n'a pas été appelé, les chemins ne sont pas
///    poussés (évite de s'afficher sous le splash).
/// 3. [markReady] est appelé après que le splash ait effectué son
///    `pushReplacement(Home/RoleSelection)` — on vide alors la file.
class IncomingFileHandler {
  IncomingFileHandler._();
  static final instance = IncomingFileHandler._();

  static const _channel = MethodChannel('adda_location/incoming_file');

  GlobalKey<NavigatorState>? _navKey;
  bool _started = false;
  bool _ready = false;
  final List<String> _pending = [];

  Future<void> start(GlobalKey<NavigatorState> navKey) async {
    if (_started) return;
    if (!_isSupported) return;
    _started = true;
    _navKey = navKey;

    // Sur Linux (et Windows à terme), le fichier passé au lanceur via le
    // gestionnaire de fichiers arrive en argument du processus. On le lit
    // directement plutôt que via un MethodChannel natif (qui n'existe pas).
    if (Platform.isLinux || Platform.isWindows) {
      for (final arg in Platform.executableArguments) {
        if (arg.isNotEmpty && !arg.startsWith('-')) {
          _enqueue(arg);
        }
      }
      return;
    }

    _channel.setMethodCallHandler(_onMethodCall);

    try {
      final pending = await _channel.invokeMethod<String>('consumePending');
      if (pending != null && pending.isNotEmpty) {
        _enqueue(pending);
      }
    } catch (e, s) {
      debugPrint('IncomingFileHandler consumePending error: $e\n$s');
    }
  }

  /// Appelé par le splash après la bascule vers Home/RoleSelection.
  void markReady() {
    _ready = true;
    _flush();
  }

  Future<dynamic> _onMethodCall(MethodCall call) async {
    if (call.method == 'fileOpened') {
      final args = call.arguments;
      if (args is Map) {
        final path = args['path'] as String?;
        if (path != null && path.isNotEmpty) {
          _enqueue(path);
        }
      }
    }
  }

  bool get _isSupported =>
      Platform.isIOS ||
      Platform.isAndroid ||
      Platform.isMacOS ||
      Platform.isLinux ||
      Platform.isWindows;

  void _enqueue(String path) {
    final lower = path.toLowerCase();
    if (!(lower.endsWith('.adlr') ||
        lower.endsWith('.adlb') ||
        lower.endsWith('.zip') ||
        lower.endsWith('.bin'))) {
      debugPrint('IncomingFileHandler ignored non-adl file: $path');
      return;
    }
    debugPrint('IncomingFileHandler queued $path (ready=$_ready)');
    _pending.add(path);
    if (_ready) _flush();
  }

  void _flush() {
    final nav = _navKey?.currentState;
    if (nav == null) {
      debugPrint('IncomingFileHandler flush skipped — navigator not ready');
      return;
    }
    while (_pending.isNotEmpty) {
      final path = _pending.removeAt(0);
      nav.push(
        MaterialPageRoute(
          builder: (_) => IncomingFileScreen(filePath: path),
        ),
      );
    }
  }
}
