import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../models/element_piece.dart';
import '../../models/etat_des_lieux.dart';
import '../../models/etat_element.dart';
import '../../models/locataire.dart';
import '../../models/logement.dart';
import '../../models/piece.dart';
import '../../models/user_profile.dart';
import '../constants.dart';

/// Génère le PDF d'un état des lieux conforme à l'article 3-2 de la loi
/// n°89-462 du 6 juillet 1989.
class EtatDesLieuxPdfBuilder {
  /// Nombre maximum de photos embarquées par élément (pour limiter la taille).
  static const int _maxPhotosPerElement = 4;

  static Future<pw.Document> build({
    required EtatDesLieux edl,
    required UserProfile bailleur,
    required Logement logement,
    required Locataire locataire,
  }) async {
    final doc = pw.Document(
      title: edl.titre,
      author: bailleur.fullName,
    );

    final dateFmt = DateFormat('dd/MM/yyyy', 'fr_FR');
    final dateTimeFmt = DateFormat('dd/MM/yyyy à HH:mm', 'fr_FR');

    final photoCache = await _loadPhotos(edl.pieces);
    final bailleurSignature = _decodeSignature(edl.proprietaireSignaturePng);

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(36, 36, 36, 48),
        header: (ctx) => ctx.pageNumber == 1
            ? pw.SizedBox.shrink()
            : _pageHeader(edl, bailleur, dateFmt),
        footer: (ctx) => _pageFooter(ctx, edl),
        build: (ctx) => [
          _header(bailleur, dateFmt),
          pw.SizedBox(height: 16),
          _title(edl),
          pw.SizedBox(height: 14),
          _parties(bailleur: bailleur, locataire: locataire),
          pw.SizedBox(height: 12),
          _logementBlock(logement, edl, dateFmt),
          pw.SizedBox(height: 16),
          _inspectionHeader(),
          ...edl.pieces.map((p) => _pieceBlock(p, photoCache)),
          if (edl.notes.trim().isNotEmpty) ...[
            pw.SizedBox(height: 12),
            _notesBlock(edl.notes),
          ],
          pw.SizedBox(height: 20),
          _signatures(
            edl: edl,
            bailleur: bailleur,
            locataire: locataire,
            bailleurSignature: bailleurSignature,
            dateTimeFmt: dateTimeFmt,
          ),
          if (edl.isFinalized) ...[
            pw.SizedBox(height: 12),
            _certification(edl),
          ],
        ],
      ),
    );

    return doc;
  }

  // ---------- sections ----------

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
              style: const pw.TextStyle(
                fontSize: 10,
                color: PdfColors.grey700,
              ),
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

  static pw.Widget _pageHeader(
    EtatDesLieux edl,
    UserProfile bailleur,
    DateFormat dateFmt,
  ) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 6),
      margin: const pw.EdgeInsets.only(bottom: 10),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.5),
        ),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            edl.titre,
            style: pw.TextStyle(
              fontSize: 9,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.grey700,
            ),
          ),
          pw.Text(
            bailleur.fullName,
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
          ),
        ],
      ),
    );
  }

  static pw.Widget _pageFooter(pw.Context ctx, EtatDesLieux edl) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(top: 6),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          top: pw.BorderSide(color: PdfColors.grey300, width: 0.5),
        ),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            AppConstants.legalNoticeEtatLieux,
            style: pw.TextStyle(
              fontSize: 7,
              fontStyle: pw.FontStyle.italic,
              color: PdfColors.grey600,
            ),
          ),
          pw.Text(
            'Page ${ctx.pageNumber} / ${ctx.pagesCount}',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
          ),
        ],
      ),
    );
  }

  static pw.Widget _title(EtatDesLieux edl) {
    return pw.Center(
      child: pw.Column(
        children: [
          pw.Text(
            'ÉTAT DES LIEUX',
            style: pw.TextStyle(
              fontSize: 22,
              fontWeight: pw.FontWeight.bold,
              letterSpacing: 2,
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Container(
            padding:
                const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: pw.BoxDecoration(
              color: PdfColors.blue800,
              borderRadius: pw.BorderRadius.circular(4),
            ),
            child: pw.Text(
              edl.type.label.toUpperCase(),
              style: pw.TextStyle(
                fontSize: 12,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.white,
                letterSpacing: 1.5,
              ),
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
            lines: [bailleur.fullName, bailleur.email],
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

  static pw.Widget _logementBlock(
    Logement logement,
    EtatDesLieux edl,
    DateFormat dateFmt,
  ) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: PdfColors.blue50,
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            children: [
              pw.Text(
                'LOGEMENT',
                style: pw.TextStyle(
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.blue900,
                  letterSpacing: 1,
                ),
              ),
              pw.Spacer(),
              pw.Text(
                'Date visite : ${dateFmt.format(edl.date)}',
                style: pw.TextStyle(
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.blue900,
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 6),
          pw.Text(
            logement.libelle,
            style: pw.TextStyle(
              fontSize: 13,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.Text(
            logement.adresseComplete,
            style: const pw.TextStyle(fontSize: 11),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            '${logement.type.label} · ${logement.surface.toStringAsFixed(0)} m² · '
            '${logement.nbPieces} pièce(s)',
            style: const pw.TextStyle(
              fontSize: 10,
              color: PdfColors.grey700,
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _inspectionHeader() {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      color: PdfColors.grey200,
      child: pw.Text(
        'INSPECTION DES PIÈCES',
        style: pw.TextStyle(
          fontSize: 10,
          fontWeight: pw.FontWeight.bold,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  static pw.Widget _pieceBlock(
    Piece piece,
    Map<String, pw.MemoryImage?> photos,
  ) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 10),
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey400, width: 0.5),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            piece.nom.toUpperCase(),
            style: pw.TextStyle(
              fontSize: 12,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.blue800,
              letterSpacing: 0.8,
            ),
          ),
          pw.SizedBox(height: 6),
          if (piece.elements.isEmpty)
            pw.Text(
              'Aucun élément inspecté.',
              style: pw.TextStyle(
                fontSize: 10,
                color: PdfColors.grey600,
                fontStyle: pw.FontStyle.italic,
              ),
            )
          else
            ...piece.elements.map((e) => _elementRow(e, photos)),
        ],
      ),
    );
  }

  static pw.Widget _elementRow(
    ElementPiece e,
    Map<String, pw.MemoryImage?> photos,
  ) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 6),
      padding: const pw.EdgeInsets.only(top: 6),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          top: pw.BorderSide(color: PdfColors.grey200, width: 0.5),
        ),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Text(
                  e.nom,
                  style: pw.TextStyle(
                    fontSize: 11,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
              _etatBadge(e.etat),
            ],
          ),
          if (e.description.trim().isNotEmpty) ...[
            pw.SizedBox(height: 3),
            pw.Text(
              e.description,
              style: const pw.TextStyle(
                fontSize: 10,
                color: PdfColors.grey800,
              ),
            ),
          ],
          if (e.photoPaths.isNotEmpty) _photosRow(e.photoPaths, photos),
        ],
      ),
    );
  }

  static pw.Widget _photosRow(
    List<String> paths,
    Map<String, pw.MemoryImage?> photos,
  ) {
    final images = paths
        .take(_maxPhotosPerElement)
        .map((p) => photos[p])
        .where((img) => img != null)
        .cast<pw.MemoryImage>()
        .toList();
    if (images.isEmpty) return pw.SizedBox.shrink();
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 6),
      child: pw.Wrap(
        spacing: 4,
        runSpacing: 4,
        children: images
            .map(
              (img) => pw.ClipRRect(
                horizontalRadius: 3,
                verticalRadius: 3,
                child: pw.Image(
                  img,
                  width: 70,
                  height: 70,
                  fit: pw.BoxFit.cover,
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  static pw.Widget _etatBadge(EtatElement etat) {
    final color = _colorFor(etat);
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: pw.BoxDecoration(
        color: color,
        borderRadius: pw.BorderRadius.circular(3),
      ),
      child: pw.Text(
        etat.label.toUpperCase(),
        style: pw.TextStyle(
          fontSize: 8,
          fontWeight: pw.FontWeight.bold,
          color: PdfColors.white,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  static PdfColor _colorFor(EtatElement etat) {
    switch (etat) {
      case EtatElement.bon:
        return PdfColors.green700;
      case EtatElement.moyen:
        return PdfColors.amber700;
      case EtatElement.mauvais:
        return PdfColors.orange800;
      case EtatElement.aRemplacer:
        return PdfColors.red700;
    }
  }

  static pw.Widget _notesBlock(String notes) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey100,
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'NOTES',
            style: pw.TextStyle(
              fontSize: 9,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.grey700,
              letterSpacing: 1,
            ),
          ),
          pw.SizedBox(height: 6),
          pw.Text(notes, style: const pw.TextStyle(fontSize: 10)),
        ],
      ),
    );
  }

  static pw.Widget _signatures({
    required EtatDesLieux edl,
    required UserProfile bailleur,
    required Locataire locataire,
    required pw.MemoryImage? bailleurSignature,
    required DateFormat dateTimeFmt,
  }) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          child: _signatureBox(
            title: 'BAILLEUR',
            name: bailleur.fullName,
            signatureImage: bailleurSignature,
            signedAt: edl.proprietaireSignatureAt,
            dateTimeFmt: dateTimeFmt,
          ),
        ),
        pw.SizedBox(width: 12),
        pw.Expanded(
          child: _signatureBox(
            title: 'LOCATAIRE',
            name: locataire.fullName,
            signatureImage: null,
            signedAt: edl.locataireSignatureAt,
            dateTimeFmt: dateTimeFmt,
            pendingLabel: edl.isFinalized
                ? null
                : edl.isPendingTenantSignature
                    ? 'En attente de signature'
                    : 'Non signé',
          ),
        ),
      ],
    );
  }

  static pw.Widget _signatureBox({
    required String title,
    required String name,
    required pw.MemoryImage? signatureImage,
    required DateTime? signedAt,
    required DateFormat dateTimeFmt,
    String? pendingLabel,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      constraints: const pw.BoxConstraints(minHeight: 120),
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
          pw.SizedBox(height: 4),
          pw.Text(
            name,
            style: pw.TextStyle(
              fontSize: 10,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 6),
          if (signatureImage != null)
            pw.Container(
              height: 60,
              alignment: pw.Alignment.centerLeft,
              child: pw.Image(signatureImage, height: 60, fit: pw.BoxFit.contain),
            )
          else if (pendingLabel != null)
            pw.Container(
              height: 60,
              alignment: pw.Alignment.center,
              child: pw.Text(
                pendingLabel,
                style: pw.TextStyle(
                  fontSize: 10,
                  fontStyle: pw.FontStyle.italic,
                  color: PdfColors.grey500,
                ),
              ),
            )
          else
            pw.Container(
              height: 60,
              alignment: pw.Alignment.center,
              child: pw.Text(
                'Co-signature électronique validée',
                style: pw.TextStyle(
                  fontSize: 9,
                  fontStyle: pw.FontStyle.italic,
                  color: PdfColors.green800,
                ),
              ),
            ),
          pw.Divider(color: PdfColors.grey400, height: 10),
          pw.Text(
            signedAt != null
                ? 'Signé le ${dateTimeFmt.format(signedAt.toLocal())}'
                : 'Non signé',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
          ),
        ],
      ),
    );
  }

  static pw.Widget _certification(EtatDesLieux edl) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: PdfColors.green50,
        border: pw.Border.all(color: PdfColors.green300),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'CERTIFICATION D\'INTÉGRITÉ',
            style: pw.TextStyle(
              fontSize: 9,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.green900,
              letterSpacing: 1,
            ),
          ),
          pw.SizedBox(height: 6),
          pw.Text(
            'Ce document a été co-signé électroniquement et scellé par un hash '
            'SHA-256. Toute modification ultérieure invaliderait le scellement.',
            style: const pw.TextStyle(fontSize: 9),
          ),
          pw.SizedBox(height: 6),
          pw.Text(
            'Hash : ${edl.integrityHash ?? '—'}',
            style: pw.TextStyle(
              fontSize: 7,
              font: pw.Font.courier(),
              color: PdfColors.grey800,
            ),
          ),
          pw.Text(
            'ID : ${edl.id}',
            style: pw.TextStyle(
              fontSize: 7,
              font: pw.Font.courier(),
              color: PdfColors.grey800,
            ),
          ),
        ],
      ),
    );
  }

  // ---------- helpers ----------

  static Future<Map<String, pw.MemoryImage?>> _loadPhotos(
    List<Piece> pieces,
  ) async {
    final map = <String, pw.MemoryImage?>{};
    for (final piece in pieces) {
      for (final element in piece.elements) {
        for (final path in element.photoPaths.take(_maxPhotosPerElement)) {
          if (map.containsKey(path)) continue;
          try {
            final file = File(path);
            if (!await file.exists()) {
              map[path] = null;
              continue;
            }
            final bytes = await file.readAsBytes();
            map[path] = pw.MemoryImage(bytes);
          } catch (_) {
            map[path] = null;
          }
        }
      }
    }
    return map;
  }

  static pw.MemoryImage? _decodeSignature(String? base64Png) {
    if (base64Png == null || base64Png.isEmpty) return null;
    try {
      final bytes = Uint8List.fromList(base64Decode(base64Png));
      return pw.MemoryImage(bytes);
    } catch (_) {
      return null;
    }
  }
}
