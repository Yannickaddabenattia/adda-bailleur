import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../models/avenant.dart';
import '../../models/contrat_bail.dart';
import '../../services/avenant_service.dart';

/// Liste des avenants d'un contrat de bail + création/édition via dialog.
class AvenantListScreen extends StatelessWidget {
  final ContratBail bail;
  const AvenantListScreen({super.key, required this.bail});

  @override
  Widget build(BuildContext context) {
    final svc = context.watch<AvenantService>();
    final list = svc.forContrat(bail.id);
    final money = NumberFormat.currency(locale: 'fr_FR', symbol: '€');
    final df = DateFormat('dd MMM yyyy', 'fr_FR');
    return Scaffold(
      appBar: AppBar(
        title: const Text('Avenants'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _open(context, null),
        icon: const Icon(Icons.add),
        label: const Text('Nouvel avenant'),
      ),
      body: list.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.note_add_outlined,
                        size: 64, color: AppColors.textSecondary),
                    SizedBox(height: 16),
                    Text('Aucun avenant',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w700)),
                    SizedBox(height: 8),
                    Text(
                      'Crée un avenant pour modifier le loyer, la durée, '
                      'ou ajouter une clause. Il sera annexé au contrat '
                      'initial et signé par les deux parties.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 96),
              itemCount: list.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (ctx, i) {
                final a = list[i];
                return InkWell(
                  onTap: () => _open(context, a),
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: context.surfaceColor,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: context.dividerColor),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: AppColors.primary
                                    .withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                'Avenant #${a.numero}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.primary,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Effet le ${df.format(a.dateEffet)}',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: context.textSecondaryColor),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          a.objet,
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w700),
                        ),
                        if (a.description.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            a.description,
                            style: const TextStyle(fontSize: 12),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        if (a.nouveauLoyerHC != null ||
                            a.nouvellesCharges != null ||
                            a.nouvelleDureeMois != null) ...[
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            children: [
                              if (a.nouveauLoyerHC != null)
                                _Chip(
                                  text:
                                      'Loyer → ${money.format(a.nouveauLoyerHC)}',
                                ),
                              if (a.nouvellesCharges != null)
                                _Chip(
                                  text:
                                      'Charges → ${money.format(a.nouvellesCharges)}',
                                ),
                              if (a.nouvelleDureeMois != null)
                                _Chip(
                                  text: 'Durée → ${a.nouvelleDureeMois} mois',
                                ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }

  Future<void> _open(BuildContext context, Avenant? existing) async {
    final svc = context.read<AvenantService>();
    final result = await showDialog<Avenant?>(
      context: context,
      builder: (ctx) => _AvenantFormDialog(
        bail: bail,
        existing: existing,
        nextNumero: existing?.numero ?? svc.nextNumeroFor(bail.id),
      ),
    );
    if (result == null) return;
    await svc.save(result);
  }
}

class _Chip extends StatelessWidget {
  final String text;
  const _Chip({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 11,
          color: AppColors.success,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _AvenantFormDialog extends StatefulWidget {
  final ContratBail bail;
  final Avenant? existing;
  final int nextNumero;

  const _AvenantFormDialog({
    required this.bail,
    required this.existing,
    required this.nextNumero,
  });

  @override
  State<_AvenantFormDialog> createState() => _AvenantFormDialogState();
}

class _AvenantFormDialogState extends State<_AvenantFormDialog> {
  late TextEditingController _objet;
  late TextEditingController _description;
  late TextEditingController _nouveauLoyer;
  late TextEditingController _nouvellesCharges;
  late TextEditingController _nouvelleDuree;
  late DateTime _dateEffet;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _objet = TextEditingController(text: e?.objet ?? '');
    _description = TextEditingController(text: e?.description ?? '');
    _nouveauLoyer = TextEditingController(
        text: e?.nouveauLoyerHC?.toStringAsFixed(2) ?? '');
    _nouvellesCharges = TextEditingController(
        text: e?.nouvellesCharges?.toStringAsFixed(2) ?? '');
    _nouvelleDuree =
        TextEditingController(text: e?.nouvelleDureeMois?.toString() ?? '');
    _dateEffet = e?.dateEffet ?? DateTime.now();
  }

  @override
  void dispose() {
    _objet.dispose();
    _description.dispose();
    _nouveauLoyer.dispose();
    _nouvellesCharges.dispose();
    _nouvelleDuree.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateEffet,
      firstDate: widget.bail.dateDebut,
      lastDate: DateTime(DateTime.now().year + 10),
    );
    if (picked != null) setState(() => _dateEffet = picked);
  }

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('dd MMMM yyyy', 'fr_FR');
    return AlertDialog(
      title: Text(widget.existing == null
          ? 'Nouvel avenant #${widget.nextNumero}'
          : 'Modifier l\'avenant #${widget.existing!.numero}'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _objet,
                decoration: const InputDecoration(
                  labelText: 'Objet *',
                  helperText: 'Ex : Révision IRL 2027, Ajout dressing…',
                  prefixIcon: Icon(Icons.title),
                ),
              ),
              const SizedBox(height: 12),
              InkWell(
                onTap: _pickDate,
                borderRadius: BorderRadius.circular(12),
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Date d\'effet',
                    prefixIcon: Icon(Icons.event_outlined),
                  ),
                  child: Text(dateFmt.format(_dateEffet)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _description,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  helperText: 'Précise les modifications de manière claire.',
                ),
                minLines: 3,
                maxLines: 8,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _nouveauLoyer,
                      decoration: const InputDecoration(
                        labelText: 'Nouveau loyer HC',
                        helperText: 'Vide = inchangé',
                        suffixText: '€',
                      ),
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _nouvellesCharges,
                      decoration: const InputDecoration(
                        labelText: 'Nouvelles charges',
                        suffixText: '€',
                      ),
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _nouvelleDuree,
                decoration: const InputDecoration(
                  labelText: 'Nouvelle durée (mois)',
                  helperText: 'Vide = inchangée',
                  prefixIcon: Icon(Icons.timer_outlined),
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: () {
            if (_objet.text.trim().isEmpty) return;
            final nouveauLoyer =
                double.tryParse(_nouveauLoyer.text.replaceAll(',', '.'));
            final nouvellesCharges =
                double.tryParse(_nouvellesCharges.text.replaceAll(',', '.'));
            final nouvelleDuree = int.tryParse(_nouvelleDuree.text);
            DateTime? nouvelleDateFin;
            if (nouvelleDuree != null && nouvelleDuree > 0) {
              nouvelleDateFin = DateTime(
                widget.bail.dateDebut.year +
                    ((widget.bail.dateDebut.month - 1 + nouvelleDuree) ~/ 12),
                ((widget.bail.dateDebut.month - 1 + nouvelleDuree) % 12) + 1,
                widget.bail.dateDebut.day,
              );
            }
            final existing = widget.existing;
            final a = existing ??
                Avenant.create(
                  contratBailId: widget.bail.id,
                  numero: widget.nextNumero,
                  dateEffet: _dateEffet,
                  objet: _objet.text.trim(),
                );
            a.objet = _objet.text.trim();
            a.description = _description.text.trim();
            a.dateEffet = _dateEffet;
            a.nouveauLoyerHC = nouveauLoyer;
            a.nouvellesCharges = nouvellesCharges;
            a.nouvelleDureeMois = nouvelleDuree;
            a.nouvelleDateFin = nouvelleDateFin;
            Navigator.of(context).pop(a);
          },
          child: const Text('Enregistrer'),
        ),
      ],
    );
  }
}
