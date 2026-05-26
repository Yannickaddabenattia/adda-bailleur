import 'dart:math' as math;

import 'package:hive_ce/hive.dart';
import 'package:uuid/uuid.dart';

import '../core/crypto/hash_service.dart';

/// Statut d'un crédit immobilier.
enum StatutCredit {
  actif,
  rachete,
  cloture,
}

/// Crédit immobilier rattaché à un logement.
///
/// Plusieurs crédits sont possibles par logement (par ex. crédit principal +
/// crédit travaux). L'amortissement est calculé à partir de la formule
/// classique :
///   M = C × t / (1 - (1 + t)^-n)
/// où t est le taux mensuel et n la durée en mois.
///
/// Un crédit peut être **racheté** (refinancé) à une date donnée. Dans ce cas,
/// l'amortissement bascule au moment du rachat avec de nouvelles conditions
/// (taux, durée, mensualité). Un rachat **partiel** ne couvre qu'une partie
/// du capital restant : la portion non rachetée continue selon les conditions
/// originales (taux, mensualité), tandis que la portion rachetée est traitée
/// comme un nouveau crédit.
class CreditImmobilier {
  final String id;
  final String logementId;
  String libelle;
  double capitalEmprunte;
  double tauxAnnuel;
  DateTime dateDebut;
  int dureeMois;
  double mensualiteHorsAssurance;
  double assuranceMensuelle;
  String notes;
  final DateTime createdAt;
  String? integrityHash;

  // ---- Rachat ----
  StatutCredit statut;
  DateTime? dateRachat;
  double? montantRachete;
  String banqueRacheteur;
  double? nouveauTaux;
  int? nouvelleDureeMois;
  double? fraisRachat;
  bool rachatPartiel;

  // ---- Clôture manuelle ----
  DateTime? dateCloture;

  CreditImmobilier({
    required this.id,
    required this.logementId,
    required this.libelle,
    required this.capitalEmprunte,
    required this.tauxAnnuel,
    required this.dateDebut,
    required this.dureeMois,
    required this.mensualiteHorsAssurance,
    required this.assuranceMensuelle,
    required this.notes,
    required this.createdAt,
    this.integrityHash,
    this.statut = StatutCredit.actif,
    this.dateRachat,
    this.montantRachete,
    this.banqueRacheteur = '',
    this.nouveauTaux,
    this.nouvelleDureeMois,
    this.fraisRachat,
    this.rachatPartiel = false,
    this.dateCloture,
  });

  factory CreditImmobilier.create({
    required String logementId,
    required String libelle,
    required double capitalEmprunte,
    required double tauxAnnuel,
    required DateTime dateDebut,
    required int dureeMois,
    double? mensualiteHorsAssurance,
    double assuranceMensuelle = 0,
    String notes = '',
  }) {
    final now = DateTime.now().toUtc();
    final m = mensualiteHorsAssurance ??
        _computeMensualite(capitalEmprunte, tauxAnnuel, dureeMois);
    final c = CreditImmobilier(
      id: const Uuid().v4(),
      logementId: logementId,
      libelle: libelle.trim(),
      capitalEmprunte: capitalEmprunte,
      tauxAnnuel: tauxAnnuel,
      dateDebut: dateDebut,
      dureeMois: dureeMois,
      mensualiteHorsAssurance: m,
      assuranceMensuelle: assuranceMensuelle,
      notes: notes.trim(),
      createdAt: now,
    );
    c.integrityHash = c.computeIntegrityHash();
    return c;
  }

  bool get isRachete => statut == StatutCredit.rachete && dateRachat != null;
  bool get isCloture => statut == StatutCredit.cloture;
  bool get isActif => statut == StatutCredit.actif;

  /// Mensualité totale (capital + intérêts + assurance) à la date courante.
  /// Bascule automatiquement sur la nouvelle mensualité après rachat.
  double get mensualiteTotale => mensualiteTotaleA(DateTime.now());

  /// Mensualité totale effective à une date donnée.
  double mensualiteTotaleA(DateTime date) {
    if (isCloture && dateCloture != null && !date.isBefore(dateCloture!)) {
      return 0;
    }
    if (isRachete && date.isAfter(dateRachat!)) {
      double mens = _newMensualiteHorsAssurance;
      if (rachatPartiel) mens += _continuationMensualite;
      return mens + assuranceMensuelle;
    }
    return mensualiteHorsAssurance + assuranceMensuelle;
  }

