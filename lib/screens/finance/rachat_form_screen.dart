import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../models/credit_immobilier.dart';
import '../../services/credit_service.dart';
import '../../widgets/primary_button.dart';

/// Formulaire pour ajouter ou modifier un rachat de crédit.
class RachatFormScreen extends StatefulWidget {
  final CreditImmobilier credit;
  const RachatFormScreen({super.key, required this.credit});

  @override
  State<RachatFormScreen> createState() => _RachatFormScreenState();
}

enum _DureeUnit { annees, mois }

class _RachatFormScreenState extends State<RachatFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _montantCtrl = TextEditingController();
  final _banqueCtrl = TextEditingController();
  final _tauxCtrl = TextEditingController();
  final _dureeCtrl = TextEditingController();
  _DureeUnit _dureeUnit = _DureeUnit.annees;
  final _fraisCtrl = TextEditingController(text: '0');
  late DateTime _dateRachat;
  bool _partiel = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final c = widget.credit;
    _dateRachat = c.dateRachat ??
        DateTime(DateTime.now().year, DateTime.now().month);
    if (c.isRachete) {
      _montantCtrl.text = (c.montantRachete ?? 0).toStringAsFixed(2);
      _banqueCtrl.text = c.banqueRacheteur;
      _tauxCtrl.text = (c.nouveauTaux ?? c.tauxAnnuel).toString();
      final mois = c.nouvelleDureeMois ?? c.dureeMois;
      _setDureeFromMois(mois);
      _fraisCtrl.text = (c.fraisRachat ?? 0).toStringAsFixed(2);
      _partiel = c.rachatPartiel;
    } else {
      // Pré-remplit avec le CRD au moment du rachat (date courante)
      final crdAuRachat = c.capitalRestantA(_dateRachat);
      _montantCtrl.text = crdAuRachat.toStringAsFixed(2);
      _tauxCtrl.text = c.tauxAnnuel.toString();
      final moisRest = c.dureeMois - c.moisEcoulesA(_dateRachat);
      _setDureeFromMois(moisRest);
    }
  }

  void _setDureeFromMois(int mois) {
    if (mois > 0 && mois % 12 == 0) {
      _dureeUnit = _DureeUnit.annees;
      _dureeCtrl.text = (mois ~/ 12).toString();
    } else {
      _dureeUnit = _DureeUnit.mois;
      _dureeCtrl.text = mois.toString();
    }
  }

  int? _parseDureeMois() {
    final raw = _dureeCtrl.text.replaceAll(',', '.').trim();
    final v = double.tryParse(raw);
    if (v == null || v <= 0) return null;
    return _dureeUnit == _DureeUnit.annees ? (v * 12).round() : v.round();
  }

  void _switchUnit(_DureeUnit next) {
    if (next == _dureeUnit) return;
    final raw = _dureeCtrl.text.replaceAll(',', '.').trim();
    final v = double.tryParse(raw);
    setState(() {
      _dureeUnit = next;
      if (v != null && v > 0) {
        if (next == _DureeUnit.mois) {
          _dureeCtrl.text = (v * 12).round().toString();
        } else {
          final years = v / 12;
          _dureeCtrl.text = years == years.roundToDouble()
              ? years.toStringAsFixed(0)
              : years.toStringAsFixed(1);
        }
      }
    });
  }

  @override
  void dispose() {
    _montantCtrl.dispose();
    _banqueCtrl.dispose();
    _tauxCtrl.dispose();
    _dureeCtrl.dispose();
    _fraisCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _dateRachat,
      firstDate: widget.credit.dateDebut,
      lastDate: DateTime(DateTime.now().year + 30),
      helpText: 'Date du rachat',
    );
    if (selected != null) {
      setState(() => _dateRachat = DateTime(selected.year, selected.month, 1));
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final c = widget.credit;
    final montant = double.parse(_montantCtrl.text.replaceAll(',', '.'));
    final taux = double.parse(_tauxCtrl.text.replaceAll(',', '.'));
    final dureeMois = _parseDureeMois()!;
    final frais = double.parse(_fraisCtrl.text.replaceAll(',', '.'));

    c.statut = StatutCredit.rachete;
    c.dateRachat = _dateRachat;
    c.montantRachete = montant;
    c.banqueRacheteur = _banqueCtrl.text.trim();
    c.nouveauTaux = taux;
    c.nouvelleDureeMois = dureeMois;
    c.fraisRachat = frais;
    c.rachatPartiel = _partiel;

    await context.read<CreditService>().update(c);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer le rachat ?'),
        content: const Text(
          'Le crédit redevient actif avec ses conditions d\'origine.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Supprimer',
                style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final c = widget.credit;
    c.statut = StatutCredit.actif;
    c.dateRachat = null;
    c.montantRachete = null;
    c.banqueRacheteur = '';
    c.nouveauTaux = null;
    c.nouvelleDureeMois = null;
    c.fraisRachat = null;
    c.rachatPartiel = false;
    if (!mounted) return;
    await context.read<CreditService>().update(c);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final dfMonth = DateFormat('MMMM yyyy', 'fr_FR');
    final money = NumberFormat.currency(locale: 'fr_FR', symbol: '€');
    final crdAuRachat = widget.credit.capitalRestantA(_dateRachat);
    final isEdit = widget.credit.isRachete;
    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? 'Modifier le rachat' : 'Ajouter un rachat'),
        actions: [
          if (isEdit)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: _delete,
              tooltip: 'Supprimer le rachat',
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF7C3AED).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFF7C3AED).withValues(alpha: 0.25),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.swap_horiz_outlined,
                      color: Color(0xFF7C3AED)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.credit.libelle,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          'CRD au ${dfMonth.format(_dateRachat)} : ${money.format(crdAuRachat)}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            _PickerTile(
              icon: Icons.event_outlined,
              label: 'Date du rachat',
              value:
                  '${dfMonth.format(_dateRachat)[0].toUpperCase()}${dfMonth.format(_dateRachat).substring(1)}',
              onTap: _pickDate,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _montantCtrl,
              decoration: const InputDecoration(
                labelText: 'Montant racheté (€)',
                helperText: 'Capital repris par la nouvelle banque',
                prefixIcon: Icon(Icons.payments_outlined),
              ),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Requis';
                final p = double.tryParse(v.replaceAll(',', '.'));
                if (p == null || p <= 0) return 'Montant invalide';
                if (p > crdAuRachat * 1.05) {
                  return 'Supérieur au CRD à cette date';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            CheckboxListTile(
              value: _partiel,
              onChanged: (v) => setState(() => _partiel = v ?? false),
              title: const Text('Rachat partiel'),
              subtitle: const Text(
                'La portion non rachetée continue avec les conditions d\'origine.',
                style: TextStyle(fontSize: 12),
              ),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _banqueCtrl,
              decoration: const InputDecoration(
                labelText: 'Banque racheteur',
                prefixIcon: Icon(Icons.account_balance_outlined),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Requis' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _tauxCtrl,
              decoration: const InputDecoration(
                labelText: 'Nouveau taux annuel (%)',
                prefixIcon: Icon(Icons.percent_outlined),
              ),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              validator: _validatePositive,
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _dureeCtrl,
                    decoration: InputDecoration(
                      labelText: _dureeUnit == _DureeUnit.annees
                          ? 'Nouvelle durée (années)'
                          : 'Nouvelle durée (mois)',
                      prefixIcon: const Icon(Icons.timer_outlined),
                    ),
                    keyboardType: TextInputType.numberWithOptions(
                      decimal: _dureeUnit == _DureeUnit.annees,
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Requis';
                      final p = double.tryParse(v.replaceAll(',', '.'));
                      if (p == null || p <= 0) return 'Valeur invalide';
                      if (_dureeUnit == _DureeUnit.mois &&
                          p != p.roundToDouble()) {
                        return 'Entier requis';
                      }
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: SegmentedButton<_DureeUnit>(
                    segments: const [
                      ButtonSegment(
                        value: _DureeUnit.annees,
                        label: Text('Années'),
                      ),
                      ButtonSegment(
                        value: _DureeUnit.mois,
                        label: Text('Mois'),
                      ),
                    ],
                    selected: {_dureeUnit},
                    showSelectedIcon: false,
                    onSelectionChanged: (s) => _switchUnit(s.first),
                    style: const ButtonStyle(
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _fraisCtrl,
              decoration: const InputDecoration(
                labelText: 'Frais de rachat (€)',
                helperText:
                    'Indemnités, garanties, frais de dossier… (0 si aucun)',
                prefixIcon: Icon(Icons.receipt_long_outlined),
              ),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return null;
                final p = double.tryParse(v.replaceAll(',', '.'));
                if (p == null || p < 0) return 'Montant invalide';
                return null;
              },
            ),
            const SizedBox(height: 24),
            PrimaryButton(
              label: isEdit ? 'Enregistrer' : 'Confirmer le rachat',
              icon: Icons.check_circle_outline,
              loading: _saving,
              onPressed: _submit,
            ),
          ],
        ),
      ),
    );
  }

  String? _validatePositive(String? v) {
    if (v == null || v.trim().isEmpty) return 'Requis';
    final p = double.tryParse(v.replaceAll(',', '.'));
    if (p == null || p <= 0) return 'Valeur invalide';
    return null;
  }
}

class _PickerTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;
  const _PickerTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.divider),
        ),
        child: Row(
          children: [
            Icon(icon, color: AppColors.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textSecondary)),
                  const SizedBox(height: 2),
                  Text(value,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }
}
