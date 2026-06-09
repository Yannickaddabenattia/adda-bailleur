import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

import '../core/storage/local_database.dart';
import 'backup_service.dart';

/// Statut courant de la sauvegarde automatique (consommé par le badge UI).
enum AutoBackupState {
  /// Non configurée (dossier ou passphrase manquants).
  disabled,

  /// À jour : dernière sauvegarde correspond à l'état actuel.
  upToDate,

  /// Modifications locales en attente (debounce ou réseau).
  dirty,

  /// Sauvegarde en cours d'écriture.
  inProgress,

  /// Dernière tentative a échoué (dossier perdu, écriture refusée…).
  error,
}

/// Résultat d'une exécution de [AutoBackupService.runIfNeeded].
class AutoBackupResult {
  final bool didBackup;
  final String? reason;
  final String? filePath;
  final String? errorMessage;

  const AutoBackupResult.skipped({this.reason})
      : didBackup = false,
        filePath = null,
        errorMessage = null;

  const AutoBackupResult.success(this.filePath)
      : didBackup = true,
        reason = null,
        errorMessage = null;

  const AutoBackupResult.error(this.errorMessage)
      : didBackup = false,
        reason = null,
        filePath = null;
}

/// Déclencheur d'une sauvegarde auto.
enum AutoBackupTrigger {
  manual,
  onResume,
  quittance,
  edl,
  bail,
  logement,
  locataire,
  fiscalite,
}

/// Service d'auto-sauvegarde vers un dossier choisi par l'utilisateur
/// (typiquement un dossier iCloud Drive / OneDrive / Drive / pCloud).
///
/// Stratégie :
/// - Le user pointe un dossier une fois (via `file_selector`).
/// - La passphrase est mémorisée dans le keychain (flutter_secure_storage).
/// - À chaque déclencheur métier (debounce 5 min), l'app calcule un hash
///   SHA-256 du payload sérialisé puis :
///   - Si identique au dernier hash → skip.
///   - Sinon → produit un `.adls` daté, l'écrit dans le dossier, met à jour
///     le manifest local, applique la rotation pyramidale.
/// - La synchronisation cloud est gérée par le client OS du fournisseur
///   (Dropbox/iCloud/OneDrive/pCloud) qui détecte le fichier nouveau.
///
/// Multi-device : un `deviceId` UUID est inclus dans chaque payload. Au
/// démarrage, si on détecte un fichier plus récent provenant d'un autre
/// device, on alerte l'utilisateur (sans rien écraser tant qu'il n'a pas
/// confirmé).
class AutoBackupService extends ChangeNotifier {
  static const String _kEnabled = 'auto_backup_enabled';
  static const String _kFolderPath = 'auto_backup_folder_path';
  static const String _kPassphraseStored = 'auto_backup_passphrase_stored';
  static const String _kLastAtIso = 'auto_backup_last_at_iso';
  static const String _kLastHash = 'auto_backup_last_hash';
  static const String _kLastDeviceId = 'auto_backup_last_device_id';
  static const String _kLastFilePath = 'auto_backup_last_file_path';
  static const String _kDeviceId = 'auto_backup_device_id';

  // Secure storage key (passphrase chiffrée par l'OS)
  static const String _ksPassphrase = 'auto_backup_passphrase';

  static const _secureStorage = FlutterSecureStorage();
  static const _debounce = Duration(minutes: 5);

  AutoBackupState _state = AutoBackupState.disabled;
  AutoBackupState get state => _state;

  String? _lastError;
  String? get lastError => _lastError;

  Timer? _debounceTimer;
  final List<StreamSubscription> _boxSubs = [];

  AutoBackupService() {
    _refreshState();
    _attachBoxWatchers();
  }

