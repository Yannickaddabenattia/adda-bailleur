import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../models/diagnostic.dart';
import '../../services/diagnostic_service.dart';
import '../../services/logement_service.dart';
import 'diagnostic_list_screen.dart';

/// Vue agrégée de tous les diagnostics, tous logements confondus. Met en
/// avant les diagnostics expirés et permet d'ouvrir directement le PDF ou
/// la fiche d'édition.
class MesDiagnosticsScreen extends StatelessWidget {
  const MesDiagnosticsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final svc = context.watch<DiagnosticService>();
    final logementSvc = context.watch<LogementService>();
    final items = svc.all;
    final df = DateFormat('dd MMM yyyy', 'fr_FR');

    final expires = items.where((d) => d.estExpire).toList();
    final aJour = items.where((d) => !d.estExpire).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Mes diagnostics')),
      body: items.isEmpty
          ? const _Empty()
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              children: [
                if (expires.isNotEmpty) ...[
                  _Header(
                    label: 'À renouveler',
                    color: AppColors.error,
                    count: expires.length,
                  ),
                  const SizedBox(height: 8),
                  for (final d in expires) ...[
                    _Tile(
                      d: d,
                      logementLabel:
                          logementSvc.byId(d.logementId)?.libelle ??
                              'Logement supprimé',
                      dateFmt: df,
                      onTap: () => _openEdit(
                          context, d.logementId, d.id, logementSvc),
                      onOpenFile: d.filePath == null
                          ? null
                          : () => _openFile(context, d.filePath!),
                    ),
                    const SizedBox(height: 8),
                  ],
                  const SizedBox(height: 16),
                ],
                if (aJour.isNotEmpty) ...[
                  _Header(
                    label: 'À jour',
                    color: AppColors.success,
                    count: aJour.length,
                  ),
                  const SizedBox(height: 8),
                  for (final d in aJour) ...[
                    _Tile(
                      d: d,
                      logementLabel:
                          logementSvc.byId(d.logementId)?.libelle ??
                              'Logement supprimé',
                      dateFmt: df,
                      onTap: () => _openEdit(
                          context, d.logementId, d.id, logementSvc),
                      onOpenFile: d.filePath == null
                          ? null
                          : () => _openFile(context, d.filePath!),
                    ),
                    const SizedBox(height: 8),
                  ],
                ],
              ],
            ),
    );
  }

  void _openEdit(BuildContext context, String logementId, String diagId,
      LogementService logementSvc) {
    final logement = logementSvc.byId(logementId);
    final diag = context.read<DiagnosticService>().byId(diagId);
    if (logement == null || diag == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DiagnosticFormScreen(
          logement: logement,
          existing: diag,
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

class _Header extends StatelessWidget {
  final String label;
  final Color color;
  final int count;

  const _Header({
    required this.label,
    required this.color,
    required this.count,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: color,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '($count)',
          style: TextStyle(
            fontSize: 13,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  final Diagnostic d;
  final String logementLabel;
  final DateFormat dateFmt;
  final VoidCallback onTap;
  final VoidCallback? onOpenFile;

  const _Tile({
    required this.d,
    required this.logementLabel,
    required this.dateFmt,
    required this.onTap,
    required this.onOpenFile,
  });

  @override
  Widget build(BuildContext context) {
    final exp = d.estExpire;
    final dateExp = d.dateExpiration;
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
                exp
                    ? Icons.warning_amber_outlined
                    : Icons.description_outlined,
                color: exp ? AppColors.error : AppColors.primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    d.type.label,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    logementLabel,
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Réalisé le ${dateFmt.format(d.dateRealisation)}'
                    '${dateExp != null ? " · ${exp ? 'expiré le' : "valide jusqu'au"} ${dateFmt.format(dateExp)}" : ""}',
                    style: TextStyle(
                      fontSize: 11,
                      color: exp ? AppColors.error : AppColors.textSecondary,
                      fontWeight: exp ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
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
              'Ouvre la fiche d\'un logement pour y ajouter ses diagnostics '
              '(DPE, ERP, plomb, électrique, gaz…). Ils seront listés en '
              'annexe des baux.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
