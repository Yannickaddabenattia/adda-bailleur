import 'package:flutter_test/flutter_test.dart';
// ignore_for_file: implementation_imports
import 'package:hive_ce/src/binary/binary_reader_impl.dart';
import 'package:hive_ce/src/binary/binary_writer_impl.dart';
import 'package:hive_ce/src/registry/type_registry_impl.dart';

import 'package:adda_location/models/etat_des_lieux.dart';

/// B1/B2 — EDL de sortie conforme au décret n° 2016-382 : nouvelle adresse du
/// locataire (`nouvelleAdresseLocataire` index 23) + date de l'EDL d'entrée
/// (`dateEtatEntree` index 24).
///
/// On vérifie : (a) round-trip Hive ; (b) défauts null ; (c) le hash
/// d'intégrité inclut les champs quand ils sont renseignés (tamper-evidence)
/// mais reste insensible quand ils sont null (compat des EDL antérieurs).
void main() {
  EtatDesLieux make(EtatDesLieuxType type) => EtatDesLieux.create(
        type: type,
        logementId: 'log-1',
        locataireId: 'loc-1',
        date: DateTime(2026, 1, 1),
      );

  EtatDesLieux roundTrip(EtatDesLieux edl) {
    final reg = TypeRegistryImpl();
    final w = BinaryWriterImpl(reg);
    EtatDesLieuxAdapter().write(w, edl);
    final r = BinaryReaderImpl(w.toBytes(), reg);
    return EtatDesLieuxAdapter().read(r);
  }

  test('round-trip Hive des champs de sortie (index 23/24)', () {
    final edl = make(EtatDesLieuxType.sortie)
      ..nouvelleAdresseLocataire = '5 avenue Foch, 75116 Paris'
      ..dateEtatEntree = DateTime(2024, 1, 15);
    final back = roundTrip(edl);
    expect(back.nouvelleAdresseLocataire, '5 avenue Foch, 75116 Paris');
    expect(back.dateEtatEntree, DateTime(2024, 1, 15));
  });

  test('EDL neuf → champs de sortie à null', () {
    final back = roundTrip(make(EtatDesLieuxType.entree));
    expect(back.nouvelleAdresseLocataire, isNull);
    expect(back.dateEtatEntree, isNull);
  });

  test('hash inchangé quand les champs B1/B2 sont null (compat antérieure)', () {
    // Deux EDL identiques (mêmes id/date/created via une seule instance) :
    // renseigner puis vider les champs doit redonner le hash initial.
    final edl = make(EtatDesLieuxType.sortie);
    final hBase = edl.computeIntegrityHash();
    edl
      ..nouvelleAdresseLocataire = '5 avenue Foch'
      ..dateEtatEntree = DateTime(2024, 1, 15);
    expect(edl.computeIntegrityHash(), isNot(hBase)); // inclus quand renseignés
    edl
      ..nouvelleAdresseLocataire = null
      ..dateEtatEntree = null;
    expect(edl.computeIntegrityHash(), hBase); // insensible quand null
  });

  test('intégrité : altération de la nouvelle adresse détectée', () {
    final edl = make(EtatDesLieuxType.sortie)
      ..nouvelleAdresseLocataire = '5 avenue Foch'
      ..dateEtatEntree = DateTime(2024, 1, 15);
    edl.integrityHash = edl.computeIntegrityHash();
    expect(edl.verifyIntegrity(), isTrue);
    edl.nouvelleAdresseLocataire = '1 rue ailleurs';
    expect(edl.verifyIntegrity(), isFalse);
  });
}
