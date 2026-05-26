import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../models/diagnostic.dart';
import '../../models/logement.dart';
import '../../services/diagnostic_service.dart';
import '../../widgets/primary_button.dart';

/// Liste des diagnostics d'un logement. Permet d'en ajouter, éditer,
/// supprimer ou ouvrir le PDF rattaché.
class DiagnosticListScreen extends StatelessWidget {
  final Logement logement;
  const DiagnosticListScreen({super.key, required this.logement});

  @override
  Widget build(BuildContext context) {
    final svc = context.watch<DiagnosticService>();
    final items = svc.forLogement(logement.id);
    final df = DateFormat('dd MMM yyyy', 'fr_FR');
    return Scaffold(
      appBar: AppBar(title: const Text('Diagnostics')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(context, null),
        icon: const Icon(Icons.add),
        label: const Text('Nouveau diagnostic'),
      ),
      body: items.isEmpty
          ? const _Empty()
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 96),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (ctx, i) {
                final d = items[i];
                return _DiagnosticCard(
                  diagnostic: d,
                  dateFmt: df,
                  onTap: () => _openForm(context, d),
                  onOpenFile: d.filePath == null
                      ? null
                      : () => _openFile(context, d.filePath!),
                );
              },
            ),
    );
  }

  void _openForm(BuildContext context, Diagnostic? existing) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DiagnosticFormScreen(
          logement: logement,
          existing: existing,
        ),
      ),
    );
  }

  Future<void> _openFile(BuildContext context, String path) async {
    final file = File(path);
    if (!file.existsSync()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Fichier introuvable.')),
      );
      return;
    }
    final bytes = await file.readAsBytes();
    await Printing.layoutPdf(onLayout: (_) async => bytes);
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.fact_check_outlined,
                size: 64, color: AppColors.textSecondary),
            SizedBox(height: 16),
            Text('Aucun diagnostic',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            SizedBox(height: 8),
            Text(
              'Ajoute les diagnostics obligatoires (DPE, ERP, plomb, '
              'électrique, gaz…) avec leur PDF. Ils seront automatiquement '
              'listés en annexe des contrats de bail.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _DiagnosticCard extends StatelessWidget {
  final Diagnostic diagnostic;
  final DateFormat dateFmt;
  final VoidCallback onTap;
  final VoidCallback? onOpenFile;
  const _DiagnosticCard({
    required this.diagnostic,
    required this.dateFmt,
    required this.onTap,
    required this.onOpenFile,
  });

  @override
  Widget build(BuildContext context) {
    final exp = diagnostic.estExpire;
    final dateExp = diagnostic.dateExpiration;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: context.surfaceColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: exp
                ? AppColors.error.withValues(alpha: 0.4)
                : context.dividerColor,
            width: exp ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: (exp ? AppColors.error : AppColors.primary)
                    .withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                exp ? Icons.warning_amber_outlined : Icons.description_outlined,
                color: exp ? AppColors.error : AppColors.primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    diagnostic.type.label,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Réalisé le ${dateFmt.format(diagnostic.dateRealisation)}'
                    '${dateExp != null ? " · valide jusqu'au ${dateFmt.format(dateExp)}" : ""}',
                    style: TextStyle(
                      fontSize: 11,
                      color: exp ? AppColors.error : AppColors.textSecondary,
                      fontWeight:
                          exp ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                  if (diagnostic.resume.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      diagnostic.resume,
                      style: const TextStyle(fontSize: 12),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            if (onOpenFile != null)
              IconButton(
                icon: const Icon(Icons.open_in_new),
                onPressed: onOpenFile,
                tooltip: 'Ouvrir le PDF',
              ),
          ],
        ),
      ),
    );
  }
}

class DiagnosticFormScreen extends StatefulWidget {
  final Logement logement;
  final Diagnostic? existing;
  const DiagnosticFormScreen({
    super.key,
    required this.logement,
    this.existing,
  });

  @override
  State<DiagnosticFormScreen> createState() => _DiagnosticFormScreenState();
}