  /// S'abonne aux box Hive métier pour déclencher automatiquement
  /// une sauvegarde (debouncée) à chaque création / modification /
  /// suppression d'entité significative.
  void _attachBoxWatchers() {
    // Boxes à surveiller : tout ce qui constitue de la donnée utilisateur.
    final boxes = [
      LocalDatabase.logementsBox,
      LocalDatabase.locatairesBox,
      LocalDatabase.quittancesBox,
      LocalDatabase.etatDesLieuxBox,
      LocalDatabase.contratsBailBox,
      LocalDatabase.depensesBox,
      LocalDatabase.creditsImmobiliersBox,
      LocalDatabase.diagnosticsBox,
      LocalDatabase.avenantsBox,
      LocalDatabase.scisBox,
      LocalDatabase.revisionsLoyerBox,
      LocalDatabase.fiscalSettingsBox,
      LocalDatabase.bailTemplatesBox,
    ];
    for (final box in boxes) {
      final sub = box.watch().listen((event) {
        if (!isEnabled) return;
        // Marque dirty + déclenche un run avec debounce (5 min via Timer).
        _state = AutoBackupState.dirty;
        notifyListeners();
        // On utilise un trigger générique car on n'a pas l'info précise ici.
        runIfNeeded(trigger: AutoBackupTrigger.logement);
      });
      _boxSubs.add(sub);
    }
  }

  /// `true` si l'auto-backup est configurée (dossier + passphrase OK).
  bool get isEnabled =>
      (LocalDatabase.settingsBox.get(_kEnabled) ?? 'false') == 'true';

  /// Chemin du dossier de destination (ex: ~/iCloud Drive/ADDA Bailleur/).
  String? get folderPath => LocalDatabase.settingsBox.get(_kFolderPath);

  /// Date ISO du dernier backup réussi, null si jamais lancé.
  DateTime? get lastBackupAt {
    final iso = LocalDatabase.settingsBox.get(_kLastAtIso);
    if (iso == null) return null;
    return DateTime.tryParse(iso);
  }

  /// Chemin du dernier .adls écrit (informatif).
  String? get lastBackupFilePath =>
      LocalDatabase.settingsBox.get(_kLastFilePath);

  /// ID UUID de ce device (généré au premier appel, stable ensuite).
  Future<String> deviceId() async {
    final existing = LocalDatabase.settingsBox.get(_kDeviceId);
    if (existing != null && existing.isNotEmpty) return existing;
    final id = const Uuid().v4();
    await LocalDatabase.settingsBox.put(_kDeviceId, id);
    return id;
  }

  /// Configure (ou met à jour) la sauvegarde automatique.
  /// [folderPath] est le dossier cible local (idéalement dans iCloud
  /// Drive / OneDrive / etc.). [passphrase] est mémorisée dans le keychain.
  Future<void> configure({
    required String folderPath,
    required String passphrase,
  }) async {
    final dir = Directory(folderPath);
    if (!dir.existsSync()) {
      throw ArgumentError('Le dossier n\'existe pas : $folderPath');
    }
    await LocalDatabase.settingsBox.put(_kFolderPath, folderPath);
    await LocalDatabase.settingsBox.put(_kEnabled, 'true');
    await _secureStorage.write(key: _ksPassphrase, value: passphrase);
    await LocalDatabase.settingsBox.put(_kPassphraseStored, 'true');
    await deviceId(); // s'assure que le deviceId existe
    _refreshState();
    notifyListeners();
  }

  /// Désactive l'auto-backup et supprime la passphrase du keychain.
  /// N'efface PAS les fichiers .adls déjà écrits dans le cloud.
  Future<void> disable() async {
    await LocalDatabase.settingsBox.put(_kEnabled, 'false');
    await _secureStorage.delete(key: _ksPassphrase);
    await LocalDatabase.settingsBox.put(_kPassphraseStored, 'false');
    _state = AutoBackupState.disabled;
    _lastError = null;
    _debounceTimer?.cancel();
    notifyListeners();
  }

  /// Récupère la passphrase mémorisée (null si non configurée).
  Future<String?> _readPassphrase() async {
    return _secureStorage.read(key: _ksPassphrase);
  }

  /// Calcule le SHA-256 d'un payload sérialisé en JSON canonique.
  /// Sert à détecter si l'état a changé depuis la dernière sauvegarde.
  String _computeHash(Map<String, dynamic> payload) {
    // Sérialisation canonique : on retire les champs « bruit » qui changent
    // à chaque export (exportedAt, lastBackupAt côté méta) pour ne détecter
    // que les vrais changements de données.
    final copy = Map<String, dynamic>.from(payload)..remove('exportedAt');
    final json = jsonEncode(copy);
    return sha256.convert(utf8.encode(json)).toString();
  }

