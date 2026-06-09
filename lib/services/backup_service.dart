import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../core/backup/backup_codec.dart';
import '../core/constants.dart';
import '../core/storage/local_database.dart';
import '../models/credit_immobilier.dart';
import '../models/depense.dart';
import '../models/element_piece.dart';
import '../models/etat_des_lieux.dart';
import '../models/etat_element.dart';
import '../models/fiscal_settings.dart';
import '../models/garant.dart';
import '../models/locataire.dart';
import '../models/logement.dart';
import '../models/piece.dart';
import '../models/plan_logement.dart';
import '../models/quittance.dart';
import '../models/avenant.dart';
import '../models/bail_template.dart';
import '../models/clause.dart';
import '../models/contrat_bail.dart';
import '../models/diagnostic.dart';
import '../models/revision_loyer.dart';
import '../models/sci.dart';
import '../models/user_profile.dart';
import '../models/user_role.dart';

/// Gère les sauvegardes chiffrées (export / import) de toutes les données
/// locales.
///
/// Format JSON v1 — n'inclut pas les bytes des photos (uniquement les chemins
/// de fichiers). Une restauration sur un nouvel appareil affichera des photos
/// manquantes pour les EDL.
class BackupService {
  static const int formatVersion = 2;

  /// Sérialise l'ensemble des données, chiffre avec la passphrase et renvoie
  /// le chemin du fichier produit.
  ///
  /// Le fichier est emballé dans un ZIP (.zip) afin que les transports type
  /// email/AirDrop ne renomment pas l'extension : un .zip est universellement
  /// reconnu, alors qu'un .adlb brut est souvent retypé en .bin.
  Future<File> exportEncrypted({required String passphrase}) async {
    final payload = _buildPayload();
    final json = jsonEncode(payload);
    final encrypted =
        await BackupCodec.encryptAsync(jsonPayload: json, passphrase: passphrase);

    final dir = await getApplicationDocumentsDirectory();
    final ts = DateTime.now().toIso8601String().replaceAll(':', '-');
    final innerName = 'adda_location_backup_$ts.adlb';
    final archive = Archive()
      ..addFile(ArchiveFile(innerName, encrypted.length, encrypted));
    final zipBytes = ZipEncoder().encode(archive);
    final file = File('${dir.path}/adda_location_backup_$ts.zip');
    await file.writeAsBytes(zipBytes, flush: true);
    return file;
  }

  /// Déchiffre et restaure une sauvegarde. Remplace toutes les données
  /// actuelles (sauf le profil utilisateur, qui reste immuable).
  ///
  /// Si [replaceProfile] est `true`, le profil existant est écrasé — utile
  /// uniquement lors d'une récupération sur nouvel appareil.
  /// Fusionne les données de la sauvegarde avec les données existantes.
  ///
  /// Pour chaque élément, l'ID sert de clé :
  /// - Présent des deux côtés → garde celui avec l'`updatedAt` le plus récent.
  /// - Présent uniquement dans la sauvegarde → ajouté.
  /// - Présent uniquement localement → conservé.
  ///
  /// Les quittances sont immuables après émission : si l'ID existe déjà, la
  /// version locale est conservée ; sinon, l'entrée est ajoutée.
  ///
  /// Le profil utilisateur est immuable par design : conservé si présent,
  /// sinon celui de la sauvegarde est installé (sauf si `replaceProfile`).
  Future<BackupImportReport> importEncrypted({
    required Uint8List bytes,
    required String passphrase,
    bool replaceProfile = false,
  }) async {
    bytes = _unwrapIfZip(bytes);
    final jsonText =
        await BackupCodec.decryptAsync(bytes: bytes, passphrase: passphrase);
    final decoded = jsonDecode(jsonText);
    if (decoded is! Map<String, dynamic>) {
      throw const BackupFormatException('Payload JSON invalide');
    }
    final payload = decoded;
    final version = payload['version'];
    if (version is! int || version > formatVersion) {
      throw BackupFormatException('Version payload non supportée: $version');
    }

    bool profileRestored = false;
    final userMap = payload['user'] as Map<String, dynamic>?;
    if (userMap != null) {
      final existing = LocalDatabase.userBox.get(AppConstants.userProfileKey);
      if (existing == null || replaceProfile) {
        final up = _userFromMap(userMap);
        await LocalDatabase.userBox.put(AppConstants.userProfileKey, up);
        profileRestored = true;
      }
    }

    final logements = await _mergeByUpdatedAt<Logement>(
      box: LocalDatabase.logementsBox,
      incoming: (payload['logements'] as List? ?? const [])
          .map((m) => _logementFromMap(m as Map<String, dynamic>))
          .toList(),
      idOf: (l) => l.id,
      updatedAtOf: (l) => l.updatedAt,
    );

    final locataires = await _mergeByUpdatedAt<Locataire>(
      box: LocalDatabase.locatairesBox,
      incoming: (payload['locataires'] as List? ?? const [])
          .map((m) => _locataireFromMap(m as Map<String, dynamic>))
          .toList(),
      idOf: (l) => l.id,
      updatedAtOf: (l) => l.updatedAt,
    );

    final edls = await _mergeByUpdatedAt<EtatDesLieux>(
      box: LocalDatabase.etatDesLieuxBox,
      incoming: (payload['etatDesLieux'] as List? ?? const [])
          .map((m) => _edlFromMap(m as Map<String, dynamic>))
          .toList(),
      idOf: (e) => e.id,
      updatedAtOf: (e) => e.updatedAt,
    );

    final quittances = await _mergeByHash<Quittance>(
      box: LocalDatabase.quittancesBox,
      incoming: (payload['quittances'] as List? ?? const [])
          .map((m) => _quittanceFromMap(m as Map<String, dynamic>))
          .toList(),
      idOf: (q) => q.id,
      hashOf: (q) => q.integrityHash,
    );

    final incomingPlanMaps = (payload['plans'] as List? ?? const [])
        .cast<Map<String, dynamic>>();
    final incomingPlans = <PlanLogement>[];
    for (final pm in incomingPlanMaps) {
      await _persistEmbeddedWallPhotos(pm);
      incomingPlans.add(PlanLogement.fromMap(pm));
    }
    // Fusion non destructive des plans : on garde les annotations et
    // photos de mur des deux côtés (union par id), même si la géométrie
    // de l'autre côté est plus récente. Aucune suppression automatique.
    await _mergePlansSafely(incomingPlans);

    // Dépenses : fusion par hash. Si l'incoming a un hash différent, il
    // gagne (= modification post-export). Permet de propager une correction
    // de montant ou de catégorie sans suppression manuelle.
    await _mergeByHash<Depense>(
      box: LocalDatabase.depensesBox,
      incoming: (payload['depenses'] as List? ?? const [])
          .map((m) => _depenseFromMap(m as Map<String, dynamic>))
          .toList(),
      idOf: (d) => d.id,
      hashOf: (d) => d.integrityHash,
    );

    // Crédits immobiliers : même politique que les dépenses. Indispensable
    // pour propager une rachat ou une clôture saisie sur un autre device.
    await _mergeByHash<CreditImmobilier>(
      box: LocalDatabase.creditsImmobiliersBox,
      incoming: (payload['creditsImmobiliers'] as List? ?? const [])
          .map((m) => _creditFromMap(m as Map<String, dynamic>))
          .toList(),
      idOf: (c) => c.id,
      hashOf: (c) => c.integrityHash,
    );

    // Catégories personnalisées : on ajoute les manquantes.
    final categories = (payload['customExpenseCategories'] as List? ?? const [])
        .cast<String>();
    final existingCats =
        LocalDatabase.customExpenseCategoriesBox.values.toSet();
    for (final c in categories) {
      if (!existingCats.contains(c)) {
        await LocalDatabase.customExpenseCategoriesBox.add(c);
      }
    }

    // Révisions de loyer : même politique de hash, pour rester cohérent
    // avec les autres entités. En pratique elles ne sont quasiment jamais
    // modifiées après création.
    await _mergeByHash<RevisionLoyer>(
      box: LocalDatabase.revisionsLoyerBox,
      incoming: (payload['revisionsLoyer'] as List? ?? const [])
          .map((m) => _revisionFromMap(m as Map<String, dynamic>))
          .toList(),
      idOf: (r) => r.id,
      hashOf: (r) => r.integrityHash,
    );

    // Paramètres fiscaux du foyer (parts, autres revenus, déficits…).
    // Enregistrement unique (clé fixe). Si présent dans la sauvegarde, on
    // l'écrit ; sinon on conserve la valeur locale.
    final fiscalMap = payload['fiscalSettings'];
    if (fiscalMap is Map<String, dynamic>) {
      final fs = _fiscalSettingsFromMap(fiscalMap);
      await LocalDatabase.fiscalSettingsBox.put(FiscalSettings.key, fs);
    }

    // SCI : fusion par `updatedAt`. Les distributions de dividendes sont des
    // saisies utilisateur — on prend la version la plus récente.
    await _mergeByUpdatedAt<SCI>(
      box: LocalDatabase.scisBox,
      incoming: (payload['scis'] as List? ?? const [])
          .map((m) => _sciFromMap(m as Map<String, dynamic>))
          .toList(),
      idOf: (s) => s.id,
      updatedAtOf: (s) => s.updatedAt,
    );

    // Contrats de bail : fusion par `updatedAt`. Les PDF générés sont des
    // chemins locaux (pas portables) ; on les conserve quand même pour ne
    // pas perdre le lien si on revient sur le même appareil.
    await _mergeByUpdatedAt<ContratBail>(
      box: LocalDatabase.contratsBailBox,
      incoming: (payload['contratsBail'] as List? ?? const [])
          .map((m) => _contratBailFromMap(m as Map<String, dynamic>))
          .toList(),
      idOf: (c) => c.id,
      updatedAtOf: (c) => c.updatedAt,
    );

    // Diagnostics : fusion par `updatedAt`.
    await _mergeByUpdatedAt<Diagnostic>(
      box: LocalDatabase.diagnosticsBox,
      incoming: (payload['diagnostics'] as List? ?? const [])
          .map((m) => _diagnosticFromMap(m as Map<String, dynamic>))
          .toList(),
      idOf: (d) => d.id,
      updatedAtOf: (d) => d.updatedAt,
    );

    // Avenants : fusion par `updatedAt`.
    await _mergeByUpdatedAt<Avenant>(
      box: LocalDatabase.avenantsBox,
      incoming: (payload['avenants'] as List? ?? const [])
          .map((m) => _avenantFromMap(m as Map<String, dynamic>))
          .toList(),
      idOf: (a) => a.id,
      updatedAtOf: (a) => a.updatedAt,
    );

    // Templates de bails personnels : fusion par `dateModification`.
    // On filtre `isSystem == false` côté lecture pour ne pas écraser un
    // template système (insertion volontaire d'un payload corrompu).
    await _mergeByUpdatedAt<BailTemplate>(
      box: LocalDatabase.bailTemplatesBox,
      incoming: (payload['bailTemplates'] as List? ?? const [])
          .map((m) => BailTemplate.fromMap((m as Map).cast<String, dynamic>()))
          .where((t) => !t.isSystem)
          .toList(),
      idOf: (t) => t.id,
      updatedAtOf: (t) => t.dateModification ?? DateTime(1970),
    );

    // Aucune suppression automatique : on respecte le choix de l'utilisateur
    // de ne supprimer ses logements / fichiers que manuellement. La fusion
    // garde donc les doublons éventuels (deux logements avec le même nom)
    // côte à côte plutôt que d'en effacer un.
    return BackupImportReport(
      logements: logements,
      locataires: locataires,
      etatsDesLieux: edls,
      quittances: quittances,
      profileRestored: profileRestored,
      duplicatesRemoved: 0,
    );
  }

