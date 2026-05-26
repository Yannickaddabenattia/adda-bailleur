import 'package:flutter/foundation.dart';

import '../core/storage/local_database.dart';
import '../models/depense.dart';

/// Catégories de dépense extensibles : par défaut + ajoutées par l'utilisateur.
class ExpenseCategoriesService extends ChangeNotifier {
  /// Retourne la liste fusionnée et triée alphabétiquement.
  /// "Autre" est toujours placée en dernier.
  List<String> get all {
    final box = LocalDatabase.customExpenseCategoriesBox;
    final set = <String>{...ExpenseCategories.defaults, ...box.values};
    final list = set.toList();
    list.sort((a, b) {
      if (a == ExpenseCategories.autre) return 1;
      if (b == ExpenseCategories.autre) return -1;
      return a.toLowerCase().compareTo(b.toLowerCase());
    });
    return list;
  }

  bool isDefault(String name) =>
      ExpenseCategories.defaults.contains(name.trim());

  Future<void> add(String name) async {
    final clean = name.trim();
    if (clean.isEmpty) return;
    if (ExpenseCategories.defaults.contains(clean)) return;
    final box = LocalDatabase.customExpenseCategoriesBox;
    if (box.values.contains(clean)) return;
    await box.add(clean);
    notifyListeners();
  }

  Future<void> remove(String name) async {
    final box = LocalDatabase.customExpenseCategoriesBox;
    final keys = box.keys.where((k) => box.get(k) == name).toList();
    for (final k in keys) {
      await box.delete(k);
    }
    notifyListeners();
  }
}
