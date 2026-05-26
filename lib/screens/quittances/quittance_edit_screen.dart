import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../models/quittance.dart';
import '../../services/locataire_service.dart';
import '../../services/logement_service.dart';
import '../../services/quittance_service.dart';
import '../../widgets/primary_button.dart';

class QuittanceEditScreen extends StatefulWidget {
  final String quittanceId;
  const QuittanceEditScreen({super.key, required this.quittanceId});

  @override
  State<QuittanceEditScreen> createState() => _QuittanceEditScreenState();
}

class _QuittanceEditScreenState extends State<QuittanceEditScreen> {
  final _formKey = GlobalKey<FormState>();
  late DateTime _periode;
  late DateTime _datePaiement;
  late TextEditingController _loyerCtrl;
  late TextEditingController _chargesCtrl;
  late TextEditingController _notesCtrl;
  bool _saving = false;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    final q = context.read<QuittanceService>().byId(widget.quittanceId);
    if (q == null) return;
    _periode = DateTime(q.periodYear, q.periodMonth);
    _datePaiement = q.datePaiement;
    _loyerCtrl = TextEditingController(text: q.loyerHC.toStringAsFixed(2));
    _chargesCtrl = TextEditingController(text: q.charges.toStringAsFixed(2));
    _notesCtrl = TextEditingController(text: q.notes);
    _initialized = true;
  }

  @override
  void dispose() {
    if (_initialized) {
      _loyerCtrl.dispose();
      _chargesCtrl.dispose();
      _notesCtrl.dispose();
    }
    super.dispose();
  }

  Future<void> _pickPeriode() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _periode,
      firstDate: DateTime(DateTime.now().year - 20),
      lastDate: DateTime(DateTime.now().year + 5, 12),
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
      firstDate: DateTime(DateTime.now().year - 20),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      helpText: 'Date de paiement',
    );
    if (selected != null) {
      setState(() => _datePaiement = selected);
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final service = context.read<QuittanceService>();
    final original = service.byId(widget.quittanceId);
    if (original == null) return;

    final periodChanged = _periode.year != original.periodYear ||
        _periode.month != original.periodMonth;
    if (periodChanged) {
      final collision = service.all.any((other) =>
          other.id != original.id &&
          other.locataireId == original.locataireId &&
          other.periodYear == _periode.year &&
          other.periodMonth == _periode.month);
      if (collision) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Une autre quittance existe déjà pour ce locataire sur cette période.',
            ),
          ),
        );
        return;
      }
    }

    setState(() => _saving = true);
    final updated = Quittance.edit(
      original: original,
      periodYear: _periode.year,
      periodMonth: _periode.month,
      loyerHC: double.parse(_loyerCtrl.text.replaceAll(',', '.')),
      charges: double.parse(_chargesCtrl.text.replaceAll(',', '.')),
      datePaiement: _datePaiement,
      notes: _notesCtrl.text,
    );
    await service.update(updated);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final q = context.watch<QuittanceService>().byId(widget.quittanceId);
    if (q == null) {
      return const Scaffold(
        body: Center(child: Text('Quittance introuvable.')),
      );
    }
    final logement = context.watch<LogementService>().byId(q.logementId);
    final locataire = context.watch<LocataireService>().byId(q.locataireId);
    final dfPeriode = DateFormat('MMMM yyyy', 'fr_FR');
    final dfDate = DateFormat('dd/MM/yyyy', 'fr_FR');

    return Scaffold(
      appBar: AppBar(title: const Text('Modifier la quittance')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _ReadOnlyTile(
              icon: Icons.apartment_outlined,
              label: 'Logement',
              value: logement?.libelle ?? '—',
            ),
            const SizedBox(height: 10),
            _ReadOnlyTile(
              icon: Icons.person_outline,
              label: 'Locataire',
              value: locataire?.fullName ?? '—',
            ),
            const SizedBox(height: 16),
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
              label: 'Enregistrer les modifications',
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
          color: context.surfaceColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: context.dividerColor),
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
                      style: TextStyle(
                          fontSize: 12,
                          color: context.textSecondaryColor)),
                  const SizedBox(height: 2),
                  Text(value,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: context.textSecondaryColor),
          ],
        ),
      ),
    );
  }
}

class _ReadOnlyTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _ReadOnlyTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.dividerColor),
      ),
      child: Row(
        children: [
          Icon(icon, color: context.textSecondaryColor),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        fontSize: 12, color: context.textSecondaryColor)),
                const SizedBox(height: 2),
                Text(value,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