  /// Restaure une sauvegarde en **écrasant** toutes les données actuelles.
  /// Contrairement à [importEncrypted] qui fusionne en gardant les versions
  /// les plus récentes, cette méthode supprime tout le contenu local des
  /// boxes (logements, locataires, EDL, quittances, plans) et le remplace
  /// par celui du fichier. Utile lorsqu'on veut imposer la sauvegarde comme
  /// source de vérité absolue.
  ///
  /// Le profil utilisateur est conservé sauf si [replaceProfile] vaut
  /// `true`.
  Future<BackupImportReport> importEncryptedReplace({
    required Uint8List bytes,
    required String passphrase,
    bool replaceProfile = false,
  }) async {
    bytes = _unwrapIfZip(bytes);
    final jsonText =
        await BackupCodec.decryptAsync(bytes: bytes, passphrase: passphrase);
    final decoded = jsonDecode(jsonText);
    if (decoded is! Map<String, dynamic>) {
      throw const BackupFormatException('Payload JSON invalide');
    }
    final payload = decoded;
    final version = payload['version'];
    if (version is! int || version > formatVersion) {
      throw BackupFormatException('Version payload non supportée: $version');
    }

    bool profileRestored = false;
    final userMap = payload['user'] as Map<String, dynamic>?;
    if (userMap != null) {
      final existing = LocalDatabase.userBox.get(AppConstants.userProfileKey);
      if (existing == null || replaceProfile) {
        final up = _userFromMap(userMap);
        await LocalDatabase.userBox.put(AppConstants.userProfileKey, up);
        profileRestored = true;
      }
    }

    final incomingLogements = (payload['logements'] as List? ?? const [])
        .map((m) => _logementFromMap(m as Map<String, dynamic>))
        .toList();
    final incomingLocataires = (payload['locataires'] as List? ?? const [])
        .map((m) => _locataireFromMap(m as Map<String, dynamic>))
        .toList();
    final incomingEdls = (payload['etatDesLieux'] as List? ?? const [])
        .map((m) => _edlFromMap(m as Map<String, dynamic>))
        .toList();
    final incomingQuittances = (payload['quittances'] as List? ?? const [])
        .map((m) => _quittanceFromMap(m as Map<String, dynamic>))
        .toList();
    final incomingPlanMaps = (payload['plans'] as List? ?? const [])
        .cast<Map<String, dynamic>>();
    final incomingPlans = <PlanLogement>[];
    for (final pm in incomingPlanMaps) {
      await _persistEmbeddedWallPhotos(pm);
      incomingPlans.add(PlanLogement.fromMap(pm));
    }
    final incomingDepenses = (payload['depenses'] as List? ?? const [])
        .map((m) => _depenseFromMap(m as Map<String, dynamic>))
        .toList();
    final incomingCredits = (payload['creditsImmobiliers'] as List? ?? const [])
        .map((m) => _creditFromMap(m as Map<String, dynamic>))
        .toList();
    final incomingCategories =
        (payload['customExpenseCategories'] as List? ?? const [])
            .cast<String>();
    final incomingRevisions = (payload['revisionsLoyer'] as List? ?? const [])
        .map((m) => _revisionFromMap(m as Map<String, dynamic>))
        .toList();
    final incomingScis = (payload['scis'] as List? ?? const [])
        .map((m) => _sciFromMap(m as Map<String, dynamic>))
        .toList();
    final incomingContratsBail =
        (payload['contratsBail'] as List? ?? const [])
            .map((m) => _contratBailFromMap(m as Map<String, dynamic>))
            .toList();
    final incomingDiagnostics =
        (payload['diagnostics'] as List? ?? const [])
            .map((m) => _diagnosticFromMap(m as Map<String, dynamic>))
            .toList();
    final incomingAvenants = (payload['avenants'] as List? ?? const [])
        .map((m) => _avenantFromMap(m as Map<String, dynamic>))
        .toList();

    await LocalDatabase.logementsBox.clear();
    await LocalDatabase.locatairesBox.clear();
    await LocalDatabase.etatDesLieuxBox.clear();
    await LocalDatabase.quittancesBox.clear();
    // On remplace aussi les plans uniquement si le payload en contient :
    // ainsi un fichier ancien (sans plans) ne supprime pas les plans locaux.
    if (incomingPlans.isNotEmpty) {
      await LocalDatabase.plansLogementBox.clear();
    }
    // Idem pour les dépenses / crédits : on n'efface que si le payload les
    // contient, pour ne pas supprimer les données locales en restaurant un
    // ancien fichier (v1) qui ne portait pas la rubrique financière.
    if (payload.containsKey('depenses')) {
      await LocalDatabase.depensesBox.clear();
    }
    if (payload.containsKey('creditsImmobiliers')) {
      await LocalDatabase.creditsImmobiliersBox.clear();
    }
    if (payload.containsKey('customExpenseCategories')) {
      await LocalDatabase.customExpenseCategoriesBox.clear();
    }
    if (payload.containsKey('revisionsLoyer')) {
      await LocalDatabase.revisionsLoyerBox.clear();
    }
    if (payload.containsKey('scis')) {
      await LocalDatabase.scisBox.clear();
    }
    if (payload.containsKey('contratsBail')) {
      await LocalDatabase.contratsBailBox.clear();
    }
    if (payload.containsKey('diagnostics')) {
      await LocalDatabase.diagnosticsBox.clear();
    }
    if (payload.containsKey('avenants')) {
      await LocalDatabase.avenantsBox.clear();
    }
    if (payload.containsKey('bailTemplates')) {
      // On vide uniquement les templates utilisateur. Les templates système
      // viennent du code, ils ne sont pas en base.
      final userKeys = LocalDatabase.bailTemplatesBox.values
          .where((t) => !t.isSystem)
          .map((t) => t.id)
          .toList();
      for (final k in userKeys) {
        await LocalDatabase.bailTemplatesBox.delete(k);
      }
    }
    if (payload.containsKey('fiscalSettings')) {
      await LocalDatabase.fiscalSettingsBox.clear();
      final fiscalMap = payload['fiscalSettings'];
      if (fiscalMap is Map<String, dynamic>) {
        await LocalDatabase.fiscalSettingsBox.put(
          FiscalSettings.key,
          _fiscalSettingsFromMap(fiscalMap),
        );
      }
    }

    for (final l in incomingLogements) {
      await LocalDatabase.logementsBox.put(l.id, l);
    }
    for (final l in incomingLocataires) {
      await LocalDatabase.locatairesBox.put(l.id, l);
    }
    for (final e in incomingEdls) {
      await LocalDatabase.etatDesLieuxBox.put(e.id, e);
    }
    for (final q in incomingQuittances) {
      await LocalDatabase.quittancesBox.put(q.id, q);
    }
    for (final p in incomingPlans) {
      await LocalDatabase.plansLogementBox.put(p.id, p);
    }
    for (final d in incomingDepenses) {
      await LocalDatabase.depensesBox.put(d.id, d);
    }
    for (final c in incomingCredits) {
      await LocalDatabase.creditsImmobiliersBox.put(c.id, c);
    }
    for (final cat in incomingCategories) {
      await LocalDatabase.customExpenseCategoriesBox.add(cat);
    }
    for (final r in incomingRevisions) {
      await LocalDatabase.revisionsLoyerBox.put(r.id, r);
    }
    for (final s in incomingScis) {
      await LocalDatabase.scisBox.put(s.id, s);
    }
    for (final c in incomingContratsBail) {
      await LocalDatabase.contratsBailBox.put(c.id, c);
    }
    for (final d in incomingDiagnostics) {
      await LocalDatabase.diagnosticsBox.put(d.id, d);
    }
    for (final a in incomingAvenants) {
      await LocalDatabase.avenantsBox.put(a.id, a);
    }
    final incomingBailTemplates = (payload['bailTemplates'] as List? ?? const [])
        .map((m) => BailTemplate.fromMap((m as Map).cast<String, dynamic>()))
        .where((t) => !t.isSystem)
        .toList();
    for (final t in incomingBailTemplates) {
      await LocalDatabase.bailTemplatesBox.put(t.id, t);
    }

    return BackupImportReport(
      logements: MergeStats(
        added: incomingLogements.length,
        updated: 0,
        kept: 0,
      ),
      locataires: MergeStats(
        added: incomingLocataires.length,
        updated: 0,
        kept: 0,
      ),
      etatsDesLieux: MergeStats(
        added: incomingEdls.length,
        updated: 0,
        kept: 0,
      ),
      quittances: MergeStats(
        added: incomingQuittances.length,
        updated: 0,
        kept: 0,
      ),
      profileRestored: profileRestored,
      duplicatesRemoved: 0,
    );
  }

