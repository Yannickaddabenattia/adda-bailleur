import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../models/etat_des_lieux.dart';
import '../../models/etat_element.dart';
import '../../models/locataire.dart';
import '../../models/logement.dart';
import '../../models/piece.dart';
import '../../models/plan_logement.dart';
import '../../models/user_profile.dart';
import '../constants.dart';

/// Génère le PDF d'un état des lieux conforme à l'article 3-2 de la loi
/// N.89-462 du 6 juillet 1989, dans une mise en page éditoriale (couverture,
/// sommaire, fiches par pièce).
class EtatDesLieuxPdfBuilder {
  static const int _maxPhotosPerElement = 4;

  // Palette éditoriale crème / vert anglais / or.
  static const PdfColor _cream = PdfColor.fromInt(0xFFF5F1E5);
  static const PdfColor _creamDeep = PdfColor.fromInt(0xFFEFE8D6);
  static const PdfColor _green = PdfColor.fromInt(0xFF1F3D2A);
  static const PdfColor _gold = PdfColor.fromInt(0xFFA38242);
  static const PdfColor _brown = PdfColor.fromInt(0xFF6B4423);
  static const PdfColor _ink = PdfColor.fromInt(0xFF2C2C2C);
  static const PdfColor _muted = PdfColor.fromInt(0xFF7A7263);
  static const PdfColor _hairline = PdfColor.fromInt(0xFFD8D0BE);

  /// Fonts Roboto chargées une seule fois pour supporter € / accents /
  /// guillemets typographiques sans afficher de carrés. Roboto-BoldItalic
  /// n'est pas embarqué (seuls Regular/Bold/Italic sont fournis) → on retombe
  /// sur Bold pour les rares cas qui en demandent.
  static pw.Font? _regularCache;
  static pw.Font? _boldCache;
  static pw.Font? _italicCache;

  static pw.Font get _regular => _regularCache!;
  static pw.Font get _bold => _boldCache!;
  static pw.Font get _italic => _italicCache!;
  static pw.Font get _boldItalic => _boldCache!;

  static Future<void> _ensureFontsLoaded() async {
    _regularCache ??= pw.Font.ttf(
      await rootBundle.load('assets/fonts/Roboto-Regular.ttf'),
    );
    _boldCache ??= pw.Font.ttf(
      await rootBundle.load('assets/fonts/Roboto-Bold.ttf'),
    );
    _italicCache ??= pw.Font.ttf(
      await rootBundle.load('assets/fonts/Roboto-Italic.ttf'),
    );
  }

