import 'dart:async';
import 'dart:io' show File, Platform, Process;
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/email_sender.dart';
import '../../core/storage/contrat_storage.dart';
import '../../models/locataire.dart';
import '../../models/logement.dart';
import '../../services/dossier_locataire_service.dart';
import '../../services/locataire_service.dart';
import '../../services/logement_service.dart';
import '../../services/quittance_service.dart';
import '../logements/logement_detail_screen.dart';
import '../quittances/quittance_form_screen.dart';
import 'locataire_form_screen.dart';

class LocataireDetailScreen extends StatelessWidget {
  final String locataireId;
  const LocataireDetailScreen({super.key, required this.locataireId});

  static const _bg = Color(0xFFEFF1F7);
  static const _ink = Color(0xFF1F1F2E);
  static const _muted = Color(0xFF8A8AA0);
  static const _hairline = Color(0xFFE3E5EE);
  static const _surface = Colors.white;

  static const _purple = Color(0xFF7C3AED);
  static const _greenDark = Color(0xFF059669);
  static const _orange = Color(0xFFC66E1A);
  static const _red = Color(0xFFEF4444);

  static const _heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFFFF8E63),
      Color(0xFFE65A8A),
      Color(0xFF9C44C7),
      Color(0xFF6D5CD6),
    ],
    stops: [0, 0.32, 0.7, 1],
  );

  static const _headerGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF6D5CD6),
      Color(0xFF9C44C7),
      Color(0xFFE65A8A),
      Color(0xFFFF8E63),
    ],
    stops: [0, 0.45, 0.78, 1],
  );

  @override
  Widget build(BuildContext context) {
    final locataire = context.watch<LocataireService>().byId(locataireId);
    if (locataire == null) {
      return const Scaffold(
        backgroundColor: _bg,
        body: Center(child: Text('Locataire introuvable.')),
      );
    }
    final logementService = context.watch<LogementService>();
    final logements = locataire.logementIds
        .map(logementService.byId)
        .whereType<Logement>()
        .toList();

    final quittanceService = context.watch<QuittanceService>();
    final quittances = quittanceService.forLocataire(locataireId);

    final now = DateTime.now();
    final loyerEncaisse = logements.any((l) => quittanceService
        .forLogement(l.id)
        .any((q) => q.periodYear == now.year && q.periodMonth == now.month));

    final money = NumberFormat.currency(
        locale: 'fr_FR', symbol: '€', decimalDigits: 0);

    final loyerMensuel = logements.isNotEmpty ? logements.first.loyerTTC : 0.0;
    final caution = loyerMensuel * 2;
    final totalPercu =
        quittances.fold<double>(0, (sum, q) => sum + q.loyerHC + q.charges);

    final dureeLabel = _dureeBail(locataire);
    final depuisLabel = locataire.dateEntree == null
        ? null
        : DateFormat('MM/yyyy', 'fr_FR').format(locataire.dateEntree!);

    return Scaffold(
      backgroundColor: _bg,
      body: CustomScrollView(
        slivers: [
          _GradientHeader(
            title: locataire.fullName,
            subtitle: 'FICHE LOCATAIRE · ADDA',
            onEdit: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => LocataireFormScreen(locataire: locataire),
              ),
            ),
            onDelete: () => _confirmDelete(context, locataire),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Transform.translate(
                offset: const Offset(0, -8),
                child: _HeroCard(
                  locataire: locataire,
                  loyerEncaisse: loyerEncaisse,
                  depuisLabel: depuisLabel,
                  dureeLabel: dureeLabel,
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => _envoyerDossier(context, locataire),
                  icon: const Icon(Icons.send_outlined),
                  label: const Text('Envoyer le dossier au locataire'),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: _SectionHeaderRow(
                color: _purple,
                title: 'INDICATEURS',
                count: 4,
                trailing: 'Aperçu locatif',
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: _StatsGrid(
                loyerMensuel: loyerMensuel,
                dureeLabel: dureeLabel,
                caution: caution,
                totalPercu: totalPercu,
                quittancesCount: quittances.length,
                money: money,
              ),
            ),
          ),
          if (locataire.isArchived &&
              (locataire.nouvelleAdresse != null ||
                  locataire.nouveauTelephone != null ||
                  locataire.nouvelEmail != null))
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: _NouvellesCoordonneesCard(locataire: locataire),
              ),
            ),
          if (locataire.isArchived)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: _AjouterAncienColocataireButton(
                  logementIds: locataire.logementIds,
                ),
              ),
            ),
          if (logements.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: _AjouterLoyerPercuButton(
                  locataireId: locataireId,
                  logementId: logements.first.id,
                ),
              ),
            ),
          if (locataire.notes.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: _NotesCard(notes: locataire.notes),
              ),
            ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: _SectionHeaderRow(
                color: const Color(0xFFE65A8A),
                title: 'LOGEMENT LOUÉ',
                count: logements.length,
                trailing: logements.length <= 1
                    ? 'Bail solidaire · ${logements.length} occupant'
                    : '${logements.length} logements',
              ),
            ),
          ),
          if (logements.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: _EmptyLogementCard(),
              ),
            )
          else
            SliverList.builder(
              itemCount: logements.length,
              itemBuilder: (ctx, i) => Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: _LogementCard(
                  logement: logements[i],
                  gradientIndex: i,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => LogementDetailScreen(
                        logementId: logements[i].id,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: _SectionHeaderRow(
                color: _greenDark,
                title: 'GESTION LOCATIVE',
                count: logements.fold<int>(
                  0,
                  (sum, l) => sum + l.contratBailPaths.length,
                ),
                trailing: logements.length <= 1
                    ? 'Documents du bail'
                    : 'Bail partagé · ${logements.length} logements',
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: _ContratBailCard(
                locataireName: locataire.fullName,
                logements: logements,
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 24 + MediaQuery.of(context).viewPadding.bottom,
            ),
          ),
        ],
      ),
    );
  }

  static String _dureeBail(Locataire l) {
    if (l.dateEntree == null) return '—';
    final now = DateTime.now();
    final months =
        (now.year - l.dateEntree!.year) * 12 + now.month - l.dateEntree!.month;
    if (months <= 0) return 'Ce mois-ci';
    final years = months ~/ 12;
    final restMonths = months % 12;
    final parts = <String>[];
    if (years > 0) parts.add('$years an${years > 1 ? 's' : ''}');
    if (restMonths > 0) parts.add('$restMonths mois');
    return parts.isEmpty ? 'Ce mois-ci' : parts.join(' ');
  }

  /// Demande le format + la qualité photos avant de générer le dossier.
  Future<({DossierFormat format, DossierQualite qualite})?> _askDossierOptions(
      BuildContext context) {
    DossierFormat fmt = DossierFormat.pdfFusionne;
    DossierQualite q = DossierQualite.leger;
    return showDialog<({DossierFormat format, DossierQualite qualite})>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Envoyer le dossier'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Format',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              SegmentedButton<DossierFormat>(
                segments: const [
                  ButtonSegment(
                      value: DossierFormat.pdfFusionne,
                      label: Text('PDF fusionné')),
                  ButtonSegment(
                      value: DossierFormat.zip, label: Text('ZIP')),
                ],
                selected: {fmt},
                onSelectionChanged: (s) => setLocal(() => fmt = s.first),
              ),
              const SizedBox(height: 14),
              const Text('Qualité photos',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              SegmentedButton<DossierQualite>(
                segments: const [
                  ButtonSegment(
                      value: DossierQualite.leger,
                      label: Text('Léger (e-mail)')),
                  ButtonSegment(
                      value: DossierQualite.max, label: Text('Max')),
                ],
                selected: {q},
                onSelectionChanged: (s) => setLocal(() => q = s.first),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Annuler')),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(ctx, (format: fmt, qualite: q)),
              child: const Text('Générer'),
            ),
          ],
        ),
      ),
    );
  }

  /// Génère le dossier (quittances + bail + EDL) et ouvre la feuille de
  /// partage. Universel : PDF ou ZIP standard, ouvrable sans ADDA Locataire.
  Future<void> _envoyerDossier(
      BuildContext context, Locataire locataire) async {
    final opts = await _askDossierOptions(context);
    if (opts == null) return;
    if (!context.mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    DossierExport export;
    try {
      export = await DossierLocataireService.build(
        locataire,
        format: opts.format,
        qualite: opts.qualite,
      );
    } catch (e) {
      if (context.mounted) Navigator.of(context).pop();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur lors de la génération : $e')),
        );
      }
      return;
    }
    if (context.mounted) Navigator.of(context).pop();
    if (!context.mounted) return;
    if (export.docCount == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Aucun document à envoyer pour ce locataire.')),
      );
      return;
    }
    if (export.sizeBytes > DossierLocataireService.seuilEmailOctets) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Fichier volumineux'),
          content: Text(
            'Le dossier fait ${export.sizeMo.toStringAsFixed(1)} Mo — '
            'probablement trop gros pour un e-mail.\n\n'
            'Conseil : relance en qualité « Léger », ou partage-le via un '
            'lien cloud (pCloud) depuis la fenêtre de partage.',
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Annuler')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Partager quand même')),
          ],
        ),
      );
      if (proceed != true) return;
    }
    if (!context.mounted) return;
    // Écrit dans un fichier temporaire puis ouvre la feuille de partage avec
    // l'objet et le corps d'e-mail pré-remplis (noms + liste des documents).
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/${export.filename}';
    await File(path).writeAsBytes(export.bytes, flush: true);
    await EmailSender.sendWithAttachment(
      path: path,
      subject: export.emailSubject,
      body: export.emailBody,
      recipients: export.recipientEmails,
      mimeType: export.isPdf ? 'application/pdf' : 'application/zip',
    );
  }

  void _confirmDelete(BuildContext context, Locataire locataire) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer ce locataire ?'),
        content: Text(
          '${locataire.fullName} sera supprimé définitivement. '
          'Les logements associés ne seront PAS supprimés.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () async {
              await context.read<LocataireService>().delete(locataire.id);
              if (!ctx.mounted) return;
              Navigator.of(ctx).pop();
              Navigator.of(context).pop();
            },
            style: TextButton.styleFrom(foregroundColor: _red),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