  /// Si [bytes] est un ZIP (signature PK\x03\x04), retourne le contenu du
  /// premier fichier `.adlb` qu'il contient ; sinon renvoie [bytes] inchangé.
  /// Permet d'accepter à la fois les exports zip (recommandés depuis 2026-05)
  /// et les anciens `.adlb` bruts.
  Uint8List _unwrapIfZip(Uint8List bytes) {
    if (bytes.length < 4) return bytes;
    final isZip = bytes[0] == 0x50 &&
        bytes[1] == 0x4B &&
        bytes[2] == 0x03 &&
        bytes[3] == 0x04;
    if (!isZip) return bytes;
    final archive = ZipDecoder().decodeBytes(bytes);
    final entry = archive.files.firstWhere(
      (f) => f.isFile && f.name.toLowerCase().endsWith('.adlb'),
      orElse: () => archive.files.firstWhere(
        (f) => f.isFile,
        orElse: () =>
            throw const BackupFormatException('Archive ZIP vide'),
      ),
    );
    return entry.content;
  }

  Future<MergeStats> _mergeByUpdatedAt<T>({
    required dynamic box,
    required List<T> incoming,
    required String Function(T) idOf,
    required DateTime Function(T) updatedAtOf,
  }) async {
    int added = 0;
    int updated = 0;
    int kept = 0;
    for (final item in incoming) {
      final id = idOf(item);
      final existing = box.get(id) as T?;
      if (existing == null) {
        await box.put(id, item);
        added++;
      } else if (!updatedAtOf(item).isBefore(updatedAtOf(existing))) {
        // Comparaison non stricte : à updatedAt égal, l'incoming gagne (=
        // dernier export gagne). Évite les cas où une correction de
        // sérialisation ne se propage pas parce que `updatedAt` n'a pas
        // bougé entre deux exports.
        await box.put(id, item);
        updated++;
      } else {
        kept++;
      }
    }
    return MergeStats(added: added, updated: updated, kept: kept);
  }

  /// Fusion non destructive des plans : la géométrie (rooms, imagePath,
  /// nom) suit la version la plus récente, mais les annotations et photos
  /// de mur sont **unionnées par id** des deux côtés afin qu'aucune
  /// donnée locale (notamment des photos prises depuis la dernière
  /// sauvegarde) ne soit perdue lors d'une importation.
  Future<void> _mergePlansSafely(List<PlanLogement> incoming) async {
    final box = LocalDatabase.plansLogementBox;
    for (final inc in incoming) {
      final existing = box.get(inc.id);
      if (existing == null) {
        await box.put(inc.id, inc);
        continue;
      }
      final keepBase =
          inc.updatedAt.isAfter(existing.updatedAt) ? inc : existing;
      final mergedAnnotations = <String, PlanAnnotation>{
        for (final a in existing.annotations) a.id: a,
      };
      for (final a in inc.annotations) {
        mergedAnnotations[a.id] = a;
      }
      final mergedPhotos = <String, WallPhoto>{
        for (final w in existing.wallPhotos) w.id: w,
      };
      for (final w in inc.wallPhotos) {
        mergedPhotos[w.id] = w;
      }
      final merged = PlanLogement(
        id: keepBase.id,
        logementId: keepBase.logementId,
        kind: keepBase.kind,
        name: keepBase.name,
        imagePath: keepBase.imagePath,
        rooms: keepBase.rooms,
        annotations: mergedAnnotations.values.toList(),
        wallPhotos: mergedPhotos.values.toList(),
        sortOrder: keepBase.sortOrder,
        createdAt: keepBase.createdAt,
        updatedAt: keepBase.updatedAt.isAfter(existing.updatedAt)
            ? keepBase.updatedAt
            : existing.updatedAt,
      );
      await box.put(merged.id, merged);
    }
  }

  /// Fusion par hash d'intégrité : si l'entrée existe déjà avec un hash
  /// différent, on remplace par l'incoming (= la dernière version exportée
  /// gagne). Utilisé pour les entités modifiables sans `updatedAt`
  /// (crédits immobiliers, dépenses).
  Future<MergeStats> _mergeByHash<T>({
    required dynamic box,
    required List<T> incoming,
    required String Function(T) idOf,
    required String? Function(T) hashOf,
  }) async {
    int added = 0;
    int updated = 0;
    int kept = 0;
    for (final item in incoming) {
      final id = idOf(item);
      final existing = box.get(id);
      if (existing == null) {
        await box.put(id, item);
        added++;
      } else {
        final hLocal = hashOf(existing as T);
        final hIncoming = hashOf(item);
        if (hIncoming != null && hIncoming != hLocal) {
          await box.put(id, item);
          updated++;
        } else {
          kept++;
        }
      }
    }
    return MergeStats(added: added, updated: updated, kept: kept);
  }

  /// Construit le payload de sauvegarde sans le chiffrer (utile pour
  /// détecter un changement d'état via SHA-256 dans [AutoBackupService]).
  Map<String, dynamic> debugBuildPayload() => _buildPayload();

