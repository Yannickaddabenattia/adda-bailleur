import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Notice d'information officielle annexée au bail (annexe C).
/// 📚 Arrêté du 29/05/2015 (NOR ETLL1511666A) consolidé au 16/02/2023 ;
/// art. 3 de la loi n° 89-462. Reproduite VERBATIM (asset), jamais résumée.
void main() {
  final raw =
      File('assets/legal/fr/notice_information.md').readAsStringSync();

  test('asset présent et version consolidée 16/02/2023', () {
    // Preuves de la bonne version (section 2.3 + sommaire jusqu'à 6).
    expect(
      raw,
      contains(
          '2.3. Obligations des parties en matière de lutte contre les nuisibles'),
    );
    expect(raw, contains('article 2297 du code civil'));
    expect(raw, contains('6. Contacts utiles'));
    expect(raw, contains('Préambule'));
    // En-tête de provenance présent dans l'asset.
    expect(raw, contains('NOR ETLL1511666A'));
    expect(raw, contains('JORFTEXT000047318946'));
  });

  test('retrait de l\'en-tête (même regex que loadNoticeOfficielle)', () {
    final notice =
        raw.replaceFirst(RegExp(r'<!--.*?-->', dotAll: true), '').trim();
    // L'en-tête de provenance est retiré du texte annexé…
    expect(notice.startsWith('<!--'), isFalse);
    expect(notice.contains('NOR ETLL1511666A'), isFalse);
    // …mais le texte officiel intégral est conservé.
    expect(
      notice,
      contains(
          '2.3. Obligations des parties en matière de lutte contre les nuisibles'),
    );
    expect(notice, contains('article 2297 du code civil'));
    expect(notice.length, greaterThan(50000)); // notice complète, non abrégée
  });
}