//  HEADER
// ────────────────────────────────────────────────────────────────────────────

class _GradientHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  const _GradientHeader({
    required this.title,
    required this.subtitle,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return SliverToBoxAdapter(
      child: Container(
        decoration:
            const BoxDecoration(gradient: LocataireDetailScreen._headerGradient),
        padding: EdgeInsets.fromLTRB(12, top + 8, 12, 24),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _GlassIcon(
              icon: Icons.arrow_back,
              onTap: () => Navigator.of(context).maybePop(),
            ),
            Expanded(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Column(
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            _GlassIcon(icon: Icons.edit_outlined, onTap: onEdit),
            const SizedBox(width: 8),
            _GlassIcon(icon: Icons.delete_outline, onTap: onDelete),
          ],
        ),
      ),
    );
  }
}

class _GlassIcon extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _GlassIcon({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
        ),
        child: Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
//  HERO CARD
// ────────────────────────────────────────────────────────────────────────────

class _HeroCard extends StatelessWidget {
  final Locataire locataire;
  final bool loyerEncaisse;
  final String? depuisLabel;
  final String dureeLabel;

  const _HeroCard({
    required this.locataire,
    required this.loyerEncaisse,
    required this.depuisLabel,
    required this.dureeLabel,
  });

  @override
  Widget build(BuildContext context) {
    final letter =
        locataire.firstName.isNotEmpty ? locataire.firstName[0] : '?';
    final hasPhone = locataire.phone != null && locataire.phone!.isNotEmpty;
    return Container(
      decoration: BoxDecoration(
        gradient: LocataireDetailScreen._heroGradient,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFE65A8A).withValues(alpha: 0.25),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(child: _BigSquareAvatar(letter: letter)),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              _HeroPill(
                dot: true,
                dotColor: loyerEncaisse
                    ? const Color(0xFF34D399)
                    : Colors.white.withValues(alpha: 0.6),
                label: loyerEncaisse ? 'LOYER ENCAISSÉ' : 'LOYER EN ATTENTE',
              ),
              if (depuisLabel != null)
                _HeroPill(
                  icon: Icons.calendar_today_outlined,
                  label:
                      'DEPUIS $depuisLabel · ${dureeLabel.toUpperCase()}',
                ),
              _HeroPill(
                icon: Icons.check_rounded,
                label: 'DOSSIER COMPLET',
              ),
            ],
          ),
          const SizedBox(height: 14),
          Center(
            child: _BigSerifName(
              firstName: locataire.firstName,
              lastName: locataire.lastName,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.mail_outline, color: Colors.white, size: 16),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  locataire.email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.95),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          if (hasPhone) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.phone_outlined,
                    color: Colors.white, size: 16),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    locataire.phone!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.95),
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 14),
          Container(
            height: 1,
            color: Colors.white.withValues(alpha: 0.25),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _GlassActionButton(
                  icon: Icons.mail_outline,
                  label: 'Envoyer un email',
                  onTap: () => _sendEmail(context, locataire.email),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _GlassActionButton(
                  icon: Icons.phone_outlined,
                  label: 'Appeler',
                  onTap: hasPhone
                      ? () => _callPhone(context, locataire.phone!)
                      : () => _copyEmail(context, locataire.email),
                  disabled: !hasPhone,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static Future<void> _sendEmail(BuildContext context, String email) async {
    final messenger = ScaffoldMessenger.of(context);
    final trimmed = email.trim();
    final mailtoStr = 'mailto:$trimmed';

    bool launched = false;
    try {
      launched = await launchUrl(
        Uri.parse(mailtoStr),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {}

    if (!launched && Platform.isMacOS) {
      try {
        final result = await Process.run('/usr/bin/open', [mailtoStr]);
        launched = result.exitCode == 0;
      } catch (_) {}
    }

    if (!launched) {
      await Clipboard.setData(ClipboardData(text: trimmed));
      messenger.showSnackBar(
        const SnackBar(content: Text('Email copié dans le presse-papiers')),
      );
    }
  }

  static Future<void> _callPhone(BuildContext context, String phone) async {
    final uri = Uri(scheme: 'tel', path: phone.replaceAll(' ', ''));
    final messenger = ScaffoldMessenger.of(context);
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok) throw Exception('launchUrl returned false');
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: phone));
      messenger.showSnackBar(
        const SnackBar(content: Text('Numéro copié dans le presse-papiers')),
      );
    }
  }

  static Future<void> _copyEmail(BuildContext context, String email) async {
    await Clipboard.setData(ClipboardData(text: email));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Aucun téléphone — email copié')),
      );
    }
  }
}