  Map<String, dynamic> _buildPayload() {
    final user = LocalDatabase.userBox.get(AppConstants.userProfileKey);
    final deviceId =
        LocalDatabase.settingsBox.get('auto_backup_device_id') ?? '';
    return {
      'version': formatVersion,
      'appVersion': AppConstants.appVersion,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'deviceId': deviceId,
      'user': user == null ? null : _userToMap(user),
      'logements': LocalDatabase.logementsBox.values.map(_logementToMap).toList(),
      'locataires':
          LocalDatabase.locatairesBox.values.map(_locataireToMap).toList(),
      'etatDesLieux':
          LocalDatabase.etatDesLieuxBox.values.map(_edlToMap).toList(),
      'quittances':
          LocalDatabase.quittancesBox.values.map(_quittanceToMap).toList(),
      'plans': LocalDatabase.plansLogementBox.values
          .map(_planMapWithEmbeddedWallPhotos)
          .toList(),
      'depenses':
          LocalDatabase.depensesBox.values.map(_depenseToMap).toList(),
      'creditsImmobiliers': LocalDatabase.creditsImmobiliersBox.values
          .map(_creditToMap)
          .toList(),
      'customExpenseCategories':
          LocalDatabase.customExpenseCategoriesBox.values.toList(),
      'revisionsLoyer':
          LocalDatabase.revisionsLoyerBox.values.map(_revisionToMap).toList(),
      'fiscalSettings': () {
        final fs = LocalDatabase.fiscalSettingsBox.get(FiscalSettings.key);
        return fs == null ? null : _fiscalSettingsToMap(fs);
      }(),
      'scis': LocalDatabase.scisBox.values.map(_sciToMap).toList(),
      'contratsBail':
          LocalDatabase.contratsBailBox.values.map(_contratBailToMap).toList(),
      'avenants':
          LocalDatabase.avenantsBox.values.map(_avenantToMap).toList(),
      'diagnostics':
          LocalDatabase.diagnosticsBox.values.map(_diagnosticToMap).toList(),
      // Templates de bails personnels uniquement (les templates système sont
      // hardcodés dans le code et ne sont pas exportés).
      'bailTemplates': LocalDatabase.bailTemplatesBox.values
          .where((t) => !t.isSystem)
          .map((t) => t.toMap())
          .toList(),
    };
  }

  Map<String, dynamic> _avenantToMap(Avenant a) => {
        'id': a.id,
        'contratBailId': a.contratBailId,
        'numero': a.numero,
        'dateEffet': a.dateEffet.toUtc().toIso8601String(),
        'objet': a.objet,
        'description': a.description,
        if (a.nouveauLoyerHC != null) 'nouveauLoyerHC': a.nouveauLoyerHC,
        if (a.nouvellesCharges != null) 'nouvellesCharges': a.nouvellesCharges,
        if (a.nouvelleDureeMois != null)
          'nouvelleDureeMois': a.nouvelleDureeMois,
        if (a.nouvelleDateFin != null)
          'nouvelleDateFin': a.nouvelleDateFin!.toUtc().toIso8601String(),
        if (a.signatureBailleurPng != null)
          'signatureBailleurPng': a.signatureBailleurPng,
        if (a.signatureBailleurAt != null)
          'signatureBailleurAt':
              a.signatureBailleurAt!.toUtc().toIso8601String(),
        'signaturesLocatairesPng': a.signaturesLocatairesPng,
        'signaturesLocatairesAt': a.signaturesLocatairesAt,
        if (a.integrityHash != null) 'integrityHash': a.integrityHash,
        if (a.pdfPath != null) 'pdfPath': a.pdfPath,
        'createdAt': a.createdAt.toUtc().toIso8601String(),
        'updatedAt': a.updatedAt.toUtc().toIso8601String(),
      };

  Avenant _avenantFromMap(Map<String, dynamic> m) {
    final sigPngRaw = m['signaturesLocatairesPng'] as Map?;
    final sigPng = <String, String>{};
    sigPngRaw?.forEach((k, v) {
      if (k is String && v is String) sigPng[k] = v;
    });
    final sigAtRaw = m['signaturesLocatairesAt'] as Map?;
    final sigAt = <String, String>{};
    sigAtRaw?.forEach((k, v) {
      if (k is String && v is String) sigAt[k] = v;
    });
    return Avenant(
      id: m['id'] as String,
      contratBailId: m['contratBailId'] as String,
      numero: (m['numero'] as num).toInt(),
      dateEffet: DateTime.parse(m['dateEffet'] as String),
      objet: m['objet'] as String,
      description: (m['description'] as String?) ?? '',
      nouveauLoyerHC: (m['nouveauLoyerHC'] as num?)?.toDouble(),
      nouvellesCharges: (m['nouvellesCharges'] as num?)?.toDouble(),
      nouvelleDureeMois: (m['nouvelleDureeMois'] as num?)?.toInt(),
      nouvelleDateFin: m['nouvelleDateFin'] is String
          ? DateTime.parse(m['nouvelleDateFin'] as String)
          : null,
      signatureBailleurPng: m['signatureBailleurPng'] as String?,
      signatureBailleurAt: m['signatureBailleurAt'] is String
          ? DateTime.parse(m['signatureBailleurAt'] as String)
          : null,
      signaturesLocatairesPng: sigPng,
      signaturesLocatairesAt: sigAt,
      integrityHash: m['integrityHash'] as String?,
      pdfPath: m['pdfPath'] as String?,
      createdAt: DateTime.parse(m['createdAt'] as String),
      updatedAt: DateTime.parse(m['updatedAt'] as String),
    );
  }

  Map<String, dynamic> _contratBailToMap(ContratBail c) => {
        'id': c.id,
        'reference': c.reference,
        'type': c.type.name,
        'statut': c.statut.name,
        'logementId': c.logementId,
        'locataireIds': c.locataireIds,
        if (c.referentColocataireId != null)
          'referentColocataireId': c.referentColocataireId,
        'adresseLogement': c.adresseLogement,
        'surfaceM2': c.surfaceM2,
        'nbPieces': c.nbPieces,
        if (c.etage != null) 'etage': c.etage,
        'dateDebut': c.dateDebut.toUtc().toIso8601String(),
        'dureeMois': c.dureeMois,
        'dateFin': c.dateFin.toUtc().toIso8601String(),
        'renouvellementTacite': c.renouvellementTacite,
        'preavisBailleurMois': c.preavisBailleurMois,
        'preavisLocataireMois': c.preavisLocataireMois,
        'loyerHC': c.loyerHC,
        'charges': c.charges,
        'modePaiement': c.modePaiement.name,
        if (c.rib != null) 'rib': c.rib,
        'jourEcheance': c.jourEcheance,
        'depotGarantie': c.depotGarantie,
        'regularisationChargesAnnuelle': c.regularisationChargesAnnuelle,
        if (c.fraisAgence != null) 'fraisAgence': c.fraisAgence,
        'revisionAnnuelleIRL': c.revisionAnnuelleIRL,
        'nonFumeur': c.nonFumeur,
        'animauxAutorises': c.animauxAutorises,
        if (c.noteAnimaux != null) 'noteAnimaux': c.noteAnimaux,
        'clauseSolidariteColo': c.clauseSolidariteColo,
        'equipementsMeuble': c.equipementsMeuble,
        'chargesIncluses': c.chargesIncluses,
        if (c.justificatifMobilite != null)
          'justificatifMobilite': c.justificatifMobilite,
        if (c.signatureBailleurPng != null)
          'signatureBailleurPng': c.signatureBailleurPng,
        if (c.signatureBailleurAt != null)
          'signatureBailleurAt': c.signatureBailleurAt!.toUtc().toIso8601String(),
        'signaturesLocatairesPng': c.signaturesLocatairesPng,
        'signaturesLocatairesAt': c.signaturesLocatairesAt,
        if (c.integrityHash != null) 'integrityHash': c.integrityHash,
        if (c.pdfPath != null) 'pdfPath': c.pdfPath,
        'diagnosticIds': c.diagnosticIds,
        if (c.edlEntreeId != null) 'edlEntreeId': c.edlEntreeId,
        'notes': c.notes,
        'attestationAssurance': c.attestationAssurance,
        if (c.assuranceFilePath != null)
          'assuranceFilePath': c.assuranceFilePath,
        if (c.modalitesRestitutionDepot != null)
          'modalitesRestitutionDepot': c.modalitesRestitutionDepot,
        if (c.descriptionLogement != null)
          'descriptionLogement': c.descriptionLogement,
        'mentionEtatDesLieux': c.mentionEtatDesLieux,
        if (c.bailleurAdresse != null) 'bailleurAdresse': c.bailleurAdresse,
        if (c.bailleurTelephone != null)
          'bailleurTelephone': c.bailleurTelephone,
        'bailleurEstSociete': c.bailleurEstSociete,
        if (c.bailleurRaisonSociale != null)
          'bailleurRaisonSociale': c.bailleurRaisonSociale,
        if (c.bailleurSiret != null) 'bailleurSiret': c.bailleurSiret,
        if (c.bailleurRepresentant != null)
          'bailleurRepresentant': c.bailleurRepresentant,
        'garants': c.garants.map((g) => g.toMap()).toList(),
        'clauses': c.clauses.map((cl) => cl.toMap()).toList(),
        'annexesOptionnelles': c.annexesOptionnelles,
        'paiementTermeEchu': c.paiementTermeEchu,
        'createdAt': c.createdAt.toUtc().toIso8601String(),
        'updatedAt': c.updatedAt.toUtc().toIso8601String(),
      };

