import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../models/depense.dart';
import '../../models/logement.dart';
import '../../services/depense_service.dart';
import '../../services/expense_categories_service.dart';
import '../../services/logement_service.dart';
import '../../widgets/primary_button.dart';

class DepenseFormScreen extends StatefulWidget {
  final Depense? existing;
  final String? initialLogementId;
  const DepenseFormScreen({
    super.key,
    this.existing,
    this.initialLogementId,
  });

  @override
  State<DepenseFormScreen> createState() => _DepenseFormScreenState();
}

class _DepenseFormScreenState extends State<DepenseFormScreen> {
  final _formKey = GlobalKey<FormState>();
  Logement? _logement;
  String? _categorie;
  final _libelleCtrl = TextEditingController();
  final _montantCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  DateTime _date = DateTime.now();
  final List<String> _justifs = [];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _libelleCtrl.text = e.libelle;
      _montantCtrl.text = e.montant.toStringAsFixed(2);
      _notesCtrl.text = e.notes;
      _date = e.date;
      _categorie = e.categorie;
      _justifs.addAll(e.justificatifs);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_logement == null) {
      final logements = context.read<LogementService>().all;
      final id = widget.existing?.logementId ?? widget.initialLogementId;
      if (id != null) {
        for (final l in logements) {
          if (l.id == id) {
            _logement = l;
            break;
          }
        }
      }
    }
  }

  @override
  void dispose() {
    _libelleCtrl.dispose();
    _montantCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(DateTime.now().year - 10),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (selected != null) setState(() => _date = selected);
  }

  Future<void> _addPhotoJustif() async {
    final picker = ImagePicker();
    final src = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Prendre une photo'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Galerie'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (src == null) return;
    final picked = await picker.pickImage(source: src, imageQuality: 85);
    if (picked == null) return;
    await _saveJustifFile(File(picked.path));
  }

  Future<void> _addPdfJustif() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (res == null || res.files.isEmpty) return;
    final p = res.files.single.path;
    if (p == null) return;
    await _saveJustifFile(File(p));
  }

  Future<void> _saveJustifFile(File source) async {
    final service = context.read<DepenseService>();
    final id = widget.existing?.id ??
        DateTime.now().millisecondsSinceEpoch.toString();
    final stored = await service.attachJustificatif(id, source);
    setState(() => _justifs.add(stored));
  }

  Future<void> _addCustomCategory() async {
    final ctrl = TextEditingController();
    final service = context.read<ExpenseCategoriesService>();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nouvelle catégorie'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Nom de la catégorie'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Ajouter'),
          ),
        ],
      ),
    );
    if (result == null || result.isEmpty) return;
    await service.add(result);
    if (!mounted) return;
    setState(() => _categorie = result);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_logement == null || _categorie == null) return;
    setState(() => _saving = true);
    final service = context.read<DepenseService>();
    final montant = double.parse(_montantCtrl.text.replaceAll(',', '.'));
    if (widget.existing == null) {
      final d = Depense.create(
        logementId: _logement!.id,
        categorie: _categorie!,
        libelle: _libelleCtrl.text,
        montant: montant,
        date: _date,
        notes: _notesCtrl.text,
        justificatifs: _justifs,
      );
      await service.add(d);
    } else {
      final e = widget.existing!;
      e.categorie = _categorie!;
      e.libelle = _libelleCtrl.text.trim();
      e.montant = montant;
      e.date = _date;
      e.notes = _notesCtrl.text.trim();
      e.justificatifs = List<String>.from(_justifs);
      await service.update(e);
    }
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final logements = context.watch<LogementService>().all;
    final categories = context.watch<ExpenseCategoriesService>().all;
    final df = DateFormat('dd/MM/yyyy', 'fr_FR');

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing == null
            ? 'Nouvelle dépense'
            : 'Modifier la dépense'),
      ),
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
                setState(() {
                  _logement = logements.firstWhere((e) => e.id == id);
                });
              },
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _categorie,
              decoration: InputDecoration(
                labelText: 'Catégorie',
                prefixIcon: const Icon(Icons.category_outlined),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.add_circle_outline),
                  tooltip: 'Ajouter une catégorie',
                  onPressed: _addCustomCategory,
                ),
              ),
              items: categories
                  .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                  .toList(),
              validator: (v) => v == null ? 'Sélectionnez une catégorie' : null,
              onChanged: (v) => setState(() => _categorie = v),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _libelleCtrl,
              decoration: const InputDecoration(
                labelText: 'Libellé',
                prefixIcon: Icon(Icons.short_text),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Requis' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _montantCtrl,
              decoration: const InputDecoration(
                labelText: 'Montant (€)',
                prefixIcon: Icon(Icons.payments_outlined),
              ),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Requis';
                final p = double.tryParse(v.replaceAll(',', '.'));
                if (p == null || p < 0) return 'Montant invalide';
                return null;
              },
            ),
            const SizedBox(height: 16),
            _PickerTile(
              icon: Icons.event_outlined,
              label: 'Date',
              value: df.format(_date),
              onTap: _pickDate,
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
            const Text(
              'Justificatifs',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            if (_justifs.isEmpty)
              const Text(
                'Aucun justificatif ajouté.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
            ..._justifs.map(_justifTile),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _addPhotoJustif,
                    icon: const Icon(Icons.photo_camera_outlined),
                    label: const Text('Photo'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _addPdfJustif,
                    icon: const Icon(Icons.picture_as_pdf_outlined),
                    label: const Text('PDF'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            PrimaryButton(
              label: widget.existing == null
                  ? 'Créer la dépense'
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

  Widget _justifTile(String path) {
    final isPdf = path.toLowerCase().endsWith('.pdf');
    final fileName = path.split('/').last;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          Icon(
            isPdf ? Icons.picture_as_pdf_outlined : Icons.image_outlined,
            color: AppColors.primary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              fileName,
              style: const TextStyle(fontSize: 13),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: AppColors.error),
            onPressed: () => setState(() => _justifs.remove(path)),
          ),
        ],
      ),
    );
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