  /// Exécute une sauvegarde si nécessaire.
  /// - Si l'auto-backup est désactivée → skip.
  /// - Si trigger != manual et debounce en cours → skip.
  /// - Si le hash du payload est identique au dernier backup → skip.
  /// - Sinon → écrit un .adls daté, applique la rotation pyramidale.
  Future<AutoBackupResult> runIfNeeded({
    required AutoBackupTrigger trigger,
  }) async {
    if (!isEnabled) {
      return const AutoBackupResult.skipped(reason: 'Auto-backup désactivée');
    }
    final folder = folderPath;
    if (folder == null) {
      return const AutoBackupResult.skipped(reason: 'Dossier non configuré');
    }
    final passphrase = await _readPassphrase();
    if (passphrase == null || passphrase.isEmpty) {
      return const AutoBackupResult.skipped(reason: 'Passphrase manquante');
    }

    // Debounce : sauf trigger manuel ou onResume, on attend 5 min entre 2 backups.
    if (trigger != AutoBackupTrigger.manual &&
        trigger != AutoBackupTrigger.onResume) {
      _debounceTimer?.cancel();
      final completer = Completer<AutoBackupResult>();
      _debounceTimer = Timer(_debounce, () async {
        final r = await _doBackup(folder, passphrase);
        completer.complete(r);
      });
      _state = AutoBackupState.dirty;
      notifyListeners();
      return completer.future;
    }

    return _doBackup(folder, passphrase);
  }

  Future<AutoBackupResult> _doBackup(
      String folderPath, String passphrase) async {
    _state = AutoBackupState.inProgress;
    notifyListeners();
    try {
      final svc = BackupService();
      // Vérifier le dossier
      final dir = Directory(folderPath);
      if (!dir.existsSync()) {
        _state = AutoBackupState.error;
        _lastError = 'Dossier introuvable : $folderPath';
        notifyListeners();
        return AutoBackupResult.error(_lastError!);
      }

      // Détection de changement : calcule le hash du payload avant écriture.
      final payload = svc.debugBuildPayload();
      final newHash = _computeHash(payload);
      final lastHash = LocalDatabase.settingsBox.get(_kLastHash);
      if (lastHash == newHash) {
        _state = AutoBackupState.upToDate;
        notifyListeners();
        return const AutoBackupResult.skipped(reason: 'Aucun changement');
      }

      // Écrit le .adls daté dans le dossier cible.
      final now = DateTime.now();
      final stamp = '${now.year}'
          '-${now.month.toString().padLeft(2, '0')}'
          '-${now.day.toString().padLeft(2, '0')}'
          '_${now.hour.toString().padLeft(2, '0')}'
          '${now.minute.toString().padLeft(2, '0')}';
      final fileName = 'addalocation_$stamp.adls';
      final targetPath = '$folderPath${Platform.pathSeparator}$fileName';

      // Génère le bundle chiffré via BackupService (écrit dans Documents).
      final tempFile = await svc.exportEncrypted(passphrase: passphrase);
      // Déplace/copie vers le dossier cible (atomique : tmp + rename).
      final tmpTarget = File('$targetPath.tmp');
      await tempFile.copy(tmpTarget.path);
      await tmpTarget.rename(targetPath);
      // Supprime le fichier source temporaire (Documents) — il a été archivé.
      try {
        await tempFile.delete();
      } catch (_) {/* pas critique */}

      await LocalDatabase.settingsBox.put(_kLastAtIso, now.toIso8601String());
      await LocalDatabase.settingsBox.put(_kLastHash, newHash);
      await LocalDatabase.settingsBox
          .put(_kLastDeviceId, await deviceId());
      await LocalDatabase.settingsBox.put(_kLastFilePath, targetPath);

      // Rotation pyramidale (7j / 4 sem / 12 mois / ∞ ans).
      await _pruneOldBackups(folderPath);

      _state = AutoBackupState.upToDate;
      _lastError = null;
      notifyListeners();
      return AutoBackupResult.success(targetPath);
    } catch (e) {
      _state = AutoBackupState.error;
      _lastError = e.toString();
      notifyListeners();
      return AutoBackupResult.error(_lastError!);
    }
  }