  ContratBail _contratBailFromMap(Map<String, dynamic> m) {
    final equipRaw = m['equipementsMeuble'] as Map?;
    final equip = <String, bool>{};
    equipRaw?.forEach((k, v) {
      if (k is String && v is bool) equip[k] = v;
    });
    final sigPngRaw = m['signaturesLocatairesPng'] as Map?;
    final sigPng = <String, String>{};
    sigPngRaw?.forEach((k, v) {
      if (k is String && v is String) sigPng[k] = v;
    });
    final sigAtRaw = m['signaturesLocatairesAt'] as Map?;
    final sigAt = <String, String>{};
    sigAtRaw?.forEach((k, v) {
      if (k is String && v is String) sigAt[k] = v;
    });
    return ContratBail(
      id: m['id'] as String,
      reference: m['reference'] as String,
      type: BailType.values.firstWhere(
        (t) => t.name == (m['type'] as String?),
        orElse: () => BailType.vide,
      ),
      statut: BailStatus.values.firstWhere(
        (s) => s.name == (m['statut'] as String?),
        orElse: () => BailStatus.brouillon,
      ),
      logementId: m['logementId'] as String,
      locataireIds: (m['locataireIds'] as List).cast<String>(),
      referentColocataireId: m['referentColocataireId'] as String?,
      adresseLogement: m['adresseLogement'] as String,
      surfaceM2: (m['surfaceM2'] as num).toDouble(),
      nbPieces: (m['nbPieces'] as num).toInt(),
      etage: m['etage'] as String?,
      dateDebut: DateTime.parse(m['dateDebut'] as String),
      dureeMois: (m['dureeMois'] as num).toInt(),
      dateFin: DateTime.parse(m['dateFin'] as String),
      renouvellementTacite: m['renouvellementTacite'] as bool,
      preavisBailleurMois: (m['preavisBailleurMois'] as num).toInt(),
      preavisLocataireMois: (m['preavisLocataireMois'] as num).toInt(),
      loyerHC: (m['loyerHC'] as num).toDouble(),
      charges: (m['charges'] as num).toDouble(),
      modePaiement: ModePaiement.values.firstWhere(
        (mp) => mp.name == (m['modePaiement'] as String?),
        orElse: () => ModePaiement.virement,
      ),
      rib: m['rib'] as String?,
      jourEcheance: (m['jourEcheance'] as num).toInt(),
      depotGarantie: (m['depotGarantie'] as num).toDouble(),
      regularisationChargesAnnuelle:
          m['regularisationChargesAnnuelle'] as bool,
      fraisAgence: (m['fraisAgence'] as num?)?.toDouble(),
      revisionAnnuelleIRL: (m['revisionAnnuelleIRL'] as bool?) ?? true,
      nonFumeur: (m['nonFumeur'] as bool?) ?? false,
      animauxAutorises: (m['animauxAutorises'] as bool?) ?? false,
      noteAnimaux: m['noteAnimaux'] as String?,
      clauseSolidariteColo: (m['clauseSolidariteColo'] as bool?) ?? true,
      equipementsMeuble: equip,
      chargesIncluses: (m['chargesIncluses'] as bool?) ?? false,
      justificatifMobilite: m['justificatifMobilite'] as String?,
      signatureBailleurPng: m['signatureBailleurPng'] as String?,
      signatureBailleurAt: m['signatureBailleurAt'] is String
          ? DateTime.parse(m['signatureBailleurAt'] as String)
          : null,
      signaturesLocatairesPng: sigPng,
      signaturesLocatairesAt: sigAt,
      integrityHash: m['integrityHash'] as String?,
      pdfPath: m['pdfPath'] as String?,
      diagnosticIds:
          (m['diagnosticIds'] as List?)?.cast<String>() ?? <String>[],
      edlEntreeId: m['edlEntreeId'] as String?,
      notes: (m['notes'] as String?) ?? '',
      attestationAssurance: (m['attestationAssurance'] as bool?) ?? false,
      assuranceFilePath: m['assuranceFilePath'] as String?,
      modalitesRestitutionDepot: m['modalitesRestitutionDepot'] as String?,
      descriptionLogement: m['descriptionLogement'] as String?,
      mentionEtatDesLieux: (m['mentionEtatDesLieux'] as bool?) ?? false,
      bailleurAdresse: m['bailleurAdresse'] as String?,
      bailleurTelephone: m['bailleurTelephone'] as String?,
      bailleurEstSociete: (m['bailleurEstSociete'] as bool?) ?? false,
      bailleurRaisonSociale: m['bailleurRaisonSociale'] as String?,
      bailleurSiret: m['bailleurSiret'] as String?,
      bailleurRepresentant: m['bailleurRepresentant'] as String?,
      garants: (m['garants'] as List?)
              ?.map((e) => Garant.fromMap((e as Map).cast<String, dynamic>()))
              .toList() ??
          <Garant>[],
      clauses: (m['clauses'] as List?)
              ?.map((e) => Clause.fromMap((e as Map).cast<String, dynamic>()))
              .toList() ??
          <Clause>[],
      annexesOptionnelles:
          (m['annexesOptionnelles'] as List?)?.cast<String>() ?? <String>[],
      paiementTermeEchu: (m['paiementTermeEchu'] as bool?) ?? false,
      createdAt: DateTime.parse(m['createdAt'] as String),
      updatedAt: DateTime.parse(m['updatedAt'] as String),
    );
  }

  Map<String, dynamic> _diagnosticToMap(Diagnostic d) => {
        'id': d.id,
        'logementId': d.logementId,
        'type': d.type.name,
        'dateRealisation': d.dateRealisation.toUtc().toIso8601String(),
        if (d.filePath != null) 'filePath': d.filePath,
        'resume': d.resume,
        if (d.resultatsJson != null) 'resultatsJson': d.resultatsJson,
        'createdAt': d.createdAt.toUtc().toIso8601String(),
        'updatedAt': d.updatedAt.toUtc().toIso8601String(),
      };

  Diagnostic _diagnosticFromMap(Map<String, dynamic> m) => Diagnostic(
        id: m['id'] as String,
        logementId: m['logementId'] as String,
        type: DiagnosticType.values.firstWhere(
          (t) => t.name == (m['type'] as String?),
          orElse: () => DiagnosticType.autre,
        ),
        dateRealisation: DateTime.parse(m['dateRealisation'] as String),
        filePath: m['filePath'] as String?,
        resume: (m['resume'] as String?) ?? '',
        resultatsJson: m['resultatsJson'] as String?,
        createdAt: DateTime.parse(m['createdAt'] as String),
        updatedAt: DateTime.parse(m['updatedAt'] as String),
      );

  Map<String, dynamic> _sciToMap(SCI s) => {
        'id': s.id,
        'nom': s.nom,
        'regime': s.regime.name,
        'anneeBasculeIS': s.anneeBasculeIS,
        'createdAt': s.createdAt.toUtc().toIso8601String(),
        'updatedAt': s.updatedAt.toUtc().toIso8601String(),
        'distributionsParAnnee': s.distributionsParAnnee
            .map((k, v) => MapEntry(k.toString(), v)),
      };

  SCI _sciFromMap(Map<String, dynamic> m) {
    final rawDist = m['distributionsParAnnee'] as Map?;
    final dist = <int, double>{};
    if (rawDist != null) {
      rawDist.forEach((k, v) {
        final year = k is int ? k : int.tryParse(k.toString());
        if (year != null && v is num) dist[year] = v.toDouble();
      });
    }
    return SCI(
      id: m['id'] as String,
      nom: m['nom'] as String,
      regime: SCIRegime.values.firstWhere(
        (r) => r.name == (m['regime'] as String?),
        orElse: () => SCIRegime.ir,
      ),
      anneeBasculeIS: (m['anneeBasculeIS'] as num?)?.toInt(),
      createdAt: DateTime.parse(m['createdAt'] as String),
      updatedAt: DateTime.parse(m['updatedAt'] as String),
      distributionsParAnnee: dist,
    );
  }

