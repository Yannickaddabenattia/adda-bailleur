import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/logement.dart';
import '../../../models/revision_loyer.dart';
import '../../../services/revision_loyer_service.dart';
import '../../../widgets/primary_button.dart';

class RevisionLoyerFormScreen extends StatefulWidget {
  final Logement logement;
  final RevisionLoyer? existing;
  const RevisionLoyerFormScreen({
    super.key,
    required this.logement,
    this.existing,
  });

  @override
  State<RevisionLoyerFormScreen> createState() =>
      _RevisionLoyerFormScreenState();
}

class _RevisionLoyerFormScreenState extends State<RevisionLoyerFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late DateTime _dateEffet;
  final _loyerCtrl = TextEditingController();
  final _chargesCtrl = TextEditingController();
  final _motifCtrl = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _dateEffet = e.dateEffet;
      _loyerCtrl.text = e.loyerHC.toStringAsFixed(2);
      _chargesCtrl.text = e.charges.toStringAsFixed(2);
      _motifCtrl.text = e.motif;
    } else {
      final now = DateTime.now();
      _dateEffet = DateTime(now.year, now.month, 1);
      _loyerCtrl.text = widget.logement.loyerHC.toStringAsFixed(2);
      _chargesCtrl.text = widget.logement.charges.toStringAsFixed(2);
    }
  }

  @override
  void dispose() {
    _loyerCtrl.dispose();
    _chargesCtrl.dispose();
    _motifCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _dateEffet,
      firstDate: DateTime(DateTime.now().year - 10),
      lastDate: DateTime(DateTime.now().year + 10),
      helpText: "Date d'effet (1er du mois)",
      initialDatePickerMode: DatePickerMode.year,
    );
    if (selected != null) {
      setState(() => _dateEffet = DateTime(selected.year, selected.month));
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final loyer = double.parse(_loyerCtrl.text.replaceAll(',', '.'));
    final charges = double.parse(_chargesCtrl.text.replaceAll(',', '.'));
    final service = context.read<RevisionLoyerService>();
    if (widget.existing == null) {
      final r = RevisionLoyer.create(
        logementId: widget.logement.id,
        dateEffet: _dateEffet,
        loyerHC: loyer,
        charges: charges,
        motif: _motifCtrl.text,
      );
      await service.add(r);
    } else {
      final r = widget.existing!;
      r.dateEffet = DateTime(_dateEffet.year, _dateEffet.month, 1);
      r.loyerHC = loyer;
      r.charges = charges;
      r.motif = _motifCtrl.text.trim();
      await service.update(r);
    }
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final dfMonth = DateFormat('MMMM yyyy', 'fr_FR');
    final money =
        NumberFormat.currency(locale: 'fr_FR', symbol: '€', decimalDigits: 2);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing == null
            ? 'Nouvelle révision de loyer'
            : 'Modifier la révision'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.2),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: AppColors.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      "Loyer actuel du logement : "
                      "${money.format(widget.logement.loyerHC)} HC + "
                      "${money.format(widget.logement.charges)} charges.",
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            _PickerTile(
              icon: Icons.event_outlined,
              label: "Date d'effet",
              value:
                  '${dfMonth.format(_dateEffet)[0].toUpperCase()}${dfMonth.format(_dateEffet).substring(1)}',
              onTap: _pickDate,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _loyerCtrl,
              decoration: const InputDecoration(
                labelText: 'Nouveau loyer hors charges (€)',
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
                labelText: 'Nouvelles charges (€)',
                prefixIcon: Icon(Icons.receipt_outlined),
              ),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              validator: _validateAmount,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _motifCtrl,
              decoration: const InputDecoration(
                labelText: 'Motif (facultatif)',
                prefixIcon: Icon(Icons.notes_outlined),
                hintText: 'Indexation IRL, négociation, travaux…',
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 24),
            PrimaryButton(
              label: widget.existing == null
                  ? 'Créer la révision'
                  : 'Enregistrer',
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
    final p = double.tryParse(v.replaceAll(',', '.'));
    if (p == null || p < 0) return 'Montant invalide';
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