class _BigSquareAvatar extends StatelessWidget {
  final String letter;
  const _BigSquareAvatar({required this.letter});

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 88,
          height: 88,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFFFFC59E),
                Color(0xFFE07AB5),
                Color(0xFF9C7CFF),
              ],
            ),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.4),
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: Text(
            letter.toUpperCase(),
            style: const TextStyle(
              fontFamily: 'serif',
              color: Colors.white,
              fontSize: 44,
              fontWeight: FontWeight.w700,
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
        Positioned(
          right: -2,
          bottom: -2,
          child: Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: const Color(0xFF34D399),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
            ),
          ),
        ),
      ],
    );
  }
}

class _HeroPill extends StatelessWidget {
  final IconData? icon;
  final bool dot;
  final Color? dotColor;
  final String label;
  const _HeroPill({
    this.icon,
    this.dot = false,
    this.dotColor,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot)
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: dotColor ?? const Color(0xFF34D399),
                shape: BoxShape.circle,
              ),
            )
          else if (icon != null)
            Icon(icon, color: Colors.white, size: 14),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
        ],
      ),
    );
  }
}

class _BigSerifName extends StatelessWidget {
  final String firstName;
  final String lastName;
  const _BigSerifName({required this.firstName, required this.lastName});

  @override
  Widget build(BuildContext context) {
    return RichText(
      textAlign: TextAlign.center,
      text: TextSpan(
        style: const TextStyle(
          fontFamily: 'serif',
          color: Colors.white,
          fontSize: 30,
          fontWeight: FontWeight.w700,
          height: 1.1,
        ),
        children: [
          TextSpan(
            text: firstName,
            style: const TextStyle(fontStyle: FontStyle.italic),
          ),
          const TextSpan(text: ' '),
          TextSpan(text: lastName.toUpperCase()),
        ],
      ),
    );
  }
}