  static Future<pw.Document> build({
    required EtatDesLieux edl,
    required UserProfile bailleur,
    required Logement logement,
    required Locataire locataire,
    List<WallPhoto> wallPhotos = const [],
    List<PlanLogement> plans = const [],
    bool includePhotosAnnex = true,
  }) async {
    await _ensureFontsLoaded();
    final theme = pw.ThemeData.withFont(
      base: _regular,
      bold: _bold,
      italic: _italic,
      boldItalic: _boldItalic,
    );

    final doc = pw.Document(
      title: edl.titre,
      author: bailleur.fullName,
      theme: theme,
    );

    final dateFmt = DateFormat('dd/MM/yyyy', 'fr_FR');
    final dateLongFmt = DateFormat('d MMMM yyyy', 'fr_FR');
    final dateTimeFmt = DateFormat('dd/MM/yyyy à HH:mm', 'fr_FR');

    final photoCache = await _loadPhotos(edl.pieces);
    final wallPhotoCache = await _loadWallPhotos(wallPhotos);
    final wallPhotosByRoom = _groupWallPhotosByRoom(wallPhotos);
    final bailleurSignature = _decodeSignature(edl.proprietaireSignaturePng);
    final locataireSignature = _decodeSignature(edl.locataireSignaturePng);
    final annexEntries = includePhotosAnnex
        ? _collectAnnexPhotos(edl.pieces, wallPhotos, photoCache, wallPhotoCache)
        : const <_AnnexPhoto>[];

    final sortedPlans = [...plans]
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

    final toc = _buildToc(
      pieces: edl.pieces,
      hasMetadata: _hasMetadata(edl),
      planCount: sortedPlans.length,
      annexCount: annexEntries.length,
    );

    // ---- Page 1 : Couverture
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(0),
        build: (ctx) => _coverPage(
          edl: edl,
          bailleur: bailleur,
          logement: logement,
          locataire: locataire,
          dateFmt: dateFmt,
          dateLongFmt: dateLongFmt,
        ),
      ),
    );

    // ---- Page 2 : Sommaire
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(0),
        build: (ctx) => _sommairePage(toc),
      ),
    );

    // ---- Informations générales
    doc.addPage(
      pw.MultiPage(
        pageTheme: _pageTheme(),
        header: (ctx) => _runningHeader(
          bailleur: bailleur,
          sectionLabel: 'Informations générales',
          counter: 'N. 03',
        ),
        footer: (ctx) => _runningFooter(ctx),
        build: (ctx) => [
          _sectionHeader(
            number: 'N. 03',
            title: 'Parties & logement',
            subtitle: _intoSubtitleParts(edl),
          ),
          pw.SizedBox(height: 18),
          _partiesBlock(
            bailleur: bailleur,
            locataire: locataire,
            bailleurAdresse: edl.bailleurAdresse,
          ),
          pw.SizedBox(height: 14),
          _logementCard(logement, edl, dateLongFmt),
          if (_hasMetadata(edl)) ...[
            pw.SizedBox(height: 14),
            _metadataCard(edl),
          ],
          pw.SizedBox(height: 16),
          _legalQuoteBox(),
        ],
      ),
    );

    // ---- Une fiche par pièce
    for (var i = 0; i < edl.pieces.length; i++) {
      final piece = edl.pieces[i];
      final wallPhotosOfPiece =
          wallPhotosByRoom[_normalizeRoomName(piece.nom)] ?? const <WallPhoto>[];
      doc.addPage(
        pw.MultiPage(
          pageTheme: _pageTheme(),
          header: (ctx) => _runningHeader(
            bailleur: bailleur,
            sectionLabel: 'Inspection des pièces',
            counter: 'PIÈCE ${_n2(i + 1)} / ${_n2(edl.pieces.length)}',
          ),
          footer: (ctx) => _runningFooter(ctx),
          build: (ctx) => [
            _pieceHeader(
              edl: edl,
              piece: piece,
              index: i + 1,
              total: edl.pieces.length,
            ),
            pw.SizedBox(height: 14),
            _pieceTable(edl: edl, piece: piece, photos: photoCache),
            if (wallPhotosOfPiece.isNotEmpty) ...[
              pw.SizedBox(height: 14),
              _wallPhotosBand(wallPhotosOfPiece, wallPhotoCache),
            ],
            if (piece.elements.any((e) => e.description.trim().isNotEmpty)) ...[
              pw.SizedBox(height: 14),
              _commentairesBox(piece),
            ],
          ],
        ),
      );
    }

    // ---- Plans (paysage)
    if (sortedPlans.isNotEmpty) {
      for (final plan in sortedPlans) {
        pw.MemoryImage? bg;
        if (plan.imagePath != null && plan.imagePath!.isNotEmpty) {
          final f = File(plan.imagePath!);
          if (await f.exists()) {
            try {
              bg = pw.MemoryImage(await f.readAsBytes());
            } catch (_) {
              bg = null;
            }
          }
        }
        doc.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4.landscape,
            margin: const pw.EdgeInsets.all(0),
            build: (ctx) => _planPage(plan, bg, edl, bailleur),
          ),
        );
      }
    }

    // ---- Annexe photos
    if (annexEntries.isNotEmpty) {
      doc.addPage(
        pw.MultiPage(
          pageTheme: _pageTheme(),
          header: (ctx) => _runningHeader(
            bailleur: bailleur,
            sectionLabel: 'Annexe photographique',
            counter: '${annexEntries.length} CLICHÉS',
          ),
          footer: (ctx) => _runningFooter(ctx),
          build: (ctx) => [
            _sectionHeader(
              number: 'N. ${_n2(toc.length - 1)}',
              title: 'Annexe photographique',
              subtitle: '${annexEntries.length} cliché(s) joint(s) au présent état des lieux',
            ),
            pw.SizedBox(height: 18),
            _annexGrid(annexEntries),
          ],
        ),
      );
    }

    // ---- Signatures
    doc.addPage(
      pw.MultiPage(
        pageTheme: _pageTheme(),
        header: (ctx) => _runningHeader(
          bailleur: bailleur,
          sectionLabel: 'Signatures',
          counter: 'N. ${_n2(toc.length)}',
        ),
        footer: (ctx) => _runningFooter(ctx),
        build: (ctx) => [
          _sectionHeader(
            number: 'N. ${_n2(toc.length)}',
            title: 'Signatures & certification',
            subtitle:
                'Le présent document devient opposable après signature des deux parties.',
          ),
          pw.SizedBox(height: 18),
          if (edl.notes.trim().isNotEmpty) ...[
            _notesBox(edl.notes),
            pw.SizedBox(height: 14),
          ],
          _signaturesBlock(
            edl: edl,
            bailleur: bailleur,
            locataire: locataire,
            bailleurSignature: bailleurSignature,
            locataireSignature: locataireSignature,
            dateTimeFmt: dateTimeFmt,
          ),
          if (edl.isFinalized) ...[
            pw.SizedBox(height: 14),
            _certificationBox(edl),
          ],
        ],
      ),
    );

    return doc;
  }

  // ============================================================
  //                       COUVERTURE (page 1)
  // ============================================================

  static pw.Widget _coverPage({
    required EtatDesLieux edl,
    required UserProfile bailleur,
    required Logement logement,
    required Locataire locataire,
    required DateFormat dateFmt,
    required DateFormat dateLongFmt,
  }) {
    final initial = bailleur.fullName.trim().isEmpty
        ? '-'
        : bailleur.fullName.trim()[0].toUpperCase();
    final etablissementDate = dateFmt.format(DateTime.now());
    final isEntree = edl.type == EtatDesLieuxType.entree;

    return pw.Container(
      width: double.infinity,
      height: double.infinity,
      color: _cream,
      padding: const pw.EdgeInsets.fromLTRB(56, 56, 56, 56),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          // En-tête : carré Y + bailleur + date d'établissement
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Container(
                width: 38,
                height: 38,
                decoration: pw.BoxDecoration(
                  color: _green,
                  borderRadius: pw.BorderRadius.circular(2),
                ),
                alignment: pw.Alignment.center,
                child: pw.Text(
                  initial,
                  style: pw.TextStyle(
                    color: _cream,
                    fontSize: 22,
                    font: EtatDesLieuxPdfBuilder._boldItalic,
                  ),
                ),
              ),
              pw.SizedBox(width: 14),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      bailleur.fullName,
                      style: pw.TextStyle(
                        fontSize: 12,
                        font: EtatDesLieuxPdfBuilder._bold,
                        color: _ink,
                      ),
                    ),
                    pw.SizedBox(height: 1),
                    pw.Text(
                      bailleur.email,
                      style: pw.TextStyle(
                        fontSize: 9,
                        color: _muted,
                      ),
                    ),
                  ],
                ),
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text(
                    'ÉTABLI LE',
                    style: pw.TextStyle(
                      fontSize: 7,
                      letterSpacing: 1.6,
                      color: _muted,
                    ),
                  ),
                  pw.SizedBox(height: 2),
                  pw.Text(
                    etablissementDate,
                    style: pw.TextStyle(
                      fontSize: 11,
                      font: EtatDesLieuxPdfBuilder._bold,
                      color: _ink,
                    ),
                  ),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 36),

          // " - DOCUMENT OFFICIEL - "
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.center,
            children: [
              pw.Container(
                width: 24,
                height: 0.7,
                color: _gold,
              ),
              pw.SizedBox(width: 10),
              pw.Text(
                'DOCUMENT OFFICIEL',
                style: pw.TextStyle(
                  fontSize: 9,
                  letterSpacing: 3,
                  color: _gold,
                  font: EtatDesLieuxPdfBuilder._bold,
                ),
              ),
              pw.SizedBox(width: 10),
              pw.Container(
                width: 24,
                height: 0.7,
                color: _gold,
              ),
            ],
          ),
          pw.SizedBox(height: 22),

          // Titre principal - État *des lieux*
          pw.Container(
            alignment: pw.Alignment.center,
            child: pw.RichText(
              text: pw.TextSpan(
                children: [
                  pw.TextSpan(
                    text: 'État ',
                    style: pw.TextStyle(
                      fontSize: 64,
                      font: EtatDesLieuxPdfBuilder._bold,
                      color: _ink,
                    ),
                  ),
                  pw.TextSpan(
                    text: 'des lieux',
                    style: pw.TextStyle(
                      fontSize: 64,
                      font: EtatDesLieuxPdfBuilder._boldItalic,
                      color: _green,
                    ),
                  ),
                ],
              ),
            ),
          ),
          pw.SizedBox(height: 6),
          pw.Container(
            alignment: pw.Alignment.center,
            child: pw.Text(
              'Article 3-2 - loi N.89-462 du 6 juillet 1989',
              style: pw.TextStyle(
                fontSize: 10,
                font: EtatDesLieuxPdfBuilder._italic,
                color: _muted,
              ),
            ),
          ),
          pw.SizedBox(height: 30),

          // Bandeau ENTRÉE / SORTIE
          pw.Row(
            children: [
              pw.Expanded(
                child: _coverDateBox(
                  label: 'ENTRÉE',
                  active: isEntree,
                  date: isEntree ? dateLongFmt.format(edl.date) : '-',
                  dotColor: _green,
                ),
              ),
              pw.SizedBox(width: 14),
              pw.Expanded(
                child: _coverDateBox(
                  label: 'SORTIE',
                  active: !isEntree,
                  date: !isEntree ? dateLongFmt.format(edl.date) : '-',
                  dotColor: _brown,
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 28),

          // Sections numérotées en chiffres romains
          _coverRomanSection(
            roman: 'i.',
            label: 'Adresse du logement',
            lines: [
              logement.libelle,
              logement.adresseComplete,
              '${logement.type.label} - ${logement.surface.toStringAsFixed(0)} m² - '
                  '${logement.nbPieces} pièce(s)',
            ],
          ),
          _coverRomanSection(
            roman: 'ii.',
            label: 'Le bailleur',
            lines: [
              bailleur.fullName,
              if (edl.bailleurAdresse != null &&
                  edl.bailleurAdresse!.trim().isNotEmpty)
                edl.bailleurAdresse!.trim(),
              bailleur.email,
            ],
          ),
          _coverRomanSection(
            roman: 'iii.',
            label: 'Le(s) locataire(s)',
            lines: [
              locataire.fullName,
              if (locataire.email.trim().isNotEmpty) locataire.email,
              if (locataire.phone != null && locataire.phone!.trim().isNotEmpty)
                locataire.phone!.trim(),
            ],
          ),
          pw.Spacer(),

          // Citation légale encadrée or
          pw.Container(
            padding: const pw.EdgeInsets.all(14),
            decoration: pw.BoxDecoration(
              color: _creamDeep,
              border: pw.Border.all(color: _gold, width: 0.8),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'EXTRAIT - ARTICLE 3-2',
                  style: pw.TextStyle(
                    fontSize: 8,
                    letterSpacing: 1.6,
                    color: _gold,
                    font: EtatDesLieuxPdfBuilder._bold,
                  ),
                ),
                pw.SizedBox(height: 5),
                pw.Text(
                  '" Un état des lieux est établi selon des modalités définies '
                  'par décret en Conseil d\'État, dans les conditions fixées '
                  'par l\'article 3-2, contradictoirement et amiablement par '
                  'les parties ou par un tiers mandaté par elles. "',
                  style: pw.TextStyle(
                    fontSize: 9,
                    font: EtatDesLieuxPdfBuilder._italic,
                    color: _ink,
                    lineSpacing: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _coverDateBox({
    required String label,
    required bool active,
    required String date,
    required PdfColor dotColor,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: pw.BoxDecoration(
        color: active ? _cream : _creamDeep,
        border: pw.Border.all(
          color: active ? _green : _hairline,
          width: active ? 0.9 : 0.5,
        ),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            children: [
              pw.Container(
                width: 7,
                height: 7,
                decoration: pw.BoxDecoration(
                  color: active ? dotColor : _hairline,
                  shape: pw.BoxShape.circle,
                ),
              ),
              pw.SizedBox(width: 8),
              pw.Text(
                label,
                style: pw.TextStyle(
                  fontSize: 9,
                  letterSpacing: 2,
                  font: EtatDesLieuxPdfBuilder._bold,
                  color: active ? _ink : _muted,
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 8),
          pw.Text(
            date,
            style: pw.TextStyle(
              fontSize: 14,
              font: active ? EtatDesLieuxPdfBuilder._bold : EtatDesLieuxPdfBuilder._regular,
              color: active ? _ink : _muted,
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _coverRomanSection({
    required String roman,
    required String label,
    required List<String> lines,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 10),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 28,
            child: pw.Text(
              roman,
              style: pw.TextStyle(
                fontSize: 11,
                font: EtatDesLieuxPdfBuilder._italic,
                color: _gold,
              ),
            ),
          ),
          pw.SizedBox(width: 6),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  label.toUpperCase(),
                  style: pw.TextStyle(
                    fontSize: 8,
                    letterSpacing: 2,
                    color: _muted,
                    font: EtatDesLieuxPdfBuilder._bold,
                  ),
                ),
                pw.SizedBox(height: 2),
                ...lines.map(
                  (l) => pw.Text(
                    l,
                    style: pw.TextStyle(
                      fontSize: 11,
                      color: _ink,
                      lineSpacing: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  //                       SOMMAIRE (page 2)
  // ============================================================

  static pw.Widget _sommairePage(List<_TocEntry> toc) {
    return pw.Container(
      width: double.infinity,
      height: double.infinity,
      color: _cream,
      padding: const pw.EdgeInsets.fromLTRB(56, 64, 56, 64),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'N. 02',
                    style: pw.TextStyle(
                      fontSize: 11,
                      letterSpacing: 1.5,
                      color: _gold,
                      font: EtatDesLieuxPdfBuilder._italic,
                    ),
                  ),
                  pw.SizedBox(height: 4),
                  pw.RichText(
                    text: pw.TextSpan(
                      children: [
                        pw.TextSpan(
                          text: 'Sommaire ',
                          style: pw.TextStyle(
                            fontSize: 36,
                            font: EtatDesLieuxPdfBuilder._bold,
                            color: _ink,
                          ),
                        ),
                        pw.TextSpan(
                          text: 'du document',
                          style: pw.TextStyle(
                            fontSize: 36,
                            font: EtatDesLieuxPdfBuilder._italic,
                            color: _green,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              pw.Container(
                padding:
                    const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: _gold, width: 0.8),
                ),
                child: pw.Text(
                  '${_n2(toc.length)} SECTIONS',
                  style: pw.TextStyle(
                    fontSize: 9,
                    letterSpacing: 2,
                    color: _gold,
                    font: EtatDesLieuxPdfBuilder._bold,
                  ),
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 28),
          pw.Container(height: 0.6, color: _gold),
          pw.SizedBox(height: 14),
          pw.Expanded(
            child: pw.Column(
              children: toc.map(_tocRow).toList(),
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _tocRow(_TocEntry e) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(vertical: 8),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          bottom: pw.BorderSide(color: _hairline, width: 0.4),
        ),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.SizedBox(
            width: 30,
            child: pw.Text(
              e.number,
              style: pw.TextStyle(
                fontSize: 10,
                font: EtatDesLieuxPdfBuilder._bold,
                color: _gold,
              ),
            ),
          ),
          pw.Expanded(
            child: pw.Text(
              e.title,
              style: pw.TextStyle(
                fontSize: 12,
                font: EtatDesLieuxPdfBuilder._regular,
                color: _ink,
              ),
            ),
          ),
          pw.Expanded(
            child: pw.Container(
              alignment: pw.Alignment.centerRight,
              padding: const pw.EdgeInsets.only(right: 8),
              child: pw.Text(
                e.subtitle ?? '',
                style: pw.TextStyle(
                  fontSize: 9,
                  color: _muted,
                  font: EtatDesLieuxPdfBuilder._italic,
                ),
                textAlign: pw.TextAlign.right,
              ),
            ),
          ),
          pw.Text(
            'PAGE ${e.page}',
            style: pw.TextStyle(
              fontSize: 9,
              letterSpacing: 1.4,
              color: _green,
              font: EtatDesLieuxPdfBuilder._bold,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  //                   SECTIONS COURANTES
  // ============================================================

  static pw.PageTheme _pageTheme() {
    return pw.PageTheme(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(48, 56, 48, 56),
      buildBackground: (ctx) => pw.FullPage(
        ignoreMargins: true,
        child: pw.Container(color: _cream),
      ),
    );
  }

  static pw.Widget _runningHeader({
    required UserProfile bailleur,
    required String sectionLabel,
    required String counter,
  }) {
    final initial = bailleur.fullName.trim().isEmpty
        ? '-'
        : bailleur.fullName.trim()[0].toUpperCase();
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 12),
      padding: const pw.EdgeInsets.only(bottom: 8),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          bottom: pw.BorderSide(color: _hairline, width: 0.5),
        ),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Container(
            width: 18,
            height: 18,
            decoration: pw.BoxDecoration(
              color: _green,
              borderRadius: pw.BorderRadius.circular(1.5),
            ),
            alignment: pw.Alignment.center,
            child: pw.Text(
              initial,
              style: pw.TextStyle(
                color: _cream,
                fontSize: 11,
                font: EtatDesLieuxPdfBuilder._boldItalic,
              ),
            ),
          ),
          pw.SizedBox(width: 10),
          pw.RichText(
            text: pw.TextSpan(
              children: [
                pw.TextSpan(
                  text: 'État des lieux ',
                  style: pw.TextStyle(
                    fontSize: 9.5,
                    color: _ink,
                    font: EtatDesLieuxPdfBuilder._bold,
                  ),
                ),
                pw.TextSpan(
                  text: '- $sectionLabel',
                  style: pw.TextStyle(
                    fontSize: 9.5,
                    color: _muted,
                    font: EtatDesLieuxPdfBuilder._italic,
                  ),
                ),
              ],
            ),
          ),
          pw.Spacer(),
          pw.Text(
            counter,
            style: pw.TextStyle(
              fontSize: 9,
              letterSpacing: 1.6,
              color: _gold,
              font: EtatDesLieuxPdfBuilder._bold,
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _runningFooter(pw.Context ctx) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 10),
      padding: const pw.EdgeInsets.only(top: 6),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          top: pw.BorderSide(color: _hairline, width: 0.5),
        ),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Expanded(
            child: pw.Text(
              AppConstants.legalNoticeEtatLieux,
              style: pw.TextStyle(
                fontSize: 7,
                color: _muted,
                font: EtatDesLieuxPdfBuilder._italic,
              ),
            ),
          ),
          pw.SizedBox(width: 12),
          pw.Text(
            'PAGE ${_n2(ctx.pageNumber)} / ${_n2(ctx.pagesCount)}',
            style: pw.TextStyle(
              fontSize: 8,
              letterSpacing: 1.2,
              color: _green,
              font: EtatDesLieuxPdfBuilder._bold,
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _sectionHeader({
    required String number,
    required String title,
    String? subtitle,
  }) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          number,
          style: pw.TextStyle(
            fontSize: 11,
            color: _gold,
            font: EtatDesLieuxPdfBuilder._italic,
            letterSpacing: 1.2,
          ),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          title,
          style: pw.TextStyle(
            fontSize: 28,
            color: _ink,
            font: EtatDesLieuxPdfBuilder._bold,
          ),
        ),
        if (subtitle != null) ...[
          pw.SizedBox(height: 4),
          pw.Text(
            subtitle,
            style: pw.TextStyle(
              fontSize: 10,
              color: _muted,
              font: EtatDesLieuxPdfBuilder._italic,
              lineSpacing: 1.3,
            ),
          ),
        ],
        pw.SizedBox(height: 10),
        pw.Container(width: 36, height: 0.8, color: _gold),
      ],
    );
  }

  static String _intoSubtitleParts(EtatDesLieux edl) {
    final isEntree = edl.type == EtatDesLieuxType.entree;
    return 'Visite du ${DateFormat('d MMMM yyyy', 'fr_FR').format(edl.date)} - '
        '${isEntree ? 'à l\'entrée' : 'à la sortie'} du locataire.';
  }

  // ============================================================
  //                  PARTIES + LOGEMENT + RELEVÉS
  // ============================================================

  static pw.Widget _partiesBlock({
    required UserProfile bailleur,
    required Locataire locataire,
    String? bailleurAdresse,
  }) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          child: _partyCard(
            label: 'Bailleur',
            roman: 'i.',
            lines: [
              bailleur.fullName,
              if (bailleurAdresse != null && bailleurAdresse.trim().isNotEmpty)
                bailleurAdresse.trim(),
              bailleur.email,
            ],
          ),
        ),
        pw.SizedBox(width: 14),
        pw.Expanded(
          child: _partyCard(
            label: 'Locataire',
            roman: 'ii.',
            lines: [
              locataire.fullName,
              if (locataire.email.trim().isNotEmpty) locataire.email,
              if (locataire.phone != null && locataire.phone!.trim().isNotEmpty)
                locataire.phone!.trim(),
            ],
          ),
        ),
      ],
    );
  }

  static pw.Widget _partyCard({
    required String label,
    required String roman,
    required List<String> lines,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: pw.BoxDecoration(
        color: _creamDeep,
        border: pw.Border.all(color: _hairline, width: 0.5),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            children: [
              pw.Text(
                roman,
                style: pw.TextStyle(
                  fontSize: 11,
                  font: EtatDesLieuxPdfBuilder._italic,
                  color: _gold,
                ),
              ),
              pw.SizedBox(width: 6),
              pw.Text(
                label.toUpperCase(),
                style: pw.TextStyle(
                  fontSize: 8,
                  letterSpacing: 2,
                  font: EtatDesLieuxPdfBuilder._bold,
                  color: _muted,
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 8),
          ...lines.map(
            (l) => pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 1.5),
              child: pw.Text(
                l,
                style: pw.TextStyle(
                  fontSize: 11,
                  color: _ink,
                  lineSpacing: 1.3,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _logementCard(
    Logement logement,
    EtatDesLieux edl,
    DateFormat dateLongFmt,
  ) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(14),
      decoration: pw.BoxDecoration(
        color: _green,
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Row(
                children: [
                  pw.Text(
                    'iii.',
                    style: pw.TextStyle(
                      fontSize: 11,
                      font: EtatDesLieuxPdfBuilder._italic,
                      color: _gold,
                    ),
                  ),
                  pw.SizedBox(width: 6),
                  pw.Text(
                    'LOGEMENT',
                    style: pw.TextStyle(
                      fontSize: 8,
                      letterSpacing: 2,
                      font: EtatDesLieuxPdfBuilder._bold,
                      color: _cream,
                    ),
                  ),
                ],
              ),
              pw.Text(
                'Visite du ${dateLongFmt.format(edl.date)}',
                style: pw.TextStyle(
                  fontSize: 9,
                  font: EtatDesLieuxPdfBuilder._italic,
                  color: _cream,
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 10),
          pw.Text(
            logement.libelle,
            style: pw.TextStyle(
              fontSize: 16,
              font: EtatDesLieuxPdfBuilder._bold,
              color: _cream,
            ),
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            logement.adresseComplete,
            style: pw.TextStyle(fontSize: 11, color: _cream),
          ),
          pw.SizedBox(height: 6),
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: _gold, width: 0.6),
            ),
            child: pw.Text(
              '${logement.type.label} - ${logement.surface.toStringAsFixed(0)} m² - '
              '${logement.nbPieces} pièce(s)',
              style: pw.TextStyle(
                fontSize: 9,
                letterSpacing: 1.2,
                color: _gold,
                font: EtatDesLieuxPdfBuilder._bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static bool _hasMetadata(EtatDesLieux edl) {
    if (edl.nombreCles != null) return true;
    final releves = [
      edl.releveCompteurGaz,
      edl.releveCompteurEauChaude,
      edl.releveCompteurEauFroide,
      edl.releveCompteurElecJour,
      edl.releveCompteurElecNuit,
    ];
    return releves.any((v) => v != null && v.trim().isNotEmpty);
  }

  static pw.Widget _metadataCard(EtatDesLieux edl) {
    final entries = <_MetaEntry>[];
    if (edl.nombreCles != null) {
      entries.add(_MetaEntry('Clés / badges remis', '${edl.nombreCles}'));
    }
    void addReleve(String label, String? value, String unit) {
      if (value != null && value.trim().isNotEmpty) {
        entries.add(_MetaEntry(label, '${value.trim()} $unit'));
      }
    }
    addReleve('Compteur gaz', edl.releveCompteurGaz, 'm³');
    addReleve('Compteur eau chaude', edl.releveCompteurEauChaude, 'm³');
    addReleve('Compteur eau froide', edl.releveCompteurEauFroide, 'm³');
    addReleve('Électricité - heures pleines', edl.releveCompteurElecJour, 'kWh');
    addReleve('Électricité - heures creuses', edl.releveCompteurElecNuit, 'kWh');

    return pw.Container(
      padding: const pw.EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: pw.BoxDecoration(
        color: _creamDeep,
        border: pw.Border.all(color: _hairline, width: 0.5),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            children: [
              pw.Text(
                'iv.',
                style: pw.TextStyle(
                  fontSize: 11,
                  font: EtatDesLieuxPdfBuilder._italic,
                  color: _gold,
                ),
              ),
              pw.SizedBox(width: 6),
              pw.Text(
                'RELEVÉS COMPTEURS & CLÉS',
                style: pw.TextStyle(
                  fontSize: 8,
                  letterSpacing: 2,
                  font: EtatDesLieuxPdfBuilder._bold,
                  color: _muted,
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 10),
          pw.Table(
            columnWidths: const {
              0: pw.FlexColumnWidth(3),
              1: pw.FlexColumnWidth(2),
            },
            children: [
              for (var i = 0; i < entries.length; i++)
                pw.TableRow(
                  decoration: pw.BoxDecoration(
                    border: pw.Border(
                      bottom: i == entries.length - 1
                          ? pw.BorderSide.none
                          : pw.BorderSide(color: _hairline, width: 0.4),
                    ),
                  ),
                  children: [
                    pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(vertical: 4),
                      child: pw.Text(
                        entries[i].label,
                        style: pw.TextStyle(fontSize: 10, color: _ink),
                      ),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(vertical: 4),
                      child: pw.Text(
                        entries[i].value,
                        style: pw.TextStyle(
                          fontSize: 10,
                          font: EtatDesLieuxPdfBuilder._bold,
                          color: _green,
                        ),
                        textAlign: pw.TextAlign.right,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _legalQuoteBox() {
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: _gold, width: 0.7),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'POUR MÉMOIRE',
            style: pw.TextStyle(
              fontSize: 8,
              letterSpacing: 1.6,
              font: EtatDesLieuxPdfBuilder._bold,
              color: _gold,
            ),
          ),
          pw.SizedBox(height: 5),
          pw.Text(
            '" Lorsqu\'il ne peut être établi dans les conditions prévues '
            'au premier alinéa, l\'état des lieux est établi par un commissaire '
            'de justice, sur l\'initiative de la partie la plus diligente, '
            'à frais partagés par moitié entre le bailleur et le locataire. "',
            style: pw.TextStyle(
              fontSize: 9,
              font: EtatDesLieuxPdfBuilder._italic,
              color: _ink,
              lineSpacing: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  //                       PIÈCE - fiche
  // ============================================================

  static pw.Widget _pieceHeader({
    required EtatDesLieux edl,
    required Piece piece,
    required int index,
    required int total,
  }) {
    final elementsCount = piece.elements.length;
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'N. ${_n2(index + 3)}',
          style: pw.TextStyle(
            fontSize: 11,
            color: _gold,
            font: EtatDesLieuxPdfBuilder._italic,
            letterSpacing: 1.2,
          ),
        ),
        pw.SizedBox(height: 4),
        pw.RichText(
          text: pw.TextSpan(
            children: [
              pw.TextSpan(
                text: '${edl.type == EtatDesLieuxType.entree ? "Entrée" : "Sortie"} ',
                style: pw.TextStyle(
                  fontSize: 28,
                  font: EtatDesLieuxPdfBuilder._bold,
                  color: _ink,
                ),
              ),
              pw.TextSpan(
                text: '- ${piece.nom}',
                style: pw.TextStyle(
                  fontSize: 28,
                  font: EtatDesLieuxPdfBuilder._italic,
                  color: _green,
                ),
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 6),
        pw.Row(
          children: [
            pw.Text(
              '$elementsCount ÉLÉMENT${elementsCount > 1 ? 'S' : ''} INSPECTÉ${elementsCount > 1 ? 'S' : ''}',
              style: pw.TextStyle(
                fontSize: 8,
                letterSpacing: 1.6,
                color: _muted,
                font: EtatDesLieuxPdfBuilder._bold,
              ),
            ),
            pw.SizedBox(width: 14),
            pw.Container(width: 18, height: 0.6, color: _gold),
            pw.SizedBox(width: 14),
            pw.Text(
              'PIÈCE ${_n2(index)} / ${_n2(total)}',
              style: pw.TextStyle(
                fontSize: 8,
                letterSpacing: 1.6,
                color: _gold,
                font: EtatDesLieuxPdfBuilder._bold,
              ),
            ),
          ],
        ),
      ],
    );
  }

  static pw.Widget _pieceTable({
    required EtatDesLieux edl,
    required Piece piece,
    required Map<String, pw.MemoryImage?> photos,
  }) {
    final isEntree = edl.type == EtatDesLieuxType.entree;
    final headerStyle = pw.TextStyle(
      fontSize: 8,
      letterSpacing: 1.4,
      font: EtatDesLieuxPdfBuilder._bold,
      color: _cream,
    );

    pw.Widget headerCell(String text, {pw.Alignment? align}) => pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          alignment: align ?? pw.Alignment.centerLeft,
          child: pw.Text(text.toUpperCase(), style: headerStyle),
        );

    if (piece.elements.isEmpty) {
      return pw.Container(
        padding: const pw.EdgeInsets.all(16),
        decoration: pw.BoxDecoration(
          color: _creamDeep,
          border: pw.Border.all(color: _hairline, width: 0.5),
        ),
        child: pw.Text(
          'Aucun élément inspecté pour cette pièce.',
          style: pw.TextStyle(
            fontSize: 10,
            color: _muted,
            font: EtatDesLieuxPdfBuilder._italic,
          ),
        ),
      );
    }

    return pw.Table(
      columnWidths: const {
        0: pw.FlexColumnWidth(2.4),
        1: pw.FlexColumnWidth(3.2),
        2: pw.FlexColumnWidth(2.7),
        3: pw.FlexColumnWidth(2.7),
      },
      border: pw.TableBorder.symmetric(
        inside: pw.BorderSide(color: _hairline, width: 0.4),
      ),
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: _green),
          children: [
            headerCell('Élément'),
            headerCell('Description / Détail'),
            headerCell("À l'entrée"),
            headerCell('À la sortie'),
          ],
        ),
        for (final e in piece.elements)
          pw.TableRow(
            decoration: pw.BoxDecoration(
              border: pw.Border(
                bottom: pw.BorderSide(color: _hairline, width: 0.4),
              ),
            ),
            children: [
              _pieceTableCell(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      e.nom,
                      style: pw.TextStyle(
                        fontSize: 11,
                        color: _ink,
                        font: EtatDesLieuxPdfBuilder._bold,
                      ),
                    ),
                    if (e.photoPaths.isNotEmpty)
                      pw.Padding(
                        padding: const pw.EdgeInsets.only(top: 4),
                        child: pw.Text(
                          '${e.photoPaths.length} photo${e.photoPaths.length > 1 ? 's' : ''}',
                          style: pw.TextStyle(
                            fontSize: 8,
                            color: _gold,
                            font: EtatDesLieuxPdfBuilder._italic,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              _pieceTableCell(
                child: pw.Text(
                  e.description.trim().isEmpty ? '-' : e.description.trim(),
                  style: pw.TextStyle(
                    fontSize: 10,
                    color: e.description.trim().isEmpty ? _muted : _ink,
                    lineSpacing: 1.3,
                  ),
                ),
              ),
              _pieceTableCell(
                child: isEntree ? _etatPill(e.etat) : _emptyPill(),
              ),
              _pieceTableCell(
                child: !isEntree ? _etatPill(e.etat) : _emptyPill(),
              ),
            ],
          ),
      ],
    );
  }

  static pw.Widget _pieceTableCell({required pw.Widget child}) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 9),
      child: child,
    );
  }

  static pw.Widget _etatPill(EtatElement etat) {
    final color = _colorFor(etat);
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Container(
          width: 8,
          height: 8,
          decoration: pw.BoxDecoration(
            color: color,
            shape: pw.BoxShape.circle,
          ),
        ),
        pw.SizedBox(width: 6),
        pw.Expanded(
          child: pw.Text(
            etat.label,
            style: pw.TextStyle(
              fontSize: 10,
              color: _ink,
              font: EtatDesLieuxPdfBuilder._bold,
            ),
          ),
        ),
      ],
    );
  }

  static pw.Widget _emptyPill() {
    return pw.Row(
      children: [
        pw.Container(
          width: 8,
          height: 8,
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: _hairline, width: 0.6),
            shape: pw.BoxShape.circle,
          ),
        ),
        pw.SizedBox(width: 6),
        pw.Text(
          'Non renseigné',
          style: pw.TextStyle(
            fontSize: 9.5,
            color: _muted,
            font: EtatDesLieuxPdfBuilder._italic,
          ),
        ),
      ],
    );
  }

  static PdfColor _colorFor(EtatElement etat) {
    switch (etat) {
      case EtatElement.bon:
        return _green;
      case EtatElement.moyen:
        return _gold;
      case EtatElement.mauvais:
        return _brown;
      case EtatElement.aRemplacer:
        return const PdfColor.fromInt(0xFF9B2C2C);
    }
  }

  static pw.Widget _wallPhotosBand(
    List<WallPhoto> wallPhotos,
    Map<String, pw.MemoryImage?> cache,
  ) {
    final visible = wallPhotos.where((w) => cache[w.path] != null).toList();
    if (visible.isEmpty) return pw.SizedBox.shrink();
    return pw.Container(
      padding: const pw.EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: pw.BoxDecoration(
        color: _creamDeep,
        border: pw.Border.all(color: _hairline, width: 0.5),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'PHOTOGRAPHIES - ${_n2(visible.length)} EMPLACEMENT${visible.length > 1 ? 'S' : ''}',
            style: pw.TextStyle(
              fontSize: 8,
              letterSpacing: 1.6,
              font: EtatDesLieuxPdfBuilder._bold,
              color: _muted,
            ),
          ),
          pw.SizedBox(height: 8),
          pw.Wrap(
            spacing: 6,
            runSpacing: 6,
            children: visible
                .map(
                  (w) => pw.Container(
                    width: 100,
                    decoration: pw.BoxDecoration(
                      color: _cream,
                      border: pw.Border.all(color: _hairline, width: 0.5),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Image(
                          cache[w.path]!,
                          width: 100,
                          height: 100,
                          fit: pw.BoxFit.cover,
                        ),
                        pw.Container(
                          padding: const pw.EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 3,
                          ),
                          child: pw.Text(
                            w.label,
                            style: pw.TextStyle(
                              fontSize: 8,
                              font: EtatDesLieuxPdfBuilder._bold,
                              color: _green,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }

  static pw.Widget _commentairesBox(Piece piece) {
    final commentaires = piece.elements
        .where((e) => e.description.trim().isNotEmpty)
        .map((e) => '${e.nom} - ${e.description.trim()}')
        .toList();
    if (commentaires.isEmpty) return pw.SizedBox.shrink();
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: _cream,
        border: pw.Border.all(color: _gold, width: 0.7),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'COMMENTAIRES',
            style: pw.TextStyle(
              fontSize: 8,
              letterSpacing: 1.6,
              color: _gold,
              font: EtatDesLieuxPdfBuilder._bold,
            ),
          ),
          pw.SizedBox(height: 6),
          ...commentaires.map(
            (c) => pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 3),
              child: pw.Text(
                '- $c',
                style: pw.TextStyle(
                  fontSize: 9.5,
                  color: _ink,
                  lineSpacing: 1.3,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  //                  NOTES + SIGNATURES + CERTIF
  // ============================================================

  static pw.Widget _notesBox(String notes) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: _creamDeep,
        border: pw.Border.all(color: _hairline, width: 0.5),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'NOTES GÉNÉRALES',
            style: pw.TextStyle(
              fontSize: 8,
              letterSpacing: 1.6,
              color: _muted,
              font: EtatDesLieuxPdfBuilder._bold,
            ),
          ),
          pw.SizedBox(height: 6),
          pw.Text(
            notes,
            style: pw.TextStyle(
              fontSize: 10,
              color: _ink,
              lineSpacing: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _signaturesBlock({
    required EtatDesLieux edl,
    required UserProfile bailleur,
    required Locataire locataire,
    required pw.MemoryImage? bailleurSignature,
    required pw.MemoryImage? locataireSignature,
    required DateFormat dateTimeFmt,
  }) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          child: _signatureBox(
            label: 'Bailleur',
            roman: 'i.',
            name: bailleur.fullName,
            signature: bailleurSignature,
            signedAt: edl.proprietaireSignatureAt,
            dateTimeFmt: dateTimeFmt,
            pendingLabel: null,
          ),
        ),
        pw.SizedBox(width: 14),
        pw.Expanded(
          child: _signatureBox(
            label: 'Locataire',
            roman: 'ii.',
            name: locataire.fullName,
            signature: locataireSignature,
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
    required String label,
    required String roman,
    required String name,
    required pw.MemoryImage? signature,
    required DateTime? signedAt,
    required DateFormat dateTimeFmt,
    String? pendingLabel,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.fromLTRB(14, 12, 14, 12),
      constraints: const pw.BoxConstraints(minHeight: 150),
      decoration: pw.BoxDecoration(
        color: _creamDeep,
        border: pw.Border.all(color: _hairline, width: 0.5),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            children: [
              pw.Text(
                roman,
                style: pw.TextStyle(
                  fontSize: 11,
                  font: EtatDesLieuxPdfBuilder._italic,
                  color: _gold,
                ),
              ),
              pw.SizedBox(width: 6),
              pw.Text(
                label.toUpperCase(),
                style: pw.TextStyle(
                  fontSize: 8,
                  letterSpacing: 2,
                  font: EtatDesLieuxPdfBuilder._bold,
                  color: _muted,
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            name,
            style: pw.TextStyle(
              fontSize: 12,
              font: EtatDesLieuxPdfBuilder._bold,
              color: _ink,
            ),
          ),
          pw.SizedBox(height: 8),
          pw.Container(
            height: 70,
            alignment: pw.Alignment.centerLeft,
            decoration: const pw.BoxDecoration(
              border: pw.Border(
                bottom: pw.BorderSide(color: _hairline, width: 0.5),
              ),
            ),
            child: signature != null
                ? pw.Image(signature, height: 70, fit: pw.BoxFit.contain)
                : pw.Center(
                    child: pw.Text(
                      pendingLabel ?? 'Signature à venir',
                      style: pw.TextStyle(
                        fontSize: 10,
                        font: EtatDesLieuxPdfBuilder._italic,
                        color: _muted,
                      ),
                    ),
                  ),
          ),
          pw.SizedBox(height: 6),
          pw.Text(
            signedAt != null
                ? 'Signé le ${dateTimeFmt.format(signedAt.toLocal())}'
                : 'Non signé',
            style: pw.TextStyle(
              fontSize: 8.5,
              color: _muted,
              font: EtatDesLieuxPdfBuilder._italic,
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _certificationBox(EtatDesLieux edl) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: _green,
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            children: [
              pw.Text(
                'CERTIFICATION D\'INTÉGRITÉ',
                style: pw.TextStyle(
                  fontSize: 9,
                  letterSpacing: 2,
                  color: _gold,
                  font: EtatDesLieuxPdfBuilder._bold,
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 6),
          pw.Text(
            'Ce document a été co-signé électroniquement et scellé par un hash '
            'SHA-256. Toute modification ultérieure invaliderait le scellement.',
            style: pw.TextStyle(
              fontSize: 9,
              color: _cream,
              lineSpacing: 1.3,
            ),
          ),
          pw.SizedBox(height: 8),
          pw.Text(
            'Hash : ${edl.integrityHash ?? '-'}',
            style: pw.TextStyle(
              fontSize: 7,
              font: pw.Font.courier(),
              color: _cream,
            ),
          ),
          pw.SizedBox(height: 1),
          pw.Text(
            'ID : ${edl.id}',
            style: pw.TextStyle(
              fontSize: 7,
              font: pw.Font.courier(),
              color: _cream,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  //                       PLAN (paysage)
  // ============================================================

  static pw.Widget _planPage(
    PlanLogement plan,
    pw.MemoryImage? bg,
    EtatDesLieux edl,
    UserProfile bailleur,
  ) {
    final initial = bailleur.fullName.trim().isEmpty
        ? '-'
        : bailleur.fullName.trim()[0].toUpperCase();
    return pw.Container(
      width: double.infinity,
      height: double.infinity,
      color: _cream,
      padding: const pw.EdgeInsets.fromLTRB(40, 36, 40, 36),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Container(
                width: 18,
                height: 18,
                decoration: pw.BoxDecoration(
                  color: _green,
                  borderRadius: pw.BorderRadius.circular(1.5),
                ),
                alignment: pw.Alignment.center,
                child: pw.Text(
                  initial,
                  style: pw.TextStyle(
                    color: _cream,
                    fontSize: 11,
                    font: EtatDesLieuxPdfBuilder._boldItalic,
                  ),
                ),
              ),
              pw.SizedBox(width: 10),
              pw.RichText(
                text: pw.TextSpan(
                  children: [
                    pw.TextSpan(
                      text: 'Plan ',
                      style: pw.TextStyle(
                        fontSize: 13,
                        font: EtatDesLieuxPdfBuilder._bold,
                        color: _ink,
                      ),
                    ),
                    pw.TextSpan(
                      text: '- ${plan.kind.label}'
                          '${plan.name.trim().isNotEmpty ? ' : ${plan.name.trim()}' : ''}',
                      style: pw.TextStyle(
                        fontSize: 13,
                        font: EtatDesLieuxPdfBuilder._italic,
                        color: _green,
                      ),
                    ),
                  ],
                ),
              ),
              pw.Spacer(),
              pw.Text(
                edl.titre,
                style: pw.TextStyle(
                  fontSize: 9,
                  color: _muted,
                  font: EtatDesLieuxPdfBuilder._italic,
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 6),
          pw.Container(height: 0.6, color: _gold),
          pw.SizedBox(height: 12),
          pw.Expanded(
            child: pw.Container(
              decoration: pw.BoxDecoration(
                color: _cream,
                border: pw.Border.all(color: _hairline, width: 0.5),
              ),
              padding: const pw.EdgeInsets.all(6),
              child: _planCanvas(plan, bg),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  //                       ANNEXE PHOTOS
  // ============================================================

  static pw.Widget _annexGrid(List<_AnnexPhoto> entries) {
    return pw.Wrap(
      spacing: 10,
      runSpacing: 10,
      children: entries.map(_annexCard).toList(),
    );
  }

  static pw.Widget _annexCard(_AnnexPhoto entry) {
    return pw.Container(
      width: 235,
      decoration: pw.BoxDecoration(
        color: _creamDeep,
        border: pw.Border.all(color: _hairline, width: 0.5),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Image(
            entry.image,
            width: 235,
            height: 188,
            fit: pw.BoxFit.cover,
          ),
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  entry.piece.toUpperCase(),
                  style: pw.TextStyle(
                    fontSize: 8,
                    letterSpacing: 1.5,
                    color: _gold,
                    font: EtatDesLieuxPdfBuilder._bold,
                  ),
                ),
                pw.SizedBox(height: 1),
                pw.Text(
                  entry.label,
                  style: pw.TextStyle(
                    fontSize: 9.5,
                    color: _ink,
                    font: EtatDesLieuxPdfBuilder._italic,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  //                       SOMMAIRE - données
  // ============================================================

  static List<_TocEntry> _buildToc({
    required List<Piece> pieces,
    required bool hasMetadata,
    required int planCount,
    required int annexCount,
  }) {
    var page = 1;
    final out = <_TocEntry>[];
    out.add(_TocEntry(
      number: '01',
      title: 'Couverture',
      page: _n2(page++),
      subtitle: 'Présentation du document',
    ));
    out.add(_TocEntry(
      number: '02',
      title: 'Sommaire',
      page: _n2(page++),
      subtitle: 'Table des sections',
    ));
    out.add(_TocEntry(
      number: '03',
      title: 'Parties & logement',
      page: _n2(page++),
      subtitle: hasMetadata
          ? 'Bailleur - locataire - logement - relevés'
          : 'Bailleur - locataire - logement',
    ));
    for (var i = 0; i < pieces.length; i++) {
      out.add(_TocEntry(
        number: _n2(i + 4),
        title: 'Inspection - ${pieces[i].nom}',
        page: _n2(page++),
        subtitle:
            '${pieces[i].elements.length} élément${pieces[i].elements.length > 1 ? 's' : ''}',
      ));
    }
    if (planCount > 0) {
      out.add(_TocEntry(
        number: _n2(out.length + 1),
        title: planCount > 1 ? 'Plans du logement' : 'Plan du logement',
        page: _n2(page),
        subtitle: '$planCount document${planCount > 1 ? 's' : ''} graphique${planCount > 1 ? 's' : ''}',
      ));
      page += planCount;
    }
    if (annexCount > 0) {
      out.add(_TocEntry(
        number: _n2(out.length + 1),
        title: 'Annexe photographique',
        page: _n2(page++),
        subtitle: '$annexCount cliché${annexCount > 1 ? 's' : ''}',
      ));
    }
    out.add(_TocEntry(
      number: _n2(out.length + 1),
      title: 'Signatures & certification',
      page: _n2(page),
      subtitle: 'Co-signature et scellement',
    ));
    return out;
  }

  // ============================================================
  //                       HELPERS - chargement & images
  // ============================================================

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

  static Future<Map<String, pw.MemoryImage?>> _loadWallPhotos(
    List<WallPhoto> wallPhotos,
  ) async {
    final map = <String, pw.MemoryImage?>{};
    for (final w in wallPhotos) {
      if (map.containsKey(w.path)) continue;
      try {
        final file = File(w.path);
        if (!await file.exists()) {
          map[w.path] = null;
          continue;
        }
        final bytes = await file.readAsBytes();
        map[w.path] = pw.MemoryImage(bytes);
      } catch (_) {
        map[w.path] = null;
      }
    }
    return map;
  }

  static Map<String, List<WallPhoto>> _groupWallPhotosByRoom(
    List<WallPhoto> wallPhotos,
  ) {
    final out = <String, List<WallPhoto>>{};
    for (final w in wallPhotos) {
      final key = _normalizeRoomName(w.roomName);
      out.putIfAbsent(key, () => <WallPhoto>[]).add(w);
    }
    for (final list in out.values) {
      list.sort((a, b) {
        final c = a.wallNumber.compareTo(b.wallNumber);
        if (c != 0) return c;
        return a.takenAt.compareTo(b.takenAt);
      });
    }
    return out;
  }

  static String _normalizeRoomName(String name) => name.trim().toLowerCase();

  static List<_AnnexPhoto> _collectAnnexPhotos(
    List<Piece> pieces,
    List<WallPhoto> wallPhotos,
    Map<String, pw.MemoryImage?> photoCache,
    Map<String, pw.MemoryImage?> wallPhotoCache,
  ) {
    final out = <_AnnexPhoto>[];
    for (final piece in pieces) {
      for (final element in piece.elements) {
        for (final path in element.photoPaths.take(_maxPhotosPerElement)) {
          final img = photoCache[path];
          if (img == null) continue;
          out.add(_AnnexPhoto(
            image: img,
            piece: piece.nom,
            label: element.nom,
          ));
        }
      }
    }
    for (final w in wallPhotos) {
      final img = wallPhotoCache[w.path];
      if (img == null) continue;
      out.add(_AnnexPhoto(
        image: img,
        piece: w.roomName,
        label: 'Mur - ${w.label}',
      ));
    }
    return out;
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

  static String _n2(int n) => n.toString().padLeft(2, '0');

  // ============================================================
  //                       PLAN - dessin (inchangé)
  // ============================================================

  static const List<PdfColor> _planRoomColors = [
    PdfColor.fromInt(0xFFBFDBFE),
    PdfColor.fromInt(0xFFFECACA),
    PdfColor.fromInt(0xFFFEF3C7),
    PdfColor.fromInt(0xFFD9F99D),
    PdfColor.fromInt(0xFFC7D2FE),
    PdfColor.fromInt(0xFFFBCFE8),
    PdfColor.fromInt(0xFFA7F3D0),
    PdfColor.fromInt(0xFFE2E8F0),
  ];

  static PdfColor _roomColor(int idx) {
    final i = idx.clamp(0, _planRoomColors.length - 1);
    return _planRoomColors[i];
  }

  static PdfColor _withAlpha(PdfColor c, double a) =>
      PdfColor(c.red, c.green, c.blue, a);

  static pw.Widget _planCanvas(PlanLogement plan, pw.MemoryImage? bg) {
    final wallNumbers = _computeWallNumbersForPdf(plan);
    return pw.LayoutBuilder(
      builder: (ctx, constraints) {
        final w = constraints!.maxWidth;
        final h = constraints.maxHeight;
        final children = <pw.Widget>[];
        if (bg != null) {
          children.add(
            pw.Positioned.fill(
              child: pw.Image(bg, fit: pw.BoxFit.contain),
            ),
          );
        }
        for (final r in plan.rooms) {
          final color = _roomColor(r.colorIndex);
          final left = r.x * w;
          final top = r.y * h;
          final rectW = r.width * w;
          final rectH = r.height * h;
          if (r.isPolygon) {
            children.add(
              pw.Positioned(
                left: left,
                top: top,
                child: pw.SizedBox(
                  width: rectW,
                  height: rectH,
                  child: pw.CustomPaint(
                    painter: (canvas, size) =>
                        _drawPolygonShape(canvas, size, r, color),
                  ),
                ),
              ),
            );
          } else {
            children.add(
              pw.Positioned(
                left: left,
                top: top,
                child: pw.Container(
                  width: rectW,
                  height: rectH,
                  decoration: pw.BoxDecoration(
                    color: _withAlpha(color, 0.35),
                    border: _rectBorder(r, color),
                  ),
                ),
              ),
            );
          }
          children.add(
            pw.Positioned(
              left: left,
              top: top,
              child: pw.SizedBox(
                width: rectW,
                height: rectH,
                child: pw.Center(
                  child: pw.Text(
                    r.name,
                    style: pw.TextStyle(
                      fontSize: 8,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.grey900,
                    ),
                    textAlign: pw.TextAlign.center,
                    maxLines: 2,
                    overflow: pw.TextOverflow.clip,
                  ),
                ),
              ),
            ),
          );
          final nums = wallNumbers[r.id] ?? const <String, int>{};
          if (r.isPolygon) {
            final n = r.vertexCount;
            for (var i = 0; i < n; i++) {
              final wallNum = nums['edge:$i'];
              if (wallNum == null) continue;
              final v0 = r.vertexAt(i);
              final v1 = r.vertexAt((i + 1) % n);
              final mx = (v0.vx + v1.vx) / 2 * w;
              final my = (v0.vy + v1.vy) / 2 * h;
              children.add(
                pw.Positioned(
                  left: mx - 9,
                  top: my - 6,
                  child: _wallBadge(wallNum),
                ),
              );
            }
          } else {
            final cxPx = left + rectW / 2;
            final cyPx = top + rectH / 2;
            for (final s in const ['top', 'right', 'bottom', 'left']) {
              final wallNum = nums[s];
              if (wallNum == null) continue;
              double bx = cxPx, by = cyPx;
              switch (s) {
                case 'top':
                  by = top;
                  break;
                case 'bottom':
                  by = top + rectH;
                  break;
                case 'left':
                  bx = left;
                  break;
                case 'right':
                  bx = left + rectW;
                  break;
              }
              children.add(
                pw.Positioned(
                  left: bx - 9,
                  top: by - 6,
                  child: _wallBadge(wallNum),
                ),
              );
            }
          }
        }
        return pw.Stack(children: children);
      },
    );
  }

  static pw.Widget _wallBadge(int n) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 1),
      decoration: pw.BoxDecoration(
        color: _cream,
        borderRadius: pw.BorderRadius.circular(2),
        border: pw.Border.all(color: _green, width: 0.6),
      ),
      child: pw.Text(
        'M$n',
        style: pw.TextStyle(
          fontSize: 6.5,
          fontWeight: pw.FontWeight.bold,
          color: _green,
        ),
      ),
    );
  }

  static Map<String, Map<String, int>> _computeWallNumbersForPdf(
      PlanLogement plan) {
    final result = <String, Map<String, int>>{};
    for (final r in plan.rooms) {
      if (r.isPolygon) {
        final perEdge = <String, int>{};
        var counter = 1;
        final n = r.vertexCount;
        for (var i = 0; i < n; i++) {
          if (r.hiddenWalls.contains('edge:$i')) continue;
          perEdge['edge:$i'] = counter++;
        }
        if (perEdge.isNotEmpty) result[r.id] = perEdge;
        continue;
      }
      final shared = _sharedSidesForPdf(r, plan);
      final perRoom = <String, int>{};
      var counter = 1;
      for (final s in const ['top', 'right', 'bottom', 'left']) {
        final isShared = switch (s) {
          'top' => shared.top,
          'right' => shared.right,
          'bottom' => shared.bottom,
          'left' => shared.left,
          _ => false,
        };
        if (isShared) continue;
        if (r.hiddenWalls.contains(s)) continue;
        perRoom[s] = counter++;
      }
      if (perRoom.isNotEmpty) result[r.id] = perRoom;
    }
    return result;
  }

  static ({bool top, bool right, bool bottom, bool left}) _sharedSidesForPdf(
      RoomShape r, PlanLogement plan) {
    if (r.isPolygon) {
      return (top: false, right: false, bottom: false, left: false);
    }
    const eps = 0.003;
    bool top = false, right = false, bottom = false, left = false;
    final rR = r.x + r.width;
    final rB = r.y + r.height;
    for (final o in plan.rooms) {
      if (o.id == r.id) continue;
      if (o.isPolygon) continue;
      if (o.name != r.name) continue;
      final oR = o.x + o.width;
      final oB = o.y + o.height;
      final hOverlap = math.max(0.0, math.min(rB, oB) - math.max(r.y, o.y));
      final vOverlap = math.max(0.0, math.min(rR, oR) - math.max(r.x, o.x));
      if ((rR - o.x).abs() < eps && hOverlap > eps) right = true;
      if ((oR - r.x).abs() < eps && hOverlap > eps) left = true;
      if ((rB - o.y).abs() < eps && vOverlap > eps) bottom = true;
      if ((oB - r.y).abs() < eps && vOverlap > eps) top = true;
    }
    return (top: top, right: right, bottom: bottom, left: left);
  }

  static pw.Border _rectBorder(RoomShape r, PdfColor color) {
    final side = pw.BorderSide(color: color, width: 1.4);
    const none = pw.BorderSide.none;
    return pw.Border(
      top: r.hiddenWalls.contains('top') ? none : side,
      right: r.hiddenWalls.contains('right') ? none : side,
      bottom: r.hiddenWalls.contains('bottom') ? none : side,
      left: r.hiddenWalls.contains('left') ? none : side,
    );
  }

  static void _drawPolygonShape(
    PdfGraphics canvas,
    PdfPoint size,
    RoomShape r,
    PdfColor color,
  ) {
    if (!r.isPolygon || r.width <= 0 || r.height <= 0) return;
    final n = r.vertexCount;
    final pts = <List<double>>[];
    for (var i = 0; i < n; i++) {
      final v = r.vertexAt(i);
      final lx = (v.vx - r.x) / r.width * size.x;
      final ly = size.y - ((v.vy - r.y) / r.height * size.y);
      pts.add([lx, ly]);
    }
    canvas.setFillColor(_withAlpha(color, 0.35));
    canvas.moveTo(pts[0][0], pts[0][1]);
    for (var i = 1; i < pts.length; i++) {
      canvas.lineTo(pts[i][0], pts[i][1]);
    }
    canvas.closePath();
    canvas.fillPath();
    canvas.setStrokeColor(color);
    canvas.setLineWidth(1.4);
    for (var i = 0; i < pts.length; i++) {
      if (r.hiddenWalls.contains('edge:$i')) continue;
      final a = pts[i];
      final b = pts[(i + 1) % pts.length];
      canvas.drawLine(a[0], a[1], b[0], b[1]);
    }
    canvas.strokePath();
  }
}

class _MetaEntry {
  final String label;
  final String value;
  _MetaEntry(this.label, this.value);
}

class _AnnexPhoto {
  final pw.MemoryImage image;
  final String piece;
  final String label;
  _AnnexPhoto({
    required this.image,
    required this.piece,
    required this.label,
  });
}

class _TocEntry {
  final String number;
  final String title;
  final String page;
  final String? subtitle;
  _TocEntry({
    required this.number,
    required this.title,
    required this.page,
    this.subtitle,
  });
}
