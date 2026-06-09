import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../core/constants.dart';
import '../core/pdf/contrat_bail_pdf.dart';
import '../core/pdf/etat_des_lieux_pdf.dart';
import '../core/pdf/quittance_pdf.dart';
import '../core/storage/local_database.dart';
import '../models/locataire.dart';

/// Format de sortie du dossier locataire.
enum DossierFormat {
  pdfFusionne, // un seul PDF (pages rastérisées) — s'ouvre d'un double-clic partout
  zip, // ZIP standard de PDF — se décompresse sur tous les OS
}

/// Qualité des photos / pages dans le dossier exporté.
enum DossierQualite {
  leger, // compressé (rastérisation basse résolution) — adapté à l'e-mail
  max, // qualité maximale
}

/// Un document du dossier (PDF natif + nom de fichier + libellé lisible).
class DossierDoc {
  final String filename;
  final String label;
  final Uint8List bytes;
  const DossierDoc(this.filename, this.label, this.bytes);
}

/// Résultat d'un export : octets prêts à partager + métadonnées + textes
/// d'e-mail pré-remplis (objet + corps).
class DossierExport {
  final Uint8List bytes;
  final String filename;
  final bool isPdf;
  final int docCount;

  /// Noms des destinataires (locataire + colocataires) pour l'e-mail.
  final List<String> recipientNames;

  /// E-mails des destinataires (locataire + colocataires), pour pré-remplir
  /// le champ « À » du composeur.
  final List<String> recipientEmails;
  final String emailSubject;
  final String emailBody;

  const DossierExport({
    required this.bytes,
    required this.filename,
    required this.isPdf,
    required this.docCount,
    required this.recipientNames,
    required this.recipientEmails,
    required this.emailSubject,
    required this.emailBody,
  });

  int get sizeBytes => bytes.length;
  double get sizeMo => bytes.length / (1024 * 1024);
}

/// Construit un « dossier locataire » (quittances + bail + EDL) dans un format
/// universel (PDF fusionné ou ZIP de PDF), ouvrable sur n'importe quel OS sans
/// l'application ADDA Locataire.
class DossierLocataireService {
  static const int seuilEmailOctets = 20 * 1024 * 1024; // ~20 Mo

  static String _two(int n) => n.toString().padLeft(2, '0');

  static const List<String> _moisFr = [
    'janvier', 'février', 'mars', 'avril', 'mai', 'juin',
    'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre',
  ];

  /// Le locataire + les colocataires partageant un bail avec lui.
  static List<Locataire> _recipients(Locataire loc) {
    final ids = <String>{loc.id};
    for (final b in LocalDatabase.contratsBailBox.values
        .where((b) => b.locataireIds.contains(loc.id))) {
      ids.addAll(b.locataireIds);
    }
    final byId = {for (final l in LocalDatabase.locatairesBox.values) l.id: l};
    return ids.map((id) => byId[id]).whereType<Locataire>().toList();
  }

  /// Construit l'objet et le corps d'e-mail pré-remplis : salutation avec les
  /// prénoms du/des colocataire(s) + liste des documents joints + signature.
  static ({
    List<String> names,
    List<String> emails,
    String subject,
    String body
  }) _buildEmail(Locataire loc, List<DossierDoc> docs) {
    final recipients = _recipients(loc);
    final names = recipients.map((r) => r.fullName).toList();
    final emails =
        recipients.map((r) => r.email).where((e) => e.isNotEmpty).toList();
    final prenoms = recipients
        .map((r) => r.firstName)
        .where((s) => s.isNotEmpty)
        .toList();
    final bailleur = LocalDatabase.userBox.get(AppConstants.userProfileKey);
    final b = StringBuffer()
      ..writeln('Bonjour${prenoms.isEmpty ? '' : ' ${prenoms.join(', ')}'},')
      ..writeln()
      ..writeln(docs.length > 1
          ? 'Veuillez trouver ci-joint les ${docs.length} documents suivants :'
          : 'Veuillez trouver ci-joint le document suivant :');
    for (final d in docs) {
      b.writeln('  • ${d.label}');
    }
    b
      ..writeln()
      ..writeln('Cordialement,')
      ..write(bailleur?.fullName ?? '');
    return (
      names: names,
      emails: emails,
      subject: 'Vos documents de location',
      body: b.toString(),
    );
  }

