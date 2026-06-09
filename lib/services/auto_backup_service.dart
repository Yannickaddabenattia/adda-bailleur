import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

import '../core/storage/local_database.dart';
import '../core/storage/secure_folder.dart';
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

/// Métadonnées extraites du nom d'un fichier de sauvegarde `.adls`.
///
/// Deux formats acceptés (rétro-compatibilité) :
///   `addalocation_YYYY-MM-DD_HHmm(ss).adls`            (ancien, sans device)
///   `addalocation_<dev8>_YYYY-MM-DD_HHmmss.adls`       (avec identifiant device)
class BackupFileName {
  /// 8 caractères hexadécimaux identifiant l'appareil source, ou `null`
  /// (ancien format : on considère alors le fichier comme « local »).
  final String? deviceTag;

  /// Date/heure encodée dans le nom (heure locale de l'appareil source).
  final DateTime dateTime;

  const BackupFileName(this.deviceTag, this.dateTime);

  static final RegExp _re = RegExp(
    r'^addalocation_(?:([0-9a-fA-F]{8})_)?'
    r'(\d{4})-(\d{2})-(\d{2})_(\d{2})(\d{2})(\d{2})?\.adls$',
  );

  static BackupFileName? tryParse(String fileName) {
    final m = _re.firstMatch(fileName);
    if (m == null) return null;
    final dt = DateTime(
      int.parse(m.group(2)!),
      int.parse(m.group(3)!),
      int.parse(m.group(4)!),
      int.parse(m.group(5)!),
      int.parse(m.group(6)!),
      m.group(7) != null ? int.parse(m.group(7)!) : 0,
    );
    return BackupFileName(m.group(1)?.toLowerCase(), dt);
  }

  /// Construit le nom de fichier daté pour [deviceTag] (8 hex) à l'instant [now].
  static String build({required String deviceTag, required DateTime now}) {
    String two(int v) => v.toString().padLeft(2, '0');
    final stamp = '${now.year}-${two(now.month)}-${two(now.day)}'
        '_${two(now.hour)}${two(now.minute)}${two(now.second)}';
    return 'addalocation_${deviceTag}_$stamp.adls';
  }
}

/// Sauvegarde détectée provenant d'un autre appareil sur le dossier partagé.
class ForeignBackupInfo {
  final String fileName;
  final String deviceTag;
  final DateTime dateTime;

  const ForeignBackupInfo({
    required this.fileName,
    required this.deviceTag,
    required this.dateTime,
  });

  /// Parmi [fileNames], renvoie la sauvegarde la plus récente écrite par un
  /// autre appareil que [myTag] et postérieure à [since] (si fourni). `null`
  /// si rien de neuf. Fonction pure : aucune I/O, testable directement.
  static ForeignBackupInfo? newestForeign(
    Iterable<String> fileNames, {
    required String myTag,
    DateTime? since,
  }) {
    ForeignBackupInfo? best;
    for (final name in fileNames) {
      final info = BackupFileName.tryParse(name);
      if (info == null) continue;
      final tag = info.deviceTag;
      if (tag == null || tag == myTag) continue; // local / ancien format
      if (since != null && !info.dateTime.isAfter(since)) continue;
      if (best == null || info.dateTime.isAfter(best.dateTime)) {
        best = ForeignBackupInfo(
          fileName: name,
          deviceTag: tag,
          dateTime: info.dateTime,
        );
      }
    }
    return best;
  }
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
  static const String _kBookmark = 'auto_backup_folder_bookmark';
  static const String _kPassphraseStored = 'auto_backup_passphrase_stored';
  static const String _kLastAtIso = 'auto_backup_last_at_iso';
  static const String _kLastHash = 'auto_backup_last_hash';
  static const String _kLastDeviceId = 'auto_backup_last_device_id';
  static const String _kLastFilePath = 'auto_backup_last_file_path';
  static const String _kDeviceId = 'auto_backup_device_id';
  // Date (ISO) du dernier backup d'un AUTRE appareil déjà importé : sert de
  // repère pour ne pas re-proposer un fichier déjà fusionné.
  static const String _kLastImportedForeignIso =
      'auto_backup_last_imported_foreign_iso';