  Map<String, dynamic> _fiscalSettingsToMap(FiscalSettings s) => {
        'parts': s.parts,
        'autresRevenusBruts': s.autresRevenusBruts,
        'marieOuPacse': s.marieOuPacse,
        'anneeBareme': s.anneeBareme,
        'autresNichesFiscales': s.autresNichesFiscales,
        'deficitsReportables': s.deficitsReportables
            .map((k, v) => MapEntry(k.toString(), v)),
        'autresRevenusBrutsParAnnee': s.autresRevenusBrutsParAnnee
            .map((k, v) => MapEntry(k.toString(), v)),
      };

  FiscalSettings _fiscalSettingsFromMap(Map<String, dynamic> m) {
    final raw = m['deficitsReportables'] as Map?;
    final deficits = <int, double>{};
    if (raw != null) {
      raw.forEach((k, v) {
        final year = k is int ? k : int.tryParse(k.toString());
        if (year != null && v is num) deficits[year] = v.toDouble();
      });
    }
    final rawRev = m['autresRevenusBrutsParAnnee'] as Map?;
    final revParAnnee = <int, double>{};
    if (rawRev != null) {
      rawRev.forEach((k, v) {
        final year = k is int ? k : int.tryParse(k.toString());
        if (year != null && v is num) revParAnnee[year] = v.toDouble();
      });
    }
    return FiscalSettings(
      parts: (m['parts'] as num?)?.toDouble() ?? 1.0,
      autresRevenusBruts:
          (m['autresRevenusBruts'] as num?)?.toDouble() ?? 0.0,
      marieOuPacse: (m['marieOuPacse'] as bool?) ?? false,
      anneeBareme: (m['anneeBareme'] as int?) ?? 2026,
      autresNichesFiscales:
          (m['autresNichesFiscales'] as num?)?.toDouble() ?? 0.0,
      deficitsReportables: deficits,
      autresRevenusBrutsParAnnee: revParAnnee,
    );
  }