  /// Construit l'e-mail de relance d'un loyer impayé : destinataire, objet et
  /// corps pré-remplis (salutation avec les prénoms du/des colocataire(s),
  /// période et montant dû, signature bailleur).
  static ({String to, String subject, String body}) relanceEmail(
    Locataire loc, {
    required String periode,
    required String montant,
  }) {
    final recipients = _recipients(loc);
    final prenoms = recipients
        .map((r) => r.firstName)
        .where((s) => s.isNotEmpty)
        .toList();
    final bailleur = LocalDatabase.userBox.get(AppConstants.userProfileKey);
    final body = (StringBuffer()
          ..writeln(
              'Bonjour${prenoms.isEmpty ? '' : ' ${prenoms.join(', ')}'},')
          ..writeln()
          ..writeln(
              'Sauf erreur ou règlement de votre part, le loyer de $periode '
              "d'un montant de $montant reste impayé à ce jour.")
          ..writeln()
          ..writeln(
              'Nous vous remercions de bien vouloir procéder à son règlement '
              'dans les meilleurs délais. Si le paiement a déjà été effectué, '
              'merci de ne pas tenir compte de ce message.')
          ..writeln()
          ..writeln('Cordialement,')
          ..write(bailleur?.fullName ?? ''))
        .toString();
    return (
      to: loc.email,
      subject: 'Relance — loyer impayé ($periode)',
      body: body,
    );
  }

  /// Génère les PDF natifs de tous les documents rattachés à [loc].
  static Future<List<DossierDoc>> collect(Locataire loc) async {
    final docs = <DossierDoc>[];
    final bailleur = LocalDatabase.userBox.get(AppConstants.userProfileKey);
    if (bailleur == null) return docs;

    final logements = {
      for (final l in LocalDatabase.logementsBox.values) l.id: l,
    };
    final nom = loc.lastName.isEmpty ? 'locataire' : loc.lastName;

    // 1) Quittances du locataire.
    final quittances = LocalDatabase.quittancesBox.values
        .where((q) => q.locataireId == loc.id)
        .toList()
      ..sort((a, b) => a.periodYear != b.periodYear
          ? a.periodYear.compareTo(b.periodYear)
          : a.periodMonth.compareTo(b.periodMonth));
    for (final q in quittances) {
      final log = logements[q.logementId];
      if (log == null) continue;
      final doc = await QuittancePdfBuilder.build(
        quittance: q,
        bailleur: bailleur,
        logement: log,
        locataire: loc,
      );
      final moisLabel = (q.periodMonth >= 1 && q.periodMonth <= 12)
          ? _moisFr[q.periodMonth - 1]
          : '${q.periodMonth}';
      docs.add(DossierDoc(
        'Quittance_${q.periodYear}-${_two(q.periodMonth)}_$nom.pdf',
        'Quittance $moisLabel ${q.periodYear}',
        await doc.save(),
      ));
    }

    // 2) Bail(s) du locataire.
    final baux = LocalDatabase.contratsBailBox.values
        .where((b) => b.locataireIds.contains(loc.id))
        .toList();
    for (final b in baux) {
      final log = logements[b.logementId];
      if (log == null) continue;
      final diags = LocalDatabase.diagnosticsBox.values
          .where((d) => d.logementId == b.logementId)
          .toList();
      final locs = LocalDatabase.locatairesBox.values
          .where((l) => b.locataireIds.contains(l.id))
          .toList();
      final doc = await ContratBailPdfBuilder.build(
        bail: b,
        bailleur: bailleur,
        logement: log,
        locataires: locs,
        diagnostics: diags,
      );
      docs.add(DossierDoc(
        'Bail_${b.reference}.pdf',
        'Bail ${b.reference}',
        await doc.save(),
      ));
    }

    // 3) États des lieux du locataire (avec photos de murs liées à cet EDL).
    final edls = LocalDatabase.etatDesLieuxBox.values
        .where((e) => e.locataireId == loc.id)
        .toList();
    for (final e in edls) {
      final log = logements[e.logementId];
      if (log == null) continue;
      final plans = LocalDatabase.plansLogementBox.values
          .where((p) => p.logementId == e.logementId)
          .toList();
      final wallPhotos = plans
          .expand((p) => p.wallPhotos)
          .where((wp) => wp.etatId == e.id)
          .toList();
      final doc = await EtatDesLieuxPdfBuilder.build(
        edl: e,
        bailleur: bailleur,
        logement: log,
        locataire: loc,
        wallPhotos: wallPhotos,
        plans: plans,
      );
      final d = e.date;
      final edlType = e.type.name == 'entree' ? "d'entrée" : 'de sortie';
      docs.add(DossierDoc(
        'EDL_${e.type.name}_${d.year}-${_two(d.month)}-${_two(d.day)}_$nom.pdf',
        'État des lieux $edlType du ${_two(d.day)}/${_two(d.month)}/${d.year}',
        await doc.save(),
      ));
    }

    return docs;
  }

