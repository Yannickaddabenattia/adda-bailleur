import 'package:flutter_test/flutter_test.dart';

import 'package:adda_location/core/templates/countries/country_document_template.dart';
import 'package:adda_location/core/templates/countries/switzerland_documents.dart';
import 'package:adda_location/models/country.dart';

/// Template de bail SUISSE (C.7) — sections complètes, placeholders listés,
/// blocage si donnée obligatoire manquante.
///
/// 📚 Source : Code des obligations (art. 253-274g), OBLF (RS 221.213.11).
void main() {
  const lease = SwitzerlandDocuments.lease;

  test('12 sections dans l\'ordre du squelette C.7', () {
    expect(lease.sections.length, 12);
    expect(lease.sections.first.titre, startsWith('1. Parties'));
    expect(lease.sections.last.titre, contains('Signatures'));
    final titres = lease.sections.map((s) => s.titre).join(' | ');
    expect(titres, contains('adaptation du loyer'));
    expect(titres, contains('Garantie'));
    expect(titres, contains('Loyer initial'));
    expect(titres, contains('Sous-location'));
  });

  test('chaque section porte une référence légale (📚 CO/OBLF)', () {
    for (final s in lease.sections) {
      expect(s.source.contains('📚'), isTrue, reason: s.titre);
    }
  });

  test('monnaie CHF', () {
    expect(lease.currencyCode, 'CHF');
  });

  test('placeholders [À VALIDER JURISTE] listés (formule initiale, seuils…)',
      () {
    final ph = lease.placeholders;
    expect(ph, isNotEmpty);
    expect(ph.any((p) => p.toLowerCase().contains('formule officielle')), isTrue);
    for (final p in ph) {
      expect(p, startsWith('[À VALIDER JURISTE — '));
      expect(p, endsWith(']'));
    }
  });

  test('pied de page « modèle indicatif »', () {
    expect(lease.footer, kModeleIndicatifFooter);
  });

  group('Guard de génération', () {
    test('bloque sans canton ni mode d\'adaptation', () {
      final r = lease.guard({});
      expect(r.blocked, isTrue);
      expect(r.missing, contains('Canton'));
      expect(r.missing.any((m) => m.contains('adaptation')), isTrue);
    });

    test('ne bloque pas quand canton + mode sont fournis', () {
      final r = lease.guard({
        'canton': 'GE',
        'modeAdaptation': 'Taux de référence',
      });
      expect(r.blocked, isFalse);
      expect(r.missing, isEmpty);
    });
  });

  group('Contrat-cadre / RULV (force obligatoire cantonale)', () {
    test('clause RULV présente pour Vaud, absente pour GE/FR/NE/JU/VS', () {
      final vd = SwitzerlandDocuments.leaseSectionsFor(ChCanton.vd);
      expect(vd.any((s) => s.contenu.contains('RULV')), isTrue);
      // Contrat-cadre romand caduc depuis le 30/06/2020 → aucun renvoi.
      for (final c in [
        ChCanton.ge,
        ChCanton.fr,
        ChCanton.ne,
        ChCanton.ju,
        ChCanton.vs,
      ]) {
        final sections = SwitzerlandDocuments.leaseSectionsFor(c);
        expect(sections.any((s) => s.contenu.contains('RULV')), isFalse,
            reason: c.code);
      }
    });

    test('RULV de force obligatoire jusqu\'au 30/06/2026 (échéance)', () {
      expect(SwitzerlandDocuments.rulvForceObligatoireJusquau, '2026-06-30');
      expect(SwitzerlandDocuments.rulvEncoreObligatoire(DateTime(2026, 6, 30)),
          isTrue);
      expect(SwitzerlandDocuments.rulvEncoreObligatoire(DateTime(2026, 7, 1)),
          isFalse);
    });
  });
}
