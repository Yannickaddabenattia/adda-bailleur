import 'package:flutter_test/flutter_test.dart';
// ignore_for_file: implementation_imports
import 'package:hive_ce/src/binary/binary_reader_impl.dart';
import 'package:hive_ce/src/binary/binary_writer_impl.dart';
import 'package:hive_ce/src/registry/type_registry_impl.dart';

import 'package:adda_location/models/contrat_bail.dart';

/// Câblage France — persistance Hive des champs ajoutés sur `ContratBail` :
/// E5/GLI (`assuranceLoyersImpayes` index 61, `locataireEtudiantApprenti`
/// index 62) et A2/relocation (`precedentLoyerMontant` index 63,
/// `precedentLoyerDateVersement` index 64, `precedentLoyerDateRevision`
/// index 65).
///
/// On encode avec l'adaptateur ACTUEL puis on relit : les champs renseignés
/// doivent survivre au round-trip, et un bail neuf doit relire les défauts
/// (false / null) via la lecture tolérante (`(f[n] as …?) ?? défaut`).
/// 📚 GLI : loi n° 89-462, art. 22-1, al. 1er ; A2 : décret n° 2015-587.
void main() {
  ContratBail _make() => ContratBail.create(
        type: BailType.vide,
        logementId: 'log-1',
        locataireIds: const ['loc-1'],
        adresseLogement: '1 rue de la Paix, 75002 Paris',
        surfaceM2: 42,
        nbPieces: 2,
        dateDebut: DateTime(2026, 1, 1),
        loyerHC: 800,
        charges: 50,
        depotGarantie: 800,
      );

  ContratBail _roundTrip(ContratBail bail) {
    final reg = TypeRegistryImpl();
    final w = BinaryWriterImpl(reg);
    ContratBailAdapter().write(w, bail);
    final r = BinaryReaderImpl(w.toBytes(), reg);
    return ContratBailAdapter().read(r);
  }

  test('GLI + étudiant survivent au round-trip Hive (index 61/62)', () {
    final bail = _make()
      ..assuranceLoyersImpayes = true
      ..locataireEtudiantApprenti = true;
    final back = _roundTrip(bail);
    expect(back.assuranceLoyersImpayes, isTrue);
    expect(back.locataireEtudiantApprenti, isTrue);
  });

  test('bail neuf → défaut false pour les deux champs GLI', () {
    final back = _roundTrip(_make());
    expect(back.assuranceLoyersImpayes, isFalse);
    expect(back.locataireEtudiantApprenti, isFalse);
  });

  test('A2 — loyer du précédent locataire survit au round-trip (index 63-65)',
      () {
    final bail = _make()
      ..precedentLoyerMontant = 742.50
      ..precedentLoyerDateVersement = DateTime(2024, 9, 1)
      ..precedentLoyerDateRevision = DateTime(2024, 7, 1);
    final back = _roundTrip(bail);
    expect(back.precedentLoyerMontant, 742.50);
    expect(back.precedentLoyerDateVersement, DateTime(2024, 9, 1));
    expect(back.precedentLoyerDateRevision, DateTime(2024, 7, 1));
  });

  test('A2 — bail neuf → champs loyer précédent à null', () {
    final back = _roundTrip(_make());
    expect(back.precedentLoyerMontant, isNull);
    expect(back.precedentLoyerDateVersement, isNull);
    expect(back.precedentLoyerDateRevision, isNull);
  });

  test('A5 — encadrement des loyers survit au round-trip (index 66-70)', () {
    final bail = _make()
      ..zoneEncadrementLoyers = true
      ..loyerReference = 24.30
      ..loyerReferenceMajore = 29.16
      ..complementLoyer = 50
      ..complementLoyerJustification = 'Terrasse de 20 m²';
    final back = _roundTrip(bail);
    expect(back.zoneEncadrementLoyers, isTrue);
    expect(back.loyerReference, 24.30);
    expect(back.loyerReferenceMajore, 29.16);
    expect(back.complementLoyer, 50);
    expect(back.complementLoyerJustification, 'Terrasse de 20 m²');
  });

  test('A5 — bail neuf → hors zone + champs encadrement à null', () {
    final back = _roundTrip(_make());
    expect(back.zoneEncadrementLoyers, isFalse);
    expect(back.loyerReference, isNull);
    expect(back.loyerReferenceMajore, isNull);
    expect(back.complementLoyer, isNull);
    expect(back.complementLoyerJustification, isNull);
  });
}