  /// Rastérise un PDF en un nouveau PDF (1 image par page) à la résolution
  /// [dpi]. Sert à la fois à fusionner et à compresser.
  static Future<Uint8List> _rasterize(Uint8List pdf, double dpi) async {
    final out = pw.Document();
    await for (final page in Printing.raster(pdf, dpi: dpi)) {
      final png = await page.toPng();
      final img = pw.MemoryImage(png);
      final wPt = page.width / dpi * 72.0;
      final hPt = page.height / dpi * 72.0;
      out.addPage(
        pw.Page(
          pageFormat: PdfPageFormat(wPt, hPt),
          margin: pw.EdgeInsets.zero,
          build: (_) => pw.Image(img, fit: pw.BoxFit.fill),
        ),
      );
    }
    return out.save();
  }

  static double _dpiFor(DossierQualite q) =>
      q == DossierQualite.leger ? 100 : 200;

  /// Construit le dossier final selon le format et la qualité demandés.
  static Future<DossierExport> build(
    Locataire loc, {
    required DossierFormat format,
    required DossierQualite qualite,
  }) async {
    final docs = await collect(loc);
    final nom = loc.lastName.isEmpty ? 'locataire' : loc.lastName;
    final dpi = _dpiFor(qualite);
    final email = _buildEmail(loc, docs);

    if (format == DossierFormat.pdfFusionne) {
      final merged = pw.Document();
      for (final d in docs) {
        await for (final page in Printing.raster(d.bytes, dpi: dpi)) {
          final png = await page.toPng();
          final img = pw.MemoryImage(png);
          final wPt = page.width / dpi * 72.0;
          final hPt = page.height / dpi * 72.0;
          merged.addPage(
            pw.Page(
              pageFormat: PdfPageFormat(wPt, hPt),
              margin: pw.EdgeInsets.zero,
              build: (_) => pw.Image(img, fit: pw.BoxFit.fill),
            ),
          );
        }
      }
      return DossierExport(
        bytes: await merged.save(),
        filename: 'Dossier_$nom.pdf',
        isPdf: true,
        docCount: docs.length,
        recipientNames: email.names,
        recipientEmails: email.emails,
        emailSubject: email.subject,
        emailBody: email.body,
      );
    }

    // ZIP : en qualité « léger » on rastérise chaque PDF pour réduire la
    // taille ; en « max » on garde les PDF natifs (texte sélectionnable).
    final archive = Archive();
    for (final d in docs) {
      final bytes =
          qualite == DossierQualite.leger ? await _rasterize(d.bytes, dpi) : d.bytes;
      archive.addFile(ArchiveFile(d.filename, bytes.length, bytes));
    }
    final encoded = ZipEncoder().encode(archive);
    return DossierExport(
      bytes: Uint8List.fromList(encoded),
      filename: 'Dossier_$nom.zip',
      isPdf: false,
      docCount: docs.length,
      recipientNames: email.names,
      recipientEmails: email.emails,
      emailSubject: email.subject,
      emailBody: email.body,
    );
  }
}
