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
  }) async {
    final doc = pw.Document(
      title: 'Quittance ${quittance.periodLabel}',
      author: bailleur.fullName,
    );

    final money = NumberFormat.currency(locale: 'fr_FR', symbol: '€');
    final dateFmt = DateFormat('dd/MM/yyyy', 'fr_FR');

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        build: (ctx) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _header(bailleur, dateFmt),
              pw.SizedBox(height: 20),
              _title(quittance),
              pw.SizedBox(height: 18),
              _parties(bailleur: bailleur, locataire: locataire),
              pw.SizedBox(height: 14),
              _logementBlock(logement),
              pw.SizedBox(height: 18),
              _detailsTable(quittance, money),
              pw.SizedBox(height: 18),
              _quittanceMention(quittance, dateFmt),
              pw.Spacer(),
              _footer(bailleur, quittance, dateFmt),
            ],
          );
        },
      ),
    );

    return doc;
  }

  static pw.Widget _header(UserProfile bailleur, DateFormat dateFmt) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              bailleur.fullName,
              style: pw.TextStyle(
                fontSize: 14,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 2),
            pw.Text(
              bailleur.email,
              style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
            ),
          ],
        ),
        pw.Text(
          'Établi le ${dateFmt.format(DateTime.now())}',
          style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
        ),
      ],
    );
  }

  static pw.Widget _title(Quittance q) {
    return pw.Center(
      child: pw.Column(
        children: [
          pw.Text(
            'QUITTANCE DE LOYER',
            style: pw.TextStyle(
              fontSize: 22,
              fontWeight: pw.FontWeight.bold,
              letterSpacing: 2,
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            q.periodLabel.toUpperCase(),
            style: pw.TextStyle(
              fontSize: 14,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.blue800,
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _parties({
    required UserProfile bailleur,
    required Locataire locataire,
  }) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          child: _partyBox(
            title: 'BAILLEUR',
            lines: [
              bailleur.fullName,
              bailleur.email,
            ],
          ),
        ),
        pw.SizedBox(width: 12),
        pw.Expanded(
          child: _partyBox(
            title: 'LOCATAIRE',
            lines: [
              locataire.fullName,
              if (locataire.email.isNotEmpty) locataire.email,
              if (locataire.phone != null && locataire.phone!.isNotEmpty)
                locataire.phone!,
            ],
          ),
        ),
      ],
    );
  }

  static pw.Widget _partyBox({
    required String title,
    required List<String> lines,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey400),
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            title,
            style: pw.TextStyle(
              fontSize: 9,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.grey700,
              letterSpacing: 1,
            ),
          ),
          pw.SizedBox(height: 6),
          ...lines.map(
            (l) => pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 2),
              child: pw.Text(l, style: const pw.TextStyle(fontSize: 11)),
            ),
          ),
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
            'LOGEMENT : ',
            style: pw.TextStyle(
              fontSize: 10,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.blue900,
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
    pw.TableRow row(String label, String value, {bool bold = false}) {
      return pw.TableRow(
        children: [
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: pw.Text(
              label,
              style: pw.TextStyle(
                fontSize: 11,
                fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
              ),
            ),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: pw.Text(
              value,
              textAlign: pw.TextAlign.right,
              style: pw.TextStyle(
                fontSize: 11,
                fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
              ),
            ),
          ),
        ],
      );
    }

    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
      columnWidths: const {
        0: pw.FlexColumnWidth(3),
        1: pw.FlexColumnWidth(1),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey200),
          children: [
            pw.Padding(
              padding:
                  const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: pw.Text(
                'DÉTAIL DU RÈGLEMENT',
                style: pw.TextStyle(
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
            ),
            pw.Padding(
              padding:
                  const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: pw.Text(
                'MONTANT',
                textAlign: pw.TextAlign.right,
                style: pw.TextStyle(
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
            ),
          ],
        ),
        row('Loyer hors charges', money.format(q.loyerHC)),
        row('Provision pour charges', money.format(q.charges)),
        row('TOTAL PERÇU', money.format(q.total), bold: true),
      ],
    );
  }

  static pw.Widget _quittanceMention(Quittance q, DateFormat dateFmt) {
    final start = dateFmt.format(q.periodStart);
    final end = dateFmt.format(q.periodEnd);
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey500),
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'Je soussigné(e) donne quittance pour la somme de '
            '${NumberFormat.currency(locale: 'fr_FR', symbol: '€').format(q.total)}, '
            'au titre du loyer et des charges de la période '
            'du $start au $end.',
            style: const pw.TextStyle(fontSize: 11, lineSpacing: 3),
          ),
          pw.SizedBox(height: 8),
          pw.Text(
            'Cette quittance annule tous les autres reçus qui auraient pu '
            'être établis précédemment en cas de paiement partiel du montant '
            'du présent terme. Elle est à conserver pendant trois ans par le '
            'locataire (article 7-1 de la loi du 6 juillet 1989).',
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

  static pw.Widget _footer(
    UserProfile bailleur,
    Quittance q,
    DateFormat dateFmt,
  ) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'Paiement reçu le ${dateFmt.format(q.datePaiement)}',
                  style: const pw.TextStyle(fontSize: 10),
                ),
              ],
            ),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text(
                  'Fait le ${dateFmt.format(q.dateEmission.toLocal())}',
                  style: const pw.TextStyle(fontSize: 10),
                ),
                pw.SizedBox(height: 6),
                pw.Text(
                  'Signature du bailleur',
                  style: pw.TextStyle(
                    fontSize: 9,
                    color: PdfColors.grey700,
                  ),
                ),
                pw.Container(
                  width: 180,
                  padding: const pw.EdgeInsets.only(top: 22),
                  decoration: const pw.BoxDecoration(
                    border: pw.Border(
                      top: pw.BorderSide(color: PdfColors.grey500, width: 0.5),
                    ),
                  ),
                  child: pw.Text(
                    bailleur.fullName,
                    style: pw.TextStyle(
                      fontSize: 10,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        pw.SizedBox(height: 16),
        pw.Container(
          padding: const pw.EdgeInsets.all(8),
          decoration: const pw.BoxDecoration(color: PdfColors.grey100),
          child: pw.Text(
            AppConstants.legalNoticeQuittance,
            style: pw.TextStyle(
              fontSize: 8,
              color: PdfColors.grey700,
              fontStyle: pw.FontStyle.italic,
            ),
          ),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          'ID: ${q.id} · Hash: ${q.integrityHash ?? '—'}',
          style: const pw.TextStyle(fontSize: 6, color: PdfColors.grey500),
        ),
      ],
    );
  }
}