  // Secure storage key (passphrase chiffrée par l'OS)
  static const String _ksPassphrase = 'auto_backup_passphrase';

  static const _secureStorage = FlutterSecureStorage();
  static const _debounce = Duration(minutes: 5);
  static const _watchInterval = Duration(seconds: 60);

  AutoBackupState _state = AutoBackupState.disabled;
  AutoBackupState get state => _state;

  String? _lastError;
  String? get lastError => _lastError;

  Timer? _debounceTimer;
  Timer? _watchTimer;
  final List<StreamSubscription> _boxSubs = [];

  /// Sauvegarde d'un autre appareil détectée et en attente d'import (`null`
  /// si rien de neuf). Surfacé par l'UI pour proposer une fusion en 1 tap.
  ForeignBackupInfo? _pendingForeign;
  ForeignBackupInfo? get pendingForeign => _pendingForeign;

  /// Verrou anti-concurrence : empêche deux écritures simultanées (ex. bouton
  /// « Sauvegarder maintenant » pendant qu'un backup debouncé se déclenche,
  /// ou onResume + debounce) qui courraient sur le même fichier `.tmp`.
  bool _backupInProgress = false;

  AutoBackupService() {
    _refreshState();
    _attachBoxWatchers();
    _startWatchTimer();
  }

  /// 8 premiers caractères hexadécimaux d'un UUID d'appareil (tag court).
  static String _shortDeviceTag(String deviceUuid) =>
      deviceUuid.replaceAll('-', '').toLowerCase().padRight(8, '0').substring(0, 8);

