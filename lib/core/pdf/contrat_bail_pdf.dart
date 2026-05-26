import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../models/contrat_bail.dart';
import '../../models/diagnostic.dart';
import '../../models/locataire.dart';
import '../../models/logement.dart';
import '../../models/user_profile.dart';

/// Génère le PDF d'un contrat de bail conforme à la loi ALUR et au Code
/// civil (articles 1708 à 1762). Couvre les 5 types de bail :
/// vide / meublé / colocation / saisonnier / mobilité.
class ContratBailPdfBuilder {
  static const PdfColor _ink = PdfColor.fromInt(0xFF1A1A1A);
  static const PdfColor _muted = PdfColor.fromInt(0xFF555555);
  static const PdfColor _accent = PdfColor.fromInt(0xFF1E3A8A);
  static const PdfColor _hairline = PdfColor.fromInt(0xFFCFCFCF);
  static const PdfColor _bg = PdfColor.fromInt(0xFFFFFFFF);

  /// Charge les 3 polices Roboto depuis les assets — doit être appelé sur
  /// l'isolate principal (rootBundle n'est pas accessible ailleurs).
  static Future<({ByteData regular, ByteData bold, ByteData italic})>
      loadFontBytes() async {
    final regular = await rootBundle.load('assets/fonts/Roboto-Regular.ttf');
    final bold = await rootBundle.load('assets/fonts/Roboto-Bold.ttf');
    final italic = await rootBundle.load('assets/fonts/Roboto-Italic.ttf');
    return (regular: regular, bold: bold, italic: italic);
  }

