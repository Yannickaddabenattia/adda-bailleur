import 'package:flutter_test/flutter_test.dart';

import 'package:adda_location/core/templates/countries/belgium_documents.dart';
import 'package:adda_location/core/templates/countries/switzerland_documents.dart';

/// Guard de génération de document (A.2) : une donnée obligatoire manquante
/// bloque la génération et renvoie la liste motivée des champs manquants.
void main() {
  group('Belgique — bail', () {
    test('refus motivé avec liste quand région + PEB manquent', () {
      final r = BelgiumDocuments.lease.guard({'region': '', 'pebClasse': null});
      expect(r.blocked, isTrue);
      expect(r.missing, isNotEmpty);
      expect(r.missing.any((m) => m.contains('Région')), isTrue);
      expect(r.missing.any((m) => m.contains('PEB')), isTrue);
    });

    test('génération autorisée quand tout est fourni', () {
      final r = BelgiumDocuments.lease.guard({
        'region': 'Bruxelles',
        'pebClasse': 'B',
        'pebNumero': 'BXL-123',
      });
      expect(r.blocked, isFalse);
    });
  });

  group('Suisse — bail', () {
    test('refus motivé quand canton + mode d\'adaptation manquent', () {
      final r = SwitzerlandDocuments.lease.guard({});
      expect(r.blocked, isTrue);
      expect(r.missing, contains('Canton'));
      expect(r.missing.any((m) => m.contains('adaptation')), isTrue);
    });

    test('génération autorisée quand canton + mode fournis', () {
      final r = SwitzerlandDocuments.lease.guard({
        'canton': 'VD',
        'modeAdaptation': 'Bail échelonné',
      });
      expect(r.blocked, isFalse);
    });
  });

  test('EDL/quittance sans champ obligatoire ne bloquent pas', () {
    expect(BelgiumDocuments.edl.guard({'region': 'Wallonie'}).blocked, isFalse);
    expect(BelgiumDocuments.quittance.guard({}).blocked, isFalse);
    expect(SwitzerlandDocuments.edl.guard({}).blocked, isFalse);
    expect(SwitzerlandDocuments.quittance.guard({}).blocked, isFalse);
  });
}
