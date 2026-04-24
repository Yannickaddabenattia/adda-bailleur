import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/templates/edl_templates.dart';
import '../../core/theme/app_theme.dart';
import '../../models/etat_des_lieux.dart';
import '../../services/etat_des_lieux_service.dart';
import '../../services/locataire_service.dart';
import '../../services/logement_service.dart';
import '../../widgets/primary_button.dart';
import 'etat_des_lieux_edit_screen.dart';

/// Wizard de création d'un nouvel EDL : choix type + logement + locataire + date.
class EtatDesLieuxWizardScreen extends StatefulWidget {
  const EtatDesLieuxWizardScreen({super.key});

  @override
  State<EtatDesLieuxWizardScreen> createState() =>
      _EtatDesLieuxWizardScreenState();
}

class _EtatDesLieuxWizardScreenState extends State<EtatDesLieuxWizardScreen> {
  EtatDesLieuxType _type = EtatDesLieuxType.entree;
  String? _logementId;
  String? _locataireId;
  DateTime _date = DateTime.now();
  bool _saving = false;

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(DateTime.now().year - 5),
      lastDate: DateTime(DateTime.now().year + 5),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _create() async {
    if (_logementId == null || _locataireId == null) return;
    setState(() => _saving = true);

    final logement = context.read<LogementService>().byId(_logementId!);
    if (logement == null) {
      setState(() => _saving = false);
      return;
    }

    final edl = EtatDesLieux.create(
      type: _type,
      logementId: _logementId!,
      locataireId: _locataireId!,
      date: _date,
      pieces: EdlTemplates.defaultFor(logement.type),
    );
    await context.read<EtatDesLieuxService>().save(edl);

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => EtatDesLieuxEditScreen(edlId: edl.id),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final logements = context.watch<LogementService>().all;
    final locataires = context.watch<LocataireService>().all;

    final canSubmit = _logementId != null && _locataireId != null && !_saving;

    return Scaffold(
      appBar: AppBar(title: const Text('Nouvel état des lieux')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const _Label('Type'),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _TypeButton(
                    selected: _type == EtatDesLieuxType.entree,
                    icon: Icons.login_rounded,
                    label: 'Entrée',
                    onTap: () =>
                        setState(() => _type = EtatDesLieuxType.entree),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _TypeButton(
                    selected: _type == EtatDesLieuxType.sortie,
                    icon: Icons.logout_rounded,
                    label: 'Sortie',
                    onTap: () =>
                        setState(() => _type = EtatDesLieuxType.sortie),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const _Label('Logement'),
            const SizedBox(height: 8),
            if (logements.isEmpty)
              const _Hint('Créez d\'abord un logement.')
            else
              DropdownButtonFormField<String>(
                initialValue: _logementId,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.apartment_rounded),
                  hintText: 'Choisissez un logement',
                ),
                items: logements
                    .map((l) => DropdownMenuItem(
                          value: l.id,
                          child: Text(l.libelle,
                              overflow: TextOverflow.ellipsis),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _logementId = v),
              ),
            const SizedBox(height: 20),
            const _Label('Locataire'),
            const SizedBox(height: 8),
            if (locataires.isEmpty)
              const _Hint('Créez d\'abord un locataire.')
            else
              DropdownButtonFormField<String>(
                initialValue: _locataireId,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.person_outline),
                  hintText: 'Choisissez un locataire',
                ),
                items: locataires
                    .map((l) => DropdownMenuItem(
                          value: l.id,
                          child: Text(l.fullName),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _locataireId = v),
              ),
            const SizedBox(height: 20),
            const _Label('Date'),
            const SizedBox(height: 8),
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: _pickDate,
              child: InputDecorator(
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.calendar_today_outlined),
                ),
                child: Text(
                  '${_date.day.toString().padLeft(2, '0')}/'
                  '${_date.month.toString().padLeft(2, '0')}/${_date.year}',
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ),
            const SizedBox(height: 32),
            PrimaryButton(
              label: 'Créer et pré-remplir les pièces',
              icon: Icons.arrow_forward,
              loading: _saving,
              onPressed: canSubmit ? _create : null,
            ),
            const SizedBox(height: 12),
            const Text(
              'Les pièces seront pré-remplies selon le type de logement. '
              'Vous pourrez les ajuster librement à l\'écran suivant.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        fontSize: 12,
        letterSpacing: 1,
        fontWeight: FontWeight.w700,
        color: AppColors.textSecondary,
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  final String text;
  const _Hint(this.text);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Text(text,
          style: const TextStyle(color: AppColors.textSecondary)),
    );
  }
}

class _TypeButton extends StatelessWidget {
  final bool selected;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _TypeButton({
    required this.selected,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.1)
              : AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.divider,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(icon,
                color:
                    selected ? AppColors.primary : AppColors.textSecondary),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                color:
                    selected ? AppColors.primary : AppColors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