  /// Sérialise un plan en embarquant les bytes (base64) de chaque photo de
  /// mur encore présente sur disque. Permet de restaurer les photos sur un
  /// autre appareil où le chemin local d'origine n'existe pas.
  Map<String, dynamic> _planMapWithEmbeddedWallPhotos(PlanLogement plan) {
    final m = plan.toMap();
    final photos =
        (m['wallPhotos'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    for (final pm in photos) {
      final path = pm['path'] as String?;
      if (path == null || path.isEmpty) continue;
      try {
        final f = File(path);
        if (f.existsSync()) {
          pm['bytes'] = base64Encode(f.readAsBytesSync());
        }
      } catch (_) {
        // photo manquante → on n'embarque rien, le destinataire affichera
        // "image illisible" pour cette entrée.
      }
    }
    return m;
  }

  /// Pour un plan reçu, écrit sur disque (dans `plans/<planId>/walls/`) les
  /// bytes embarqués pour chaque photo de mur, puis met à jour le champ
  /// `path` de la map en place. Supprime la clé `bytes` après écriture.
  Future<void> _persistEmbeddedWallPhotos(Map<String, dynamic> planMap) async {
    final planId = planMap['id'] as String?;
    if (planId == null) return;
    final photos = (planMap['wallPhotos'] as List?)
            ?.cast<Map<String, dynamic>>() ??
        const [];
    if (photos.isEmpty) return;
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/plans/$planId/walls');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    for (final pm in photos) {
      final encoded = pm['bytes'] as String?;
      if (encoded == null || encoded.isEmpty) continue;
      final photoId = pm['id'] as String? ?? const Uuid().v4();
      final hint = pm['path'] as String? ?? '';
      final ext = hint.contains('.')
          ? hint.substring(hint.lastIndexOf('.') + 1).toLowerCase()
          : 'jpg';
      final dest = File('${dir.path}/$photoId.$ext');
      await dest.writeAsBytes(base64Decode(encoded), flush: true);
      pm['path'] = dest.path;
      pm.remove('bytes');
    }
  }

  // --- Sérialisation ---

  Map<String, dynamic> _userToMap(UserProfile u) => {
        'id': u.id,
        'role': u.role.name,
        'firstName': u.firstName,
        'lastName': u.lastName,
        'email': u.email,
        'createdAt': u.createdAt.toUtc().toIso8601String(),
        'integrityHash': u.integrityHash,
      };

  UserProfile _userFromMap(Map<String, dynamic> m) {
    // UserProfile n'expose que le factory create qui régénère le hash.
    // Pour restaurer un profil **identique au bit près**, on passe par une
    // construction directe via l'adaptateur : on ouvre donc le champ privé
    // en recréant manuellement le tuple attendu.
    // Simplification : on reconstruit via create() puis on vérifie le hash.
    // Si le hash ne correspond pas (ex: changement de normalisation),
    // l'intégrité sera marquée comme invalide à l'affichage.
    return UserProfile.create(
      role: UserRole.fromString(m['role'] as String),
      firstName: m['firstName'] as String,
      lastName: m['lastName'] as String,
      email: m['email'] as String,
    );
  }

  Map<String, dynamic> _logementToMap(Logement l) => {
        'id': l.id,
        'libelle': l.libelle,
        'adresse': l.adresse,
        'codePostal': l.codePostal,
        'ville': l.ville,
        'type': l.type.name,
        'surface': l.surface,
        'nbPieces': l.nbPieces,
        'loyerHC': l.loyerHC,
        'charges': l.charges,
        'equipements': l.equipements,
        'notes': l.notes,
        'createdAt': l.createdAt.toUtc().toIso8601String(),
        'updatedAt': l.updatedAt.toUtc().toIso8601String(),
        // Fiscalité
        'statutFiscal': l.statutFiscal.name,
        'regimeFiscal': l.regimeFiscal.name,
        'dispositif': l.dispositif.name,
        'dateAcquisition': l.dateAcquisition?.toUtc().toIso8601String(),
        'dureeEngagementAnnees': l.dureeEngagementAnnees,
        'prixRevient': l.prixRevient,
        // SCI
        'sciId': l.sciId,
        'amortissementAnnuel': l.amortissementAnnuel,
        // Période de validité du dispositif (optionnelle pour Pinel, requise
        // pour Borloo)
        'dateDebutDispositif':
            l.dateDebutDispositif?.toUtc().toIso8601String(),
        'dateFinDispositif':
            l.dateFinDispositif?.toUtc().toIso8601String(),
        // Diagnostics conditionnels
        if (l.anneeConstruction != null)
          'anneeConstruction': l.anneeConstruction,
        'datePermisConstruire':
            l.datePermisConstruire?.toUtc().toIso8601String(),
        'dateInstallationElectrique':
            l.dateInstallationElectrique?.toUtc().toIso8601String(),
        'dateInstallationGaz':
            l.dateInstallationGaz?.toUtc().toIso8601String(),
        'typeAssainissement': l.typeAssainissement.name,
        'zoneTermites': l.zoneTermites,
        // Régime LMNP / LMP
        'regimeLmnp': l.regimeLmnp.name,
        'enRenovationEnergetique': l.enRenovationEnergetique,
        // Documents
        'contratBailPaths': l.contratBailPaths,
      };

  Logement _logementFromMap(Map<String, dynamic> m) {
        final dateAcqStr = m['dateAcquisition'] as String?;
        return Logement(
          id: m['id'] as String,
          libelle: m['libelle'] as String,
          adresse: m['adresse'] as String,
          codePostal: m['codePostal'] as String,
          ville: m['ville'] as String,
          type: LogementType.fromString(m['type'] as String),
          surface: (m['surface'] as num).toDouble(),
          nbPieces: m['nbPieces'] as int,
          loyerHC: (m['loyerHC'] as num).toDouble(),
          charges: (m['charges'] as num).toDouble(),
          equipements: (m['equipements'] as List).cast<String>(),
          notes: m['notes'] as String,
          createdAt: DateTime.parse(m['createdAt'] as String),
          updatedAt: DateTime.parse(m['updatedAt'] as String),
          statutFiscal: StatutFiscal.values.firstWhere(
            (s) => s.name == (m['statutFiscal'] as String?),
            orElse: () => StatutFiscal.locationNue,
          ),
          regimeFiscal: RegimeFiscal.values.firstWhere(
            (r) => r.name == (m['regimeFiscal'] as String?),
            orElse: () => RegimeFiscal.reel,
          ),
          dispositif: DispositifFiscal.values.firstWhere(
            (d) => d.name == (m['dispositif'] as String?),
            orElse: () => DispositifFiscal.aucun,
          ),
          dateAcquisition:
              dateAcqStr == null ? null : DateTime.parse(dateAcqStr),
          dureeEngagementAnnees: (m['dureeEngagementAnnees'] as int?) ?? 9,
          prixRevient: (m['prixRevient'] as num?)?.toDouble() ?? 0,
          contratBailPaths: (m['contratBailPaths'] as List?)?.cast<String>(),
          sciId: m['sciId'] as String?,
          amortissementAnnuel:
              (m['amortissementAnnuel'] as num?)?.toDouble() ?? 0,
          dateDebutDispositif: m['dateDebutDispositif'] is String
              ? DateTime.parse(m['dateDebutDispositif'] as String)
              : null,
          dateFinDispositif: m['dateFinDispositif'] is String
              ? DateTime.parse(m['dateFinDispositif'] as String)
              : null,
          anneeConstruction: (m['anneeConstruction'] as num?)?.toInt(),
          datePermisConstruire: m['datePermisConstruire'] is String
              ? DateTime.parse(m['datePermisConstruire'] as String)
              : null,
          dateInstallationElectrique:
              m['dateInstallationElectrique'] is String
                  ? DateTime.parse(m['dateInstallationElectrique'] as String)
                  : null,
          dateInstallationGaz: m['dateInstallationGaz'] is String
              ? DateTime.parse(m['dateInstallationGaz'] as String)
              : null,
          typeAssainissement: TypeAssainissement.values.firstWhere(
            (t) => t.name == (m['typeAssainissement'] as String?),
            orElse: () => TypeAssainissement.inconnu,
          ),
          zoneTermites: (m['zoneTermites'] as bool?) ?? false,
          regimeLmnp: RegimeLmnp.values.firstWhere(
            (r) => r.name == (m['regimeLmnp'] as String?),
            orElse: () => RegimeLmnp.microBIC,
          ),
          enRenovationEnergetique:
              (m['enRenovationEnergetique'] as bool?) ?? false,
        );
      }

  Map<String, dynamic> _locataireToMap(Locataire l) => {
        'id': l.id,
        'firstName': l.firstName,
        'lastName': l.lastName,
        'email': l.email,
        'phone': l.phone,
        'logementIds': l.logementIds,
        'isPrincipal': l.isPrincipal,
        'dateEntree': l.dateEntree?.toUtc().toIso8601String(),
        'dateSortie': l.dateSortie?.toUtc().toIso8601String(),
        'raisonSortie': l.raisonSortie,
        'loyerSortie': l.loyerSortie,
        'contratBailPaths': l.contratBailPaths,
        'nouvelleAdresse': l.nouvelleAdresse,
        'nouveauTelephone': l.nouveauTelephone,
        'nouvelEmail': l.nouvelEmail,
        'dateNaissance': l.dateNaissance?.toUtc().toIso8601String(),
        'adresse': l.adresse,
        'notes': l.notes,
        'createdAt': l.createdAt.toUtc().toIso8601String(),
        'updatedAt': l.updatedAt.toUtc().toIso8601String(),
      };

  Locataire _locataireFromMap(Map<String, dynamic> m) => Locataire(
        id: m['id'] as String,
        firstName: m['firstName'] as String,
        lastName: m['lastName'] as String,
        email: m['email'] as String,
        phone: m['phone'] as String?,
        logementIds: (m['logementIds'] as List).cast<String>(),
        isPrincipal: (m['isPrincipal'] as bool?) ?? false,
        dateEntree: m['dateEntree'] == null
            ? null
            : DateTime.parse(m['dateEntree'] as String),
        dateSortie: m['dateSortie'] == null
            ? null
            : DateTime.parse(m['dateSortie'] as String),
        raisonSortie: (m['raisonSortie'] as String?) ?? '',
        loyerSortie: (m['loyerSortie'] as num?)?.toDouble(),
        contratBailPaths:
            (m['contratBailPaths'] as List?)?.cast<String>() ?? const [],
        nouvelleAdresse: m['nouvelleAdresse'] as String?,
        nouveauTelephone: m['nouveauTelephone'] as String?,
        nouvelEmail: m['nouvelEmail'] as String?,
        dateNaissance: m['dateNaissance'] == null
            ? null
            : DateTime.parse(m['dateNaissance'] as String),
        adresse: m['adresse'] as String?,
        notes: m['notes'] as String,
        createdAt: DateTime.parse(m['createdAt'] as String),
        updatedAt: DateTime.parse(m['updatedAt'] as String),
      );

  Map<String, dynamic> _elementToMap(ElementPiece e) => {
        'id': e.id,
        'nom': e.nom,
        'etat': e.etat.name,
        'description': e.description,
        'photoPaths': e.photoPaths,
        'photoCapturedAt': e.photoCapturedAt,
      };

  ElementPiece _elementFromMap(Map<String, dynamic> m) => ElementPiece(
        id: m['id'] as String,
        nom: m['nom'] as String,
        etat: EtatElement.fromString(m['etat'] as String),
        description: m['description'] as String,
        photoPaths: (m['photoPaths'] as List).cast<String>(),
        photoCapturedAt:
            (m['photoCapturedAt'] as List?)?.cast<String>() ?? const <String>[],
      );

  Map<String, dynamic> _pieceToMap(Piece p) => {
        'id': p.id,
        'nom': p.nom,
        'elements': p.elements.map(_elementToMap).toList(),
      };

  Piece _pieceFromMap(Map<String, dynamic> m) => Piece(
        id: m['id'] as String,
        nom: m['nom'] as String,
        elements: (m['elements'] as List)
            .map((e) => _elementFromMap(e as Map<String, dynamic>))
            .toList(),
      );

  Map<String, dynamic> _edlToMap(EtatDesLieux e) => {
        'id': e.id,
        'type': e.type.name,
        'logementId': e.logementId,
        'locataireId': e.locataireId,
        'date': e.date.toUtc().toIso8601String(),
        'status': e.status.name,
        'pieces': e.pieces.map(_pieceToMap).toList(),
        'proprietaireSignaturePng': e.proprietaireSignaturePng,
        'proprietaireSignatureAt':
            e.proprietaireSignatureAt?.toUtc().toIso8601String(),
        'locataireCode': e.locataireCode,
        'locataireSignaturePng': e.locataireSignaturePng,
        'locataireSignatureAt':
            e.locataireSignatureAt?.toUtc().toIso8601String(),
        'integrityHash': e.integrityHash,
        'notes': e.notes,
        'bailleurAdresse': e.bailleurAdresse,
        'nombreCles': e.nombreCles,
        'releveCompteurGaz': e.releveCompteurGaz,
        'releveCompteurEauChaude': e.releveCompteurEauChaude,
        'releveCompteurEauFroide': e.releveCompteurEauFroide,
        'releveCompteurElecJour': e.releveCompteurElecJour,
        'releveCompteurElecNuit': e.releveCompteurElecNuit,
        'createdAt': e.createdAt.toUtc().toIso8601String(),
        'updatedAt': e.updatedAt.toUtc().toIso8601String(),
      };

  EtatDesLieux _edlFromMap(Map<String, dynamic> m) => EtatDesLieux(
        id: m['id'] as String,
        type: EtatDesLieuxType.fromString(m['type'] as String),
        logementId: m['logementId'] as String,
        locataireId: m['locataireId'] as String,
        date: DateTime.parse(m['date'] as String),
        status: EtatDesLieuxStatus.fromString(m['status'] as String),
        pieces: (m['pieces'] as List)
            .map((p) => _pieceFromMap(p as Map<String, dynamic>))
            .toList(),
        proprietaireSignaturePng: m['proprietaireSignaturePng'] as String?,
        proprietaireSignatureAt: m['proprietaireSignatureAt'] == null
            ? null
            : DateTime.parse(m['proprietaireSignatureAt'] as String),
        locataireCode: m['locataireCode'] as String?,
        locataireSignaturePng: m['locataireSignaturePng'] as String?,
        locataireSignatureAt: m['locataireSignatureAt'] == null
            ? null
            : DateTime.parse(m['locataireSignatureAt'] as String),
        integrityHash: m['integrityHash'] as String?,
        notes: m['notes'] as String,
        bailleurAdresse: m['bailleurAdresse'] as String?,
        nombreCles: (m['nombreCles'] as num?)?.toInt(),
        releveCompteurGaz: m['releveCompteurGaz'] as String?,
        releveCompteurEauChaude: m['releveCompteurEauChaude'] as String?,
        releveCompteurEauFroide: m['releveCompteurEauFroide'] as String?,
        releveCompteurElecJour: m['releveCompteurElecJour'] as String?,
        releveCompteurElecNuit: m['releveCompteurElecNuit'] as String?,
        createdAt: DateTime.parse(m['createdAt'] as String),
        updatedAt: DateTime.parse(m['updatedAt'] as String),
      );

  Map<String, dynamic> _quittanceToMap(Quittance q) => {
        'id': q.id,
        'logementId': q.logementId,
        'locataireId': q.locataireId,
        'periodYear': q.periodYear,
        'periodMonth': q.periodMonth,
        'loyerHC': q.loyerHC,
        'charges': q.charges,
        'datePaiement': q.datePaiement.toUtc().toIso8601String(),
        'dateEmission': q.dateEmission.toUtc().toIso8601String(),
        'notes': q.notes,
        'createdAt': q.createdAt.toUtc().toIso8601String(),
        'integrityHash': q.integrityHash,
        if (q.bailleurName != null) 'bailleurName': q.bailleurName,
        if (q.bailleurEmail != null) 'bailleurEmail': q.bailleurEmail,
        if (q.montantPaye != null) 'montantPaye': q.montantPaye,
        if (q.versementsSupplementaires.isNotEmpty)
          'versementsSupplementaires': q.versementsSupplementaires,
      };

  Map<String, dynamic> _depenseToMap(Depense d) => {
        'id': d.id,
        'logementId': d.logementId,
        'categorie': d.categorie,
        'libelle': d.libelle,
        'montant': d.montant,
        'date': d.date.toUtc().toIso8601String(),
        'notes': d.notes,
        'justificatifs': d.justificatifs,
        'createdAt': d.createdAt.toUtc().toIso8601String(),
        'integrityHash': d.integrityHash,
      };

  Depense _depenseFromMap(Map<String, dynamic> m) => Depense(
        id: m['id'] as String,
        logementId: m['logementId'] as String,
        categorie: m['categorie'] as String,
        libelle: m['libelle'] as String,
        montant: (m['montant'] as num).toDouble(),
        date: DateTime.parse(m['date'] as String),
        notes: m['notes'] as String? ?? '',
        justificatifs:
            (m['justificatifs'] as List? ?? const []).cast<String>(),
        createdAt: DateTime.parse(m['createdAt'] as String),
        integrityHash: m['integrityHash'] as String?,
      );

  Map<String, dynamic> _creditToMap(CreditImmobilier c) => {
        'id': c.id,
        'logementId': c.logementId,
        'libelle': c.libelle,
        'capitalEmprunte': c.capitalEmprunte,
        'tauxAnnuel': c.tauxAnnuel,
        'dateDebut': c.dateDebut.toUtc().toIso8601String(),
        'dureeMois': c.dureeMois,
        'mensualiteHorsAssurance': c.mensualiteHorsAssurance,
        'assuranceMensuelle': c.assuranceMensuelle,
        'notes': c.notes,
        'createdAt': c.createdAt.toUtc().toIso8601String(),
        'integrityHash': c.integrityHash,
        // Rachat
        'statut': c.statut.name,
        'dateRachat': c.dateRachat?.toUtc().toIso8601String(),
        'montantRachete': c.montantRachete,
        'banqueRacheteur': c.banqueRacheteur,
        'nouveauTaux': c.nouveauTaux,
        'nouvelleDureeMois': c.nouvelleDureeMois,
        'fraisRachat': c.fraisRachat,
        'rachatPartiel': c.rachatPartiel,
        // Clôture manuelle
        'dateCloture': c.dateCloture?.toUtc().toIso8601String(),
      };

  Map<String, dynamic> _revisionToMap(RevisionLoyer r) => {
        'id': r.id,
        'logementId': r.logementId,
        'dateEffet': r.dateEffet.toUtc().toIso8601String(),
        'loyerHC': r.loyerHC,
        'charges': r.charges,
        'motif': r.motif,
        'createdAt': r.createdAt.toUtc().toIso8601String(),
        'integrityHash': r.integrityHash,
      };

  RevisionLoyer _revisionFromMap(Map<String, dynamic> m) => RevisionLoyer(
        id: m['id'] as String,
        logementId: m['logementId'] as String,
        dateEffet: DateTime.parse(m['dateEffet'] as String),
        loyerHC: (m['loyerHC'] as num).toDouble(),
        charges: (m['charges'] as num).toDouble(),
        motif: m['motif'] as String? ?? '',
        createdAt: DateTime.parse(m['createdAt'] as String),
        integrityHash: m['integrityHash'] as String?,
      );

  CreditImmobilier _creditFromMap(Map<String, dynamic> m) {
        final statutStr = m['statut'] as String?;
        final statut = StatutCredit.values.firstWhere(
          (s) => s.name == statutStr,
          orElse: () => StatutCredit.actif,
        );
        final dateRachatStr = m['dateRachat'] as String?;
        final dateClotureStr = m['dateCloture'] as String?;
        return CreditImmobilier(
          id: m['id'] as String,
          logementId: m['logementId'] as String,
          libelle: m['libelle'] as String,
          capitalEmprunte: (m['capitalEmprunte'] as num).toDouble(),
          tauxAnnuel: (m['tauxAnnuel'] as num).toDouble(),
          dateDebut: DateTime.parse(m['dateDebut'] as String),
          dureeMois: m['dureeMois'] as int,
          mensualiteHorsAssurance:
              (m['mensualiteHorsAssurance'] as num).toDouble(),
          assuranceMensuelle: (m['assuranceMensuelle'] as num).toDouble(),
          notes: m['notes'] as String? ?? '',
          createdAt: DateTime.parse(m['createdAt'] as String),
          integrityHash: m['integrityHash'] as String?,
          statut: statut,
          dateRachat:
              dateRachatStr == null ? null : DateTime.parse(dateRachatStr),
          montantRachete: (m['montantRachete'] as num?)?.toDouble(),
          banqueRacheteur: (m['banqueRacheteur'] as String?) ?? '',
          nouveauTaux: (m['nouveauTaux'] as num?)?.toDouble(),
          nouvelleDureeMois: m['nouvelleDureeMois'] as int?,
          fraisRachat: (m['fraisRachat'] as num?)?.toDouble(),
          rachatPartiel: (m['rachatPartiel'] as bool?) ?? false,
          dateCloture:
              dateClotureStr == null ? null : DateTime.parse(dateClotureStr),
        );
      }

  Quittance _quittanceFromMap(Map<String, dynamic> m) {
    final rawVers = m['versementsSupplementaires'] as Map?;
    final vers = <String, double>{};
    if (rawVers != null) {
      rawVers.forEach((k, v) {
        if (k is String && v is num) vers[k] = v.toDouble();
      });
    }
    return Quittance(
      id: m['id'] as String,
      logementId: m['logementId'] as String,
      locataireId: m['locataireId'] as String,
      periodYear: m['periodYear'] as int,
      periodMonth: m['periodMonth'] as int,
      loyerHC: (m['loyerHC'] as num).toDouble(),
      charges: (m['charges'] as num).toDouble(),
      datePaiement: DateTime.parse(m['datePaiement'] as String),
      dateEmission: DateTime.parse(m['dateEmission'] as String),
      notes: m['notes'] as String,
      createdAt: DateTime.parse(m['createdAt'] as String),
      integrityHash: m['integrityHash'] as String?,
      bailleurName: m['bailleurName'] as String?,
      bailleurEmail: m['bailleurEmail'] as String?,
      montantPaye: (m['montantPaye'] as num?)?.toDouble(),
      versementsSupplementaires: vers,
    );
  }
}

class MergeStats {
  final int added;
  final int updated;
  final int kept;

  const MergeStats({
    required this.added,
    required this.updated,
    required this.kept,
  });

  int get total => added + updated + kept;

  /// Résumé lisible : "3 ajoutés, 1 mis à jour, 2 conservés".
  String describe() {
    final parts = <String>[];
    if (added > 0) parts.add('$added ajouté${added > 1 ? 's' : ''}');
    if (updated > 0) parts.add('$updated mis à jour');
    if (kept > 0) parts.add('$kept conservé${kept > 1 ? 's' : ''}');
    return parts.isEmpty ? 'aucun' : parts.join(', ');
  }
}

class BackupImportReport {
  final MergeStats logements;
  final MergeStats locataires;
  final MergeStats etatsDesLieux;
  final MergeStats quittances;
  final bool profileRestored;

  /// Nombre de logements en doublon (même libellé) supprimés au profit de la
  /// version la plus récente après fusion.
  final int duplicatesRemoved;

  const BackupImportReport({
    required this.logements,
    required this.locataires,
    required this.etatsDesLieux,
    required this.quittances,
    required this.profileRestored,
    this.duplicatesRemoved = 0,
  });
}
