import 'package:flutter_test/flutter_test.dart';

import 'package:adda_location/core/templates/countries/belgium_documents.dart';
import 'package:adda_location/core/templates/countries/country_document_template.dart';

/// Template de bail BELGIQUE (B.8) — sections complètes, placeholders listés,
/// blocage si donnée obligatoire manquante.
///
/// 📚 Source : décrets/ordonnances régionaux 2018-2019 + loi 20/02/1991 ;
/// enregistrement (Code des droits d'enregistrement art. 19,3°/161,12°) ;
/// indexation (art. 1728bis ancien Code civil).
void main() {
  const lease = BelgiumDocuments.lease;

  test('14 sections (squelette B.8 + assurance incendie wallonne)', () {
    expect(lease.sections.length, 14);
    expect(lease.sections.first.titre, startsWith('1. Parties'));
    expect(lease.sections.last.titre, contains('Signatures'));
    // Sections clés présentes.
    final titres = lease.sections.map((s) => s.titre).join(' | ');
    expect(titres, contains('Indexation'));
    expect(titres, contains('Garantie'));
    expect(titres, contains('PEB'));
    expect(titres, contains('Enregistrement'));
    expect(titres, contains('Annexe régionale'));
    expect(titres, contains('Assurance incendie')); // Wallonie art. 17 §2
  });

  test('garantie : sources régionales corrigées (art. 20 / 248)', () {
    final garantie =
        lease.sections.firstWhere((s) => s.titre.contains('Garantie'));
    expect(garantie.source, contains('art. 20')); // Wallonie (corrige art. 25)
    expect(garantie.source, contains('art. 248')); // Bruxelles ord. 04/04/2024
    expect(garantie.contenu, contains('01/11/2024')); // bascule BXL par date
  });

  test('clause assurance incendie wallonne (décret 15/03/2018 art. 17 §2)', () {
    final s =
        lease.sections.firstWhere((s) => s.titre.contains('Assurance incendie'));
    expect(s.source, contains('art. 17 §2'));
  });

  test('chaque section porte une référence légale (📚 source)', () {
    for (final s in lease.sections) {
      expect(s.source.contains('📚'), isTrue, reason: s.titre);
    }
  });

  test('placeholders [À VALIDER JURISTE] listés (annexe, congés, entretien…)',
      () {
    final ph = lease.placeholders;
    expect(ph, isNotEmpty);
    expect(ph.any((p) => p.contains('annexe')), isTrue);
    // Tous bien formés.
    for (final p in ph) {
      expect(p, startsWith('[À VALIDER JURISTE — '));
      expect(p, endsWith(']'));
    }
  });

  test('pied de page « modèle indicatif »', () {
    expect(lease.footer, kModeleIndicatifFooter);
  });

  group('Guard de génération', () {
    test('bloque sans région ni PEB, avec la liste des champs manquants', () {
      final r = lease.guard({});
      expect(r.blocked, isTrue);
      expect(r.missing, contains('Région (Wallonie / Bruxelles / Flandre)'));
      expect(r.missing.any((m) => m.contains('PEB')), isTrue);
    });

    test('ne bloque pas quand région + PEB sont fournis', () {
      final r = lease.guard({
        'region': 'Wallonie',
        'pebClasse': 'C',
        'pebNumero': 'BE-2026-0001',
      });
      expect(r.blocked, isFalse);
      expect(r.missing, isEmpty);
    });
  });
}
