import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../models/logement.dart';
import '../../services/logement_service.dart';
import '../../widgets/primary_button.dart';

class LogementFormScreen extends StatefulWidget {
  final Logement? logement;
  const LogementFormScreen({super.key, this.logement});

  @override
  State<LogementFormScreen> createState() => _LogementFormScreenState();
}

class _LogementFormScreenState extends State<LogementFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _libelle;
  late TextEditingController _adresse;
  late TextEditingController _codePostal;
  late TextEditingController _ville;
  late TextEditingController _surface;
  late TextEditingController _nbPieces;
  late TextEditingController _loyerHC;
  late TextEditingController _charges;
  late TextEditingController _equipements;
  late TextEditingController _notes;
  late LogementType _type;
  bool _saving = false;

  bool get _isEdit => widget.logement != null;

  @override
  void initState() {
    super.initState();
    final l = widget.logement;
    _libelle = TextEditingController(text: l?.libelle ?? '');
    _adresse = TextEditingController(text: l?.adresse ?? '');
    _codePostal = TextEditingController(text: l?.codePostal ?? '');
    _ville = TextEditingController(text: l?.ville ?? '');
    _surface = TextEditingController(
        text: l == null ? '' : l.surface.toStringAsFixed(0));
    _nbPieces =
        TextEditingController(text: l == null ? '' : l.nbPieces.toString());
    _loyerHC = TextEditingController(
        text: l == null ? '' : l.loyerHC.toStringAsFixed(2));
    _charges = TextEditingController(
        text: l == null ? '' : l.charges.toStringAsFixed(2));
    _equipements =
        TextEditingController(text: l?.equipements.join(', ') ?? '');
    _notes = TextEditingController(text: l?.notes ?? '');
    _type = l?.type ?? LogementType.appartement;
  }

  @override
  void dispose() {
    _libelle.dispose();
    _adresse.dispose();
    _codePostal.dispose();
    _ville.dispose();
    _surface.dispose();
    _nbPieces.dispose();
    _loyerHC.dispose();
    _charges.dispose();
    _equipements.dispose();
    _notes.dispose();
    super.dispose();
  }

  List<String> _parseEquipements(String raw) {
    return raw
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final service = context.read<LogementService>();
    try {
      if (_isEdit) {
        final l = widget.logement!;
        l.libelle = _libelle.text.trim();
        l.adresse = _adresse.text.trim();
        l.codePostal = _codePostal.text.trim();
        l.ville = _ville.text.trim();
        l.type = _type;
        l.surface = double.parse(_surface.text.replaceAll(',', '.'));
        l.nbPieces = int.parse(_nbPieces.text);
        l.loyerHC = double.parse(_loyerHC.text.replaceAll(',', '.'));
        l.charges = double.parse(_charges.text.replaceAll(',', '.'));
        l.equipements = _parseEquipements(_equipements.text);
        l.notes = _notes.text.trim();
        await service.update(l);
      } else {
        final logement = Logement.create(
          libelle: _libelle.text,
          adresse: _adresse.text,
          codePostal: _codePostal.text,
          ville: _ville.text,
          type: _type,
          surface: double.parse(_surface.text.replaceAll(',', '.')),
          nbPieces: int.parse(_nbPieces.text),
          loyerHC: double.parse(_loyerHC.text.replaceAll(',', '.')),
          charges: double.parse(_charges.text.replaceAll(',', '.')),
          equipements: _parseEquipements(_equipements.text),
          notes: _notes.text,
        );
        await service.add(logement);
      }
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur : $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Modifier le logement' : 'Nouveau logement'),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              _Section(title: 'Identification'),
              const SizedBox(height: 8),
              TextFormField(
                controller: _libelle,
                decoration: const InputDecoration(
                  labelText: 'Libellé *',
                  hintText: 'Ex: Appartement République',
                  prefixIcon: Icon(Icons.label_outline),
                ),
                textCapitalization: TextCapitalization.sentences,
                validator: (v) =>
                    (v?.trim().length ?? 0) < 2 ? 'Libellé requis' : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<LogementType>(
                initialValue: _type,
                decoration: const InputDecoration(
                  labelText: 'Type *',
                  prefixIcon: Icon(Icons.home_work_outlined),
                ),
                items: LogementType.values
                    .map((t) => DropdownMenuItem(
                          value: t,
                          child: Text(t.label),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _type = v ?? _type),
              ),
              const SizedBox(height: 20),
              _Section(title: 'Adresse'),
              const SizedBox(height: 8),
              TextFormField(
                controller: _adresse,
                decoration: const InputDecoration(
                  labelText: 'Adresse *',
                  prefixIcon: Icon(Icons.location_on_outlined),
                ),
                textCapitalization: TextCapitalization.words,
                validator: (v) =>
                    (v?.trim().length ?? 0) < 3 ? 'Adresse requise' : null,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  SizedBox(
                    width: 120,
                    child: TextFormField(
                      controller: _codePostal,
                      decoration: const InputDecoration(
                        labelText: 'CP *',
                      ),
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(5),
                      ],
                      validator: (v) =>
                          (v?.length ?? 0) != 5 ? 'CP sur 5 chiffres' : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _ville,
                      decoration: const InputDecoration(
                        labelText: 'Ville *',
                      ),
                      textCapitalization: TextCapitalization.words,
                      validator: (v) => (v?.trim().length ?? 0) < 2
                          ? 'Ville requise'
                          : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _Section(title: 'Caractéristiques'),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _surface,
                      decoration: const InputDecoration(
                        labelText: 'Surface (m²) *',
                        prefixIcon: Icon(Icons.square_foot),
                      ),
                      keyboardType: TextInputType.number,
                      validator: _numberValidator,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _nbPieces,
                      decoration: const InputDecoration(
                        labelText: 'Pièces *',
                        prefixIcon: Icon(Icons.door_front_door_outlined),
                      ),
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      validator: _numberValidator,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _Section(title: 'Loyer'),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _loyerHC,
                      decoration: const InputDecoration(
                        labelText: 'Loyer HC *',
                        suffixText: '€',
                      ),
                      keyboardType: TextInputType.number,
                      validator: _numberValidator,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _charges,
                      decoration: const InputDecoration(
                        labelText: 'Charges *',
                        suffixText: '€',
                      ),
                      keyboardType: TextInputType.number,
                      validator: _numberValidator,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _Section(title: 'Optionnel'),
              const SizedBox(height: 8),
              TextFormField(
                controller: _equipements,
                decoration: const InputDecoration(
                  labelText: 'Équipements (séparés par des virgules)',
                  hintText: 'Chauffage, Balcon, Parking',
                  prefixIcon: Icon(Icons.checklist_outlined),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _notes,
                decoration: const InputDecoration(
                  labelText: 'Notes',
                  alignLabelWithHint: true,
                ),
                maxLines: 3,
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 28),
              PrimaryButton(
                label: _isEdit ? 'Enregistrer' : 'Créer le logement',
                icon: Icons.check,
                loading: _saving,
                onPressed: _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String? _numberValidator(String? v) {
    if (v == null || v.trim().isEmpty) return 'Requis';
    final parsed = double.tryParse(v.replaceAll(',', '.'));
    if (parsed == null) return 'Nombre invalide';
    if (parsed < 0) return 'Doit être positif';
    return null;
  }
}

class _Section extends StatelessWidget {
  final String title;
  const _Section({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title.toUpperCase(),
      style: const TextStyle(
        fontSize: 12,
        letterSpacing: 1,
        fontWeight: FontWeight.w700,
        color: AppColors.textSecondary,
      ),
    );
  }
}