  static Future<pw.Document> build({
    required ContratBail bail,
    required UserProfile bailleur,
    required Logement logement,
    required List<Locataire> locataires,
    List<Diagnostic> diagnostics = const [],
    ({ByteData regular, ByteData bold, ByteData italic})? preloadedFonts,
  }) async {
    // Charge Roboto en TTF pour avoir un support Unicode complet
    // (€, espaces insécables, guillemets typographiques, accents) —
    // les fonts intégrées du PDF (Times/Helvetica) ne couvrent pas tout
    // et affichent des carrés à la place des glyphes manquants.
    // L'isolate spawné par Isolate.run n'hérite pas des données de locale
    // initialisées sur l'isolate principal. On les ré-initialise ici pour
    // que `DateFormat('dd/MM/yyyy', 'fr_FR')` fonctionne.
    await initializeDateFormatting('fr_FR', null);

    final fonts = preloadedFonts ?? await loadFontBytes();
    final fontRegular = pw.Font.ttf(fonts.regular);
    final fontBold = pw.Font.ttf(fonts.bold);
    final fontItalic = pw.Font.ttf(fonts.italic);

    final doc = pw.Document(
      title: '${bail.reference} - ${bail.type.label}',
      author: bailleur.fullName,
      theme: pw.ThemeData.withFont(
        base: fontRegular,
        bold: fontBold,
        italic: fontItalic,
      ),
    );

    final money = NumberFormat.currency(locale: 'fr_FR', symbol: '€');
    final dateFmt = DateFormat('dd/MM/yyyy', 'fr_FR');
    final dateLong = DateFormat('d MMMM yyyy', 'fr_FR');

    final bodyStyle = pw.TextStyle(fontSize: 10, color: _ink, lineSpacing: 2);
    final h1 = pw.TextStyle(
      fontSize: 14,
      fontWeight: pw.FontWeight.bold,
      color: _accent,
    );
    final h2 = pw.TextStyle(
      fontSize: 11.5,
      fontWeight: pw.FontWeight.bold,
      color: _ink,
    );

    pw.Widget section(String title, List<pw.Widget> children) {
      return pw.Container(
        margin: const pw.EdgeInsets.only(bottom: 14),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Container(
              decoration: const pw.BoxDecoration(
                border: pw.Border(
                  bottom: pw.BorderSide(color: _accent, width: 1.5),
                ),
              ),
              padding: const pw.EdgeInsets.only(bottom: 3),
              margin: const pw.EdgeInsets.only(bottom: 8),
              child: pw.Text(title.toUpperCase(), style: h1),
            ),
            ...children,
          ],
        ),
      );
    }

    pw.Widget paragraph(String text) => pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 5),
          child: pw.Text(text, style: bodyStyle, textAlign: pw.TextAlign.justify),
        );

    pw.Widget bullet(String text) => pw.Padding(
          padding: const pw.EdgeInsets.only(left: 12, bottom: 3),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('• ', style: bodyStyle),
              pw.Expanded(
                child:
                    pw.Text(text, style: bodyStyle, textAlign: pw.TextAlign.justify),
              ),
            ],
          ),
        );

    pw.Widget kv(String label, String value) => pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 2),
          child: pw.Row(
            children: [
              pw.SizedBox(
                width: 160,
                child: pw.Text(label,
                    style: bodyStyle.copyWith(color: _muted)),
              ),
              pw.Expanded(
                child: pw.Text(value,
                    style: bodyStyle.copyWith(
                        fontWeight: pw.FontWeight.bold)),
              ),
            ],
          ),
        );

    // ---- Page de garde
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(48),
        build: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.SizedBox(height: 180),
            pw.Text('CONTRAT DE LOCATION',
                style: pw.TextStyle(
                    fontSize: 28,
                    fontWeight: pw.FontWeight.bold,
                    color: _accent)),
            pw.SizedBox(height: 8),
            pw.Text(bail.type.label.toUpperCase(),
                style: pw.TextStyle(
                    fontSize: 16,
                    color: _muted,
                    letterSpacing: 2)),
            pw.SizedBox(height: 36),
            kv('Référence', bail.reference),
            kv('Date', dateLong.format(DateTime.now())),
            kv('Logement', logement.libelle),
            kv('Adresse', bail.adresseLogement),
            pw.SizedBox(height: 24),
            kv('Bailleur', bailleur.fullName),
            kv('Locataire${locataires.length > 1 ? 's' : ''}',
                locataires.map((l) => l.fullName).join(', ')),
            pw.Spacer(),
            pw.Container(
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: _hairline),
              ),
              child: pw.Text(
                'Contrat régi par la loi du 6 juillet 1989 (loi ALUR) et les '
                'articles 1708 à 1762 du Code civil. '
                'En 2 exemplaires originaux, un pour chaque partie.',
                style: bodyStyle.copyWith(fontSize: 9, color: _muted),
              ),
            ),
          ],
        ),
      ),
    );

    // ---- Corps du contrat (multi-pages, MultiPage gère la pagination auto)
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(48, 40, 48, 50),
        header: (ctx) => pw.Container(
          padding: const pw.EdgeInsets.only(bottom: 8),
          decoration: const pw.BoxDecoration(
            border: pw.Border(
              bottom: pw.BorderSide(color: _hairline, width: 0.5),
            ),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(bail.reference,
                  style: bodyStyle.copyWith(color: _muted, fontSize: 9)),
              pw.Text(bail.type.label,
                  style: bodyStyle.copyWith(color: _muted, fontSize: 9)),
            ],
          ),
        ),
        footer: (ctx) => pw.Container(
          padding: const pw.EdgeInsets.only(top: 8),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'Conforme loi ALUR · Code civil art. 1708-1762',
                style: bodyStyle.copyWith(color: _muted, fontSize: 8),
              ),
              pw.Text(
                'Page ${ctx.pageNumber}/${ctx.pagesCount}',
                style: bodyStyle.copyWith(color: _muted, fontSize: 8),
              ),
            ],
          ),
        ),
        build: (ctx) => [
          // ARTICLE 1 - Parties
          section('Article 1 — Parties', [
            pw.Text('Bailleur', style: h2),
            pw.SizedBox(height: 4),
            kv('Nom', bailleur.fullName),
            if (bailleur.email.isNotEmpty) kv('Email', bailleur.email),
            pw.SizedBox(height: 10),
            pw.Text(
              'Locataire${locataires.length > 1 ? 's (colocation)' : ''}',
              style: h2,
            ),
            pw.SizedBox(height: 4),
            for (final l in locataires) ...[
              kv('Nom', l.fullName),
              if (l.email.isNotEmpty) kv('Email', l.email),
              if (l.phone != null && l.phone!.isNotEmpty)
                kv('Téléphone', l.phone!),
              if (l.id == bail.referentColocataireId)
                kv('Rôle', 'Référent colocataire'),
              pw.SizedBox(height: 6),
            ],
          ]),

          // ARTICLE 2 - Logement
          section('Article 2 — Description du logement', [
            kv('Adresse', bail.adresseLogement),
            kv('Type', logement.type.label),
            kv('Surface habitable',
                '${bail.surfaceM2.toStringAsFixed(1)} m² (loi Boutin)'),
            kv('Nombre de pièces', '${bail.nbPieces}'),
            if (bail.etage != null && bail.etage!.isNotEmpty)
              kv('Étage', bail.etage!),
            pw.SizedBox(height: 6),
            paragraph(
              'Le logement est loué à usage de résidence principale '
              '${bail.type == BailType.saisonnier ? '— OU MEUBLÉ DE TOURISME pour ce bail saisonnier' : ''}'
              '. Le locataire s\'engage à ne pas changer cet usage sans accord écrit du bailleur.',
            ),
          ]),

          // ARTICLE 3 - Durée
          section('Article 3 — Durée du bail', [
            kv('Date de prise d\'effet', dateLong.format(bail.dateDebut)),
            kv('Durée initiale', '${bail.dureeMois} mois'),
            kv('Date de fin', dateLong.format(bail.dateFin)),
            kv('Renouvellement tacite',
                bail.renouvellementTacite ? 'Oui' : 'Non'),
            kv('Préavis bailleur', '${bail.preavisBailleurMois} mois'),
            kv('Préavis locataire', '${bail.preavisLocataireMois} mois'),
            pw.SizedBox(height: 4),
            paragraph(_clauseDuree(bail)),
          ]),

          // ARTICLE 4 - Loyer et charges
          section('Article 4 — Loyer et charges', [
            kv('Loyer mensuel hors charges', money.format(bail.loyerHC)),
            kv('Provisions sur charges', money.format(bail.charges)),
            kv('Total mensuel', money.format(bail.totalMensuel)),
            kv('Échéance', 'Le ${bail.jourEcheance} de chaque mois'),
            kv('Mode de paiement', bail.modePaiement.label),
            if (bail.rib != null && bail.rib!.isNotEmpty)
              kv('RIB du bailleur', bail.rib!),
            kv('Dépôt de garantie', money.format(bail.depotGarantie)),
            if (bail.fraisAgence != null && bail.fraisAgence! > 0)
              kv('Frais d\'agence', money.format(bail.fraisAgence!)),
            pw.SizedBox(height: 4),
            paragraph(
              'Le dépôt de garantie sera restitué au locataire dans un délai '
              'de 1 à 2 mois après la fin du bail, sous déduction des éventuels '
              'dégâts constatés lors de l\'état des lieux de sortie (article '
              '22 de la loi du 6 juillet 1989). Le dépôt ne peut excéder '
              '${bail.type.plafondDepotMois} mois de loyer hors charges pour '
              'ce type de bail.',
            ),
            if (bail.regularisationChargesAnnuelle)
              paragraph(
                'Les charges feront l\'objet d\'une régularisation annuelle '
                'conformément à l\'article 7 de la loi du 6 juillet 1989.',
              ),
            if (bail.revisionAnnuelleIRL)
              paragraph(
                'Révision annuelle : le loyer pourra être révisé une fois par '
                'an à la date anniversaire du bail selon l\'évolution de '
                'l\'Indice de Référence des Loyers (IRL) publié par l\'INSEE. '
                'La hausse ne pourra excéder l\'évolution de l\'IRL sur la '
                'période écoulée.',
              ),
          ]),

          // ARTICLE 5 - Obligations bailleur
          section('Article 5 — Obligations du bailleur', [
            bullet(
                'Délivrer un logement décent (article 1719 du Code civil) en bon état d\'usage et de réparations.'),
            bullet('Garantir la jouissance paisible du logement.'),
            bullet(
                'Entretenir les gros ouvrages (toiture, murs porteurs, charpente) et prendre en charge les réparations autres que locatives.'),
            bullet(
                'Remettre les diagnostics obligatoires (DPE, ERP, etc.) avant la signature.'),
            bullet(
                'Souscrire une assurance Propriétaire Non Occupant (PNO) couvrant les risques locatifs.'),
          ]),

          // ARTICLE 6 - Obligations locataire
          section('Article 6 — Obligations du locataire', [
            bullet('Payer le loyer et les charges aux dates convenues.'),
            bullet(
                'User paisiblement du logement, conformément à sa destination.'),
            bullet(
                'Effectuer l\'entretien courant (menues réparations, joints, ampoules, canalisations…) et l\'entretien des équipements.'),
            bullet(
                'Souscrire une assurance habitation couvrant les risques locatifs (incendie, dégâts des eaux, etc.) et en fournir une attestation au bailleur.'),
            bullet(
                'Respecter le voisinage : pas de trouble anormal (bruit, odeurs, etc.).'),
            bullet(
                'Ne pas sous-louer ni céder le bail sans accord écrit du bailleur.'),
            if (bail.nonFumeur)
              bullet('Ne pas fumer dans le logement (clause non-fumeur).'),
            if (!bail.animauxAutorises)
              bullet(
                  'Détention d\'animaux domestiques non autorisée sans accord écrit du bailleur.')
            else if (bail.noteAnimaux != null && bail.noteAnimaux!.isNotEmpty)
              bullet('Animaux : ${bail.noteAnimaux}.'),
          ]),

          // Clauses spécifiques selon type
          ..._clausesSpecifiques(
            bail: bail,
            money: money,
            section: section,
            paragraph: paragraph,
            bullet: bullet,
            kv: kv,
            h2: h2,
            bodyStyle: bodyStyle,
          ),

          // Clauses générales
          section('Article 9 — Clauses générales', [
            pw.Text('Force majeure', style: h2),
            paragraph(
              'Aucune des parties ne pourra être tenue responsable en cas '
              'd\'impossibilité d\'exécuter ses obligations due à un cas de '
              'force majeure (article 1218 du Code civil). La partie '
              'invoquant la force majeure devra notifier l\'autre par LRAR '
              'dans les 48 heures suivant la survenance.',
            ),
            pw.SizedBox(height: 6),
            pw.Text('Résolution des litiges', style: h2),
            paragraph(
              'En cas de litige, les parties s\'engagent à tenter une '
              'médiation avec un médiateur agréé. À défaut d\'accord dans un '
              'délai d\'un mois, le litige sera porté devant la Commission '
              'Départementale de Conciliation (CDC) du département du '
              'logement, puis devant le tribunal judiciaire compétent.',
            ),
            pw.SizedBox(height: 6),
            pw.Text('Modifications', style: h2),
            paragraph(
              'Toute modification du présent contrat doit faire l\'objet '
              'd\'un avenant écrit signé par les deux parties. Les '
              'modifications unilatérales sont nulles et de nul effet.',
            ),
          ]),

          // Mentions légales
          section('Mentions légales', [
            paragraph(
              'Le présent contrat est régi par la loi n°89-462 du 6 juillet '
              '1989 (loi ALUR) et les articles 1708 à 1762 du Code civil. '
              'Le locataire dispose d\'un droit au logement décent (article '
              '1719 du Code civil). Bailleur et locataire s\'engagent à '
              'respecter leurs obligations respectives.',
            ),
            if (bail.type == BailType.meuble)
              paragraph(
                'Droit de rétractation (uniquement si signé hors '
                'établissement commercial) : 14 jours à compter de la '
                'signature.',
              ),
            paragraph(
              'Conformément au Règlement Général sur la Protection des '
              'Données (RGPD, Règlement UE 2016/679), les données '
              'personnelles collectées sont traitées pour l\'exécution du '
              'présent contrat et conservées pendant la durée du bail + 5 '
              'ans (obligation fiscale). Le locataire dispose des droits '
              'd\'accès, de rectification, d\'effacement, d\'opposition et '
              'de portabilité de ses données.',
            ),
            if (bail.notes.isNotEmpty) ...[
              pw.SizedBox(height: 6),
              pw.Text('Notes additionnelles', style: h2),
              paragraph(bail.notes),
            ],
          ]),

          // Annexes
          if (diagnostics.isNotEmpty)
            section('Annexes — Diagnostics joints', [
              for (final d in diagnostics)
                bullet(
                    '${d.type.label} — réalisé le ${dateFmt.format(d.dateRealisation)}'
                    '${d.resume.isNotEmpty ? ' (${d.resume})' : ''}'
                    '${d.estExpire ? ' — EXPIRÉ' : ''}'),
            ]),
        ],
      ),
    );

    // ---- Signatures (page dédiée si besoin)
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(48),
        build: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('SIGNATURES', style: h1),
            pw.SizedBox(height: 4),
            pw.Container(
              height: 1.5,
              color: _accent,
              width: 60,
            ),
            pw.SizedBox(height: 16),
            paragraph(
              'Fait en 2 exemplaires originaux, un pour chaque partie. '
              'Chaque partie reconnaît avoir reçu un exemplaire à la '
              'signature.',
            ),
            pw.SizedBox(height: 24),
            _signatureBlock(
              label: 'BAILLEUR',
              fullName: bailleur.fullName,
              pngBase64: bail.signatureBailleurPng,
              signedAt: bail.signatureBailleurAt,
              dateFmt: dateFmt,
              h2: h2,
              bodyStyle: bodyStyle,
            ),
            pw.SizedBox(height: 24),
            for (final l in locataires) ...[
              _signatureBlock(
                label: 'LOCATAIRE — ${l.fullName.toUpperCase()}',
                fullName: l.fullName,
                pngBase64: bail.signaturesLocatairesPng[l.id],
                signedAt: bail.signaturesLocatairesAt[l.id] != null
                    ? DateTime.tryParse(bail.signaturesLocatairesAt[l.id]!)
                    : null,
                dateFmt: dateFmt,
                h2: h2,
                bodyStyle: bodyStyle,
              ),
              pw.SizedBox(height: 18),
            ],
            pw.Spacer(),
            if (bail.integrityHash != null) ...[
              pw.Divider(color: _hairline),
              pw.Text(
                'Hash SHA-256 d\'intégrité : ${bail.integrityHash}',
                style: bodyStyle.copyWith(
                    fontSize: 7,
                    color: _muted,
                    fontStyle: pw.FontStyle.italic),
              ),
            ],
          ],
        ),
      ),
    );

    return doc;
  }

  static pw.Widget _signatureBlock({
    required String label,
    required String fullName,
    required String? pngBase64,
    required DateTime? signedAt,
    required DateFormat dateFmt,
    required pw.TextStyle h2,
    required pw.TextStyle bodyStyle,
  }) {
    pw.Widget signatureImage;
    if (pngBase64 != null && pngBase64.isNotEmpty) {
      try {
        final bytes = base64Decode(pngBase64);
        signatureImage = pw.Container(
          width: 200,
          height: 70,
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: _hairline, width: 0.5),
          ),
          child: pw.Image(pw.MemoryImage(bytes), fit: pw.BoxFit.contain),
        );
      } catch (_) {
        signatureImage = _emptySignatureBox();
      }
    } else {
      signatureImage = _emptySignatureBox();
    }
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(label, style: h2.copyWith(fontSize: 10)),
        pw.SizedBox(height: 4),
        pw.Text(fullName, style: bodyStyle),
        if (signedAt != null)
          pw.Text(
            'Signé le ${dateFmt.format(signedAt.toLocal())}',
            style: bodyStyle.copyWith(fontSize: 8, color: _muted),
          ),
        pw.SizedBox(height: 4),
        signatureImage,
      ],
    );
  }

  static pw.Widget _emptySignatureBox() => pw.Container(
        width: 200,
        height: 70,
        decoration: pw.BoxDecoration(
          color: _bg,
          border: pw.Border.all(color: _hairline, width: 0.5),
        ),
        alignment: pw.Alignment.center,
        child: pw.Text(
          '(à signer)',
          style: pw.TextStyle(color: _muted, fontSize: 9),
        ),
      );

  /// Clauses spécifiques au type de bail (article 7 du contrat).
  static List<pw.Widget> _clausesSpecifiques({
    required ContratBail bail,
    required NumberFormat money,
    required pw.Widget Function(String, List<pw.Widget>) section,
    required pw.Widget Function(String) paragraph,
    required pw.Widget Function(String) bullet,
    required pw.Widget Function(String, String) kv,
    required pw.TextStyle h2,
    required pw.TextStyle bodyStyle,
  }) {
    switch (bail.type) {
      case BailType.meuble:
        final actifs = bail.equipementsMeuble.entries
            .where((e) => e.value)
            .map((e) => e.key)
            .toList();
        return [
          section('Article 7 — Bail meublé (décret n°2015-981)', [
            paragraph(
              'Le logement est loué meublé. Conformément au décret '
              'n°2015-981 du 31 juillet 2015, il est équipé du mobilier '
              'minimum suivant, lequel a été remis au locataire en bon état :',
            ),
            if (actifs.isEmpty)
              paragraph('(Liste des équipements à compléter dans l\'app)')
            else
              for (final eq in actifs) bullet(eq),
            pw.SizedBox(height: 4),
            paragraph(
              'L\'état des équipements (neuf / bon état / usagé) est précisé '
              'dans l\'état des lieux d\'entrée annexé. Toute panne doit '
              'être signalée sans délai au bailleur. La responsabilité du '
              'remplacement d\'un équipement défectueux par usure normale '
              'incombe au bailleur ; celle d\'un équipement détérioré par '
              'mauvais usage incombe au locataire.',
            ),
          ]),
        ];
      case BailType.colocation:
        return [
          section('Article 7 — Bail de colocation', [
            if (bail.clauseSolidariteColo)
              paragraph(
                'Solidarité entre colocataires : les colocataires sont '
                'solidairement responsables du paiement du loyer, des '
                'charges et des éventuels dégâts. En cas de départ d\'un '
                'colocataire, les autres restent responsables du paiement '
                'intégral jusqu\'à son remplacement ou la fin du bail.',
              ),
            paragraph(
              'Départ d\'un colocataire : préavis d\'1 mois par LRAR. Le '
              'nouveau colocataire doit être agréé par le bailleur et '
              'signer un avenant au contrat, en versant sa part du dépôt '
              'de garantie. Le loyer est recalculé au prorata du nombre '
              'de colocataires restants.',
            ),
            paragraph(
              'Répartition des charges : équitablement entre les '
              'colocataires, sauf accord écrit contraire entre eux.',
            ),
          ]),
        ];
      case BailType.saisonnier:
        return [
          section('Article 7 — Bail saisonnier', [
            paragraph(
              'Durée maximale de 90 jours consécutifs. Au-delà, le bail '
              'serait requalifié en résidence principale. Pas de droit au '
              'renouvellement automatique.',
            ),
            paragraph(
              bail.chargesIncluses
                  ? 'Les charges (eau, électricité, chauffage) sont incluses '
                      'dans le loyer pour la durée de la location.'
                  : 'Les charges sont à régler en sus du loyer, selon les '
                      'consommations réelles relevées à l\'entrée et à la '
                      'sortie.',
            ),
            paragraph(
              'Sous-location interdite. Le locataire s\'engage à souscrire '
              'une assurance "villégiature" couvrant sa responsabilité '
              'pendant la location.',
            ),
          ]),
        ];
      case BailType.mobilite:
        return [
          section('Article 7 — Bail mobilité (loi ELAN)', [
            paragraph(
              'Bail mobilité d\'une durée de ${bail.dureeMois} mois '
              '(comprise entre 1 et 10 mois), non renouvelable. Réservé '
              'aux locataires en situation de mobilité professionnelle, '
              'étudiante, en formation, stage, mission temporaire.',
            ),
            if (bail.justificatifMobilite != null &&
                bail.justificatifMobilite!.isNotEmpty)
              paragraph(
                'Justificatif fourni : ${bail.justificatifMobilite}.',
              ),
            paragraph(
              'Préavis d\'un mois pour le locataire comme pour le bailleur. '
              'Le bail ne peut pas être renouvelé ; à son terme, soit un '
              'nouveau bail mobilité est conclu pour une durée différente, '
              'soit un bail meublé classique d\'1 an est signé.',
            ),
          ]),
        ];
      case BailType.vide:
        return [
          section('Article 7 — Bail vide (location nue)', [
            paragraph(
              'Le logement est loué nu (non meublé). La durée minimale du '
              'bail est de 3 ans (6 ans si le bailleur est une personne '
              'morale).',
            ),
          ]),
        ];
    }
  }

  static String _clauseDuree(ContratBail bail) {
    switch (bail.type) {
      case BailType.vide:
      case BailType.colocation:
        return 'Le bail est conclu pour une durée minimale de 3 ans. À '
            'défaut de congé donné dans les formes légales, le bail est '
            'reconduit tacitement pour la même durée.';
      case BailType.meuble:
        return 'Le bail est conclu pour une durée d\'un an. À défaut de '
            'congé, il est reconduit tacitement.';
      case BailType.saisonnier:
        return 'Bail à durée déterminée, non renouvelable, prenant fin '
            'automatiquement à la date convenue.';
      case BailType.mobilite:
        return 'Bail mobilité à durée déterminée, non renouvelable. À son '
            'terme, le locataire doit quitter le logement.';
    }
  }

  /// Sauvegarde le PDF généré dans le sandbox de l'app et retourne le
  /// chemin du fichier. Le fichier est nommé `BAIL-<type>-<ref>-<date>.pdf`.
  static Future<String> savePdf({
    required pw.Document doc,
    required ContratBail bail,
    required Directory dir,
  }) async {
    if (!await dir.exists()) await dir.create(recursive: true);
    final safeRef = bail.reference.replaceAll(RegExp(r'[^A-Za-z0-9-]'), '_');
    final file = File('${dir.path}/$safeRef.pdf');
    await file.writeAsBytes(await doc.save(), flush: true);
    return file.path;
  }
}
