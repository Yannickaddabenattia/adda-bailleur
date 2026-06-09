import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../models/bail_template.dart';
import '../../models/clause.dart';
import '../../models/contrat_bail.dart';
import '../../services/bail_template_service.dart';

/// Édition d'un template utilisateur.
///
/// [existing] = null pour créer un nouveau template, sinon édition d'un
/// template utilisateur. Refuse les templates `isSystem = true` (à
/// dupliquer d'abord via `BailTemplateService.duplicateSystem`).
class BailTemplateEditScreen extends StatefulWidget {
  final BailTemplate? existing;

  const BailTemplateEditScreen({super.key, this.existing});

  @override
  State<BailTemplateEditScreen> createState() => _BailTemplateEditScreenState();
}

class _BailTemplateEditScreenState extends State<BailTemplateEditScreen> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _nom;
  late final TextEditingController _description;
  late final TextEditingController _duree;
  late final TextEditingController _depotMultiplicateur;
  late final TextEditingController _preavisBailleur;
  late final TextEditingController _preavisLocataire;
  late BailType _typeBail;
  late bool _renouvellementTacite;
  late bool _depotInterdit;
  late bool _justificatifMobilite;
  late Set<String> _clausesCochees;

  @override
  void initState() {
    super.initState();
    final t = widget.existing;
    _nom = TextEditingController(text: t?.nom ?? '');
    _description = TextEditingController(text: t?.description ?? '');
    _typeBail = t?.typeBail ?? BailType.vide;
    _duree = TextEditingController(
      text: (t?.dureeDefautMois ?? _typeBail.dureeDefautMois).toString(),
    );
    _depotMultiplicateur = TextEditingController(
      text: (t?.depotMultiplicateurLoyer ??
              _typeBail.plafondDepotMois.toDouble())
          .toString(),
    );
    _preavisBailleur = TextEditingController(
      text: (t?.preavisBailleurMois ?? _typeBail.preavisBailleurMois)
          .toString(),
    );
    _preavisLocataire = TextEditingController(
      text: (t?.preavisLocataireMois ?? _typeBail.preavisLocataireMois)
          .toString(),
    );
    _renouvellementTacite =
        t?.renouvellementTacite ?? _typeBail.renouvellementTaciteParDefaut;
    _depotInterdit = t?.depotInterdit ?? (_typeBail == BailType.mobilite);
    _justificatifMobilite = t?.justificatifMobiliteRequis ?? false;
    _clausesCochees = Set<String>.from(t?.clausesPreCochees ?? const []);
  }

  @override
  void dispose() {
    _nom.dispose();
    _description.dispose();
    _duree.dispose();
    _depotMultiplicateur.dispose();
    _preavisBailleur.dispose();
    _preavisLocataire.dispose();
    super.dispose();
  }

  void _onTypeChanged(BailType t) {
    setState(() {
      _typeBail = t;
      _duree.text = t.dureeDefautMois.toString();
      _depotMultiplicateur.text = t.plafondDepotMois.toDouble().toString();
      _preavisBailleur.text = t.preavisBailleurMois.toString();
      _preavisLocataire.text = t.preavisLocataireMois.toString();
      _renouvellementTacite = t.renouvellementTaciteParDefaut;
      _depotInterdit = t == BailType.mobilite;
      _justificatifMobilite = t == BailType.mobilite;
    });
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final svc = context.read<BailTemplateService>();
    final t = widget.existing?.copy() ??
        BailTemplate.userTemplate(
          nom: _nom.text.trim(),
          description: _description.text.trim(),
          typeBail: _typeBail,
          dureeDefautMois: int.parse(_duree.text.trim()),
          depotMultiplicateurLoyer:
              double.parse(_depotMultiplicateur.text.replaceAll(',', '.')),
          depotInterdit: _depotInterdit,
          preavisBailleurMois: int.parse(_preavisBailleur.text.trim()),
          preavisLocataireMois: int.parse(_preavisLocataire.text.trim()),
          renouvellementTacite: _renouvellementTacite,
          justificatifMobiliteRequis: _justificatifMobilite,
          clausesPreCochees: _clausesCochees.toList(),
        );
    if (widget.existing != null) {
      t.nom = _nom.text.trim();
      t.description = _description.text.trim();
      t.typeBail = _typeBail;
      t.dureeDefautMois = int.parse(_duree.text.trim());
      t.depotMultiplicateurLoyer =
          double.parse(_depotMultiplicateur.text.replaceAll(',', '.'));
      t.depotInterdit = _depotInterdit;
      t.preavisBailleurMois = int.parse(_preavisBailleur.text.trim());
      t.preavisLocataireMois = int.parse(_preavisLocataire.text.trim());
      t.renouvellementTacite = _renouvellementTacite;
      t.justificatifMobiliteRequis = _justificatifMobilite;
      t.clausesPreCochees = _clausesCochees.toList();
    }
    await svc.save(t);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    final clauses = ClauseCatalogue.standard;
    // Grouper les clauses par catégorie
    final byCategory = <ClauseCategorie, List<Clause>>{};
    for (final c in clauses) {
      byCategory.putIfAbsent(c.categorie, () => []).add(c);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? 'Modifier le modèle' : 'Nouveau modèle'),
        actions: [
          TextButton(
            onPressed: _save,
            child: const Text('Enregistrer'),
          ),
        ],
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
          children: [
            TextFormField(
              controller: _nom,
              decoration: const InputDecoration(
                labelText: 'Nom du modèle',
                hintText: 'Ex : Mon T2 Nice meublé étudiant',
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Nom requis' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _description,
              decoration: const InputDecoration(
                labelText: 'Description (optionnel)',
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 20),
            DropdownButtonFormField<BailType>(
              initialValue: _typeBail,
              decoration: const InputDecoration(labelText: 'Type de bail'),
              items: BailType.values
                  .map((t) => DropdownMenuItem(
                        value: t,
                        child: Text(t.label),
                      ))
                  .toList(),
              onChanged: (t) {
                if (t != null) _onTypeChanged(t);
              },
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _duree,
                    decoration: const InputDecoration(
                      labelText: 'Durée (mois)',
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _depotMultiplicateur,
                    enabled: !_depotInterdit,
                    decoration: const InputDecoration(
                      labelText: 'Dépôt × loyer HC',
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            CheckboxListTile(
              value: _depotInterdit,
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('Dépôt de garantie interdit (mobilité)'),
              onChanged: (v) =>
                  setState(() => _depotInterdit = v ?? false),
            ),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _preavisBailleur,
                    decoration: const InputDecoration(
                      labelText: 'Préavis bailleur (mois)',
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _preavisLocataire,
                    decoration: const InputDecoration(
                      labelText: 'Préavis locataire (mois)',
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ),
              ],
            ),
            CheckboxListTile(
              value: _renouvellementTacite,
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('Renouvellement tacite'),
              onChanged: (v) =>
                  setState(() => _renouvellementTacite = v ?? false),
            ),
            CheckboxListTile(
              value: _justificatifMobilite,
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('Justificatif de mobilité requis'),
              onChanged: (v) =>
                  setState(() => _justificatifMobilite = v ?? false),
            ),
            const SizedBox(height: 20),
            Text(
              'Clauses pré-cochées (${_clausesCochees.length} / ${clauses.length})',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            for (final cat
                in ClauseCategorie.values.where((c) => byCategory[c] != null))
              _CategorySection(
                titre: cat.label,
                clauses: byCategory[cat]!,
                cochees: _clausesCochees,
                onToggle: (id, v) => setState(() {
                  if (v) {
                    _clausesCochees.add(id);
                  } else {
                    _clausesCochees.remove(id);
                  }
                }),
              ),
          ],
        ),
      ),
    );
  }
}

class _CategorySection extends StatelessWidget {
  final String titre;
  final List<Clause> clauses;
  final Set<String> cochees;
  final void Function(String id, bool v) onToggle;

  const _CategorySection({
    required this.titre,
    required this.clauses,
    required this.cochees,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      title: Text(titre),
      tilePadding: EdgeInsets.zero,
      childrenPadding: EdgeInsets.zero,
      initiallyExpanded: false,
      children: [
        for (final c in clauses)
          CheckboxListTile(
            value: cochees.contains(c.id),
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 8),
            title: Text(
              c.titre,
              style: const TextStyle(fontSize: 13),
            ),
            subtitle: Text(
              c.contenu,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color: context.textSecondaryColor,
              ),
            ),
            onChanged: (v) => onToggle(c.id, v ?? false),
          ),
      ],
    );
  }
}
