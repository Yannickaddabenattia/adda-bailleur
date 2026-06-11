import 'package:intl/intl.dart';

/// Formatage monétaire **par devise du bien** (multi-pays).
///
/// Les montants sont stockés et affichés dans la devise du bien (EUR/CHF),
/// jamais convertis (cf. ARCHITECTURE-MULTIPAYS §4). Le symbole vient du bien,
/// pas de la locale du téléphone.
class CurrencyFormat {
  const CurrencyFormat._();

  static String _symbol(String currencyCode) =>
      currencyCode.toUpperCase() == 'CHF' ? 'CHF' : '€';

  /// Formate [amount] avec le symbole de [currencyCode] (ex. `1 234,50 €`).
  static String format(double amount, String currencyCode, {int decimals = 2}) {
    return NumberFormat.currency(
      locale: 'fr_FR',
      symbol: _symbol(currencyCode),
      decimalDigits: decimals,
    ).format(amount);
  }

  /// Variante sans décimales (montants arrondis).
  static String formatRounded(double amount, String currencyCode) =>
      format(amount, currencyCode, decimals: 0);

  /// Formate un total **groupé par devise** sans jamais additionner des devises
  /// différentes (cf. ARCHITECTURE-MULTIPAYS §4). Ex. `12 400 € + 8 200 CHF`.
  ///
  /// Pour un utilisateur mono-devise (cas courant), le résultat est identique à
  /// [format] sur l'unique devise. EUR est affiché en premier.
  /// [signed] préfixe `+ ` les montants positifs (les négatifs portent déjà le
  /// signe) — utile pour un solde/bilan.
  static String formatByCurrency(
    Map<String, double> byCurrency, {
    bool signed = false,
    String separator = ' + ',
    int decimals = 2,
  }) {
    if (byCurrency.isEmpty) return format(0, 'EUR', decimals: decimals);
    final keys = byCurrency.keys.toList()
      ..sort((a, b) {
        if (a == 'EUR') return -1;
        if (b == 'EUR') return 1;
        return a.compareTo(b);
      });
    return keys.map((c) {
      final v = byCurrency[c]!;
      final formatted = format(v, c, decimals: decimals);
      return signed && v >= 0 ? '+ $formatted' : formatted;
    }).join(separator);
  }
}
