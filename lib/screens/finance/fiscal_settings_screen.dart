import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../models/fiscal_settings.dart';
import '../../services/fiscalite_service.dart';
import '../../widgets/primary_button.dart';

/// Réglages fiscaux du foyer (parts, autres revenus, statut marital).
class FiscalSettingsScreen extends StatefulWidget {
  const FiscalSettingsScreen({super.key});

  @override
  State<FiscalSettingsScreen> createState() => _FiscalSettingsScreenState();
}

class _FiscalSettingsScreenState extends State<FiscalSettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _partsCtrl = TextEditingController();
  final _autresRevenusCtrl = TextEditingController();
  final _autresNichesCtrl = TextEditingController();
  final Map<int, TextEditingController> _revenusParAnnee = {};
  late List<int> _annees;
  bool _marie = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final s = context.read<FiscaliteService>().settings;
    _partsCtrl.text = s.parts.toString().replaceAll('.', ',');
    _autresRevenusCtrl.text = s.autresRevenusBruts.toStringAsFixed(0);
    _autresNichesCtrl.text = s.autresNichesFiscales.toStringAsFixed(0);
    _marie = s.marieOuPacse;

    final now = DateTime.now().year;
    // Fenêtre par défaut : 5 années passées + année en cours. On ajoute aussi
    // toute année déjà saisie en dehors de cette fenêtre (utile pour l'historique).
    final autres = s.autresRevenusBrutsParAnnee.keys.toSet();
    final base = {
      for (var i = 4; i >= 0; i--) now - i,
    };
    _annees = {...base, ...autres}.toList()..sort();
    for (final y in _annees) {
      final v = s.autresRevenusBrutsParAnnee[y];
      _revenusParAnnee[y] = TextEditingController(
        text: v == null ? '' : v.toStringAsFixed(0),
      );
    }
  }

  @override
  void dispose() {
    _partsCtrl.dispose();
    _autresRevenusCtrl.dispose();
    _autresNichesCtrl.dispose();
    for (final c in _revenusParAnnee.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _addPreviousYear() {
    final earliest =
        _annees.isEmpty ? DateTime.now().year : _annees.first;
    final newYear = earliest - 1;
    setState(() {
      _annees.insert(0, newYear);
      _revenusParAnnee[newYear] = TextEditingController();
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final svc = context.read<FiscaliteService>();
    final current = svc.settings;
    final parts = double.parse(_partsCtrl.text.replaceAll(',', '.'));
    final autres = double.parse(
      _autresRevenusCtrl.text.replaceAll(',', '.').replaceAll(' ', ''),
    );
    final niches = _autresNichesCtrl.text.trim().isEmpty
        ? 0.0
        : double.parse(
            _autresNichesCtrl.text.replaceAll(',', '.').replaceAll(' ', ''),
          );
    final revenusParAnnee = <int, double>{};
    for (final entry in _revenusParAnnee.entries) {
      final raw = entry.value.text.trim();
      if (raw.isEmpty) continue;
      final v = double.tryParse(
        raw.replaceAll(',', '.').replaceAll(' ', ''),
      );
      if (v != null && v >= 0) {
        revenusParAnnee[entry.key] = v;
      }
    }
    final updated = FiscalSettings(
      parts: parts,
      autresRevenusBruts: autres,
      marieOuPacse: _marie,
      deficitsReportables: current.deficitsReportables,
      anneeBareme: current.anneeBareme,
      autresNichesFiscales: niches,
      autresRevenusBrutsParAnnee: revenusParAnnee,
    );
    await svc.saveSettings(updated);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Paramètres fiscaux')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.25),
                ),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: AppColors.primary),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Ces paramètres concernent l\'ensemble du foyer fiscal '
                      'et servent à estimer l\'impôt sur le revenu et les '
                      'prélèvements sociaux.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const _SectionLabel('SITUATION'),
            const SizedBox(height: 8),
            SwitchListTile(
              title: const Text('Marié(e) ou pacsé(e)'),
              subtitle: const Text(
                'Déclaration commune (parts de référence : 2)',
                style: TextStyle(fontSize: 12),
              ),
              value: _marie,
              onChanged: (v) => setState(() => _marie = v),
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _partsCtrl,
              decoration: const InputDecoration(
                labelText: 'Nombre de parts fiscales',
                helperText:
                    'Célibataire : 1 · Couple : 2 · +0,5 par enfant (1er, 2e) · +1 dès le 3e',
                prefixIcon: Icon(Icons.family_restroom_outlined),
              ),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
              ],
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Requis';
                final p = double.tryParse(v.replaceAll(',', '.'));
                if (p == null || p < 0.5 || p > 20) {
                  return 'Entre 0,5 et 20';
                }
                return null;
              },
            ),
            const SizedBox(height: 20),
            const _SectionLabel('AUTRES REVENUS DU FOYER'),
            const SizedBox(height: 8),
            TextFormField(
              controller: _autresRevenusCtrl,
              decoration: const InputDecoration(
                labelText: 'Valeur par défaut (€/an)',
                helperText:
                    'Utilisée pour toute année non renseignée ci-dessous. '
                    'Salaires + pensions, hors revenus fonciers.',
                helperMaxLines: 2,
                prefixIcon: Icon(Icons.work_outline),
              ),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,\s]')),
              ],
              validator: (v) {
                if (v == null || v.trim().isEmpty) return null;
                final p = double.tryParse(
                  v.replaceAll(',', '.').replaceAll(' ', ''),
                );
                if (p == null || p < 0) return 'Montant invalide';
                return null;
              },
            ),
            const SizedBox(height: 16),
            const _SectionLabel('SAISIE ANNÉE PAR ANNÉE'),
            const SizedBox(height: 4),
            const Text(
              'Renseigne le revenu brut pour chaque année. Une année laissée '
              'vide retombe sur la valeur par défaut ci-dessus.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            for (final year in _annees) ...[
              TextFormField(
                controller: _revenusParAnnee[year],
                decoration: InputDecoration(
                  labelText: 'Revenu brut $year (€)',
                  prefixIcon: const Icon(Icons.calendar_month_outlined),
                ),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,\s]')),
                ],
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return null;
                  final p = double.tryParse(
                    v.replaceAll(',', '.').replaceAll(' ', ''),
                  );
                  if (p == null || p < 0) return 'Montant invalide';
                  return null;
                },
              ),
              const SizedBox(height: 8),
            ],
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _addPreviousYear,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Ajouter une année antérieure'),
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.divider),
              ),
              child: const Text(
                'L\'application applique automatiquement l\'abattement '
                'forfaitaire de 10 % sur les autres revenus pour le calcul '
                'de l\'impôt.',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            const SizedBox(height: 20),
            const _SectionLabel('AUTRES RÉDUCTIONS / CRÉDITS D\'IMPÔT'),
            const SizedBox(height: 8),
            TextFormField(
              controller: _autresNichesCtrl,
              decoration: const InputDecoration(
                labelText: 'Autres niches fiscales déjà déclarées (€)',
                helperText:
                    'Services à la personne, dons, garde d\'enfant… '
                    'Hors revenus fonciers. Sert au plafonnement global '
                    '(10 000 €/an).',
                prefixIcon: Icon(Icons.savings_outlined),
              ),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,\s]')),
              ],
              validator: (v) {
                if (v == null || v.trim().isEmpty) return null;
                final p = double.tryParse(
                  v.replaceAll(',', '.').replaceAll(' ', ''),
                );
                if (p == null || p < 0) return 'Montant invalide';
                return null;
              },
            ),
            const SizedBox(height: 28),
            PrimaryButton(
              label: 'Enregistrer',
              icon: Icons.check_circle_outline,
              loading: _saving,
              onPressed: _save,
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel(this.label);

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        color: AppColors.textSecondary,
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
      ),
    );
  }
}