class _DiagnosticFormScreenState extends State<DiagnosticFormScreen> {
  late DiagnosticType _type;
  late DateTime _date;
  late TextEditingController _resume;
  String? _filePath;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _type = e?.type ?? DiagnosticType.dpe;
    _date = e?.dateRealisation ?? DateTime.now();
    _resume = TextEditingController(text: e?.resume ?? '');
    _filePath = e?.filePath;
  }

  @override
  void dispose() {
    _resume.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(DateTime.now().year - 20),
      lastDate: DateTime(DateTime.now().year + 1),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickFile() async {
    final r = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (r == null || r.files.single.path == null) return;
    // Copie le PDF dans le sandbox de l'app pour ne pas dépendre du chemin
    // d'origine (qui peut être un dossier temporaire système).
    final src = File(r.files.single.path!);
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/diagnostics/${widget.logement.id}');
    if (!await dir.exists()) await dir.create(recursive: true);
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final dest = File('${dir.path}/${_type.name}_$stamp.pdf');
    await src.copy(dest.path);
    setState(() => _filePath = dest.path);
  }

  Future<void> _save() async {
    final svc = context.read<DiagnosticService>();
    final existing = widget.existing;
    final d = existing ??
        Diagnostic.create(
          logementId: widget.logement.id,
          type: _type,
          dateRealisation: _date,
        );
    d.type = _type;
    d.dateRealisation = _date;
    d.resume = _resume.text.trim();
    d.filePath = _filePath;
    await svc.save(d);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final e = widget.existing;
    if (e == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer ce diagnostic ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Annuler'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await context.read<DiagnosticService>().delete(e.id);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('dd MMMM yyyy', 'fr_FR');
    final dateExp = _type.dureeValiditeAns > 0
        ? DateTime(
            _date.year + _type.dureeValiditeAns,
            _date.month,
            _date.day,
          )
        : null;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing == null
            ? 'Nouveau diagnostic'
            : 'Modifier le diagnostic'),
        actions: [
          if (widget.existing != null)
            IconButton(
              icon: const Icon(Icons.delete_outline, color: AppColors.error),
              onPressed: _delete,
              tooltip: 'Supprimer',
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          DropdownButtonFormField<DiagnosticType>(
            initialValue: _type,
            decoration: const InputDecoration(
              labelText: 'Type de diagnostic',
              prefixIcon: Icon(Icons.assignment_outlined),
            ),
            items: DiagnosticType.values
                .map((t) => DropdownMenuItem(
                      value: t,
                      child: Text(t.label),
                    ))
                .toList(),
            onChanged: (v) => setState(() => _type = v ?? _type),
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              _type.description,
              style: const TextStyle(
                  fontSize: 12, color: AppColors.textSecondary),
            ),
          ),
          const SizedBox(height: 16),
          InkWell(
            onTap: _pickDate,
            borderRadius: BorderRadius.circular(12),
            child: InputDecorator(
              decoration: InputDecoration(
                labelText: 'Date de réalisation',
                helperText: dateExp != null
                    ? 'Validité ${_type.dureeValiditeAns} ans · expire le ${dateFmt.format(dateExp)}'
                    : 'Pas de durée de validité légale stricte',
                helperMaxLines: 2,
                prefixIcon: const Icon(Icons.event_outlined),
              ),
              child: Text(dateFmt.format(_date)),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _resume,
            decoration: const InputDecoration(
              labelText: 'Résumé / résultat',
              helperText:
                  'Ex : Classe D/E pour le DPE, Conforme, Plomb absent…',
              prefixIcon: Icon(Icons.summarize_outlined),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: context.surfaceColor,
              border: Border.all(color: AppColors.divider),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Icon(Icons.picture_as_pdf_outlined,
                    color: AppColors.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _filePath == null
                        ? 'Aucun PDF rattaché'
                        : _filePath!.split('/').last,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                TextButton.icon(
                  onPressed: _pickFile,
                  icon: const Icon(Icons.upload_file_outlined),
                  label: Text(_filePath == null ? 'Importer' : 'Remplacer'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          PrimaryButton(
            label: 'Enregistrer',
            icon: Icons.check_circle_outline,
            onPressed: _save,
          ),
        ],
      ),
    );
  }
}
