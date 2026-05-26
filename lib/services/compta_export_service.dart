import 'dart:io';

import 'package:csv/csv.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

import '../core/storage/local_database.dart';
import '../models/locataire.dart';
import '../models/logement.dart';

/// Génère un export CSV de toutes les données financières (quittances +
/// dépenses + crédits) sur une période donnée, exploitable par un logiciel
/// de compta tiers (Excel, Numbers, Indy, Quickbooks…).
///
/// Format : 3 sections dans un seul fichier `comptabilite_<year>.csv` :
/// - Quittances (recettes)
/// - Dépenses (sorties courantes)
/// - Crédits (mensualités, intérêts, amortissement)
class ComptaExportService {
  /// Génère le CSV pour [year]. Retourne le chemin du fichier produit.
  Future<String> exportYear(int year) async {
    final df = DateFormat('dd/MM/yyyy');
    final logements = {
      for (final l in LocalDatabase.logementsBox.values) l.id: l,
    };
    final locataires = {
      for (final t in LocalDatabase.locatairesBox.values) t.id: t,
    };

    final rows = <List<dynamic>>[];

    // En-tête général
    rows.add([
      'Type',
      'Date',
      'Logement',
      'Adresse',
      'Locataire',
      'Catégorie / Période',
      'Libellé / Notes',
      'Montant (€)',
      'Loyer HC (€)',
      'Charges (€)',
      'Réf / Hash',
    ]);

    // --- Quittances ---
    final quittances = LocalDatabase.quittancesBox.values
        .where((q) => q.periodYear == year)
        .toList()
      ..sort((a, b) {
        final c = a.periodMonth.compareTo(b.periodMonth);
        if (c != 0) return c;
        return a.datePaiement.compareTo(b.datePaiement);
      });
    for (final q in quittances) {
      final l = logements[q.logementId];
      final t = locataires[q.locataireId];
      rows.add([
        'Quittance',
        df.format(q.datePaiement.toLocal()),
        _logementLabel(l),
        _adresse(l),
        _locataireLabel(t),
        _moisAnnee(q.periodMonth, q.periodYear),
        q.notes,
        (q.loyerHC + q.charges).toStringAsFixed(2),
        q.loyerHC.toStringAsFixed(2),
        q.charges.toStringAsFixed(2),
        q.integrityHash,
      ]);
    }

    // Total recettes (ligne de synthèse)
    final totalRecettes = quittances.fold<double>(
      0,
      (s, q) => s + q.loyerHC + q.charges,
    );
    rows.add([]);
    rows.add([
      'TOTAL RECETTES',
      '',
      '',
      '',
      '',
      'Année $year',
      '${quittances.length} quittance(s)',
      totalRecettes.toStringAsFixed(2),
      '',
      '',
      '',
    ]);

    // --- Dépenses ---
    rows.add([]);
    rows.add(['---', 'DÉPENSES', '---', '', '', '', '', '', '', '', '']);
    final depenses = LocalDatabase.depensesBox.values
        .where((d) => d.date.year == year)
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    for (final d in depenses) {
      final l = logements[d.logementId];
      rows.add([
        'Dépense',
        df.format(d.date.toLocal()),
        _logementLabel(l),
        _adresse(l),
        '',
        d.categorie,
        d.libelle.isEmpty ? d.notes : d.libelle,
        '-${d.montant.toStringAsFixed(2)}',
        '',
        '',
        d.integrityHash,
      ]);
    }
    final totalDepenses =
        depenses.fold<double>(0, (s, d) => s + d.montant);
    rows.add([]);
    rows.add([
      'TOTAL DÉPENSES',
      '',
      '',
      '',
      '',
      'Année $year',
      '${depenses.length} dépense(s)',
      '-${totalDepenses.toStringAsFixed(2)}',
      '',
      '',
      '',
    ]);

    // --- Crédits ---
    rows.add([]);
    rows.add(['---', 'CRÉDITS IMMOBILIERS', '---', '', '', '', '', '', '', '', '']);
    final credits = LocalDatabase.creditsImmobiliersBox.values.toList();
    for (final c in credits) {
      final l = logements[c.logementId];
      var moisActifs = 0;
      var totalMensualites = 0.0;
      for (var m = 1; m <= 12; m++) {
        final date = DateTime(year, m, 1);
        if (date.isBefore(
            DateTime(c.dateDebut.year, c.dateDebut.month, 1))) {
          continue;
        }
        if (date.isAfter(c.dateFin)) continue;
        moisActifs += 1;
        totalMensualites += c.mensualiteTotaleA(date);
      }
      if (moisActifs == 0) continue;
      rows.add([
        'Crédit',
        '01/01/$year',
        _logementLabel(l),
        _adresse(l),
        '',
        c.libelle,
        '$moisActifs mois actifs',
        '-${totalMensualites.toStringAsFixed(2)}',
        '',
        '',
        c.integrityHash,
      ]);
    }

    // --- Synthèse globale ---
    rows.add([]);
    rows.add(['', '', '', '', '', '', '', '', '', '', '']);
    rows.add([
      'BILAN NET',
      '',
      '',
      '',
      '',
      'Année $year',
      'Recettes − dépenses (hors crédits)',
      (totalRecettes - totalDepenses).toStringAsFixed(2),
      '',
      '',
      '',
    ]);

    final csv = const ListToCsvConverter(
      fieldDelimiter: ';',
      eol: '\r\n',
    ).convert(rows);

    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/exports_compta');
    if (!await dir.exists()) await dir.create(recursive: true);
    final file = File('${dir.path}/comptabilite_$year.csv');
    await file.writeAsString(csv);
    return file.path;
  }

  String _logementLabel(Logement? l) => l == null ? '?' : l.libelle;
  String _adresse(Logement? l) =>
      l == null ? '' : '${l.adresse}, ${l.codePostal} ${l.ville}';
  String _locataireLabel(Locataire? t) => t == null ? '?' : t.fullName;

  static const _mois = [
    'janv.',
    'févr.',
    'mars',
    'avr.',
    'mai',
    'juin',
    'juil.',
    'août',
    'sept.',
    'oct.',
    'nov.',
    'déc.',
  ];
  String _moisAnnee(int month, int year) {
    final m =
        (month >= 1 && month <= 12) ? _mois[month - 1] : '?';
    return '$m $year';
  }
}
