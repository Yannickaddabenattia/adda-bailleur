import 'package:flutter_test/flutter_test.dart';
import 'package:adda_location/models/quittance.dart';
import 'package:adda_location/services/quittance_service.dart';

/// Quittance de test : total = loyerHC + charges = 800 € par défaut.
Quittance _q({
  String id = 'q',
  String logementId = 'A',
  required int year,
  required int month,
  double loyerHC = 700,
  double charges = 100,
  double? montantPaye,
  Map<String, double>? versements,
}) {
  final d = DateTime(year, month, 5);
  return Quittance(
    id: id,
    logementId: logementId,
    locataireId: 'loc',
    periodYear: year,
    periodMonth: month,
    loyerHC: loyerHC,
    charges: charges,
    datePaiement: d,
    dateEmission: d,
    notes: '',
    createdAt: d,
    montantPaye: montantPaye,
    versementsSupplementaires: versements,
  );
}

double _total(Map<int, double> m) =>
    m.values.fold<double>(0, (s, v) => s + v);

void main() {
  group('QuittanceService.encaisseParMoisLogement', () {
    Map<int, double> run(List<Quittance> qs, {int year = 2026}) =>
        QuittanceService.encaisseParMoisLogement(
            quittances: qs, logementId: 'A', year: year);

    test('montantPaye null → on retombe sur le total (anciennes quittances)',
        () {
      final r = run([_q(year: 2026, month: 3)]);
      expect(r[3], closeTo(800, 1e-9));
    });

    test('paiement partiel → on compte le montant réellement payé', () {
      final r = run([_q(year: 2026, month: 3, montantPaye: 300)]);
      expect(r[3], closeTo(300, 1e-9));
    });

    test('colocataires : deux quittances du même mois → max, pas la somme', () {
      final r = run([
        _q(id: 'a', year: 2026, month: 4),
        _q(id: 'b', year: 2026, month: 4),
      ]);
      expect(r[4], closeTo(800, 1e-9)); // pas 1600
    });

    test('colocataires partiels : on garde le plus élevé', () {
      final r = run([
        _q(id: 'a', year: 2026, month: 4, montantPaye: 800),
        _q(id: 'b', year: 2026, month: 4, montantPaye: 500),
      ]);
      expect(r[4], closeTo(800, 1e-9));
    });

    test('versement de régularisation ajouté au mois ciblé', () {
      // Quittance de juin qui rattrape 150 € d'arriéré de février.
      final r = run([
        _q(year: 2026, month: 6, versements: {'2026-02': 150}),
      ]);
      expect(r[6], closeTo(800, 1e-9));
      expect(r[2], closeTo(150, 1e-9));
    });

    test('versement comptabilisé même s\'il est saisi sur une quittance '
        'd\'une autre année', () {
      // Quittance de décembre 2025, versement d'avance sur janvier 2026.
      final r = run([
        _q(year: 2025, month: 12, versements: {'2026-01': 200}),
      ], year: 2026);
      expect(r[1], closeTo(200, 1e-9)); // le loyer 2025 n'est pas compté
      expect(r.containsKey(12), isFalse);
    });

    test('versement ciblant une autre année → ignoré', () {
      final r = run([
        _q(year: 2026, month: 1, versements: {'2025-12': 100}),
      ]);
      expect(r[1], closeTo(800, 1e-9)); // seulement le loyer de janvier
      expect(_total(r), closeTo(800, 1e-9)); // les 100 € de 2025 exclus
    });

    test('autre logement exclu', () {
      final r = run([
        _q(year: 2026, month: 5, logementId: 'B', montantPaye: 999),
      ]);
      expect(r.isEmpty, isTrue);
    });

    test('total annuel = loyers encaissés + régularisations', () {
      final r = run([
        _q(id: '1', year: 2026, month: 1, montantPaye: 800),
        _q(id: '2', year: 2026, month: 2, montantPaye: 600), // partiel
        _q(id: '3', year: 2026, month: 3, versements: {'2026-02': 200}),
      ]);
      // jan 800 + fév (600 + 200 régul) + mars 800 = 2400
      expect(_total(r), closeTo(2400, 1e-9));
      expect(r[2], closeTo(800, 1e-9));
    });
  });
}
