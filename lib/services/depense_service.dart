import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../core/storage/local_database.dart';
import '../models/depense.dart';

class DepenseService extends ChangeNotifier {
  static const _justifsDir = 'expense_justifs';

  List<Depense> get all {
    final items = LocalDatabase.depensesBox.values.toList();
    items.sort((a, b) => b.date.compareTo(a.date));
    return items;
  }

  Depense? byId(String id) => LocalDatabase.depensesBox.get(id);

  List<Depense> forLogement(String logementId) =>
      all.where((d) => d.logementId == logementId).toList();

  /// Total des dépenses d'un logement sur une année.
  double totalForLogementYear(String logementId, int year) {
    return forLogement(logementId)
        .where((d) => d.date.year == year)
        .fold<double>(0, (sum, d) => sum + d.montant);
  }

  /// Totaux mensuels (clé 1..12) pour un logement et une année.
  Map<int, double> monthlyTotals(String logementId, int year) {
    final out = <int, double>{};
    for (var m = 1; m <= 12; m++) {
      out[m] = 0;
    }
    for (final d in forLogement(logementId).where((d) => d.date.year == year)) {
      out[d.date.month] = (out[d.date.month] ?? 0) + d.montant;
    }
    return out;
  }

  /// Totaux par catégorie pour un logement et une année.
  Map<String, double> totalsByCategory(String logementId, int year) {
    final out = <String, double>{};
    for (final d in forLogement(logementId).where((d) => d.date.year == year)) {
      out[d.categorie] = (out[d.categorie] ?? 0) + d.montant;
    }
    return out;
  }

  Future<Depense> add(Depense d) async {
    await LocalDatabase.depensesBox.put(d.id, d);
    notifyListeners();
    return d;
  }

  Future<Depense> update(Depense d) async {
    d.integrityHash = d.computeIntegrityHash();
    await LocalDatabase.depensesBox.put(d.id, d);
    notifyListeners();
    return d;
  }

  Future<void> delete(String id) async {
    final d = byId(id);
    if (d != null) {
      for (final path in d.justificatifs) {
        try {
          final f = File(path);
          if (await f.exists()) await f.delete();
        } catch (_) {}
      }
      try {
        final dir = Directory(await _expenseDir(id));
        if (await dir.exists()) await dir.delete(recursive: true);
      } catch (_) {}
    }
    await LocalDatabase.depensesBox.delete(id);
    notifyListeners();
  }

  /// Copie un justificatif (image ou PDF) dans le dossier dédié à la dépense
  /// et renvoie le chemin absolu enregistré.
  Future<String> attachJustificatif(String depenseId, File source) async {
    final dir = Directory(await _expenseDir(depenseId));
    if (!await dir.exists()) await dir.create(recursive: true);
    final dot = source.path.lastIndexOf('.');
    final ext = (dot >= 0 && dot > source.path.lastIndexOf('/'))
        ? source.path.substring(dot)
        : '';
    final dest = File('${dir.path}/${const Uuid().v4()}$ext');
    await source.copy(dest.path);
    return dest.path;
  }

  Future<String> _expenseDir(String depenseId) async {
    final base = await getApplicationDocumentsDirectory();
    return '${base.path}/$_justifsDir/$depenseId';
  }

  int get count => LocalDatabase.depensesBox.length;
}
