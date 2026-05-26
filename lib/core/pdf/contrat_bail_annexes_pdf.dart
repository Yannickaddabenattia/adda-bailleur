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

/// Génère le PDF des **annexes obligatoires** au contrat de bail, conformes
/// à la loi du 6 juillet 1989, à la loi ALUR (2014), à la loi ELAN (2018)
/// et au décret n°87-712 du 26 août 1987.
///
/// Couvre :
/// 1.  Notice d'information (décret du 29 mai 2015)
/// 2.  Dossier de Diagnostic Technique (DDT) — art. 3-3 loi 89-462
/// 3.  Référence à l'état des lieux d'entrée
/// 4.  Liste des charges récupérables (décret 26/08/1987)
/// 5.  Liste des réparations locatives (décret 26/08/1987)
/// 6.  Acte de cautionnement (si applicable)
/// 7.  Attestation d'assurance habitation
/// 8.  Inventaire du mobilier (bail meublé — décret du 31/07/2015)
/// 9.  Grille de vétusté (décret du 30/03/2016)
/// 10. Convention APL/AL (logement conventionné)
/// 11. Encadrement des loyers (zones tendues)
class ContratBailAnnexesPdfBuilder {
  static const PdfColor _ink = PdfColor.fromInt(0xFF1A1A1A);
  static const PdfColor _muted = PdfColor.fromInt(0xFF555555);
  static const PdfColor _accent = PdfColor.fromInt(0xFF1E3A8A);
  static const PdfColor _hairline = PdfColor.fromInt(0xFFCFCFCF);

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
    // L'isolate spawné par Isolate.run n'hérite pas des données de locale
    // initialisées sur l'isolate principal. On les ré-initialise ici pour
    // que `DateFormat('dd/MM/yyyy', 'fr_FR')` fonctionne.
    await initializeDateFormatting('fr_FR', null);

    final fonts = preloadedFonts ?? await loadFontBytes();
    final fontRegular = pw.Font.ttf(fonts.regular);
    final fontBold = pw.Font.ttf(fonts.bold);
    final fontItalic = pw.Font.ttf(fonts.italic);

    final doc = pw.Document(
      title: 'Annexes - ${bail.reference}',
      author: bailleur.fullName,
      theme: pw.ThemeData.withFont(
        base: fontRegular,
        bold: fontBold,
        italic: fontItalic,
      ),
    );