  /// Date de fin (dernière mensualité).
  ///
  /// Pour un crédit racheté, c'est la fin du nouveau crédit (rachat).
  /// Pour un rachat partiel, c'est la dernière des deux fins (continuation
  /// de l'ancien crédit ou fin du nouveau).
  DateTime get dateFin {
    if (isRachete) {
      final endNew = _addMonths(dateRachat!, _newDureeMois);
      if (rachatPartiel) {
        final moisRest = dureeMois - moisEcoulesA(dateRachat!);
        if (moisRest > 0) {
          final endCont = _addMonths(dateRachat!, moisRest);
          return endNew.isAfter(endCont) ? endNew : endCont;
        }
      }
      return endNew;
    }
    return _addMonths(dateDebut, dureeMois);
  }

  static DateTime _addMonths(DateTime date, int months) {
    final y = date.year + (date.month + months - 1) ~/ 12;
    final m = (date.month + months - 1) % 12 + 1;
    final lastDay = DateTime(y, m + 1, 0).day;
    final d = date.day > lastDay ? lastDay : date.day;
    return DateTime(y, m, d);
  }

  /// Mois écoulés à une date donnée. Borné à [0, dureeMois].
  int moisEcoulesA(DateTime date) {
    final months =
        (date.year - dateDebut.year) * 12 + (date.month - dateDebut.month);
    if (months < 0) return 0;
    if (months > dureeMois) return dureeMois;
    return months;
  }

  /// Nombre de mois entre deux dates (capable de retourner 0+).
  static int _moisEntre(DateTime a, DateTime b) {
    final months = (b.year - a.year) * 12 + (b.month - a.month);
    return months < 0 ? 0 : months;
  }

  /// Capital restant dû avant rachat selon les conditions d'origine.
  double _capitalRestantOriginal(DateTime date) {
    final n = moisEcoulesA(date);
    if (n >= dureeMois) return 0;
    final t = tauxAnnuel / 100 / 12;
    if (t == 0) {
      final crd = capitalEmprunte - (mensualiteHorsAssurance * n);
      return crd < 0 ? 0 : crd;
    }
    final pow = math.pow(1 + t, n).toDouble();
    final crd = capitalEmprunte * pow -
        mensualiteHorsAssurance * (pow - 1) / t;
    return crd < 0 ? 0 : crd;
  }

  /// Capital restant dû à une date donnée (toutes phases incluses).
  double capitalRestantA(DateTime date) {
    if (isCloture && dateCloture != null && !date.isBefore(dateCloture!)) {
      return 0;
    }
    if (isRachete && date.isAfter(dateRachat!)) {
      // Phase post-rachat
      double crd = _capitalRestantPost(date);
      if (rachatPartiel) {
        crd += _capitalRestantContinuation(date);
      }
      return crd;
    }
    return _capitalRestantOriginal(date);
  }

  /// Décomposition d'une mensualité originale (1-indexée).
  ({double capital, double interets}) _decomposerOriginal(int numero) {
    if (numero < 1 || numero > dureeMois) {
      return (capital: 0, interets: 0);
    }
    final t = tauxAnnuel / 100 / 12;
    if (t == 0) {
      return (capital: mensualiteHorsAssurance, interets: 0);
    }
    final pow = math.pow(1 + t, numero - 1).toDouble();
    final crd = capitalEmprunte * pow -
        mensualiteHorsAssurance * (pow - 1) / t;
    final interets = crd * t;
    final capital = mensualiteHorsAssurance - interets;
    return (
      capital: capital < 0 ? 0 : capital,
      interets: interets < 0 ? 0 : interets,
    );
  }

  /// Décomposition d'une mensualité (compat ancienne API).
  ({double capital, double interets}) decomposerMensualite(int numero) {
    return _decomposerOriginal(numero);
  }

  // ---- Helpers post-rachat (nouveau crédit) ----

  double get _newCapital => montantRachete ?? 0;
  double get _newTaux => nouveauTaux ?? tauxAnnuel;
  int get _newDureeMois =>
      nouvelleDureeMois ?? math.max(0, dureeMois - moisEcoulesA(dateRachat ?? dateDebut));
  double get _newMensualiteHorsAssurance =>
      _computeMensualite(_newCapital, _newTaux, _newDureeMois);