class _GlassActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool disabled;
  const _GlassActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.disabled = false,
  });

  @override
  Widget build(BuildContext context) {
    final opacity = disabled ? 0.5 : 1.0;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Opacity(
          opacity: opacity,
          child: Container(
            height: 46,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
            ),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: Colors.white, size: 16),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
//  SECTION HEADER
// ────────────────────────────────────────────────────────────────────────────

class _SectionHeaderRow extends StatelessWidget {
  final Color color;
  final String title;
  final int count;
  final String? trailing;
  const _SectionHeaderRow({
    required this.color,
    required this.title,
    required this.count,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 6,
          height: 16,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: const TextStyle(
            color: LocataireDetailScreen._ink,
            fontSize: 13,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: LocataireDetailScreen._hairline),
          ),
          child: Text(
            count.toString(),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: LocataireDetailScreen._muted,
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
        const Spacer(),
        if (trailing != null)
          Flexible(
            child: Text(
              trailing!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
              style: const TextStyle(
                color: LocataireDetailScreen._muted,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
      ],
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
//  STATS GRID
// ────────────────────────────────────────────────────────────────────────────

class _StatsGrid extends StatelessWidget {
  final double loyerMensuel;
  final String dureeLabel;
  final double caution;
  final double totalPercu;
  final int quittancesCount;
  final NumberFormat money;

  const _StatsGrid({
    required this.loyerMensuel,
    required this.dureeLabel,
    required this.caution,
    required this.totalPercu,
    required this.quittancesCount,
    required this.money,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _StatCard(
                icon: Icons.attach_money,
                iconBg: const Color(0xFFD7F1E2),
                iconFg: LocataireDetailScreen._greenDark,
                value: money.format(loyerMensuel),
                label: 'LOYER MENSUEL',
                valueColor: LocataireDetailScreen._greenDark,
                chip: '+0€ · Stable',
                chipColor: LocataireDetailScreen._greenDark,
                chipBg: const Color(0xFFD7F1E2),
                pattern: _StatPattern.coins,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _StatCard(
                icon: Icons.calendar_today_outlined,
                iconBg: const Color(0xFFEDE6FF),
                iconFg: LocataireDetailScreen._purple,
                value: dureeLabel,
                label: 'DURÉE DU BAIL',
                valueColor: LocataireDetailScreen._purple,
                chip: 'Sans incident',
                chipColor: LocataireDetailScreen._purple,
                chipBg: const Color(0xFFEDE6FF),
                small: true,
                pattern: _StatPattern.dotsGrid,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _StatCard(
                icon: Icons.emoji_events_outlined,
                iconBg: const Color(0xFFFCE3C7),
                iconFg: LocataireDetailScreen._orange,
                value: money.format(caution),
                label: 'CAUTION DÉPOSÉE',
                valueColor: LocataireDetailScreen._orange,
                chip: '2 mois · à restituer',
                chipColor: LocataireDetailScreen._orange,
                chipBg: const Color(0xFFFCE3C7),
                pattern: _StatPattern.rays,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _StatCard(
                icon: Icons.account_balance_wallet_outlined,
                iconBg: const Color(0xFFFCE3C7),
                iconFg: LocataireDetailScreen._orange,
                value: money.format(totalPercu),
                label: 'TOTAL PERÇU',
                valueColor: LocataireDetailScreen._orange,
                chip:
                    '$quittancesCount mensualité${quittancesCount > 1 ? 's' : ''}',
                chipColor: LocataireDetailScreen._orange,
                chipBg: const Color(0xFFFCE3C7),
                pattern: _StatPattern.waves,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

enum _StatPattern { coins, dotsGrid, rays, waves }

class _StatCard extends StatefulWidget {
  final IconData icon;
  final Color iconBg;
  final Color iconFg;
  final String value;
  final String label;
  final Color valueColor;
  final String chip;
  final Color chipColor;
  final Color chipBg;
  final bool small;
  final _StatPattern pattern;

  const _StatCard({
    required this.icon,
    required this.iconBg,
    required this.iconFg,
    required this.value,
    required this.label,
    required this.valueColor,
    required this.chip,
    required this.chipColor,
    required this.chipBg,
    required this.pattern,
    this.small = false,
  });

  @override
  State<_StatCard> createState() => _StatCardState();
}

class _StatCardState extends State<_StatCard> {
  bool _hover = false;
  bool _pressed = false;
  bool _afterglow = false;
  Timer? _afterglowTimer;

  @override
  void dispose() {
    _afterglowTimer?.cancel();
    super.dispose();
  }

  void _triggerAfterglow() {
    _afterglowTimer?.cancel();
    setState(() => _afterglow = true);
    _afterglowTimer = Timer(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _afterglow = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final lifted = _hover || _pressed || _afterglow;
    final dy = _pressed
        ? 0.0
        : (_hover || _afterglow ? -6.0 : 0.0);
    final scale = _pressed ? 0.96 : 1.0;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) {
          setState(() => _pressed = false);
          _triggerAfterglow();
        },
        onTapCancel: () => setState(() => _pressed = false),
        onTap: () {},
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          transform: Matrix4.identity()
            ..translateByDouble(0.0, dy, 0.0, 1.0)
            ..scaleByDouble(scale, scale, 1.0, 1.0),
          transformAlignment: Alignment.center,
          decoration: BoxDecoration(
            color: LocataireDetailScreen._surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: lifted
                  ? widget.iconFg.withValues(alpha: 0.35)
                  : LocataireDetailScreen._hairline,
            ),
            boxShadow: lifted
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 26,
                      offset: const Offset(0, 12),
                    ),
                    BoxShadow(
                      color: widget.iconFg.withValues(alpha: 0.32),
                      blurRadius: 30,
                      offset: const Offset(0, 10),
                    ),
                  ]
                : const [],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Stack(
              children: [
                Positioned(
                  right: -50,
                  bottom: -50,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 280),
                    curve: Curves.easeOut,
                    width: lifted ? 160 : 70,
                    height: lifted ? 160 : 70,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          widget.iconFg.withValues(
                              alpha: lifted ? 0.32 : 0.0),
                          widget.iconFg.withValues(alpha: 0.0),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: CustomPaint(
                    painter: _StatPatternPainter(
                      pattern: widget.pattern,
                      color: widget.iconFg,
                      intensified: lifted,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: widget.iconBg,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(widget.icon,
                            color: widget.iconFg, size: 18),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        widget.value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'serif',
                          color: widget.valueColor,
                          fontSize: widget.small ? 18 : 22,
                          fontWeight: FontWeight.w700,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.label,
                        style: const TextStyle(
                          color: LocataireDetailScreen._muted,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: widget.chipBg,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          widget.chip,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: widget.chipColor,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatPatternPainter extends CustomPainter {
  final _StatPattern pattern;
  final Color color;
  final bool intensified;

  _StatPatternPainter({
    required this.pattern,
    required this.color,
    required this.intensified,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final base = intensified ? 0.13 : 0.07;
    final faint = color.withValues(alpha: base);
    switch (pattern) {
      case _StatPattern.coins:
        _paintCoins(canvas, size, faint);
        break;
      case _StatPattern.dotsGrid:
        _paintDotsGrid(canvas, size, faint);
        break;
      case _StatPattern.rays:
        _paintRays(canvas, size, faint);
        break;
      case _StatPattern.waves:
        _paintWaves(canvas, size, faint);
        break;
    }
  }

  void _paintCoins(Canvas canvas, Size size, Color c) {
    final stroke = Paint()
      ..color = c
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final cx = size.width - 18;
    final cy = 22.0;
    for (var i = 0; i < 4; i++) {
      canvas.drawCircle(Offset(cx - i * 6, cy + i * 5), 18 + i * 2.0, stroke);
    }
  }

  void _paintDotsGrid(Canvas canvas, Size size, Color c) {
    final dot = Paint()..color = c;
    const spacing = 10.0;
    const r = 1.4;
    for (double y = 6; y < size.height - 4; y += spacing) {
      for (double x = size.width / 2; x < size.width - 4; x += spacing) {
        canvas.drawCircle(Offset(x, y), r, dot);
      }
    }
  }

  void _paintRays(Canvas canvas, Size size, Color c) {
    final stroke = Paint()
      ..color = c
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    final origin = Offset(size.width - 6, 6);
    for (var i = 0; i < 7; i++) {
      final angle = 1.4 + i * 0.18;
      final dx = origin.dx - 60 * math.cos(angle);
      final dy = origin.dy + 60 * math.sin(angle);
      canvas.drawLine(origin, Offset(dx, dy), stroke);
    }
  }

  void _paintWaves(Canvas canvas, Size size, Color c) {
    final stroke = Paint()
      ..color = c
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    for (var row = 0; row < 4; row++) {
      final y = 14.0 + row * 12.0;
      final path = Path()..moveTo(size.width / 2, y);
      for (double x = size.width / 2; x < size.width - 2; x += 8) {
        path.relativeQuadraticBezierTo(4, -4, 8, 0);
        path.relativeQuadraticBezierTo(4, 4, 8, 0);
      }
      canvas.drawPath(path, stroke);
    }
  }

  @override
  bool shouldRepaint(covariant _StatPatternPainter oldDelegate) =>
      oldDelegate.intensified != intensified ||
      oldDelegate.pattern != pattern ||
      oldDelegate.color != color;
}

// ────────────────────────────────────────────────────────────────────────────
//  NOTES
// ────────────────────────────────────────────────────────────────────────────

class _NouvellesCoordonneesCard extends StatelessWidget {
  final Locataire locataire;
  const _NouvellesCoordonneesCard({required this.locataire});

  @override
  Widget build(BuildContext context) {
    final adr = locataire.nouvelleAdresse;
    final tel = locataire.nouveauTelephone;
    final mail = locataire.nouvelEmail;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: LocataireDetailScreen._surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: LocataireDetailScreen._hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: const Color(0xFFEDE6FF),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.swap_horiz_outlined,
                    color: LocataireDetailScreen._purple, size: 18),
              ),
              const SizedBox(width: 10),
              const Text(
                'NOUVELLES COORDONNÉES',
                style: TextStyle(
                  fontSize: 12,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w800,
                  color: LocataireDetailScreen._ink,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (adr != null) ...[
            _CoordRow(icon: Icons.location_on_outlined, text: adr),
            const SizedBox(height: 8),
          ],
          if (tel != null) ...[
            _CoordRow(icon: Icons.phone_outlined, text: tel),
            const SizedBox(height: 8),
          ],
          if (mail != null) _CoordRow(icon: Icons.mail_outline, text: mail),
        ],
      ),
    );
  }
}

class _CoordRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _CoordRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: LocataireDetailScreen._muted),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 14,
              color: LocataireDetailScreen._ink,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}

class _AjouterAncienColocataireButton extends StatelessWidget {
  final List<String> logementIds;
  const _AjouterAncienColocataireButton({required this.logementIds});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => LocataireFormScreen(
              archiveMode: true,
              preselectedLogementIds: logementIds,
            ),
          ),
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: LocataireDetailScreen._surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: LocataireDetailScreen._purple.withValues(alpha: 0.35),
              width: 1.5,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFFEDE6FF),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.person_add_outlined,
                  color: LocataireDetailScreen._purple,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Ajouter un ancien colocataire',
                      style: TextStyle(
                        color: LocataireDetailScreen._ink,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Crée un autre locataire archivé sur le(s) même(s) logement(s).',
                      style: TextStyle(
                        color: LocataireDetailScreen._muted,
                        fontSize: 11.5,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right,
                  color: LocataireDetailScreen._muted),
            ],
          ),
        ),
      ),
    );
  }
}

class _AjouterLoyerPercuButton extends StatelessWidget {
  final String locataireId;
  final String logementId;
  const _AjouterLoyerPercuButton({
    required this.locataireId,
    required this.logementId,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => QuittanceFormScreen(
              initialLocataireId: locataireId,
              initialLogementId: logementId,
            ),
          ),
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: LocataireDetailScreen._surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: LocataireDetailScreen._greenDark.withValues(alpha: 0.35),
              width: 1.5,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFFD8F3E4),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.payments_outlined,
                  color: LocataireDetailScreen._greenDark,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Ajouter un loyer perçu',
                      style: TextStyle(
                        color: LocataireDetailScreen._ink,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Enregistre une quittance pour ce locataire.',
                      style: TextStyle(
                        color: LocataireDetailScreen._muted,
                        fontSize: 11.5,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right,
                  color: LocataireDetailScreen._muted),
            ],
          ),
        ),
      ),
    );
  }
}

class _NotesCard extends StatelessWidget {
  final String notes;
  const _NotesCard({required this.notes});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: LocataireDetailScreen._surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: LocataireDetailScreen._hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF4D9),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.sticky_note_2_outlined,
                    color: Color(0xFFC66E1A), size: 18),
              ),
              const SizedBox(width: 10),
              const Text(
                'NOTES',
                style: TextStyle(
                  fontSize: 12,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w800,
                  color: LocataireDetailScreen._ink,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            notes,
            style: const TextStyle(
              fontSize: 14,
              color: LocataireDetailScreen._ink,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
//  LOGEMENT CARD
// ────────────────────────────────────────────────────────────────────────────

class _LogementCard extends StatelessWidget {
  final Logement logement;
  final int gradientIndex;
  final VoidCallback onTap;
  const _LogementCard({
    required this.logement,
    required this.gradientIndex,
    required this.onTap,
  });

  static const _gradients = <List<Color>>[
    [Color(0xFFE07AB5), Color(0xFFE89460)],
    [Color(0xFF6FB1FF), Color(0xFFB46BFF)],
    [Color(0xFF5BB9C4), Color(0xFF7C5BC4)],
    [Color(0xFF6BD2A1), Color(0xFF3F8F6B)],
  ];

  @override
  Widget build(BuildContext context) {
    final gradient = _gradients[gradientIndex % _gradients.length];
    final money = NumberFormat.currency(
        locale: 'fr_FR', symbol: '€', decimalDigits: 0);
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: LocataireDetailScreen._surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: LocataireDetailScreen._hairline),
        ),
        child: Row(
          children: [
            Container(
              width: 6,
              height: 92,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: gradient,
                ),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(20),
                  bottomLeft: Radius.circular(20),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: gradient,
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(_typeIcon(logement.type),
                    color: Colors.white, size: 26),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      logement.libelle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: LocataireDetailScreen._ink,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.location_on_outlined,
                            size: 12, color: LocataireDetailScreen._muted),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            logement.adresseComplete,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              color: LocataireDetailScreen._muted,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        _MiniPill(
                          text: logement.type.label.toUpperCase(),
                          color: gradient.last,
                          bg: gradient.last.withValues(alpha: 0.1),
                        ),
                        const SizedBox(width: 6),
                        _MiniPill(
                          text: '${logement.surface.toStringAsFixed(0)} m²',
                          color: LocataireDetailScreen._muted,
                          bg: const Color(0xFFF1F2F8),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    money.format(logement.loyerTTC),
                    style: const TextStyle(
                      fontFamily: 'serif',
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: LocataireDetailScreen._ink,
                    ),
                  ),
                  const Text(
                    '/ mois TTC',
                    style: TextStyle(
                      fontSize: 11,
                      color: LocataireDetailScreen._muted,
                    ),
                  ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: Icon(Icons.chevron_right,
                  color: LocataireDetailScreen._muted),
            ),
          ],
        ),
      ),
    );
  }

  static IconData _typeIcon(LogementType t) {
    switch (t) {
      case LogementType.maison:
        return Icons.home_outlined;
      case LogementType.appartement:
        return Icons.apartment_rounded;
      case LogementType.studio:
        return Icons.weekend_outlined;
      case LogementType.garage:
        return Icons.garage_outlined;
      case LogementType.parking:
        return Icons.local_parking_rounded;
      case LogementType.box:
        return Icons.inventory_2_outlined;
      case LogementType.localCommercial:
        return Icons.storefront_outlined;
      case LogementType.autre:
        return Icons.location_city_outlined;
    }
  }
}