    final dateFmt = DateFormat('dd/MM/yyyy', 'fr_FR');

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
    final mutedSmall =
        pw.TextStyle(fontSize: 8, color: _muted, fontStyle: pw.FontStyle.italic);

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
              pw.Text('- ', style: bodyStyle),
              pw.Expanded(child: pw.Text(text, style: bodyStyle)),
            ],
          ),
        );

    pw.Widget signatureLine(String label) => pw.Padding(
          padding: const pw.EdgeInsets.only(top: 10, bottom: 4),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(label, style: bodyStyle),
              pw.SizedBox(height: 8),
              pw.Container(
                width: 240,
                height: 1,
                color: _hairline,
              ),
            ],
          ),
        );

    pw.Widget label(String text) => pw.Padding(
          padding: const pw.EdgeInsets.only(top: 8, bottom: 4),
          child: pw.Text(text, style: h2),
        );

    pw.Widget legalRef(String text) => pw.Padding(
          padding: const pw.EdgeInsets.only(top: 2, bottom: 6),
          child: pw.Text(text, style: mutedSmall),
        );

    // ============================
    //  Couverture
    // ============================
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(36, 60, 36, 36),
        build: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'ANNEXES OBLIGATOIRES',
              style: pw.TextStyle(
                fontSize: 26,
                fontWeight: pw.FontWeight.bold,
                color: _accent,
              ),
            ),
            pw.SizedBox(height: 6),
            pw.Text(
              'au contrat de bail ${bail.type.label.toLowerCase()}',
              style: pw.TextStyle(fontSize: 14, color: _muted),
            ),
            pw.SizedBox(height: 24),
            pw.Container(
              padding: const pw.EdgeInsets.all(14),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: _hairline),
                borderRadius: pw.BorderRadius.circular(6),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('Référence : ${bail.reference}',
                      style: pw.TextStyle(fontSize: 11, color: _ink)),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    'Logement : ${logement.libelle} - ${logement.adresse}, ${logement.codePostal} ${logement.ville}',
                    style: pw.TextStyle(fontSize: 11, color: _ink),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    'Locataire(s) : ${locataires.map((l) => l.fullName).join(", ")}',
                    style: pw.TextStyle(fontSize: 11, color: _ink),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    'Bail conclu le ${dateFmt.format(bail.dateDebut)} pour ${bail.dureeMois} mois (fin : ${dateFmt.format(bail.dateFin)})',
                    style: pw.TextStyle(fontSize: 11, color: _ink),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 24),
            pw.Text('Sommaire des annexes', style: h2),
            pw.SizedBox(height: 8),
            ..._sommaireEntries(bail).map(
              (e) => pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 4),
                child: pw.Text(e, style: bodyStyle),
              ),
            ),
            pw.Spacer(),
            pw.Text(
              'Document généré par ADDA Bailleur. Toutes les annexes ci-dessous sont '
              'requises par la loi n. 89-462 du 6 juillet 1989, la loi ALUR (2014), '
              'la loi ELAN (2018) et le décret n. 87-712 du 26 août 1987.',
              style: mutedSmall,
              textAlign: pw.TextAlign.justify,
            ),
          ],
        ),
      ),
    );

    // ============================
    //  Annexe 1 - Notice d'information
    // ============================
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(36, 36, 36, 36),
        build: (ctx) => [
          section('Annexe 1 - Notice d\'information', [
            legalRef(
                'Décret n. 2015-587 du 29 mai 2015 - Article 3 de la loi n. 89-462 du 6 juillet 1989'),
            paragraph(
              'Cette notice résume les droits et obligations principaux du '
              'bailleur et du locataire dans le cadre d\'une location à usage de '
              'résidence principale. Elle est remise au locataire à la signature '
              'du bail.',
            ),
            label('Droits du locataire'),
            bullet(
                'Jouir paisiblement du logement et bénéficier d\'un logement décent (décret du 30/01/2002).'),
            bullet(
                'Obtenir du bailleur un état des lieux d\'entrée et de sortie, joints au contrat.'),
            bullet(
                'Donner congé à tout moment, par lettre recommandée AR, acte de commissaire de justice ou remise en main propre contre récépissé.'),
            bullet(
                'Demander la réalisation des réparations à la charge du bailleur (réparations autres que locatives).'),
            bullet(
                'Bénéficier du dépôt de garantie restitué dans les 1 à 2 mois suivant la sortie (art. 22).'),
            label('Obligations du locataire'),
            bullet(
                'Payer le loyer et les charges aux échéances convenues (art. 7 a).'),
            bullet(
                'Souscrire et maintenir une assurance habitation couvrant les risques locatifs (art. 7 g).'),
            bullet(
                'Entretenir le logement et effectuer les menues réparations et l\'entretien courant (décret 26/08/1987).'),
            bullet(
                'Ne pas transformer le logement sans accord écrit du bailleur (art. 7 f).'),
            bullet(
                'Permettre l\'accès au logement pour préparer la relocation ou réaliser les travaux nécessaires (art. 7 e).'),
            label('Droits du bailleur'),
            bullet(
                'Encaisser le loyer et les charges récupérables.'),
            bullet(
                'Donner congé pour vendre, reprendre le logement ou pour motif légitime et sérieux, dans le préavis légal (6 mois bail vide, 3 mois bail meublé).'),
            bullet(
                'Réviser le loyer annuellement selon l\'IRL si la clause est prévue au bail.'),
            bullet(
                'Conserver le dépôt de garantie en cas de manquement du locataire (loyers impayés, dégradations).'),
            label('Obligations du bailleur'),
            bullet(
                'Délivrer un logement décent, en bon état d\'usage et conforme à sa destination.'),
            bullet(
                'Entretenir les locaux en état de servir et faire toutes les réparations autres que locatives (art. 6).'),
            bullet(
                'Assurer au locataire la jouissance paisible du logement.'),
            bullet(
                'Remettre une quittance de loyer sur demande du locataire et gratuitement (art. 21).'),
            bullet(
                'Communiquer le DDT (Dossier de Diagnostic Technique) et la présente notice à la signature.'),
          ]),
        ],
      ),
    );

    // ============================
    //  Annexe 2 - DDT
    // ============================
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(36, 36, 36, 36),
        build: (ctx) => [
          section('Annexe 2 - Dossier de Diagnostic Technique (DDT)', [
            legalRef(
                'Article 3-3 de la loi n. 89-462 du 6 juillet 1989 - Articles L.271-4 et suivants du Code de la construction'),
            paragraph(
              'Le bailleur communique au locataire, à la signature du bail, le '
              'Dossier de Diagnostic Technique (DDT) qui comprend les éléments '
              'suivants applicables au logement loué :',
            ),
            label('Diagnostics joints à ce bail'),
            if (diagnostics.isEmpty)
              paragraph(
                  'Aucun diagnostic n\'a été enregistré dans l\'application au moment de la génération de ce document.')
            else
              ...diagnostics.map(
                (d) => pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 6),
                  child: pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Container(
                        width: 14,
                        height: 14,
                        decoration: pw.BoxDecoration(
                          border: pw.Border.all(color: _ink, width: 0.6),
                        ),
                        margin: const pw.EdgeInsets.only(right: 6, top: 1),
                      ),
                      pw.Expanded(
                        child: pw.RichText(
                          text: pw.TextSpan(
                            children: [
                              pw.TextSpan(
                                text: '${d.type.label} : ',
                                style: bodyStyle.copyWith(
                                    fontWeight: pw.FontWeight.bold),
                              ),
                              pw.TextSpan(
                                text:
                                    'réalisé le ${dateFmt.format(d.dateRealisation)}'
                                    '${d.dateExpiration != null ? ", expire le ${dateFmt.format(d.dateExpiration!)}" : ""}'
                                    '${d.resume.isNotEmpty ? " - ${d.resume}" : ""}',
                                style: bodyStyle,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            pw.SizedBox(height: 8),
            label('Diagnostics potentiellement obligatoires'),
            paragraph(
              'Vérifiez la liste ci-dessous et joignez physiquement chaque '
              'diagnostic concerné. Cochez les cases pour ceux que vous joignez.',
            ),
            _checklistItem('DPE (Diagnostic de Performance Énergétique) - obligatoire, valide 10 ans'),
            _checklistItem('CREP (Constat de Risque d\'Exposition au Plomb) - immeubles antérieurs au 1er janvier 1949'),
            _checklistItem('ERP / État des Risques et Pollutions - valide 6 mois - obligatoire selon zone'),
            _checklistItem('Diagnostic gaz - obligatoire si installation de plus de 15 ans, valide 6 ans'),
            _checklistItem('Diagnostic électricité - obligatoire si installation de plus de 15 ans, valide 6 ans'),
            _checklistItem('Diagnostic amiante (DTA) - parties privatives, immeubles antérieurs au 1er juillet 1997'),
            _checklistItem('Diagnostic bruit - zones aéroportuaires (arrêté préfectoral)'),
            _checklistItem('Diagnostic mérule - zones définies par arrêté préfectoral'),
            pw.SizedBox(height: 6),
            paragraph(
              'Important : le défaut de remise d\'un diagnostic peut engager la '
              'responsabilité du bailleur et permet au locataire de demander la '
              'réfaction du loyer (art. L.271-4 CCH).',
            ),
          ]),
        ],
      ),
    );

    // ============================
    //  Annexe 3 - État des lieux
    // ============================
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(36, 36, 36, 36),
        build: (ctx) => [
          section('Annexe 3 - État des lieux', [
            legalRef(
                'Article 3-2 de la loi n. 89-462 du 6 juillet 1989 - Décret n. 2016-382 du 30 mars 2016'),
            paragraph(
              'Un état des lieux est établi contradictoirement entre le '
              'bailleur (ou son mandataire) et le locataire :'),
            bullet('Lors de la remise des clés (entrée).'),
            bullet('Lors de la restitution des clés (sortie).'),
            paragraph(
              'Il est joint au présent bail. À défaut d\'état des lieux d\'entrée, '
              'le locataire est présumé avoir reçu le logement en bon état (art. 1731 du Code civil), '
              'sauf si l\'absence d\'état des lieux est imputable au bailleur.',
            ),
            pw.SizedBox(height: 4),
            label('Modalités'),
            bullet('Établi sur support écrit ou électronique, signé par les deux parties.'),
            bullet('Décrit pièce par pièce l\'état des revêtements, équipements, et le cas échéant les meubles (bail meublé).'),
            bullet('Mentionne les relevés des compteurs (eau, électricité, gaz) à l\'entrée et à la sortie.'),
            bullet('Peut être complété dans les 10 jours suivant l\'entrée pour les éléments du logement non chauffés, et durant le 1er mois de la période de chauffe pour les éléments de chauffage.'),
            pw.SizedBox(height: 12),
            label('État des lieux d\'entrée'),
            paragraph(
              'L\'état des lieux d\'entrée a été établi le : _____ / _____ / __________'
              ' et est joint au présent bail (cocher si joint).',
            ),
            _checklistItem('État des lieux d\'entrée joint'),
            label('État des lieux de sortie'),
            paragraph(
              'L\'état des lieux de sortie sera établi à la restitution des clés. '
              'Il servira de référence pour l\'évaluation des dégradations éventuelles '
              'imputables au locataire.',
            ),
          ]),
        ],
      ),
    );

    // ============================
    //  Annexe 4 - Liste des charges récupérables
    // ============================
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(36, 36, 36, 36),
        build: (ctx) => [
          section('Annexe 4 - Liste des charges récupérables', [
            legalRef(
                'Décret n. 87-713 du 26 août 1987 - Article 23 de la loi du 6 juillet 1989'),
            paragraph(
              'Les charges récupérables (ou "charges locatives") sont les sommes que '
              'le bailleur peut récupérer auprès du locataire, en contrepartie '
              'des services et fournitures dont il bénéficie ou des dépenses '
              'd\'entretien courant des parties communes.',
            ),
            label('I. Ascenseurs et monte-charges'),
            bullet('Électricité.'),
            bullet('Exploitation : visites périodiques, nettoyage, fourniture des produits.'),
            bullet('Menues réparations de la cabine (boutons, signaux, voyants).'),
            label('II. Eau froide, eau chaude et chauffage collectif'),
            bullet('Eau froide et eau chaude des locataires (compteurs individuels ou répartition).'),
            bullet('Combustible (gaz, fioul, électricité) pour la production d\'eau chaude et le chauffage.'),
            bullet('Eau pour entretien des parties communes (arrosage, lavage).'),
            bullet('Exploitation : contrôles, ramonage, nettoyage de la chaudière, entretien.'),
            label('III. Installations individuelles'),
            bullet('Chauffage et production d\'eau chaude individuels.'),
            bullet('Combustibles consommés.'),
            bullet('Exploitation des compteurs.'),
            label('IV. Parties communes intérieures'),
            bullet('Électricité.'),
            bullet('Fournitures consommables : produits d\'entretien, sacs poubelle, ampoules.'),
            bullet('Entretien de la minuterie, des tapis, des vide-ordures.'),
            bullet('Réparations des appareils d\'entretien.'),
            label('V. Espaces extérieurs au bâtiment'),
            bullet('Voies de circulation, aires de stationnement, aires de jeux, espaces verts.'),
            bullet('Entretien : élagage, désherbage, tonte, arrosage, ramassage.'),
            label('VI. Hygiène'),
            bullet('Fourniture des sacs et bacs à déchets.'),
            bullet('Entretien et vidange des fosses d\'aisance.'),
            bullet('Entretien des colonnes d\'évacuation et désinfection.'),
            label('VII. Équipements divers'),
            bullet('Ramonage des conduits de cheminée et de fumée.'),
            bullet('Entretien des installations de ventilation.'),
            label('VIII. Impositions et redevances'),
            bullet('Taxe ou redevance d\'enlèvement des ordures ménagères.'),
            bullet('Taxe de balayage.'),
            bullet('Redevance d\'assainissement.'),
            label('IX. Personnel'),
            bullet('Frais de personnel d\'entretien : à hauteur de 75 % du montant des dépenses de rémunération et des charges sociales et fiscales y afférentes (50 % si le personnel ne s\'occupe pas de l\'entretien des parties communes et de l\'élimination des déchets).'),
          ]),
        ],
      ),
    );

    // ============================
    //  Annexe 5 - Réparations locatives
    // ============================
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(36, 36, 36, 36),
        build: (ctx) => [
          section('Annexe 5 - Liste des réparations locatives', [
            legalRef(
                'Décret n. 87-712 du 26 août 1987 - Article 7 d) de la loi du 6 juillet 1989'),
            paragraph(
              'Les réparations locatives sont celles d\'entretien courant et de '
              'menues réparations à la charge du locataire (sauf si elles sont '
              'occasionnées par vétusté, malfaçon, vice de construction, cas '
              'fortuit ou force majeure).',
            ),
            label('I. Parties extérieures dont le locataire a l\'usage exclusif'),
            bullet('Jardins privatifs : tonte, arrosage, taille des haies et arbustes, enlèvement des mousses.'),
            bullet('Auvents, terrasses et marquises : enlèvement de la mousse, des herbes.'),
            bullet('Descentes d\'eaux pluviales, chéneaux et gouttières : dégorgement des conduits.'),
            label('II. Ouvertures intérieures et extérieures'),
            bullet('Sections ouvrantes (portes, fenêtres) : graissage des gonds, remplacement de petites pièces.'),
            bullet('Vitrages : remplacement en cas de bris non causé par malfaçon.'),
            bullet('Dispositifs d\'occultation (volets, persiennes) : graissage, remplacement de cordes, poulies.'),
            bullet('Serrures et verrous de sûreté : graissage, remplacement de petites pièces, refaire les clés.'),
            label('III. Parties intérieures'),
            bullet('Plafonds, murs intérieurs, cloisons : maintien en état de propreté, menus raccords de peinture, tapisserie, faïence ; remise en place et remplacement.'),
            bullet('Parquets, moquettes, autres revêtements : encaustique, entretien, remplacement de quelques lames, vitrification.'),
            bullet('Placards, menuiseries (étagères, plinthes) : remplacement de petites pièces.'),
            label('IV. Installations de plomberie'),
            bullet('Canalisations d\'eau : dégorgement, remplacement de joints et colliers.'),
            bullet('Canalisations de gaz : entretien courant des robinets, siphons et ouvertures d\'aération.'),
            bullet('Fosses septiques, puisards et fosses d\'aisances : vidange.'),
            bullet('Chauffage, eau chaude, robinetterie : remplacement de bouchons, joints, clapets, presse-étoupe ; rinçage et nettoyage des corps de chauffe.'),
            bullet('Éviers et appareils sanitaires : nettoyage, remplacement de joints, flexibles de douche.'),
            label('V. Équipements d\'installation électrique'),
            bullet('Remplacement des interrupteurs, prises de courant, coupe-circuit, fusibles, ampoules, tubes lumineux.'),
            bullet('Réparation ou remplacement des baguettes, gaines de protection.'),
            label('VI. Autres équipements'),
            bullet('Entretien courant et menues réparations des équipements indiqués au bail (réfrigérateur, machines à laver, hottes aspirantes, antennes, meubles scellés, cheminées, glaces et miroirs).'),
            bullet('Menues réparations des appareils mobiles s\'ils sont mentionnés au bail.'),
          ]),
        ],
      ),
    );

    // ============================
    //  Annexe 6 - Acte de cautionnement
    // ============================
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(36, 36, 36, 36),
        build: (ctx) => [
          section('Annexe 6 - Acte de cautionnement (le cas échéant)', [
            legalRef(
                'Article 22-1 de la loi n. 89-462 du 6 juillet 1989 - Articles 2288 et suivants du Code civil'),
            paragraph(
              'Cette annexe ne s\'applique que si une personne physique se '
              'porte caution pour le locataire. La loi ELAN du 23 novembre 2018 '
              'autorise depuis 2022 la signature électronique de l\'acte de '
              'cautionnement, sans mention manuscrite obligatoire.',
            ),
            label('Modèle - Engagement de caution'),
            paragraph(
              'Je soussigné(e) __________________________________________________, '
              'né(e) le _____/_____/__________ à __________________________, '
              'demeurant ________________________________________________________, '
              'me porte caution solidaire de Monsieur/Madame ____________________ '
              '(le locataire), pour l\'exécution du bail signé en date du '
              '${dateFmt.format(bail.dateDebut)} portant sur le logement situé '
              '${bail.adresseLogement}.',
            ),
            pw.SizedBox(height: 4),
            paragraph(
              'Je m\'engage à payer au bailleur les sommes dues par le locataire '
              'au titre du loyer, des charges, des réparations locatives, des '
              'éventuelles indemnités d\'occupation et de toutes sommes pouvant '
              'être dues en exécution du bail.',
            ),
            paragraph(
              'Mon engagement couvre la durée du bail et son éventuel renouvellement, '
              'dans la limite de _____ années à compter de la date du bail. Il ne '
              'pourra excéder un montant total cumulé de ______________________ €.',
            ),
            paragraph(
              'J\'ai pris connaissance de l\'étendue de mon engagement et des '
              'conséquences d\'une éventuelle défaillance du locataire.',
            ),
            pw.SizedBox(height: 16),
            signatureLine('Fait à __________________________, le _____ / _____ / __________'),
            pw.SizedBox(height: 6),
            signatureLine('Signature de la caution :'),
            pw.SizedBox(height: 6),
            signatureLine('Signature du bailleur (acceptation) :'),
          ]),
        ],
      ),
    );

    // ============================
    //  Annexe 7 - Attestation d'assurance
    // ============================
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(36, 36, 36, 36),
        build: (ctx) => [
          section('Annexe 7 - Attestation d\'assurance habitation', [
            legalRef('Article 7 g) de la loi n. 89-462 du 6 juillet 1989'),
            paragraph(
              'Le locataire doit justifier d\'une assurance contre les risques '
              'locatifs (incendie, dégât des eaux, explosion) à la remise des '
              'clés, puis annuellement à chaque renouvellement, sur demande '
              'du bailleur.',
            ),
            paragraph(
              'À défaut, le bailleur peut souscrire une assurance pour le '
              'compte du locataire et lui en répercuter le coût majoré de 10 % '
              'maximum (loi ALUR).',
            ),
            label('À compléter et signer par le locataire'),
            pw.SizedBox(height: 6),
            paragraph(
                'Je soussigné(e) ____________________________________________, '
                'locataire du logement situé ${bail.adresseLogement}, atteste '
                'avoir souscrit une assurance multirisque habitation auprès de :'),
            paragraph('Compagnie d\'assurance : ______________________________________'),
            paragraph('N. de contrat : _______________________________________________'),
            paragraph('Période de validité : du _____/_____/__________ au _____/_____/__________'),
            paragraph(
              'Je m\'engage à présenter une attestation annuelle à mon bailleur '
              'pour la durée du bail.',
            ),
            pw.SizedBox(height: 16),
            signatureLine('Fait à __________________________, le _____ / _____ / __________'),
            pw.SizedBox(height: 6),
            signatureLine('Signature du locataire :'),
          ]),
        ],
      ),
    );

    // ============================
    //  Annexe 8 - Inventaire mobilier (uniquement bail meublé)
    // ============================
    if (bail.type == BailType.meuble ||
        bail.type == BailType.colocation ||
        bail.type == BailType.mobilite) {
      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.fromLTRB(36, 36, 36, 36),
          build: (ctx) => [
            section('Annexe 8 - Inventaire et état détaillé du mobilier', [
              legalRef(
                  'Article 25-7 loi n. 89-462 - Décret n. 2015-981 du 31 juillet 2015'),
              paragraph(
                'Pour les logements meublés, un inventaire et un état détaillé '
                'du mobilier sont établis lors de la remise des clés et lors '
                'de la restitution, dans les mêmes conditions que l\'état des '
                'lieux. Le mobilier doit comporter au minimum les éléments '
                'suivants (liste fixée par décret) :',
              ),
              label('I. Literie (linge inclus si fourni)'),
              _inventoryLine('Lit(s) avec couette ou couverture'),
              _inventoryLine('Oreillers / traversins'),
              _inventoryLine('Draps, taies (le cas échéant)'),
              label('II. Volets ou rideaux dans les chambres'),
              _inventoryLine('Rideaux occultants / volets / stores'),
              label('III. Plaques de cuisson'),
              _inventoryLine('Plaques (gaz, électrique, induction, vitrocéramique)'),
              label('IV. Four ou four à micro-ondes'),
              _inventoryLine('Four / four à micro-ondes'),
              label('V. Réfrigérateur, congélateur ou réfrigérateur avec compartiment ≤ -6°C'),
              _inventoryLine('Réfrigérateur'),
              _inventoryLine('Congélateur ou compartiment freezer'),
              label('VI. Vaisselle nécessaire à la prise des repas'),
              _inventoryLine('Assiettes, plats, bols'),
              _inventoryLine('Verres, tasses, mugs'),
              _inventoryLine('Couverts (couteaux, fourchettes, cuillères)'),
              label('VII. Ustensiles de cuisine'),
              _inventoryLine('Poêles, casseroles, couteau de cuisine'),
              _inventoryLine('Ustensiles divers (spatule, écumoire, etc.)'),
              label('VIII. Table et sièges'),
              _inventoryLine('Table de repas + chaises (nombre suffisant)'),
              label('IX. Étagères de rangement'),
              _inventoryLine('Étagères / placards / armoires'),
              label('X. Luminaires'),
              _inventoryLine('Plafonniers, lampes, appliques (toutes pièces)'),
              label('XI. Matériel d\'entretien ménager adapté au logement'),
              _inventoryLine('Aspirateur, balai, serpillière (si sol carrelé) ; chiffons'),
              pw.SizedBox(height: 8),
              paragraph(
                'Le présent inventaire fait foi de l\'état du mobilier à '
                'l\'entrée. Toute dégradation ou perte constatée à la sortie, '
                'non imputable à la vétusté normale, sera à la charge du locataire.',
              ),
            ]),
          ],
        ),
      );
    }

    // ============================
    //  Annexe 9 - Grille de vétusté (facultative mais recommandée)
    // ============================
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(36, 36, 36, 36),
        build: (ctx) => [
          section('Annexe 9 - Grille de vétusté (recommandée)', [
            legalRef(
                'Décret n. 2016-382 du 30 mars 2016 - Loi ALUR'),
            paragraph(
              'La grille de vétusté détermine les abattements à appliquer sur '
              'les réparations à la charge du locataire en fonction de la '
              'durée d\'usage. Elle est facultative mais fortement recommandée. '
              'Annexée au bail, elle évite des litiges au moment de la sortie.',
            ),
            label('Grille indicative (proposition)'),
            _vetusteRow('Peinture murale / plafond', '6 ans', '20% par an dès la 3e année'),
            _vetusteRow('Revêtement de sol (moquette)', '7 ans', '15% par an dès la 2e année'),
            _vetusteRow('Revêtement de sol (parquet stratifié)', '10 ans', '10% par an dès la 3e année'),
            _vetusteRow('Carrelage', '20 ans', 'Pas d\'abattement (sauf vétusté)'),
            _vetusteRow('Robinetterie', '10 ans', '10% par an dès la 3e année'),
            _vetusteRow('WC / cuvette', '15 ans', '7% par an dès la 3e année'),
            _vetusteRow('Lavabo / évier / baignoire', '20 ans', '5% par an dès la 5e année'),
            _vetusteRow('Mobilier (bail meublé)', '7 ans', '15% par an dès la 2e année'),
            _vetusteRow('Électroménager', '7 ans', '15% par an dès la 2e année'),
            pw.SizedBox(height: 6),
            paragraph(
              'L\'abattement de vétusté ne s\'applique pas en cas de dégradation '
              'volontaire ou de perte (objet manquant à la sortie). En cas de '
              'désaccord, les parties peuvent saisir la Commission '
              'Départementale de Conciliation.',
            ),
          ]),
        ],
      ),
    );

    // ============================
    //  Annexe 10 - Convention APL / AL
    // ============================
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(36, 36, 36, 36),
        build: (ctx) => [
          section('Annexe 10 - Convention APL/AL (si applicable)', [
            legalRef(
                'Articles L.353-1 et suivants du Code de la construction et de l\'habitation'),
            paragraph(
              'Si le logement est conventionné (APL / Aide Personnalisée au '
              'Logement, ou AL / Allocation Logement), une copie de la '
              'convention signée avec l\'État doit être jointe au bail.',
            ),
            label('Statut du logement'),
            _checklistItem('Logement non conventionné'),
            _checklistItem('Logement conventionné APL'),
            _checklistItem('Logement éligible à l\'AL'),
            _checklistItem('Logement en dispositif Pinel / Borloo / Cosse-Anah / autre'),
            pw.SizedBox(height: 8),
            label('Informations à compléter (si conventionné)'),
            paragraph('Numéro de convention : ____________________________________'),
            paragraph('Date de signature : ________________________________________'),
            paragraph('Date d\'échéance : __________________________________________'),
            paragraph('Plafond de loyer applicable : ______________________________'),
          ]),
        ],
      ),
    );

    // ============================
    //  Annexe 11 - Encadrement des loyers
    // ============================
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(36, 36, 36, 36),
        build: (ctx) => [
          section('Annexe 11 - Encadrement des loyers (zones tendues)', [
            legalRef(
                'Loi ALUR (2014), loi ELAN (2018), décret du 10 mai 2017 - articles 17 et 17-2 loi 89-462'),
            paragraph(
              'Dans les zones soumises à l\'encadrement des loyers, le loyer ne '
              'peut excéder un loyer de référence majoré, fixé par arrêté '
              'préfectoral. Les villes concernées sont notamment : Paris, '
              'Lille, Lyon, Villeurbanne, Plaine Commune, Est Ensemble, '
              'Montpellier, Bordeaux.',
            ),
            label('Logement concerné par l\'encadrement ?'),
            _checklistItem('Non - hors zone d\'encadrement'),
            _checklistItem('Oui - zone d\'encadrement (compléter ci-dessous)'),
            pw.SizedBox(height: 8),
            label('Informations obligatoires si zone tendue'),
            paragraph('Loyer de référence : ___________________________ € / m² / mois'),
            paragraph('Loyer de référence majoré : ____________________ € / m² / mois'),
            paragraph('Loyer du logement loué : _______________________ € / mois HC'),
            paragraph('Complément de loyer éventuel : _________________ € / mois (et justification)'),
            paragraph(
              'En cas de dépassement non justifié, le locataire peut demander '
              'la diminution du loyer dans un délai de 3 ans à compter de la '
              'signature du bail (art. 17-2).',
            ),
          ]),
        ],
      ),
    );

    // ============================
    //  Page finale - Récépissé de remise
    // ============================
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(36, 60, 36, 36),
        build: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('Récépissé de remise des annexes',
                style: pw.TextStyle(
                  fontSize: 18,
                  fontWeight: pw.FontWeight.bold,
                  color: _accent,
                )),
            pw.SizedBox(height: 16),
            paragraph(
              'Je soussigné(e) ${locataires.map((l) => l.fullName).join(", ")}, '
              'locataire du logement situé ${bail.adresseLogement}, reconnais '
              'avoir reçu en date du _____/_____/__________ les annexes '
              'obligatoires au contrat de bail référencé ${bail.reference}, '
              'comprenant les pièces suivantes :',
            ),
            pw.SizedBox(height: 8),
            ..._sommaireEntries(bail).map(
              (e) => pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 4),
                child: pw.Row(
                  children: [
                    pw.Container(
                      width: 12,
                      height: 12,
                      decoration: pw.BoxDecoration(
                        border: pw.Border.all(color: _ink, width: 0.6),
                      ),
                      margin: const pw.EdgeInsets.only(right: 8),
                    ),
                    pw.Expanded(child: pw.Text(e, style: bodyStyle)),
                  ],
                ),
              ),
            ),
            pw.SizedBox(height: 24),
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('Le bailleur',
                          style: bodyStyle.copyWith(
                              fontWeight: pw.FontWeight.bold)),
                      pw.SizedBox(height: 4),
                      pw.Text(bailleur.fullName, style: bodyStyle),
                      pw.SizedBox(height: 36),
                      pw.Container(
                          width: 200, height: 1, color: _hairline),
                      pw.SizedBox(height: 2),
                      pw.Text('Signature précédée de "Lu et approuvé"',
                          style: mutedSmall),
                    ],
                  ),
                ),
                pw.SizedBox(width: 12),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('Le(s) locataire(s)',
                          style: bodyStyle.copyWith(
                              fontWeight: pw.FontWeight.bold)),
                      pw.SizedBox(height: 4),
                      ...locataires.map(
                          (l) => pw.Text(l.fullName, style: bodyStyle)),
                      pw.SizedBox(height: 36),
                      pw.Container(
                          width: 200, height: 1, color: _hairline),
                      pw.SizedBox(height: 2),
                      pw.Text('Signature(s) précédée(s) de "Lu et approuvé"',
                          style: mutedSmall),
                    ],
                  ),
                ),
              ],
            ),
            pw.Spacer(),
            pw.Text(
              'Référence du bail : ${bail.reference} - Type : ${bail.type.label} - '
              'Logement : ${logement.libelle}',
              style: mutedSmall,
            ),
          ],
        ),
      ),
    );

    return doc;
  }

  static List<String> _sommaireEntries(ContratBail bail) {
    final base = <String>[
      'Annexe 1 - Notice d\'information (droits et obligations)',
      'Annexe 2 - Dossier de Diagnostic Technique (DDT)',
      'Annexe 3 - État des lieux d\'entrée',
      'Annexe 4 - Liste des charges récupérables (décret 26/08/1987)',
      'Annexe 5 - Liste des réparations locatives (décret 26/08/1987)',
      'Annexe 6 - Acte de cautionnement (si applicable)',
      'Annexe 7 - Attestation d\'assurance habitation',
    ];
    if (bail.type == BailType.meuble ||
        bail.type == BailType.colocation ||
        bail.type == BailType.mobilite) {
      base.add('Annexe 8 - Inventaire et état du mobilier (bail meublé)');
    }
    base.addAll([
      'Annexe 9 - Grille de vétusté (recommandée)',
      'Annexe 10 - Convention APL / AL (si conventionné)',
      'Annexe 11 - Encadrement des loyers (zones tendues)',
    ]);
    return base;
  }

  static pw.Widget _checklistItem(String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(left: 6, bottom: 4),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            width: 12,
            height: 12,
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: _ink, width: 0.6),
            ),
            margin: const pw.EdgeInsets.only(right: 6, top: 1),
          ),
          pw.Expanded(
            child: pw.Text(
              text,
              style: const pw.TextStyle(fontSize: 10, color: _ink),
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _inventoryLine(String label) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(left: 6, bottom: 4),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Container(
            width: 12,
            height: 12,
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: _ink, width: 0.6),
            ),
            margin: const pw.EdgeInsets.only(right: 6),
          ),
          pw.Expanded(
            flex: 5,
            child: pw.Text(label,
                style: const pw.TextStyle(fontSize: 10, color: _ink)),
          ),
          pw.Expanded(
            flex: 2,
            child: pw.Container(
              height: 0.7,
              color: _hairline,
              margin: const pw.EdgeInsets.symmetric(horizontal: 4),
            ),
          ),
          pw.Text('Qté / état :',
              style: pw.TextStyle(
                  fontSize: 8, fontStyle: pw.FontStyle.italic, color: _muted)),
          pw.Expanded(
            flex: 3,
            child: pw.Container(
              height: 0.7,
              color: _hairline,
              margin: const pw.EdgeInsets.only(left: 4),
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _vetusteRow(String element, String duree, String abattement) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 3),
      child: pw.Container(
        decoration: const pw.BoxDecoration(
          border: pw.Border(
            bottom: pw.BorderSide(color: _hairline, width: 0.4),
          ),
        ),
        padding: const pw.EdgeInsets.only(bottom: 3),
        child: pw.Row(
          children: [
            pw.Expanded(
              flex: 4,
              child: pw.Text(element,
                  style: const pw.TextStyle(fontSize: 9.5, color: _ink)),
            ),
            pw.Expanded(
              flex: 2,
              child: pw.Text(duree,
                  style: const pw.TextStyle(fontSize: 9.5, color: _ink)),
            ),
            pw.Expanded(
              flex: 5,
              child: pw.Text(abattement,
                  style: const pw.TextStyle(fontSize: 9.5, color: _ink)),
            ),
          ],
        ),
      ),
    );
  }

  /// Sauvegarde le PDF des annexes dans le sandbox de l'app.
  static Future<String> savePdf({
    required pw.Document doc,
    required ContratBail bail,
    required Directory dir,
  }) async {
    if (!await dir.exists()) await dir.create(recursive: true);
    final safeRef = bail.reference.replaceAll(RegExp(r'[^A-Za-z0-9-]'), '_');
    final file = File('${dir.path}/${safeRef}_ANNEXES.pdf');
    await file.writeAsBytes(await doc.save(), flush: true);
    return file.path;
  }
}