  ({double capital, double interets}) _decomposerPost(int numero) {
    if (numero < 1 || numero > _newDureeMois) {
      return (capital: 0, interets: 0);
    }
    final t = _newTaux / 100 / 12;
    final mens = _newMensualiteHorsAssurance;
    if (t == 0) {
      return (capital: mens, interets: 0);
    }
    final pow = math.pow(1 + t, numero - 1).toDouble();
    final crd = _newCapital * pow - mens * (pow - 1) / t;
    final interets = crd * t;
    final capital = mens - interets;
    return (
      capital: capital < 0 ? 0 : capital,
      interets: interets < 0 ? 0 : interets,
    );
  }

  double _capitalRestantPost(DateTime date) {
    if (dateRachat == null) return 0;
    final n = _moisEntre(dateRachat!, date);
    if (n >= _newDureeMois) return 0;
    final t = _newTaux / 100 / 12;
    final mens = _newMensualiteHorsAssurance;
    if (t == 0) {
      final crd = _newCapital - mens * n;
      return crd < 0 ? 0 : crd;
    }
    final pow = math.pow(1 + t, n).toDouble();
    final crd = _newCapital * pow - mens * (pow - 1) / t;
    return crd < 0 ? 0 : crd;
  }

  // ---- Helpers continuation (rachat partiel) ----

  /// Capital initial de la continuation = CRD au rachat - montant racheté.
  double get _continuationCapital {
    if (dateRachat == null || !rachatPartiel) return 0;
    final crdOrig = _capitalRestantOriginal(dateRachat!);
    final v = crdOrig - (montantRachete ?? 0);
    return v < 0 ? 0 : v;
  }

  int get _continuationDureeMois =>
      math.max(0, dureeMois - moisEcoulesA(dateRachat ?? dateDebut));

  double get _continuationMensualite =>
      _computeMensualite(_continuationCapital, tauxAnnuel, _continuationDureeMois);

  ({double capital, double interets}) _decomposerContinuation(int numero) {
    if (!rachatPartiel) return (capital: 0, interets: 0);
    if (numero < 1 || numero > _continuationDureeMois) {
      return (capital: 0, interets: 0);
    }
    final t = tauxAnnuel / 100 / 12;
    final mens = _continuationMensualite;
    if (t == 0) {
      return (capital: mens, interets: 0);
    }
    final pow = math.pow(1 + t, numero - 1).toDouble();
    final crd = _continuationCapital * pow - mens * (pow - 1) / t;
    final interets = crd * t;
    final capital = mens - interets;
    return (
      capital: capital < 0 ? 0 : capital,
      interets: interets < 0 ? 0 : interets,
    );
  }

  double _capitalRestantContinuation(DateTime date) {
    if (!rachatPartiel || dateRachat == null) return 0;
    final n = _moisEntre(dateRachat!, date);
    if (n >= _continuationDureeMois) return 0;
    final t = tauxAnnuel / 100 / 12;
    final mens = _continuationMensualite;
    if (t == 0) {
      final crd = _continuationCapital - mens * n;
      return crd < 0 ? 0 : crd;
    }
    final pow = math.pow(1 + t, n).toDouble();
    final crd = _continuationCapital * pow - mens * (pow - 1) / t;
    return crd < 0 ? 0 : crd;
  }

  /// Décomposition d'un mois (échéance) sur tout le cycle (avant + après rachat).
  /// Combine, pour un rachat partiel, la nouvelle mensualité + la continuation.
  ({double capital, double interets, double assurance, double crd, bool postRachat}) decomposerMois(DateTime echeance) {
    final ass = isCloture && dateCloture != null && !echeance.isBefore(dateCloture!)
        ? 0.0
        : assuranceMensuelle;
    if (isCloture && dateCloture != null && !echeance.isBefore(dateCloture!)) {
      return (capital: 0, interets: 0, assurance: 0, crd: 0, postRachat: false);
    }

    if (isRachete && echeance.isAfter(dateRachat!)) {
      final nPost = _moisEntre(dateRachat!, echeance);
      final dec = _decomposerPost(nPost);
      double cap = dec.capital;
      double inte = dec.interets;
      if (rachatPartiel) {
        final decCont = _decomposerContinuation(nPost);
        cap += decCont.capital;
        inte += decCont.interets;
      }
      return (
        capital: cap,
        interets: inte,
        assurance: ass,
        crd: capitalRestantA(echeance),
        postRachat: true,
      );
    }

    final n = _moisEntre(dateDebut, echeance);
    final dec = _decomposerOriginal(n);
    return (
      capital: dec.capital,
      interets: dec.interets,
      assurance: ass,
      crd: capitalRestantA(echeance),
      postRachat: false,
    );
  }