class _MiniPill extends StatelessWidget {
  final String text;
  final Color color;
  final Color bg;
  const _MiniPill({required this.text, required this.color, required this.bg});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 9.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

class _EmptyLogementCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: LocataireDetailScreen._surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: LocataireDetailScreen._hairline),
      ),
      child: const Row(
        children: [
          Icon(Icons.home_work_outlined,
              color: LocataireDetailScreen._muted, size: 22),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'Aucun logement associé à ce locataire.',
              style: TextStyle(color: LocataireDetailScreen._muted),
            ),
          ),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
//  GESTION LOCATIVE — CONTRAT DE BAIL
// ────────────────────────────────────────────────────────────────────────────

class _ContratBailCard extends StatefulWidget {
  final String locataireName;
  final List<Logement> logements;
  const _ContratBailCard({
    required this.locataireName,
    required this.logements,
  });

  @override
  State<_ContratBailCard> createState() => _ContratBailCardState();
}

class _ContratBailCardState extends State<_ContratBailCard> {
  String? _busyLogementId;

  Future<void> _addFiles(Logement logement) async {
    if (_busyLogementId != null) return;
    final messenger = ScaffoldMessenger.of(context);
    final service = context.read<LogementService>();
    setState(() => _busyLogementId = logement.id);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        allowMultiple: true,
        withData: false,
      );
      if (result == null || result.files.isEmpty) return;
      final added = <String>[];
      for (final f in result.files) {
        final source = f.path;
        if (source == null) continue;
        final stored = await ContratStorage.addContrat(
          logementId: logement.id,
          sourcePath: source,
          originalName: f.name,
        );
        added.add(stored);
      }
      if (added.isEmpty) return;
      logement.contratBailPaths.addAll(added);
      await service.update(logement);
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(added.length == 1
              ? 'Contrat importé'
              : '${added.length} contrats importés'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Import impossible : $e')),
      );
    } finally {
      if (mounted) setState(() => _busyLogementId = null);
    }
  }

  Future<void> _view(String path) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _ContratBailViewerScreen(
          path: path,
          locataireName: widget.locataireName,
        ),
      ),
    );
  }

  Future<void> _share(String path) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await Share.shareXFiles(
        [XFile(path, mimeType: 'application/pdf')],
        subject: 'Contrat de bail · ${widget.locataireName}',
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Partage impossible : $e')),
      );
    }
  }

  Future<void> _delete(Logement logement, String path) async {
    final service = context.read<LogementService>();
    final filename = path.split(Platform.pathSeparator).last;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer ce document ?'),
        content: Text(
          '$filename sera supprimé du stockage local. Cette action est définitive.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: LocataireDetailScreen._red,
            ),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await ContratStorage.deleteContrat(path);
    logement.contratBailPaths.remove(path);
    await service.update(logement);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.logements.isEmpty) {
      return _ContratBailNoLogement();
    }
    final showLogementHeader = widget.logements.length > 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < widget.logements.length; i++) ...[
          if (i > 0) const SizedBox(height: 12),
          if (showLogementHeader)
            Padding(
              padding: const EdgeInsets.only(bottom: 6, left: 4),
              child: Text(
                widget.logements[i].libelle.toUpperCase(),
                style: const TextStyle(
                  color: LocataireDetailScreen._muted,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.0,
                ),
              ),
            ),
          if (widget.logements[i].contratBailPaths.isEmpty)
            _ContratBailEmpty(
              busy: _busyLogementId == widget.logements[i].id,
              onTap: () => _addFiles(widget.logements[i]),
            )
          else
            _ContratBailList(
              paths: widget.logements[i].contratBailPaths,
              busy: _busyLogementId == widget.logements[i].id,
              onView: _view,
              onShare: _share,
              onDelete: (path) => _delete(widget.logements[i], path),
              onAdd: () => _addFiles(widget.logements[i]),
            ),
        ],
      ],
    );
  }
}