  /// Rotation pyramidale : garde 7 quotidiens, 4 hebdo, 12 mensuels, 1/an.
  /// Supprime les fichiers .adls excédentaires.
  Future<void> _pruneOldBackups(String folderPath) async {
    final dir = Directory(folderPath);
    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) {
          final n = f.uri.pathSegments.last;
          return n.startsWith('addalocation_') && n.endsWith('.adls');
        })
        .toList()
      ..sort((a, b) => b.path.compareTo(a.path)); // plus récent d'abord
    if (files.isEmpty) return;

    final keep = <String>{};
    final now = DateTime.now();

    // 7 derniers jours : 1 par jour
    for (var d = 0; d < 7; d++) {
      final target = now.subtract(Duration(days: d));
      final dailyTag =
          '${target.year}-${target.month.toString().padLeft(2, '0')}-${target.day.toString().padLeft(2, '0')}';
      final match = files.firstWhere(
        (f) => f.path.contains(dailyTag),
        orElse: () => File(''),
      );
      if (match.path.isNotEmpty) keep.add(match.path);
    }

    // 4 dernières semaines : 1 par semaine ISO
    for (var w = 0; w < 4; w++) {
      final target = now.subtract(Duration(days: 7 * w));
      // semaine = lundi de cette semaine
      final monday = target.subtract(Duration(days: target.weekday - 1));
      final weekTag =
          '${monday.year}-${monday.month.toString().padLeft(2, '0')}-${monday.day.toString().padLeft(2, '0')}';
      // On garde le premier backup qui correspond à ce lundi ou plus tard cette semaine.
      final candidates = files.where((f) {
        for (var d = 0; d < 7; d++) {
          final day = monday.add(Duration(days: d));
          final tag =
              '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
          if (f.path.contains(tag)) return true;
        }
        return false;
      }).toList();
      if (candidates.isNotEmpty) keep.add(candidates.first.path);
      // weekTag unused but kept for readability
      assert(weekTag.isNotEmpty);
    }

    // 12 derniers mois : 1 par mois
    for (var m = 0; m < 12; m++) {
      final target = DateTime(now.year, now.month - m, 1);
      final monthTag =
          '${target.year}-${target.month.toString().padLeft(2, '0')}';
      final candidates = files.where((f) {
        final n = f.uri.pathSegments.last;
        // addalocation_YYYY-MM-DD_HHmm.adls
        return n.startsWith('addalocation_$monthTag');
      }).toList();
      if (candidates.isNotEmpty) keep.add(candidates.first.path);
    }

    // Une sauvegarde par année (la plus récente de chaque année)
    final byYear = <int, File>{};
    for (final f in files) {
      final n = f.uri.pathSegments.last;
      // addalocation_YYYY-...
      final m = RegExp(r'addalocation_(\d{4})-').firstMatch(n);
      if (m == null) continue;
      final y = int.tryParse(m.group(1)!);
      if (y == null) continue;
      byYear[y] ??= f;
    }
    keep.addAll(byYear.values.map((f) => f.path));

    // Supprime tout ce qui n'est pas dans keep
    for (final f in files) {
      if (!keep.contains(f.path)) {
        try {
          await f.delete();
        } catch (_) {/* pas critique */}
      }
    }
  }

  void _refreshState() {
    if (!isEnabled) {
      _state = AutoBackupState.disabled;
      return;
    }
    final folder = folderPath;
    if (folder == null || folder.isEmpty) {
      _state = AutoBackupState.disabled;
      return;
    }
    if (!Directory(folder).existsSync()) {
      _state = AutoBackupState.error;
      _lastError = 'Dossier inaccessible : $folder';
      return;
    }
    // Sans hash courant facilement calculable ici (besoin d'I/O),
    // on assume upToDate jusqu'au prochain runIfNeeded.
    _state = AutoBackupState.upToDate;
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    for (final s in _boxSubs) {
      s.cancel();
    }
    _boxSubs.clear();
    super.dispose();
  }
}