  /// Liste de toutes les échéances du crédit (pré + post rachat).
  /// Ordonné chronologiquement, 1-indexé.
  List<DateTime> echeances() {
    final list = <DateTime>[];
    if (isRachete) {
      final nPre = moisEcoulesA(dateRachat!);
      for (var i = 1; i <= nPre; i++) {
        list.add(_addMonths(dateDebut, i));
      }
      final nPost = _newDureeMois;
      final nCont = rachatPartiel ? _continuationDureeMois : 0;
      final nMax = math.max(nPost, nCont);
      for (var i = 1; i <= nMax; i++) {
        list.add(_addMonths(dateRachat!, i));
      }
    } else {
      final fin = isCloture && dateCloture != null
          ? math.min(dureeMois, _moisEntre(dateDebut, dateCloture!))
          : dureeMois;
      for (var i = 1; i <= fin; i++) {
        list.add(_addMonths(dateDebut, i));
      }
    }
    return list;
  }

  /// Total intérêts payés sur toute la durée (avant + après rachat).
  double get totalInterets {
    double total = 0;
    if (isRachete) {
      final nPre = moisEcoulesA(dateRachat!);
      for (var i = 1; i <= nPre; i++) {
        total += _decomposerOriginal(i).interets;
      }
      for (var i = 1; i <= _newDureeMois; i++) {
        total += _decomposerPost(i).interets;
      }
      if (rachatPartiel) {
        for (var i = 1; i <= _continuationDureeMois; i++) {
          total += _decomposerContinuation(i).interets;
        }
      }
    } else if (isCloture && dateCloture != null) {
      final nMax = math.min(dureeMois, _moisEntre(dateDebut, dateCloture!));
      for (var i = 1; i <= nMax; i++) {
        total += _decomposerOriginal(i).interets;
      }
    } else {
      total = (mensualiteHorsAssurance * dureeMois) - capitalEmprunte;
    }
    return total < 0 ? 0 : total;
  }

  /// Intérêts payés avant la date de rachat.
  double get totalInteretsAvantRachat {
    if (!isRachete) return totalInterets;
    double total = 0;
    final nPre = moisEcoulesA(dateRachat!);
    for (var i = 1; i <= nPre; i++) {
      total += _decomposerOriginal(i).interets;
    }
    return total;
  }

  /// Intérêts payés après la date de rachat.
  double get totalInteretsApresRachat {
    if (!isRachete) return 0;
    double total = 0;
    for (var i = 1; i <= _newDureeMois; i++) {
      total += _decomposerPost(i).interets;
    }
    if (rachatPartiel) {
      for (var i = 1; i <= _continuationDureeMois; i++) {
        total += _decomposerContinuation(i).interets;
      }
    }
    return total;
  }

  /// Estimation des intérêts qui auraient été payés sans le rachat,
  /// en gardant les conditions d'origine sur la durée totale.
  double get totalInteretsSansRachat {
    return (mensualiteHorsAssurance * dureeMois) - capitalEmprunte;
  }

  /// Économies estimées grâce au rachat (intérêts d'origine - intérêts effectifs - frais).
  double get economiesRachat {
    if (!isRachete) return 0;
    final orig = totalInteretsSansRachat;
    final effectif = totalInterets + (fraisRachat ?? 0);
    return orig - effectif;
  }

  /// Total assurance sur la durée totale (avant + après rachat).
  double get totalAssurance {
    if (isCloture && dateCloture != null) {
      final n = math.min(dureeMois, _moisEntre(dateDebut, dateCloture!));
      return assuranceMensuelle * n;
    }
    if (isRachete) {
      final nPre = moisEcoulesA(dateRachat!);
      final nPost = _newDureeMois;
      final nCont = rachatPartiel ? _continuationDureeMois : 0;
      return assuranceMensuelle * (nPre + math.max(nPost, nCont));
    }
    return assuranceMensuelle * dureeMois;
  }

  static double _computeMensualite(
    double capital,
    double tauxAnnuel,
    int dureeMois,
  ) {
    if (dureeMois <= 0) return 0;
    if (capital <= 0) return 0;
    final t = tauxAnnuel / 100 / 12;
    if (t == 0) return capital / dureeMois;
    final pow = math.pow(1 + t, -dureeMois).toDouble();
    return capital * t / (1 - pow);
  }

