import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../models/bail_template.dart';
import '../../models/contrat_bail.dart';
import '../../models/logement.dart';
import '../../services/bail_template_service.dart';
import 'bail_template_edit_screen.dart';
import 'contrat_bail_form_screen.dart';

/// Galerie de templates de bails. Premier sas du flow « Nouveau bail ».
///
/// Affiche les templates système puis les templates utilisateur. Tap sur
/// un template ouvre [ContratBailFormScreen] pré-rempli avec ses valeurs.
/// Un bouton « Repartir à blanc » contourne pour les cas où aucun template
/// ne convient.
class BailTemplateGalleryScreen extends StatelessWidget {
  final Logement logement;
  const BailTemplateGalleryScreen({super.key, required this.logement});

  @override
  Widget build(BuildContext context) {
    final svc = context.watch<BailTemplateService>();
    final system = svc.systemTemplates();
    final user = svc.userTemplates();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Nouveau bail'),
        actions: [
          TextButton.icon(
            onPressed: () => _openForm(context, null),
            icon: const Icon(Icons.edit_note),
            label: const Text('Repartir à blanc'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: [
          Text(
            'Choisissez un modèle de bail. Vous pourrez tout modifier ensuite.',
            style: TextStyle(color: context.textSecondaryColor),
          ),
          const SizedBox(height: 20),
          Text(
            'Modèles standards',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 10),
          for (final t in system)
            _TemplateCard(
              template: t,
              onTap: () => _openForm(context, t),
            ),
          const SizedBox(height: 28),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Mes modèles',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              TextButton.icon(
                onPressed: () => _createUserTemplate(context),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Nouveau'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (user.isEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: context.surfaceColor.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'Pas encore de modèle personnel. Vous pouvez en créer en '
                'cliquant « Nouveau », ou en cochant « Enregistrer comme '
                'modèle » lors de la création d\'un bail.',
                style: TextStyle(color: context.textSecondaryColor),
              ),
            )
          else
            for (final t in user)
              _TemplateCard(
                template: t,
                onTap: () => _openForm(context, t),
                onEdit: () => _editUserTemplate(context, t),
                onDelete: () => _deleteUserTemplate(context, t),
              ),
        ],
      ),
    );
  }

  void _openForm(BuildContext context, BailTemplate? template) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => ContratBailFormScreen(
          logement: logement,
          template: template,
        ),
      ),
    );
  }

  Future<void> _createUserTemplate(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const BailTemplateEditScreen(),
      ),
    );
  }

  Future<void> _editUserTemplate(
      BuildContext context, BailTemplate t) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BailTemplateEditScreen(existing: t),
      ),
    );
  }

  Future<void> _deleteUserTemplate(
      BuildContext context, BailTemplate t) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer ce modèle ?'),
        content: Text(
          '« ${t.nom} » sera supprimé. Les bails déjà créés à partir de ce '
          'modèle ne seront pas modifiés.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    if (!context.mounted) return;
    await context.read<BailTemplateService>().delete(t.id);
  }
}

class _TemplateCard extends StatelessWidget {
  final BailTemplate template;
  final VoidCallback onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const _TemplateCard({
    required this.template,
    required this.onTap,
    this.onEdit,
    this.onDelete,
  });

  IconData get _icon {
    switch (template.typeBail) {
      case BailType.vide:
        return Icons.home_outlined;
      case BailType.meuble:
        return Icons.weekend_outlined;
      case BailType.colocation:
        return Icons.groups_outlined;
      case BailType.saisonnier:
        return Icons.beach_access_outlined;
      case BailType.mobilite:
        return Icons.swap_horiz_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isUser = !template.isSystem;
    final fmtDate = DateFormat('dd MMM yyyy', 'fr_FR');
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: isUser
                    ? Colors.amber.withValues(alpha: 0.18)
                    : AppColors.primary.withValues(alpha: 0.12),
                child: Icon(
                  _icon,
                  color: isUser ? Colors.amber.shade800 : AppColors.primary,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            template.nom,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (isUser)
                          PopupMenuButton<String>(
                            iconSize: 20,
                            tooltip: 'Actions',
                            onSelected: (v) {
                              if (v == 'edit' && onEdit != null) onEdit!();
                              if (v == 'delete' && onDelete != null) {
                                onDelete!();
                              }
                            },
                            itemBuilder: (_) => [
                              const PopupMenuItem(
                                value: 'edit',
                                child: Text('Modifier'),
                              ),
                              const PopupMenuItem(
                                value: 'delete',
                                child: Text('Supprimer'),
                              ),
                            ],
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      template.description,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: context.textSecondaryColor,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _Chip(label: template.typeBail.label),
                        _Chip(label: '${template.dureeDefautMois} mois'),
                        _Chip(
                          label: template.depotInterdit
                              ? 'Pas de dépôt'
                              : 'Dépôt × ${template.depotMultiplicateurLoyer.toStringAsFixed(template.depotMultiplicateurLoyer == template.depotMultiplicateurLoyer.toInt() ? 0 : 1)}',
                        ),
                        _Chip(
                          label:
                              '${template.clausesPreCochees.length} clauses',
                        ),
                        if (isUser && template.nbUtilisations > 0)
                          _Chip(
                            label:
                                'Utilisé ${template.nbUtilisations}×',
                            highlight: true,
                          ),
                        if (isUser && template.dateModification != null)
                          _Chip(
                            label:
                                'Modifié ${fmtDate.format(template.dateModification!.toLocal())}',
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool highlight;
  const _Chip({required this.label, this.highlight = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: highlight
            ? AppColors.primary.withValues(alpha: 0.12)
            : context.dividerColor.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          color: highlight ? AppColors.primary : context.textSecondaryColor,
          fontWeight: highlight ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
    );
  }
}
