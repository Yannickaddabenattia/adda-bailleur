import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/templates/edl_templates.dart';
import '../../core/theme/app_theme.dart';
import '../../models/etat_des_lieux.dart';
import '../../models/piece.dart';
import '../../services/etat_des_lieux_service.dart';
import '../../widgets/primary_button.dart';
import 'piece_edit_screen.dart';
import 'signature_screen.dart';

class EtatDesLieuxEditScreen extends StatelessWidget {
  final String edlId;
  const EtatDesLieuxEditScreen({super.key, required this.edlId});

  @override
  Widget build(BuildContext context) {
    final edl = context.watch<EtatDesLieuxService>().byId(edlId);
    if (edl == null) {
      return const Scaffold(body: Center(child: Text('EDL introuvable.')));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(edl.titre),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_home_outlined),
            tooltip: 'Ajouter une pièce',
            onPressed: () => _addPiece(context, edl),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: edl.pieces.isEmpty
                ? _empty(context)
                : ReorderableListView.builder(
                    padding: const EdgeInsets.all(16),
                    buildDefaultDragHandles: false,
                    itemCount: edl.pieces.length,
                    onReorder: (oldIndex, newIndex) async {
                      if (newIndex > oldIndex) newIndex -= 1;
                      final piece = edl.pieces.removeAt(oldIndex);
                      edl.pieces.insert(newIndex, piece);
                      await context.read<EtatDesLieuxService>().save(edl);
                    },
                    itemBuilder: (ctx, i) {
                      final p = edl.pieces[i];
                      return _PieceTile(
                        key: ValueKey(p.id),
                        index: i,
                        piece: p,
                        onTap: () => Navigator.of(ctx).push(
                          MaterialPageRoute(
                            builder: (_) => PieceEditScreen(
                              edlId: edl.id,
                              pieceId: p.id,
                            ),
                          ),
                        ),
                        onDelete: () => _confirmDeletePiece(context, edl, p),
                      );
                    },
                  ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: Border(
                top: BorderSide(color: AppColors.divider),
              ),
            ),
            child: PrimaryButton(
              label: 'Signer et générer le code',
              icon: Icons.edit_note,
              onPressed: edl.pieces.isEmpty
                  ? null
                  : () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => SignatureScreen(edlId: edl.id),
                        ),
                      ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _empty(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.home_outlined,
                size: 64,
                color: AppColors.textSecondary.withValues(alpha: 0.4)),
            const SizedBox(height: 12),
            const Text(
              'Aucune pièce',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
            ),
            const SizedBox(height: 4),
            const Text(
              'Ajoutez des pièces à l\'aide du bouton en haut à droite.',
              style: TextStyle(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addPiece(BuildContext context, EtatDesLieux edl) async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Nom de la pièce',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                ),
              ),
              const Divider(height: 1),
              SizedBox(
                height: 360,
                child: ListView(
                  children: [
                    ...EdlTemplates.suggestedPieceNames.map(
                      (name) => ListTile(
                        title: Text(name),
                        onTap: () => Navigator.of(ctx).pop(name),
                      ),
                    ),
                    ListTile(
                      leading: const Icon(Icons.edit_outlined),
                      title: const Text('Autre (saisir)'),
                      onTap: () async {
                        final custom = await _askCustomName(ctx);
                        if (!ctx.mounted) return;
                        Navigator.of(ctx).pop(custom);
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
    if (selected == null || selected.trim().isEmpty) return;
    edl.pieces.add(Piece.create(nom: selected));
    if (!context.mounted) return;
    await context.read<EtatDesLieuxService>().save(edl);
  }

  Future<String?> _askCustomName(BuildContext context) async {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nom personnalisé'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Ex: Véranda'),
          textCapitalization: TextCapitalization.sentences,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()),
            child: const Text('Ajouter'),
          ),
        ],
      ),
    );
  }

  void _confirmDeletePiece(
      BuildContext context, EtatDesLieux edl, Piece piece) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Supprimer « ${piece.nom} » ?'),
        content: const Text(
          'La pièce et tous ses éléments seront supprimés de cet état des lieux.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Annuler'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            onPressed: () async {
              edl.pieces.removeWhere((p) => p.id == piece.id);
              await context.read<EtatDesLieuxService>().save(edl);
              if (!ctx.mounted) return;
              Navigator.of(ctx).pop();
            },
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
  }
}

class _PieceTile extends StatelessWidget {
  final int index;
  final Piece piece;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  const _PieceTile({
    super.key,
    required this.index,
    required this.piece,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: ValueKey(piece.id),
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.divider),
        ),
        child: Row(
          children: [
            ReorderableDragStartListener(
              index: index,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 16),
                child: Icon(Icons.drag_handle,
                    color: AppColors.textSecondary),
              ),
            ),
            Expanded(
              child: InkWell(
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        piece.nom,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${piece.elements.length} élément(s)',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline,
                  color: AppColors.textSecondary),
              onPressed: onDelete,
            ),
            const Padding(
              padding: EdgeInsets.only(right: 12),
              child: Icon(Icons.chevron_right, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