  String computeIntegrityHash() {
    final payload = [
      id,
      logementId,
      libelle,
      capitalEmprunte.toStringAsFixed(2),
      tauxAnnuel.toStringAsFixed(4),
      dateDebut.toUtc().toIso8601String(),
      dureeMois.toString(),
      mensualiteHorsAssurance.toStringAsFixed(2),
      assuranceMensuelle.toStringAsFixed(2),
      notes,
      createdAt.toUtc().toIso8601String(),
      statut.name,
      dateRachat?.toUtc().toIso8601String() ?? '',
      montantRachete?.toStringAsFixed(2) ?? '',
      banqueRacheteur,
      nouveauTaux?.toStringAsFixed(4) ?? '',
      nouvelleDureeMois?.toString() ?? '',
      fraisRachat?.toStringAsFixed(2) ?? '',
      rachatPartiel ? '1' : '0',
      dateCloture?.toUtc().toIso8601String() ?? '',
    ].join('|::|');
    return HashService.sha256Hex(payload);
  }
}

class CreditImmobilierAdapter extends TypeAdapter<CreditImmobilier> {
  @override
  final int typeId = 15;

  @override
  CreditImmobilier read(BinaryReader reader) {
    final numFields = reader.readByte();
    final fields = <int, dynamic>{
      for (var i = 0; i < numFields; i++) reader.readByte(): reader.read(),
    };
    final statutStr = fields[12] as String?;
    final statut = StatutCredit.values.firstWhere(
      (s) => s.name == statutStr,
      orElse: () => StatutCredit.actif,
    );
    return CreditImmobilier(
      id: fields[0] as String,
      logementId: fields[1] as String,
      libelle: fields[2] as String,
      capitalEmprunte: fields[3] as double,
      tauxAnnuel: fields[4] as double,
      dateDebut: DateTime.parse(fields[5] as String),
      dureeMois: fields[6] as int,
      mensualiteHorsAssurance: fields[7] as double,
      assuranceMensuelle: fields[8] as double,
      notes: fields[9] as String,
      createdAt: DateTime.parse(fields[10] as String),
      integrityHash: fields[11] as String?,
      statut: statut,
      dateRachat: fields[13] == null
          ? null
          : DateTime.parse(fields[13] as String),
      montantRachete: fields[14] as double?,
      banqueRacheteur: (fields[15] as String?) ?? '',
      nouveauTaux: fields[16] as double?,
      nouvelleDureeMois: fields[17] as int?,
      fraisRachat: fields[18] as double?,
      rachatPartiel: (fields[19] as bool?) ?? false,
      dateCloture: fields[20] == null
          ? null
          : DateTime.parse(fields[20] as String),
    );
  }

  @override
  void write(BinaryWriter writer, CreditImmobilier obj) {
    writer.writeByte(21);
    writer
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.logementId)
      ..writeByte(2)
      ..write(obj.libelle)
      ..writeByte(3)
      ..write(obj.capitalEmprunte)
      ..writeByte(4)
      ..write(obj.tauxAnnuel)
      ..writeByte(5)
      ..write(obj.dateDebut.toUtc().toIso8601String())
      ..writeByte(6)
      ..write(obj.dureeMois)
      ..writeByte(7)
      ..write(obj.mensualiteHorsAssurance)
      ..writeByte(8)
      ..write(obj.assuranceMensuelle)
      ..writeByte(9)
      ..write(obj.notes)
      ..writeByte(10)
      ..write(obj.createdAt.toUtc().toIso8601String())
      ..writeByte(11)
      ..write(obj.integrityHash)
      ..writeByte(12)
      ..write(obj.statut.name)
      ..writeByte(13)
      ..write(obj.dateRachat?.toUtc().toIso8601String())
      ..writeByte(14)
      ..write(obj.montantRachete)
      ..writeByte(15)
      ..write(obj.banqueRacheteur)
      ..writeByte(16)
      ..write(obj.nouveauTaux)
      ..writeByte(17)
      ..write(obj.nouvelleDureeMois)
      ..writeByte(18)
      ..write(obj.fraisRachat)
      ..writeByte(19)
      ..write(obj.rachatPartiel)
      ..writeByte(20)
      ..write(obj.dateCloture?.toUtc().toIso8601String());
  }
}
