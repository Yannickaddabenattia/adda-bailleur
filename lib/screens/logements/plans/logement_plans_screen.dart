import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/plan_logement.dart';
import '../../../services/logement_service.dart';
import '../../../services/plan_logement_service.dart';
import 'plan_editor_screen.dart';

class LogementPlansScreen extends StatelessWidget {
  final String logementId;
  const LogementPlansScreen({super.key, required this.logementId});

  @override
  Widget build(BuildContext context) {
    final plans = context.watch<PlanLogementService>().byLogement(logementId);
    final logement = context.watch<LogementService>().byId(logementId);
    final niveaux = plans.where((p) => p.kind == PlanKind.niveau).toList();
    final dependances =
        plans.where((p) => p.kind == PlanKind.dependance).toList();
    final terrains =
        plans.where((p) => p.kind == PlanKind.terrain).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Plans du logement')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addPlan(context),
        icon: const Icon(Icons.add),
        label: const Text('Ajouter un plan'),
      ),
      body: plans.isEmpty
          ? _empty(context)
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
              children: [
                if (niveaux.isNotEmpty) ...[
                  _SectionTitle('Niveaux'),
                  ...niveaux.map(
                      (p) => _PlanCard(plan: p, logementPieces: logement?.nbPieces)),
                  const SizedBox(height: 16),
                ],
                if (dependances.isNotEmpty) ...[
                  _SectionTitle('Dépendances'),
                  ...dependances.map((p) => _PlanCard(plan: p)),
                  const SizedBox(height: 16),
                ],
                if (terrains.isNotEmpty) ...[
                  _SectionTitle('Terrains'),
                  ...terrains.map((p) => _PlanCard(plan: p)),
                ],
              ],
            ),
    );
  }

  Widget _empty(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.architecture_outlined,
                size: 64, color: AppColors.textSecondary),
            const SizedBox(height: 12),
            const Text(
              'Aucun plan',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            const Text(
              'Ajoutez un plan par niveau (RDC, 1ᵉʳ étage…), '
              'par dépendance (garage, cave…) ou par terrain '
              '(jardin, cour…).',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addPlan(BuildContext context) async {
    final form = await showModalBottomSheet<_PlanFormResult>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _PlanCreateSheet(),
    );
    if (form == null) return;
    if (!context.mounted) return;
    final plan = PlanLogement.create(
      logementId: logementId,
      kind: form.kind,
      name: form.name,
    );
    await context.read<PlanLogementService>().save(plan);
    if (!context.mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PlanEditorScreen(planId: plan.id)),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 4),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 1,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  final PlanLogement plan;
  final int? logementPieces;
  const _PlanCard({required this.plan, this.logementPieces});

  @override
  Widget build(BuildContext context) {
    final hasContent = plan.hasImage || plan.hasDrawing;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: 56,
            height: 56,
            color: AppColors.primary.withValues(alpha: 0.08),
            child: plan.hasImage
                ? Image.file(File(plan.imagePath!), fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) =>
                        const Icon(Icons.broken_image_outlined))
                : Icon(
                    plan.hasDrawing
                        ? Icons.grid_4x4_outlined
                        : Icons.add_chart_outlined,
                    color: AppColors.primary,
                  ),
          ),
        ),
        title: Text(plan.name,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          hasContent
              ? (plan.hasImage
                  ? 'Image importée'
                  : '${logementPieces ?? plan.rooms.length} pièce(s)')
              : 'Vide — touchez pour éditer',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
        trailing: PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert),
          onSelected: (value) async {
            if (value == 'delete') {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Supprimer ce plan ?'),
                  content: Text('« ${plan.name} » sera supprimé définitivement.'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(false),
                      child: const Text('Annuler'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(true),
                      style:
                          TextButton.styleFrom(foregroundColor: AppColors.error),
                      child: const Text('Supprimer'),
                    ),
                  ],
                ),
              );
              if (ok == true && context.mounted) {
                await context.read<PlanLogementService>().delete(plan.id);
              }
            } else if (value == 'rename') {
              final newName = await _askName(context, initial: plan.name);
              if (newName != null && newName.trim().isNotEmpty) {
                plan.name = newName.trim();
                if (context.mounted) {
                  await context.read<PlanLogementService>().save(plan);
                }
              }
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'rename', child: Text('Renommer')),
            PopupMenuItem(value: 'delete', child: Text('Supprimer')),
          ],
        ),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => PlanEditorScreen(planId: plan.id),
          ),
        ),
      ),
    );
  }

  Future<String?> _askName(BuildContext context, {String initial = ''}) async {
    final ctrl = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Renommer le plan'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Nom'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(ctrl.text),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}

class _PlanFormResult {
  final PlanKind kind;
  final String name;
  _PlanFormResult({required this.kind, required this.name});
}

class _PlanCreateSheet extends StatefulWidget {
  const _PlanCreateSheet();

  @override
  State<_PlanCreateSheet> createState() => _PlanCreateSheetState();
}

class _PlanCreateSheetState extends State<_PlanCreateSheet> {
  PlanKind _kind = PlanKind.niveau;
  final _ctrl = TextEditingController();
  final _suggestions = const {
    PlanKind.niveau: ['RDC', '1ᵉʳ étage', '2ᵉ étage', 'Sous-sol', 'Comble'],
    PlanKind.dependance: ['Garage', 'Cave', 'Atelier', 'Buanderie'],
    PlanKind.terrain: ['Terrain', 'Jardin', 'Cour avant', 'Cour arrière'],
  };

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final suggs = _suggestions[_kind]!;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Nouveau plan',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _KindButton(
                  selected: _kind == PlanKind.niveau,
                  icon: Icons.layers_outlined,
                  label: 'Niveau',
                  onTap: () => setState(() => _kind = PlanKind.niveau),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _KindButton(
                  selected: _kind == PlanKind.dependance,
                  icon: Icons.house_siding_outlined,
                  label: 'Dépendance',
                  onTap: () => setState(() => _kind = PlanKind.dependance),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _KindButton(
                  selected: _kind == PlanKind.terrain,
                  icon: Icons.grass_outlined,
                  label: 'Terrain',
                  onTap: () => setState(() => _kind = PlanKind.terrain),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _ctrl,
            decoration: InputDecoration(
              labelText: switch (_kind) {
                PlanKind.niveau => 'Nom (ex: RDC, 1ᵉʳ étage…)',
                PlanKind.dependance => 'Nom (ex: Garage, Cave…)',
                PlanKind.terrain => 'Nom (ex: Jardin, Cour…)',
              },
              prefixIcon: const Icon(Icons.label_outline),
            ),
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: suggs
                .map((s) => ActionChip(
                      label: Text(s),
                      onPressed: () => setState(() => _ctrl.text = s),
                    ))
                .toList(),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _submit,
            icon: const Icon(Icons.arrow_forward),
            label: const Text('Créer et éditer'),
          ),
        ],
      ),
    );
  }

  void _submit() {
    final name = _ctrl.text.trim();
    if (name.isEmpty) return;
    Navigator.of(context).pop(_PlanFormResult(kind: _kind, name: name));
  }
}

class _KindButton extends StatelessWidget {
  final bool selected;
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _KindButton({
    required this.selected,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.1)
              : AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.divider,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(icon,
                color: selected ? AppColors.primary : AppColors.textSecondary),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: selected ? AppColors.primary : AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
