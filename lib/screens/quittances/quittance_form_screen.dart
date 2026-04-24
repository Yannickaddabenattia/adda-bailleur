import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../models/locataire.dart';
import '../../models/logement.dart';
import '../../models/quittance.dart';
import '../../services/locataire_service.dart';
import '../../services/logement_service.dart';
import '../../services/quittance_service.dart';
import '../../widgets/primary_button.dart';
import 'quittance_detail_screen.dart';

class QuittanceFormScreen extends StatefulWidget {
  const QuittanceFormScreen({super.key});

  @override
  State<QuittanceFormScreen> createState() => _QuittanceFormScreenState();
}

class _QuittanceFormScreenState extends State<QuittanceFormScreen> {
  final _formKey = GlobalKey<FormState>();
  Logement? _logement;
  Locataire? _locataire;
  DateTime _periode = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime _datePaiement = DateTime.now();
  final _loyerCtrl = TextEditingController();
  final _chargesCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _loyerCtrl.dispose();
    _chargesCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  void _applyLogementDefaults(Logement l) {
    _loyerCtrl.text = l.loyerHC.toStringAsFixed(2);
    _chargesCtrl.text = l.charges.toStringAsFixed(2);
  }

  Future<void> _pickPeriode() async {
    final now = DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: _periode,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 1, 12),
      helpText: 'Période de la quittance',
      initialDatePickerMode: DatePickerMode.year,
    );
    if (selected != null) {
      setState(() => _periode = DateTime(selected.year, selected.month));
    }
  }

  Future<void> _pickPaiement() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _datePaiement,
      firstDate: DateTime(DateTime.now().year - 5),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      helpText: 'Date de paiement',
    );
    if (selected != null) {
      setState(() => _datePaiement = selected);
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_logement == null || _locataire == null) return;
    final service = context.read<QuittanceService>();
    if (service.exists(
      locataireId: _locataire!.id,
      year: _periode.year,
      month: _periode.month,
    )) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Une quittance existe déjà pour ce locataire sur cette période.',
          ),
        ),
      );
      return;
    }

    setState(() => _saving = true);
    final q = Quittance.create(
      logementId: _logement!.id,
      locataireId: _locataire!.id,
      periodYear: _periode.year,
      periodMonth: _periode.month,
      loyerHC: double.parse(_loyerCtrl.text.replaceAll(',', '.')),
      charges: double.parse(_chargesCtrl.text.replaceAll(',', '.')),
      datePaiement: _datePaiement,
      notes: _notesCtrl.text,
    );
    await service.add(q);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => QuittanceDetailScreen(quittanceId: q.id),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final logements = context.watch<LogementService>().all;
    final locataires = context.watch<LocataireService>().all;
    final dfPeriode = DateFormat('MMMM yyyy', 'fr_FR');
    final dfDate = DateFormat('dd/MM/yyyy', 'fr_FR');

    return Scaffold(
      appBar: AppBar(title: const Text('Nouvelle quittance')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            DropdownButtonFormField<String>(
              initialValue: _logement?.id,
              decoration: const InputDecoration(
                labelText: 'Logement',
                prefixIcon: Icon(Icons.apartment_outlined),
              ),
              items: logements
                  .map((l) =>
                      DropdownMenuItem(value: l.id, child: Text(l.libelle)))
                  .toList(),
              validator: (v) => v == null ? 'Sélectionnez un logement' : null,
              onChanged: (id) {
                if (id == null) return;
                final l = logements.firstWhere((e) => e.id == id);
                setState(() {
                  _logement = l;
                  _applyLogementDefaults(l);
                });
              },
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _locataire?.id,
              decoration: const InputDecoration(
                labelText: 'Locataire',
                prefixIcon: Icon(Icons.person_outline),
              ),
              items: locataires
                  .map((l) => DropdownMenuItem(
                      value: l.id, child: Text(l.fullName)))
                  .toList(),
              validator: (v) => v == null ? 'Sélectionnez un locataire' : null,
              onChanged: (id) {
                if (id == null) return;
                setState(() {
                  _locataire = locataires.firstWhere((e) => e.id == id);
                });
              },
            ),
            const SizedBox(height: 20),
            _PickerTile(
              icon: Icons.calendar_month_outlined,
              label: 'Période',
              value:
                  '${dfPeriode.format(_periode)[0].toUpperCase()}${dfPeriode.format(_periode).substring(1)}',
              onTap: _pickPeriode,
            ),
            const SizedBox(height: 10),
            _PickerTile(
              icon: Icons.event_available_outlined,
              label: 'Date de paiement',
              value: dfDate.format(_datePaiement),
              onTap: _pickPaiement,
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _loyerCtrl,
              decoration: const InputDecoration(
                labelText: 'Loyer hors charges (€)',
                prefixIcon: Icon(Icons.payments_outlined),
              ),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              validator: _validateAmount,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _chargesCtrl,
              decoration: const InputDecoration(
                labelText: 'Charges (€)',
                prefixIcon: Icon(Icons.receipt_outlined),
              ),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              validator: _validateAmount,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _notesCtrl,
              decoration: const InputDecoration(
                labelText: 'Notes (facultatif)',
                prefixIcon: Icon(Icons.notes_outlined),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 24),
            PrimaryButton(
              label: 'Créer la quittance',
              icon: Icons.check_circle_outline,
              loading: _saving,
              onPressed: _submit,
            ),
          ],
        ),
      ),
    );
  }

  String? _validateAmount(String? v) {
    if (v == null || v.trim().isEmpty) return 'Requis';
    final parsed = double.tryParse(v.replaceAll(',', '.'));
    if (parsed == null || parsed < 0) return 'Montant invalide';
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