class _ContratBailNoLogement extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: LocataireDetailScreen._surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: LocataireDetailScreen._hairline),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFFF1F2F8),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.info_outline,
              color: LocataireDetailScreen._muted,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Associez un logement à ce locataire pour gérer le contrat de bail.',
              style: TextStyle(
                color: LocataireDetailScreen._muted,
                fontSize: 13,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ContratBailEmpty extends StatelessWidget {
  final bool busy;
  final VoidCallback onTap;
  const _ContratBailEmpty({required this.busy, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: busy ? null : onTap,
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: LocataireDetailScreen._surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: LocataireDetailScreen._greenDark.withValues(alpha: 0.35),
              width: 1.5,
              style: BorderStyle.solid,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFFD7F1E2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.upload_file_outlined,
                  color: LocataireDetailScreen._greenDark,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Importer le contrat de bail',
                      style: TextStyle(
                        color: LocataireDetailScreen._ink,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Sélectionnez un fichier PDF — il sera copié dans le stockage de l\'application.',
                      style: TextStyle(
                        color: LocataireDetailScreen._muted,
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              if (busy)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: LocataireDetailScreen._greenDark,
                  ),
                )
              else
                const Icon(
                  Icons.add_circle_outline,
                  color: LocataireDetailScreen._greenDark,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ContratBailList extends StatelessWidget {
  final List<String> paths;
  final bool busy;
  final void Function(String) onView;
  final void Function(String) onShare;
  final void Function(String) onDelete;
  final VoidCallback onAdd;
  const _ContratBailList({
    required this.paths,
    required this.busy,
    required this.onView,
    required this.onShare,
    required this.onDelete,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: LocataireDetailScreen._surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: LocataireDetailScreen._hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < paths.length; i++) ...[
            if (i > 0)
              Container(
                height: 1,
                margin: const EdgeInsets.symmetric(horizontal: 12),
                color: LocataireDetailScreen._hairline,
              ),
            _ContratFileRow(
              path: paths[i],
              onView: () => onView(paths[i]),
              onShare: () => onShare(paths[i]),
              onDelete: () => onDelete(paths[i]),
            ),
          ],
          Container(
            height: 1,
            color: LocataireDetailScreen._hairline,
          ),
          InkWell(
            borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(20),
              bottomRight: Radius.circular(20),
            ),
            onTap: busy ? null : onAdd,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (busy)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: LocataireDetailScreen._greenDark,
                      ),
                    )
                  else
                    const Icon(
                      Icons.add_circle_outline,
                      color: LocataireDetailScreen._greenDark,
                      size: 18,
                    ),
                  const SizedBox(width: 8),
                  const Text(
                    'Ajouter un document',
                    style: TextStyle(
                      color: LocataireDetailScreen._greenDark,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ContratFileRow extends StatelessWidget {
  final String path;
  final VoidCallback onView;
  final VoidCallback onShare;
  final VoidCallback onDelete;
  const _ContratFileRow({
    required this.path,
    required this.onView,
    required this.onShare,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final file = File(path);
    final exists = file.existsSync();
    final sizeKb = exists ? (file.lengthSync() / 1024).round() : 0;
    final modified = exists
        ? DateFormat('dd/MM/yyyy', 'fr_FR').format(file.lastModifiedSync())
        : '—';
    final filename = path.split(Platform.pathSeparator).last;

    return InkWell(
      onTap: exists ? onView : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFFFEE2E2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.picture_as_pdf_outlined,
                color: Color(0xFFB91C1C),
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    filename,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: LocataireDetailScreen._ink,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    exists
                        ? '$sizeKb Ko · Ajouté le $modified'
                        : 'Fichier introuvable',
                    style: TextStyle(
                      color: exists
                          ? LocataireDetailScreen._muted
                          : LocataireDetailScreen._red,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.ios_share_outlined),
              color: LocataireDetailScreen._muted,
              iconSize: 20,
              tooltip: 'Partager',
              onPressed: exists ? onShare : null,
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              color: LocataireDetailScreen._red,
              iconSize: 20,
              tooltip: 'Supprimer',
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}

class _ContratBailViewerScreen extends StatelessWidget {
  final String path;
  final String locataireName;
  const _ContratBailViewerScreen({
    required this.path,
    required this.locataireName,
  });

  @override
  Widget build(BuildContext context) {
    final filename =
        'contrat_bail_${locataireName.replaceAll(RegExp(r'[^A-Za-z0-9]'), '_')}.pdf';
    return Scaffold(
      backgroundColor: LocataireDetailScreen._bg,
      appBar: AppBar(
        title: const Text('Contrat de bail'),
        actions: [
          IconButton(
            icon: const Icon(Icons.ios_share_outlined),
            tooltip: 'Partager',
            onPressed: () async {
              await Share.shareXFiles(
                [XFile(path, mimeType: 'application/pdf')],
                subject: 'Contrat de bail · $locataireName',
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.print_outlined),
            tooltip: 'Imprimer',
            onPressed: () async {
              final bytes = await File(path).readAsBytes();
              await Printing.layoutPdf(
                name: filename,
                onLayout: (_) async => bytes,
              );
            },
          ),
        ],
      ),
      body: PdfPreview(
        build: (format) async => File(path).readAsBytes(),
        canChangePageFormat: false,
        canChangeOrientation: false,
        canDebug: false,
        pdfFileName: filename,
        previewPageMargin: const EdgeInsets.all(8),
      ),
    );
  }
}
