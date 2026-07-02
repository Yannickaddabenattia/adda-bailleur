import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../models/locataire.dart';
import '../../models/logement.dart';
import '../../models/quittance.dart';
import '../../models/user_profile.dart';
import '../constants.dart';

/// Génère le PDF d'une quittance de loyer conforme loi ALUR (art. 21).
class QuittancePdfBuilder {
  static Future<pw.Document> build({
    required Quittance quittance,
    required UserProfile bailleur,
    required Logement logement,
    required Locataire locataire,
    List<Locataire> colocataires = const [],
    String? bailleurNameOverride,
    String? bailleurEmailOverride,
  }) async {
    final resolvedBailleurName =
        (bailleurNameOverride ?? '').isNotEmpty
            ? bailleurNameOverride!
            : bailleur.fullName;
    final resolvedBailleurEmail =
        (bailleurEmailOverride ?? '').isNotEmpty
            ? bailleurEmailOverride!
            : bailleur.email;
    final base = pw.Font.ttf(
      await rootBundle.load('assets/fonts/Roboto-Regular.ttf'),
    );
    final bold = pw.Font.ttf(
      await rootBundle.load('assets/fonts/Roboto-Bold.ttf'),
    );
    final italic = pw.Font.ttf(
      await rootBundle.load('assets/fonts/Roboto-Italic.ttf'),
    );
    final doc = pw.Document(
      title: quittance.isPaiementPartiel
          ? 'Reçu ${quittance.periodLabel}'
          : 'Quittance ${quittance.periodLabel}',
      author: resolvedBailleurName,
      theme: pw.ThemeData.withFont(base: base, bold: bold, italic: italic),
    );

    final money = NumberFormat.currency(locale: 'fr_FR', symbol: '€');
    final dateFmt = DateFormat('dd/MM/yyyy', 'fr_FR');
    final dateSlash = DateFormat('dd / MM / yyyy', 'fr_FR');

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        build: (ctx) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _titleHeader(quittance, dateFmt, dateSlash),
              pw.SizedBox(height: 18),
              _parties(
                bailleurName: resolvedBailleurName,
                bailleurEmail: resolvedBailleurEmail,
                locataire: locataire,
                colocataires: colocataires,
              ),
              pw.SizedBox(height: 12),
              _logementBlock(logement),
              pw.SizedBox(height: 18),
              _detailsTable(quittance, money),
              pw.SizedBox(height: 14),
              _quittanceMention(
                q: quittance,
                bailleurName: resolvedBailleurName,
                locataire: locataire,
                colocataires: colocataires,
                money: money,
                dateFmt: dateFmt,
              ),
              pw.Spacer(),
              _footer(
                bailleurName: resolvedBailleurName,
                ville: logement.ville,
                q: quittance,
                dateSlash: dateSlash,
              ),
              pw.SizedBox(height: 14),
              _authenticityBlock(quittance),
            ],
          );
        },
      ),
    );

    return doc;
  }

  static pw.Widget _titleHeader(
    Quittance q,
    DateFormat dateFmt,
    DateFormat dateSlash,
  ) {
    final period =
        '${q.periodLabel[0].toUpperCase()}${q.periodLabel.substring(1)}'
        ' · du ${dateFmt.format(q.periodStart)} au ${dateFmt.format(q.periodEnd)}';
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              // C3 : paiement partiel → « Reçu », jamais « Quittance ».
              q.isPaiementPartiel
                  ? 'Reçu de paiement partiel'
                  : 'Quittance de loyer',
              style: pw.TextStyle(
                fontSize: 22,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              period,
              style: pw.TextStyle(
                fontSize: 11,
                color: PdfColors.blue800,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ],
        ),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text(
              'ÉTABLI LE',
              style: pw.TextStyle(
                fontSize: 8,
                color: PdfColors.grey700,
                letterSpacing: 1,
              ),
            ),
            pw.SizedBox(height: 2),
            pw.Text(
              dateSlash.format(DateTime.now()),
              style: pw.TextStyle(
                fontSize: 11,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ],
        ),
      ],
    );
  }

  static pw.Widget _parties({
    required String bailleurName,
    required String bailleurEmail,
    required Locataire locataire,
    List<Locataire> colocataires = const [],
  }) {
    final hasColocs = colocataires.isNotEmpty;
    final principalLabel = locataire.isPrincipal && hasColocs
        ? '${locataire.fullName} (principal)'
        : locataire.fullName;
    final locataireLines = <List<String>>[
      [
        principalLabel,
        if (locataire.email.isNotEmpty) locataire.email,
        if (locataire.phone != null && locataire.phone!.isNotEmpty)
          locataire.phone!,
      ],
      for (final c in colocataires)
        [
          '${c.fullName} (colocataire)',
          if (c.email.isNotEmpty) c.email,
          if (c.phone != null && c.phone!.isNotEmpty) c.phone!,
        ],
    ];
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          child: _partyBox(
            title: 'BAILLEUR',
            entries: [
              [bailleurName, bailleurEmail],
            ],
          ),
        ),
        pw.SizedBox(width: 12),
        pw.Expanded(
          child: _partyBox(
            title: hasColocs ? 'LOCATAIRES' : 'LOCATAIRE',
            entries: locataireLines,
          ),
        ),
      ],
    );
  }

  static pw.Widget _partyBox({
    required String title,
    required List<List<String>> entries,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey100,
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            title,
            style: pw.TextStyle(
              fontSize: 8,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.grey700,
              letterSpacing: 1,
            ),
          ),
          pw.SizedBox(height: 6),
          for (var i = 0; i < entries.length; i++) ...[
            if (i > 0)
              pw.Container(
                margin: const pw.EdgeInsets.symmetric(vertical: 4),
                height: 0.5,
                color: PdfColors.grey400,
              ),
            for (var j = 0; j < entries[i].length; j++)
              pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 2),
                child: pw.Text(
                  entries[i][j],
                  style: pw.TextStyle(
                    fontSize: 11,
                    fontWeight:
                        j == 0 ? pw.FontWeight.bold : pw.FontWeight.normal,
                    color:
                        j == 0 ? PdfColors.black : PdfColors.grey700,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  static pw.Widget _logementBlock(Logement logement) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: PdfColors.blue50,
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'LOGEMENT  ',
            style: pw.TextStyle(
              fontSize: 9,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.blue900,
              letterSpacing: 1,
            ),
          ),
          pw.Expanded(
            child: pw.Text(
              '${logement.libelle} — ${logement.adresseComplete}',
              style: const pw.TextStyle(fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _detailsTable(Quittance q, NumberFormat money) {
    pw.TableRow row(
      String label,
      String value, {
      bool highlight = false,
    }) {
      return pw.TableRow(
        decoration: highlight
            ? const pw.BoxDecoration(color: PdfColors.blue50)
            : null,
        children: [
          pw.Padding(
            padding:
                const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            child: pw.Text(
              label,
              style: pw.TextStyle(
                fontSize: 11,
                fontWeight: highlight
                    ? pw.FontWeight.bold
                    : pw.FontWeight.normal,
                color: highlight ? PdfColors.blue900 : PdfColors.black,
              ),
            ),
          ),
          pw.Padding(
            padding:
                const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            child: pw.Text(
              value,
              textAlign: pw.TextAlign.right,
              style: pw.TextStyle(
                fontSize: highlight ? 13 : 11,
                fontWeight: highlight
                    ? pw.FontWeight.bold
                    : pw.FontWeight.normal,
                color: highlight ? PdfColors.blue900 : PdfColors.black,
              ),
            ),
          ),
        ],
      );
    }

    const moisFr = [
      'janvier', 'février', 'mars', 'avril', 'mai', 'juin',
      'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre',
    ];
    String labelMois(String key) {
      // "YYYY-MM"
      final parts = key.split('-');
      if (parts.length != 2) return key;
      final y = parts[0];
      final m = int.tryParse(parts[1]);
      if (m == null || m < 1 || m > 12) return key;
      return '${moisFr[m - 1]} $y';
    }

    final restantPeriode = q.restantDuPeriode;
    final versementsKeys = q.versementsSupplementaires.keys.toList()..sort();

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 6),
          child: pw.Text(
            'DÉTAIL DU RÈGLEMENT',
            style: pw.TextStyle(
              fontSize: 9,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.grey700,
              letterSpacing: 1,
            ),
          ),
        ),
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
          columnWidths: const {
            0: pw.FlexColumnWidth(3),
            1: pw.FlexColumnWidth(1),
          },
          children: [
            row('Loyer hors charges', money.format(q.loyerHC)),
            row('Provision pour charges', money.format(q.charges)),
            row('Total dû ce mois', money.format(q.total), highlight: true),
            row('Montant encaissé ce mois', money.format(q.montantPayePeriode)),
            if (restantPeriode > 0.01)
              row('Restant dû ce mois',
                  money.format(restantPeriode), highlight: true),
            for (final k in versementsKeys)
              row('Versement pour ${labelMois(k)}',
                  money.format(q.versementsSupplementaires[k]!)),
            if (versementsKeys.isNotEmpty)
              row('Total encaissé via ce document',
                  money.format(q.montantEncaisseTotal),
                  highlight: true),
          ],
        ),
      ],
    );
  }

  static pw.Widget _quittanceMention({
    required Quittance q,
    required String bailleurName,
    required Locataire locataire,
    required List<Locataire> colocataires,
    required NumberFormat money,
    required DateFormat dateFmt,
  }) {
    final tenantNames = <String>[locataire.fullName, ...colocataires.map((c) => c.fullName)];
    final tenantsLabel = _joinNames(tenantNames);
    final start = dateFmt.format(q.periodStart);
    final end = dateFmt.format(q.periodEnd);
    // Art. 21 loi du 6 juillet 1989 : la quittance atteste le paiement
    // INTÉGRAL ; un paiement partiel ne donne droit qu'à un reçu.
    final mention = q.isPaiementPartiel
        ? 'Je soussigné, $bailleurName, propriétaire du logement '
            'désigné ci-dessus, reconnais avoir reçu de $tenantsLabel la '
            'somme de ${money.format(q.montantPayePeriode)}, à valoir sur '
            'le loyer et les charges de la période du $start au $end, '
            'd\'un montant total de ${money.format(q.total)}. '
            'Reste dû : ${money.format(q.restantDuPeriode)}. '
            'Le présent document constitue un reçu de paiement partiel et '
            'ne vaut pas quittance ; la quittance sera délivrée après '
            'paiement intégral du loyer et des charges.'
        : 'Je soussigné, $bailleurName, propriétaire du logement '
            'désigné ci-dessus, donne quittance à $tenantsLabel pour la '
            'somme de ${money.format(q.montantPayePeriode)}, au titre du '
            'loyer et des charges pour la période du $start au $end.';
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey400),
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            mention,
            style: const pw.TextStyle(fontSize: 11, lineSpacing: 3),
          ),
          pw.SizedBox(height: 8),
          pw.Text(
            'Document délivré gratuitement, à la demande du locataire '
            '(article 21 de la loi du 6 juillet 1989). Sa transmission par voie '
            'dématérialisée requiert l\'accord exprès du locataire. '
            '${q.isPaiementPartiel ? '' : 'En cas de paiement partiel, le document délivré vaut reçu et non quittance. '}'
            'À conserver pendant trois ans par le locataire (article 7-1 de la '
            'loi du 6 juillet 1989).',
            style: pw.TextStyle(
              fontSize: 9,
              fontStyle: pw.FontStyle.italic,
              color: PdfColors.grey700,
              lineSpacing: 2,
            ),
          ),
        ],
      ),
    );
  }

  static String _joinNames(List<String> names) {
    if (names.length == 1) return names.first;
    if (names.length == 2) return '${names[0]} et ${names[1]}';
    return '${names.sublist(0, names.length - 1).join(', ')} et ${names.last}';
  }

  static pw.Widget _footer({
    required String bailleurName,
    required String ville,
    required Quittance q,
    required DateFormat dateSlash,
  }) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'PAIEMENT REÇU LE',
              style: pw.TextStyle(
                fontSize: 8,
                color: PdfColors.grey700,
                letterSpacing: 1,
              ),
            ),
            pw.SizedBox(height: 2),
            pw.Text(
              dateSlash.format(q.datePaiement),
              style: pw.TextStyle(
                fontSize: 11,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ],
        ),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text(
              'FAIT À ${ville.toUpperCase()} LE',
              style: pw.TextStyle(
                fontSize: 8,
                color: PdfColors.grey700,
                letterSpacing: 1,
              ),
            ),
            pw.SizedBox(height: 2),
            pw.Text(
              dateSlash.format(q.dateEmission.toLocal()),
              style: pw.TextStyle(
                fontSize: 11,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 18),
            pw.Text(
              'Signature du bailleur',
              style: pw.TextStyle(
                fontSize: 9,
                fontStyle: pw.FontStyle.italic,
                color: PdfColors.grey700,
              ),
            ),
            pw.Container(
              width: 200,
              padding: const pw.EdgeInsets.only(top: 4),
              decoration: const pw.BoxDecoration(
                border: pw.Border(
                  top: pw.BorderSide(color: PdfColors.grey500, width: 0.5),
                ),
              ),
              child: pw.Text(
                bailleurName,
                style: pw.TextStyle(
                  fontSize: 11,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  static pw.Widget _authenticityBlock(Quittance q) {
    final hash = q.integrityHash ?? '';
    final shortHash = hash.length > 14
        ? '${hash.substring(0, 7)}…${hash.substring(hash.length - 7)}'
        : (hash.isEmpty ? '—' : hash);
    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: PdfColor.fromHex('E6F4EC'),
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            width: 14,
            height: 14,
            margin: const pw.EdgeInsets.only(top: 1, right: 8),
            decoration: pw.BoxDecoration(
              color: PdfColor.fromHex('2E8B57'),
              shape: pw.BoxShape.circle,
            ),
          ),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'Document authentique · Intégrité vérifiée',
                  style: pw.TextStyle(
                    fontSize: 10,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColor.fromHex('1E5631'),
                  ),
                ),
                pw.SizedBox(height: 2),
                pw.Text(
                  AppConstants.legalNoticeQuittance,
                  style: pw.TextStyle(
                    fontSize: 8,
                    color: PdfColor.fromHex('2E5C40'),
                  ),
                ),
                pw.SizedBox(height: 2),
                pw.Text(
                  '${q.id} · $shortHash',
                  style: pw.TextStyle(
                    fontSize: 7,
                    color: PdfColor.fromHex('4A7A5D'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
