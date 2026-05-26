import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../core/storage/local_database.dart';
import '../models/plan_logement.dart';

class PlanLogementService extends ChangeNotifier {
  /// Tous les plans, triés par ordre d'affichage puis par nom.
  List<PlanLogement> all() {
    final items = LocalDatabase.plansLogementBox.values.toList();
    items.sort((a, b) {
      final c = a.sortOrder.compareTo(b.sortOrder);
      if (c != 0) return c;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return items;
  }

  /// Plans d'un logement, triés.
  List<PlanLogement> byLogement(String logementId) {
    final items = LocalDatabase.plansLogementBox.values
        .where((p) => p.logementId == logementId)
        .toList();
    items.sort((a, b) {
      // Niveaux d'abord, puis dépendances ; ensuite sortOrder ; puis nom.
      final ck = a.kind.index.compareTo(b.kind.index);
      if (ck != 0) return ck;
      final co = a.sortOrder.compareTo(b.sortOrder);
      if (co != 0) return co;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return items;
  }

  PlanLogement? byId(String id) => LocalDatabase.plansLogementBox.get(id);

  Future<PlanLogement> save(PlanLogement plan) async {
    plan.updatedAt = DateTime.now().toUtc();
    await LocalDatabase.plansLogementBox.put(plan.id, plan);
    notifyListeners();
    return plan;
  }

  Future<void> delete(String id) async {
    final plan = byId(id);
    if (plan == null) return;
    if (plan.hasImage) {
      final f = File(plan.imagePath!);
      if (await f.exists()) {
        try {
          await f.delete();
        } catch (_) {}
      }
    }
    await LocalDatabase.plansLogementBox.delete(id);
    notifyListeners();
  }

  /// Copie [source] dans le sous-répertoire `plans/` du sandbox de l'app et
  /// renvoie le chemin local persistant.
  Future<String> persistImportedFile({
    required File source,
    required String planId,
    String? extension,
  }) async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/plans');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final ext = (extension == null || extension.isEmpty)
        ? _guessExt(source.path)
        : extension;
    final dest = File('${dir.path}/$planId.$ext');
    await source.copy(dest.path);
    return dest.path;
  }

  /// Copie une photo de mur dans le sous-répertoire dédié et renvoie le
  /// chemin persistant. Le nom de fichier inclut un horodatage pour rester
  /// unique.
  Future<String> persistWallPhoto({
    required File source,
    required String planId,
    required String photoId,
    String? extension,
  }) async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/plans/$planId/walls');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final ext = (extension == null || extension.isEmpty)
        ? _guessExt(source.path)
        : extension;
    final dest = File('${dir.path}/$photoId.$ext');
    await source.copy(dest.path);
    return dest.path;
  }

  Future<void> deleteWallPhoto(WallPhoto photo) async {
    final f = File(photo.path);
    if (await f.exists()) {
      try {
        await f.delete();
      } catch (_) {}
    }
  }

  /// Supprime toutes les photos de mur taguées avec [etatId] sur tous les
  /// plans de [logementId]. Appelée quand l'EDL associé est supprimé.
  Future<void> deleteWallPhotosForEtat({
    required String logementId,
    required String etatId,
  }) async {
    final plans = LocalDatabase.plansLogementBox.values
        .where((p) => p.logementId == logementId)
        .toList();
    var changed = false;
    for (final plan in plans) {
      final toRemove =
          plan.wallPhotos.where((w) => w.etatId == etatId).toList();
      if (toRemove.isEmpty) continue;
      for (final photo in toRemove) {
        await deleteWallPhoto(photo);
      }
      plan.wallPhotos.removeWhere((w) => w.etatId == etatId);
      plan.updatedAt = DateTime.now().toUtc();
      await LocalDatabase.plansLogementBox.put(plan.id, plan);
      changed = true;
    }
    if (changed) notifyListeners();
  }

  String _guessExt(String path) {
    final dot = path.lastIndexOf('.');
    if (dot < 0 || dot == path.length - 1) return 'bin';
    return path.substring(dot + 1).toLowerCase();
  }
}