  /// (Re)démarre la surveillance périodique du dossier partagé.
  void _startWatchTimer() {
    _watchTimer?.cancel();
    _watchTimer = Timer.periodic(_watchInterval, (_) {
      checkForForeignBackups();
    });
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

  /// Bookmark security-scoped du dossier (base64), `null` si absent — l'accès
  /// retombe alors sur le chemin (valable seulement pour la session courante
  /// sur les plateformes en bac à sable).
  String? get folderBookmark {
    final b = LocalDatabase.settingsBox.get(_kBookmark);
    return (b == null || b.isEmpty) ? null : b;
  }

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
    String? bookmark,
  }) async {
    final dir = Directory(folderPath);
    if (!dir.existsSync()) {
      throw ArgumentError('Le dossier n\'existe pas : $folderPath');
    }
    await LocalDatabase.settingsBox.put(_kFolderPath, folderPath);
    await LocalDatabase.settingsBox.put(_kBookmark, bookmark ?? '');
    await LocalDatabase.settingsBox.put(_kEnabled, 'true');
    await _secureStorage.write(key: _ksPassphrase, value: passphrase);
    await LocalDatabase.settingsBox.put(_kPassphraseStored, 'true');
    await deviceId(); // s'assure que le deviceId existe
    _refreshState();
    notifyListeners();
    unawaited(checkForForeignBackups()); // détection immédiate
  }

  /// Désactive l'auto-backup et supprime la passphrase du keychain.
  /// N'efface PAS les fichiers .adls déjà écrits dans le cloud.
  Future<void> disable() async {
    await LocalDatabase.settingsBox.put(_kEnabled, 'false');
    await _secureStorage.delete(key: _ksPassphrase);
    await LocalDatabase.settingsBox.put(_kPassphraseStored, 'false');
    await LocalDatabase.settingsBox.delete(_kBookmark);
    _state = AutoBackupState.disabled;
    _lastError = null;
    _pendingForeign = null;
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
      String storedFolderPath, String passphrase) async {
    if (_backupInProgress) {
      return const AutoBackupResult.skipped(
          reason: 'Sauvegarde déjà en cours');
    }
    _backupInProgress = true;
    _state = AutoBackupState.inProgress;
    notifyListeners();
    final bookmark = folderBookmark;
    String? resolvedPath;
    try {
      // Résout le bookmark security-scoped pour (ré)obtenir un accès durable
      // au dossier choisi (pCloud, disque virtuel, NAS…). Repli sur le chemin
      // stocké si pas de bookmark (ancienne config / plateforme non sandboxée).
      if (bookmark != null) {
        resolvedPath = await SecureFolder.startAccess(bookmark);
      }
      final folderPath = resolvedPath ?? storedFolderPath;
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

      // Écrit le .adls daté, préfixé de l'identifiant d'appareil : ce tag
      // permet aux autres appareils de reconnaître nos fichiers et de
      // détecter les leurs (synchro multi-appareils).
      final now = DateTime.now();
      final myTag = _shortDeviceTag(await deviceId());
      final fileName = BackupFileName.build(deviceTag: myTag, now: now);
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
    } finally {
      if (bookmark != null && resolvedPath != null) {
        await SecureFolder.stopAccess(bookmark);
      }
      _backupInProgress = false;
    }
  }

  /// Rotation pyramidale : garde 7 quotidiens, 4 hebdo, 12 mensuels, 1/an.
  /// Supprime les fichiers .adls excédentaires. La date est lue dans le nom
  /// via [BackupFileName] (robuste au préfixe device et aux deux formats).
  Future<void> _pruneOldBackups(String folderPath) async {
    final dir = Directory(folderPath);
    final parsed = <(File, DateTime)>[];
    for (final f in dir.listSync().whereType<File>()) {
      final info = BackupFileName.tryParse(f.uri.pathSegments.last);
      if (info != null) parsed.add((f, info.dateTime));
    }
    if (parsed.isEmpty) return;
    parsed.sort((a, b) => b.$2.compareTo(a.$2)); // plus récent d'abord

    final keep = <String>{};
    final now = DateTime.now();
    bool sameDay(DateTime a, DateTime b) =>
        a.year == b.year && a.month == b.month && a.day == b.day;

    // 7 derniers jours : le plus récent de chaque jour
    for (var d = 0; d < 7; d++) {
      final day = now.subtract(Duration(days: d));
      for (final p in parsed) {
        if (sameDay(p.$2, day)) {
          keep.add(p.$1.path);
          break;
        }
      }
    }

    // 4 dernières semaines : le plus récent de chaque semaine (lun-dim)
    for (var w = 0; w < 4; w++) {
      final ref = now.subtract(Duration(days: 7 * w));
      final monday = DateTime(ref.year, ref.month, ref.day)
          .subtract(Duration(days: ref.weekday - 1));
      final nextMonday = monday.add(const Duration(days: 7));
      for (final p in parsed) {
        if (!p.$2.isBefore(monday) && p.$2.isBefore(nextMonday)) {
          keep.add(p.$1.path);
          break;
        }
      }
    }

    // 12 derniers mois : le plus récent de chaque mois
    for (var m = 0; m < 12; m++) {
      final ref = DateTime(now.year, now.month - m, 1);
      for (final p in parsed) {
        if (p.$2.year == ref.year && p.$2.month == ref.month) {
          keep.add(p.$1.path);
          break;
        }
      }
    }

    // Une sauvegarde par année (la plus récente)
    final byYear = <int, String>{};
    for (final p in parsed) {
      byYear.putIfAbsent(p.$2.year, () => p.$1.path);
    }
    keep.addAll(byYear.values);

    // Supprime tout ce qui n'est pas dans keep
    for (final p in parsed) {
      if (!keep.contains(p.$1.path)) {
        try {
          await p.$1.delete();
        } catch (_) {/* pas critique */}
      }
    }
  }

  /// Scrute le dossier partagé à la recherche d'une sauvegarde plus récente
  /// écrite par un AUTRE appareil et non encore importée. Met à jour
  /// [pendingForeign] et notifie l'UI le cas échéant. Lecture seule.
  Future<void> checkForForeignBackups() async {
    if (!isEnabled) return;
    final storedFolder = folderPath;
    if (storedFolder == null || storedFolder.isEmpty) return;
    final bookmark = folderBookmark;
    String? resolvedPath;
    try {
      if (bookmark != null) {
        resolvedPath = await SecureFolder.startAccess(bookmark);
      }
      final folder = resolvedPath ?? storedFolder;
      final dir = Directory(folder);
      if (!dir.existsSync()) return;

      final myTag = _shortDeviceTag(await deviceId());
      final iso = LocalDatabase.settingsBox.get(_kLastImportedForeignIso);
      final since = iso != null ? DateTime.tryParse(iso) : null;

      final names =
          dir.listSync().whereType<File>().map((f) => f.uri.pathSegments.last);
      final found =
          ForeignBackupInfo.newestForeign(names, myTag: myTag, since: since);

      // Reconstituer le chemin absolu (le nom seul ne suffit pas pour lire).
      final newPending = found == null
          ? null
          : ForeignBackupInfo(
              fileName: '$folder${Platform.pathSeparator}${found.fileName}',
              deviceTag: found.deviceTag,
              dateTime: found.dateTime,
            );

      final changed = newPending?.fileName != _pendingForeign?.fileName;
      _pendingForeign = newPending;
      if (changed) notifyListeners();
    } catch (_) {
      // silencieux : la détection ne doit jamais perturber l'app
    } finally {
      if (bookmark != null && resolvedPath != null) {
        await SecureFolder.stopAccess(bookmark);
      }
    }
  }

  /// Importe (fusionne) la sauvegarde étrangère en attente. La fusion garde,
  /// pour chaque élément, la version la plus récente (`updatedAt`) ; les
  /// quittances déjà présentes ne sont jamais écrasées. Mémorise la date du
  /// fichier importé pour ne pas le re-proposer.
  Future<AutoBackupResult> importForeignBackup() async {
    final pending = _pendingForeign;
    if (pending == null) {
      return const AutoBackupResult.skipped(reason: 'Aucune donnée à importer');
    }
    final passphrase = await _readPassphrase();
    if (passphrase == null || passphrase.isEmpty) {
      return const AutoBackupResult.error('Passphrase manquante');
    }
    final bookmark = folderBookmark;
    String? resolvedPath;
    try {
      if (bookmark != null) {
        resolvedPath = await SecureFolder.startAccess(bookmark);
      }
      final file = File(pending.fileName);
      if (!file.existsSync()) {
        return const AutoBackupResult.error('Fichier introuvable');
      }
      final bytes = await file.readAsBytes();
      await BackupService()
          .importEncrypted(bytes: bytes, passphrase: passphrase);
      await LocalDatabase.settingsBox
          .put(_kLastImportedForeignIso, pending.dateTime.toIso8601String());
      _pendingForeign = null;
      notifyListeners();
      return AutoBackupResult.success(pending.fileName);
    } catch (e) {
      return AutoBackupResult.error(e.toString());
    } finally {
      if (bookmark != null && resolvedPath != null) {
        await SecureFolder.stopAccess(bookmark);
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
    // Avec un bookmark, l'accès réel se vérifie à la sauvegarde (le dossier
    // peut ne pas être « stat-able » sans résoudre le scope sécurisé). Sans
    // bookmark, on vérifie l'existence du chemin.
    if (folderBookmark == null && !Directory(folder).existsSync()) {
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
    _watchTimer?.cancel();
    for (final s in _boxSubs) {
      s.cancel();
    }
    _boxSubs.clear();
    super.dispose();
  }
}
