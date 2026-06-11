import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
// ignore_for_file: implementation_imports
import 'package:hive_ce/src/binary/binary_reader_impl.dart';
import 'package:hive_ce/src/binary/binary_writer_impl.dart';
import 'package:hive_ce/src/registry/type_registry_impl.dart';

import 'package:adda_location/models/country.dart';
import 'package:adda_location/models/fiscal_settings.dart';
import 'package:adda_location/models/logement.dart';

/// Garde-fou « aucune perte de données lors d'une mise à jour » (A.1).
///
/// On encode un enregistrement au **format v1.1.0 figé** (Logement : compteur de
/// champs 33, index 0-32 ; FiscalSettings : compteur 7, index 0-6) — c'est-à-dire
/// AVANT l'ajout des champs multi-pays — puis on le relit avec l'adaptateur
/// ACTUEL. On vérifie :
///   - les champs hérités (0-32 / 0-6) sont intacts ;
///   - les nouveaux champs absents prennent leur **défaut France/EUR / null**,
///     même si l'objet source portait des valeurs non-France (preuve que c'est
///     bien le défaut, pas une valeur résiduelle, qui s'applique) ;
///   - `country == Country.france` → le bien est inclus dans le périmètre fiscal
///     français (`FiscaliteService._logementsFrance`).
///
/// Les helpers `_writeLegacy*` reproduisent volontairement l'ancien `write()`
/// (snapshot indépendant des évolutions futures de l'adaptateur).
void main() {
  Uint8List _writeLegacyLogement(Logement o) {
    final w = BinaryWriterImpl(TypeRegistryImpl());
    // Format v1.1.0 : 33 champs (index 0-32), AUCUN champ multi-pays.
    w
      ..writeByte(33)
      ..writeByte(0)
      ..write(o.id)
      ..writeByte(1)
      ..write(o.libelle)
      ..writeByte(2)
      ..write(o.adresse)
      ..writeByte(3)
      ..write(o.codePostal)
      ..writeByte(4)
      ..write(o.ville)
      ..writeByte(5)
      ..write(o.type.name)
      ..writeByte(6)
      ..write(o.surface)
      ..writeByte(7)
      ..write(o.nbPieces)
      ..writeByte(8)
      ..write(o.loyerHC)
      ..writeByte(9)
      ..write(o.charges)
      ..writeByte(10)
      ..write(o.equipements)
      ..writeByte(11)
      ..write(o.notes)
      ..writeByte(12)
      ..write(o.createdAt.toIso8601String())
      ..writeByte(13)
      ..write(o.updatedAt.toIso8601String())
      ..writeByte(14)
      ..write(o.statutFiscal.name)
      ..writeByte(15)
      ..write(o.regimeFiscal.name)
      ..writeByte(16)
      ..write(o.dispositif.name)
      ..writeByte(17)
      ..write(o.dateAcquisition?.toIso8601String())
      ..writeByte(18)
      ..write(o.dureeEngagementAnnees)
      ..writeByte(19)
      ..write(o.prixRevient)
      ..writeByte(20)
      ..write(o.contratBailPaths)
      ..writeByte(21)
      ..write(o.sciId)
      ..writeByte(22)
      ..write(o.amortissementAnnuel)
      ..writeByte(23)
      ..write(o.dateDebutDispositif?.toIso8601String())
      ..writeByte(24)
      ..write(o.dateFinDispositif?.toIso8601String())
      ..writeByte(25)
      ..write(o.anneeConstruction)
      ..writeByte(26)
      ..write(o.datePermisConstruire?.toIso8601String())
      ..writeByte(27)
      ..write(o.dateInstallationElectrique?.toIso8601String())
      ..writeByte(28)
      ..write(o.dateInstallationGaz?.toIso8601String())
      ..writeByte(29)
      ..write(o.typeAssainissement.name)
      ..writeByte(30)
      ..write(o.zoneTermites)
      ..writeByte(31)
      ..write(o.regimeLmnp.name)
      ..writeByte(32)
      ..write(o.enRenovationEnergetique);
    return w.toBytes();
  }

  Uint8List _writeLegacyFiscalSettings(FiscalSettings o) {
    final w = BinaryWriterImpl(TypeRegistryImpl());
    // Format v1.1.0 : 7 champs (index 0-6), AUCUN taux BE/CH.
    w
      ..writeByte(7)
      ..writeByte(0)
      ..write(o.parts)
      ..writeByte(1)
      ..write(o.autresRevenusBruts)
      ..writeByte(2)
      ..write(o.marieOuPacse)
      ..writeByte(3)
      ..write(o.deficitsReportables)
      ..writeByte(4)
      ..write(o.anneeBareme)
      ..writeByte(5)
      ..write(o.autresNichesFiscales)
      ..writeByte(6)
      ..write(o.autresRevenusBrutsParAnnee);
    return w.toBytes();
  }

  T _readBack<T>(Uint8List bytes, T Function(BinaryReaderImpl) read) =>
      read(BinaryReaderImpl(bytes, TypeRegistryImpl()));

  group('Logement v1.1.0 → adaptateur actuel', () {
    // Objet source AVEC des valeurs non-France volontaires : elles ne sont PAS
    // écrites au format v1.1.0, donc la lecture doit retomber sur le défaut.
    final source = Logement(
      id: 'L-legacy',
      libelle: 'Studio République',
      adresse: '10 rue de Paris',
      codePostal: '59000',
      ville: 'Lille',
      type: LogementType.studio,
      surface: 28.5,
      nbPieces: 1,
      loyerHC: 540.0,
      charges: 60.0,
      equipements: const ['Lave-linge', 'Frigo'],
      notes: 'RAS',
      createdAt: DateTime.utc(2024, 3, 1, 9, 30),
      updatedAt: DateTime.utc(2025, 1, 15, 12),
      statutFiscal: StatutFiscal.lmnp,
      regimeFiscal: RegimeFiscal.reel,
      dispositif: DispositifFiscal.aucun,
      dateAcquisition: DateTime.utc(2020, 6, 1),
      dureeEngagementAnnees: 9,
      prixRevient: 120000,
      sciId: null,
      amortissementAnnuel: 3500,
      anneeConstruction: 1995,
      typeAssainissement: TypeAssainissement.collectif,
      zoneTermites: true,
      regimeLmnp: RegimeLmnp.reelBIC,
      enRenovationEnergetique: true,
      // Valeurs multi-pays NON-DÉFAUT : ne doivent PAS survivre (champs absents
      // du format v1.1.0 → défaut France/EUR attendu à la relecture).
      country: Country.belgique,
      beRegion: BeRegion.flandre,
      chCanton: ChCanton.ge,
      currencyCode: 'CHF',
      revenuCadastral: 999,
      valeurFiscale: 888,
    );

    final relu = _readBack(
      _writeLegacyLogement(source),
      (r) => LogementAdapter().read(r),
    );

    test('champs hérités (0-32) intacts', () {
      expect(relu.id, 'L-legacy');
      expect(relu.libelle, 'Studio République');
      expect(relu.adresse, '10 rue de Paris');
      expect(relu.codePostal, '59000');
      expect(relu.ville, 'Lille');
      expect(relu.type, LogementType.studio);
      expect(relu.surface, 28.5);
      expect(relu.nbPieces, 1);
      expect(relu.loyerHC, 540.0);
      expect(relu.charges, 60.0);
      expect(relu.equipements, ['Lave-linge', 'Frigo']);
      expect(relu.statutFiscal, StatutFiscal.lmnp);
      expect(relu.regimeLmnp, RegimeLmnp.reelBIC);
      expect(relu.dateAcquisition, DateTime.utc(2020, 6, 1));
      expect(relu.anneeConstruction, 1995);
      expect(relu.typeAssainissement, TypeAssainissement.collectif);
      expect(relu.zoneTermites, isTrue);
      expect(relu.enRenovationEnergetique, isTrue);
      expect(relu.amortissementAnnuel, 3500);
      expect(relu.prixRevient, 120000);
    });

    test('nouveaux champs → défaut France/EUR/null (jamais la valeur source)',
        () {
      expect(relu.country, Country.france, reason: 'défaut, pas belgique');
      expect(relu.currencyCode, 'EUR', reason: 'défaut, pas CHF');
      expect(relu.beRegion, isNull);
      expect(relu.chCanton, isNull);
      expect(relu.revenuCadastral, isNull);
      expect(relu.precompteImmobilierAnnuel, isNull);
      expect(relu.valeurFiscale, isNull);
      expect(relu.tauxImpotFoncierPourMille, isNull);
      expect(relu.tauxReferenceContrat, isNull);
      expect(relu.dpeClasse, isNull); // index 42 absent en v1.1.0 → null
    });

    test('country == france → inclus dans le périmètre fiscal français', () {
      // _logementsFrance filtre sur country == Country.france ; un bien legacy
      // doit donc rester dans le calcul FR (aucune exclusion silencieuse).
      expect(relu.country == Country.france, isTrue);
    });
  });

  group('FiscalSettings v1.1.0 → adaptateur actuel', () {
    final source = FiscalSettings(
      parts: 2.5,
      autresRevenusBruts: 42000,
      marieOuPacse: true,
      anneeBareme: 2025,
      autresNichesFiscales: 1200,
      deficitsReportables: {2023: 800.0},
      autresRevenusBrutsParAnnee: {2024: 45000.0},
      // Taux BE/CH non-défaut : absents du format v1.1.0 → null attendu.
      tauxMarginalBE: 0.45,
      tauxCommunalBE: 0.07,
      tauxMarginalCH: 0.30,
    );

    final relu = _readBack(
      _writeLegacyFiscalSettings(source),
      (r) => FiscalSettingsAdapter().read(r),
    );

    test('champs hérités (0-6) intacts', () {
      expect(relu.parts, 2.5);
      expect(relu.autresRevenusBruts, 42000);
      expect(relu.marieOuPacse, isTrue);
      expect(relu.anneeBareme, 2025);
      expect(relu.autresNichesFiscales, 1200);
      expect(relu.deficitsReportables[2023], 800.0);
      expect(relu.autresRevenusBrutsParAnnee[2024], 45000.0);
    });

    test('nouveaux taux BE/CH → null (jamais la valeur source)', () {
      expect(relu.tauxMarginalBE, isNull);
      expect(relu.tauxCommunalBE, isNull);
      expect(relu.tauxMarginalCH, isNull);
    });
  });
}
