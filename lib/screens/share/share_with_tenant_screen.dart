import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/theme/app_theme.dart';
import 'package:intl/intl.dart';

import '../../models/locataire.dart';
import '../../models/quittance.dart';
import '../../services/etat_des_lieux_service.dart';
import '../../services/local_share_service.dart';
import '../../services/locataire_service.dart';
import '../../services/logement_service.dart';
import '../../services/quittance_service.dart';
import '../../services/tenant_share_service.dart';
import '../sharing/local_share_screen.dart';

enum _ShareMethod { bluetooth, airdrop, qrcode, email }

extension _ShareMethodLabel on _ShareMethod {
  String get title {
    switch (this) {
      case _ShareMethod.bluetooth:
        return 'Bluetooth';
      case _ShareMethod.airdrop:
        return 'AirDrop';
      case _ShareMethod.qrcode:
        return 'QR Code';
      case _ShareMethod.email:
        return 'Email';
    }
  }

  String get subtitle {
    switch (this) {
      case _ShareMethod.bluetooth:
        return 'À proximité';
      case _ShareMethod.airdrop:
        return 'iPhone / Mac';
      case _ShareMethod.qrcode:
        return 'À scanner';
      case _ShareMethod.email:
        return 'Pièce jointe';
    }
  }

  IconData get icon {
    switch (this) {
      case _ShareMethod.bluetooth:
        return Icons.bluetooth_rounded;
      case _ShareMethod.airdrop:
        return Icons.wifi_tethering_rounded;
      case _ShareMethod.qrcode:
        return Icons.qr_code_2_rounded;
      case _ShareMethod.email:
        return Icons.mail_outline_rounded;
    }
  }
}

class ShareWithTenantScreen extends StatefulWidget {
  const ShareWithTenantScreen({super.key});

  @override
  State<ShareWithTenantScreen> createState() => _ShareWithTenantScreenState();
}

class _ShareWithTenantScreenState extends State<ShareWithTenantScreen> {
  final Set<String> _docs = {'quittances', 'edl', 'bail'};
  Locataire? _selected;
  _ShareMethod _method = _ShareMethod.bluetooth;
  TenantShareResult? _result;
  bool _busy = false;

  /// IDs des quittances explicitement cochées par l'utilisateur. `null` =
  /// première sélection pas encore faite (= tout coché par défaut au moment
  /// du choix du locataire).
  Set<String>? _selectedQuittanceIds;

  Future<void> _generateBundle() async {
    if (_selected == null) return;
    setState(() => _busy = true);
    try {
      // Si la case "Quittances" est décochée → on n'envoie aucune quittance.
      // Sinon → on envoie celles cochées (null = toutes).
      final qIds = !_docs.contains('quittances')
          ? <String>{}
          : _selectedQuittanceIds;
      final result = await context
          .read<TenantShareService>()
          .createShareForLocataire(
            locataire: _selected!,
            quittanceIds: qIds,
          );
      if (!mounted) return;
      setState(() => _result = result);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erreur : $e'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _handleSelect(Locataire l) async {
    // Charge l'ensemble des quittances de ce locataire et les pré-coche
    // toutes (l'utilisateur peut ensuite décocher individuellement).
    final all = context.read<QuittanceService>().all
        .where((q) => q.locataireId == l.id)
        .map((q) => q.id)
        .toSet();
    setState(() {
      _selected = l;
      _result = null;
      _selectedQuittanceIds = all;
    });
    await _generateBundle();
  }

  Future<void> _onDemarrer() async {
    if (_selected == null) return;
    if (_result == null) await _generateBundle();
    final r = _result;
    if (r == null) return;

    switch (_method) {
      case _ShareMethod.bluetooth:
      case _ShareMethod.email:
      case _ShareMethod.airdrop:
        await _systemShare(r);
      case _ShareMethod.qrcode:
        await _shareViaQr(r);
    }
  }

  Future<void> _systemShare(TenantShareResult r) async {
    final subject = 'Partage ADDA Bailleur';
    final body =
        'Documents locatifs pour ${r.locataireName}. Ouvrir dans ADDA Bailleur et saisir le code communiqué oralement.';
    if (Platform.isMacOS) {
      const channel = MethodChannel('adda_location/mail');
      try {
        await channel.invokeMethod<void>('shareFile', {'path': r.file.path});
        return;
      } on PlatformException catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Partage indisponible : ${e.message ?? e.code}'),
            backgroundColor: AppColors.error,
          ),
        );
        return;
      }
    }
    final box = context.findRenderObject() as RenderBox?;
    await Share.shareXFiles(
      [XFile(r.file.path, mimeType: 'application/x-adda-share')],
      subject: subject,
      text: body,
      sharePositionOrigin:
          box == null ? null : box.localToGlobal(Offset.zero) & box.size,
    );
  }

  Future<void> _shareViaQr(TenantShareResult r) async {
    final filename = r.file.path.split(Platform.pathSeparator).last;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LocalShareScreen(
          title: 'Partage pour ${r.locataireName}',
          sharedCode: r.code,
          files: [
            ShareableFile(
              path: r.file.path,
              filename: filename,
              mimeType: 'application/octet-stream',
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final locataires = context.watch<LocataireService>().all;
    final quittancesAll = context.watch<QuittanceService>().all;
    final edlsAll = context.watch<EtatDesLieuxService>().all;

    // Quittances éligibles (toutes celles du locataire sélectionné).
    final quittancesEligibles = _selected == null
        ? <Quittance>[]
        : quittancesAll.where((q) => q.locataireId == _selected!.id).toList()
      ..sort((a, b) {
        final c = a.periodYear.compareTo(b.periodYear);
        if (c != 0) return -c; // plus récente d'abord
        return -a.periodMonth.compareTo(b.periodMonth);
      });
    // Nombre effectivement coché pour l'envoi.
    final qCount = _selected == null
        ? quittancesAll.length
        : (_selectedQuittanceIds?.length ?? quittancesEligibles.length);
    final edlCount = _selected == null
        ? edlsAll.length
        : edlsAll.where((e) => e.locataireId == _selected!.id).length;

    final qSize = _approxKb(qCount * 140);
    final edlSize = _approxKb(edlCount * 350);
    final bailSize = '215 Ko';

    final totalKb = (qCount * 140) + (edlCount * 350);
    final totalSize = _approxKb(totalKb);
    final realSize = _result != null
        ? _approxKb((_result!.file.lengthSync() / 1024).round())
        : totalSize;

    final hasLocataire = _selected != null;
    final stepCurrent = !hasLocataire ? 0 : (_result == null ? 1 : 2);

    return Scaffold(
      backgroundColor: context.backgroundColor,
      body: Column(
        children: [
          _Hero(onBack: () => Navigator.of(context).maybePop()),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
              children: [
                _SecuredBanner(),
                const SizedBox(height: 18),
                _Stepper(current: stepCurrent),
                const SizedBox(height: 22),
                _SectionLabel('QUE PARTAGER ?'),
                const SizedBox(height: 10),
                _ContentCard(
                  items: [
                    _ContentItem(
                      key: 'quittances',
                      icon: Icons.description_outlined,
                      iconBg: AppColors.success.withValues(alpha: 0.18),
                      iconColor: AppColors.success,
                      title: 'Quittances de loyer',
                      meta: '$qCount document${qCount > 1 ? 's' : ''} · $qSize',
                    ),
                    _ContentItem(
                      key: 'edl',
                      icon: Icons.event_available_outlined,
                      iconBg: AppColors.accent.withValues(alpha: 0.18),
                      iconColor: AppColors.accent,
                      title: 'États des lieux',
                      meta: '$edlCount document${edlCount > 1 ? 's' : ''} · $edlSize',
                    ),
                    _ContentItem(
                      key: 'bail',
                      icon: Icons.insert_drive_file_outlined,
                      iconBg: AppColors.primary.withValues(alpha: 0.18),
                      iconColor: AppColors.primary,
                      title: 'Contrat de bail',
                      meta: 'PDF · $bailSize',
                    ),
                  ],
                  selected: _docs,
                  onToggle: (k) => setState(() {
                    if (_docs.contains(k)) {
                      _docs.remove(k);
                    } else {
                      _docs.add(k);
                    }
                  }),
                ),
                const SizedBox(height: 22),
                _SectionLabel('DESTINATAIRE'),
                const SizedBox(height: 10),
                if (locataires.isEmpty)
                  _EmptyLocataireCard()
                else
                  _LocataireCard(
                    locataires: locataires,
                    selected: _selected,
                    onSelect: _handleSelect,
                  ),
                if (_selected != null &&
                    _docs.contains('quittances') &&
                    quittancesEligibles.isNotEmpty) ...[
                  const SizedBox(height: 22),
                  _SectionLabel('QUITTANCES À INCLURE'),
                  const SizedBox(height: 10),
                  _QuittancePicker(
                    quittances: quittancesEligibles,
                    selectedIds:
                        _selectedQuittanceIds ?? const <String>{},
                    onToggle: (id) {
                      setState(() {
                        final set = Set<String>.from(
                            _selectedQuittanceIds ?? const <String>{});
                        if (set.contains(id)) {
                          set.remove(id);
                        } else {
                          set.add(id);
                        }
                        _selectedQuittanceIds = set;
                        _result = null;
                      });
                    },
                    onSelectAll: () {
                      setState(() {
                        _selectedQuittanceIds = quittancesEligibles
                            .map((q) => q.id)
                            .toSet();
                        _result = null;
                      });
                    },
                    onSelectNone: () {
                      setState(() {
                        _selectedQuittanceIds = <String>{};
                        _result = null;
                      });
                    },
                  ),
                ],
                const SizedBox(height: 22),
                _SectionLabel('MÉTHODE DE TRANSFERT'),
                const SizedBox(height: 10),
                _MethodGrid(
                  selected: _method,
                  onChanged: (m) => setState(() => _method = m),
                ),
                const SizedBox(height: 22),
                _CodeCard(
                  code: _result?.code,
                  busy: _busy,
                  onRegenerate: _selected == null ? null : _generateBundle,
                ),
                const SizedBox(height: 6),
                _TipRow(
                  recipientFirstName:
                      _selected?.firstName ?? 'votre locataire',
                ),
                const SizedBox(height: 18),
                _SummaryCard(
                  contenu: _docs.contains('quittances')
                      ? 'Quittances · $qCount doc${qCount > 1 ? 's' : ''}'
                      : 'Aucun',
                  destinataire: _selected?.fullName ?? '—',
                  method: _method,
                  totalSize: realSize,
                ),
                const SizedBox(height: 18),
                _PrimaryButton(
                  enabled: hasLocataire && !_busy && _docs.isNotEmpty,
                  busy: _busy,
                  onPressed: _onDemarrer,
                ),
                const SizedBox(height: 12),
                Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.shield_outlined,
                          size: 14, color: context.textSecondaryColor),
                      const SizedBox(width: 6),
                      Text(
                        'Aucune donnée n\'est envoyée à un serveur',
                        style: TextStyle(
                          color: context.textSecondaryColor,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _approxKb(int kb) {
    if (kb <= 0) return '—';
    if (kb < 1024) return '$kb Ko';
    return '${(kb / 1024).toStringAsFixed(1)} Mo';
  }
}

class _Hero extends StatelessWidget {
  final VoidCallback onBack;
  const _Hero({required this.onBack});

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0F1B3A),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(28),
          bottomRight: Radius.circular(28),
        ),
      ),
      padding: EdgeInsets.fromLTRB(20, topInset + 12, 20, 22),
      child: Row(
        children: [
          InkResponse(
            onTap: onBack,
            radius: 26,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.arrow_back_rounded,
                  color: Colors.white, size: 20),
            ),
          ),
          Expanded(
            child: Column(
              children: const [
                Text(
                  'Partager en local',
                  style: TextStyle(
                    fontFamily: 'serif',
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Transfert chiffré de bout en bout',
                  style: TextStyle(color: Colors.white60, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 40),
        ],
      ),
    );
  }
}

class _SecuredBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final accent = AppColors.primary;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.lock_outline_rounded, color: accent, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: TextStyle(
                  color: context.textPrimaryColor,
                  fontSize: 13,
                  height: 1.4,
                ),
                children: [
                  const TextSpan(
                    text:
                        'Vos données restent chiffrées sur votre appareil. ',
                  ),
                  TextSpan(
                    text: 'Aucun serveur n\'y a accès',
                    style: TextStyle(
                      color: accent,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const TextSpan(
                    text:
                        ' — seul votre locataire pourra les déchiffrer avec le code à 8 caractères.',
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

class _Stepper extends StatelessWidget {
  final int current;
  const _Stepper({required this.current});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _StepDot(index: 1, label: 'Contenu', state: _stateFor(0)),
        Expanded(child: _StepLine(active: current >= 1)),
        _StepDot(index: 2, label: 'Locataire', state: _stateFor(1)),
        Expanded(child: _StepLine(active: current >= 2)),
        _StepDot(index: 3, label: 'Envoi', state: _stateFor(2)),
      ],
    );
  }

  _StepState _stateFor(int i) {
    if (current > i) return _StepState.done;
    if (current == i) return _StepState.current;
    return _StepState.idle;
  }
}

enum _StepState { idle, current, done }

class _StepDot extends StatelessWidget {
  final int index;
  final String label;
  final _StepState state;
  const _StepDot({
    required this.index,
    required this.label,
    required this.state,
  });

  @override
  Widget build(BuildContext context) {
    final filled = state != _StepState.idle;
    return Row(
      children: [
        Container(
          width: 26,
          height: 26,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: filled ? const Color(0xFF0F1B3A) : Colors.transparent,
            shape: BoxShape.circle,
            border: Border.all(
              color: filled
                  ? const Color(0xFF0F1B3A)
                  : context.dividerColor,
              width: 1.5,
            ),
          ),
          child: Text(
            '$index',
            style: TextStyle(
              color: filled ? Colors.white : context.textSecondaryColor,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: state == _StepState.idle
                ? context.textSecondaryColor
                : context.textPrimaryColor,
          ),
        ),
      ],
    );
  }
}

class _StepLine extends StatelessWidget {
  final bool active;
  const _StepLine({required this.active});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Container(
        height: 1.5,
        color: active
            ? const Color(0xFF0F1B3A)
            : context.dividerColor,
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel(this.label);
  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: TextStyle(
        color: context.textSecondaryColor,
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.4,
      ),
    );
  }
}

class _ContentItem {
  final String key;
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String title;
  final String meta;
  const _ContentItem({
    required this.key,
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.title,
    required this.meta,
  });
}

class _ContentCard extends StatelessWidget {
  final List<_ContentItem> items;
  final Set<String> selected;
  final ValueChanged<String> onToggle;
  const _ContentCard({
    required this.items,
    required this.selected,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.dividerColor),
      ),
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => onToggle(items[i].key),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    _Checkbox(checked: selected.contains(items[i].key)),
                    const SizedBox(width: 12),
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: items[i].iconBg,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(items[i].icon,
                          color: items[i].iconColor, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            items[i].title,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: context.textPrimaryColor,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            items[i].meta,
                            style: TextStyle(
                              fontSize: 12,
                              color: context.textSecondaryColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (i < items.length - 1)
              Divider(height: 1, color: context.dividerColor),
          ],
        ],
      ),
    );
  }
}

class _Checkbox extends StatelessWidget {
  final bool checked;
  const _Checkbox({required this.checked});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: checked ? const Color(0xFF0F1B3A) : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: checked ? const Color(0xFF0F1B3A) : context.dividerColor,
          width: 1.5,
        ),
      ),
      child: checked
          ? const Icon(Icons.check_rounded, color: Colors.white, size: 16)
          : null,
    );
  }
}

class _LocataireCard extends StatelessWidget {
  final List<Locataire> locataires;
  final Locataire? selected;
  final ValueChanged<Locataire> onSelect;
  const _LocataireCard({
    required this.locataires,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.dividerColor),
      ),
      child: Column(
        children: [
          for (var i = 0; i < locataires.length; i++) ...[
            _LocataireRow(
              locataire: locataires[i],
              selected: selected?.id == locataires[i].id,
              onTap: () => onSelect(locataires[i]),
            ),
            if (i < locataires.length - 1)
              Divider(height: 1, color: context.dividerColor),
          ],
        ],
      ),
    );
  }
}

class _LocataireRow extends StatelessWidget {
  final Locataire locataire;
  final bool selected;
  final VoidCallback onTap;
  const _LocataireRow({
    required this.locataire,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final initials = _initials(locataire.fullName);
    final isActive = locataire.logementIds.isNotEmpty;
    final bg = selected ? AppColors.primary.withValues(alpha: 0.05) : null;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        color: bg,
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor:
                  AppColors.primary.withValues(alpha: 0.18),
              child: Text(
                initials,
                style: const TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          locataire.fullName,
                          style: TextStyle(
                            fontFamily: 'serif',
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: context.textPrimaryColor,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      _StatusBadge(active: isActive),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    locataire.email.isEmpty ? '—' : locataire.email,
                    style: TextStyle(
                      color: context.textSecondaryColor,
                      fontSize: 12,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: selected ? const Color(0xFF0F1B3A) : Colors.transparent,
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected
                      ? const Color(0xFF0F1B3A)
                      : context.dividerColor,
                  width: 1.5,
                ),
              ),
              child: selected
                  ? const Icon(Icons.check_rounded,
                      color: Colors.white, size: 16)
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  String _initials(String full) {
    final parts = full.split(' ').where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }
}

class _StatusBadge extends StatelessWidget {
  final bool active;
  const _StatusBadge({required this.active});

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.success : AppColors.accent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        active ? 'ACTIF' : 'ANCIEN',
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

class _EmptyLocataireCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.dividerColor),
      ),
      child: Center(
        child: Text(
          'Aucun locataire enregistré.\nAjoutez d\'abord un locataire.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: context.textSecondaryColor,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}

class _MethodGrid extends StatelessWidget {
  final _ShareMethod selected;
  final ValueChanged<_ShareMethod> onChanged;
  const _MethodGrid({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final methods = _ShareMethod.values;
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.5,
      children: [
        for (final m in methods)
          _MethodTile(
            method: m,
            selected: m == selected,
            onTap: () => onChanged(m),
          ),
      ],
    );
  }
}

class _MethodTile extends StatelessWidget {
  final _ShareMethod method;
  final bool selected;
  final VoidCallback onTap;
  const _MethodTile({
    required this.method,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: context.surfaceColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? const Color(0xFF0F1B3A)
                : context.dividerColor,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Stack(
          children: [
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(method.icon,
                      color: context.textPrimaryColor, size: 26),
                  const SizedBox(height: 8),
                  Text(
                    method.title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: context.textPrimaryColor,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    method.subtitle,
                    style: TextStyle(
                      fontSize: 11,
                      color: context.textSecondaryColor,
                    ),
                  ),
                ],
              ),
            ),
            if (selected)
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  width: 20,
                  height: 20,
                  decoration: const BoxDecoration(
                    color: Color(0xFF0F1B3A),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check_rounded,
                      color: Colors.white, size: 14),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CodeCard extends StatelessWidget {
  final String? code;
  final bool busy;
  final VoidCallback? onRegenerate;
  const _CodeCard({
    required this.code,
    required this.busy,
    required this.onRegenerate,
  });

  @override
  Widget build(BuildContext context) {
    final chars = (code ?? '·· ·· ·· ··').replaceAll(' ', '').split('');
    while (chars.length < 8) {
      chars.add('·');
    }
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'CODE DE DÉCHIFFREMENT',
                  style: TextStyle(
                    color: context.textSecondaryColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.4,
                  ),
                ),
              ),
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: onRegenerate,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: context.dividerColor.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.refresh_rounded,
                          size: 14, color: context.textSecondaryColor),
                      const SizedBox(width: 4),
                      Text(
                        'Régénérer',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: context.textSecondaryColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (busy)
            const SizedBox(
              height: 56,
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
              ),
            )
          else
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (final c in chars.take(8))
                  _CodeCell(char: c, empty: code == null),
              ],
            ),
        ],
      ),
    );
  }
}

class _CodeCell extends StatelessWidget {
  final String char;
  final bool empty;
  const _CodeCell({required this.char, required this.empty});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 50,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: context.backgroundColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.4),
        ),
      ),
      child: Text(
        char,
        style: TextStyle(
          fontFamily: 'serif',
          fontSize: 22,
          fontWeight: FontWeight.w700,
          color: empty
              ? context.textSecondaryColor
              : context.textPrimaryColor,
        ),
      ),
    );
  }
}

class _TipRow extends StatelessWidget {
  final String recipientFirstName;
  const _TipRow({required this.recipientFirstName});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded,
              size: 14, color: context.textSecondaryColor),
          const SizedBox(width: 6),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: TextStyle(
                  fontSize: 12,
                  color: context.textSecondaryColor,
                  height: 1.4,
                ),
                children: [
                  TextSpan(text: 'Communiquez ce code à $recipientFirstName '),
                  const TextSpan(
                    text: 'par un autre canal (SMS, oral)',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const TextSpan(text: '.'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String contenu;
  final String destinataire;
  final _ShareMethod method;
  final String totalSize;
  const _SummaryCard({
    required this.contenu,
    required this.destinataire,
    required this.method,
    required this.totalSize,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.dividerColor),
      ),
      child: Column(
        children: [
          _SummaryRow(label: 'Contenu', value: contenu),
          const SizedBox(height: 10),
          _SummaryRow(label: 'Destinataire', value: destinataire),
          const SizedBox(height: 10),
          _SummaryRow(
            label: 'Méthode',
            valueWidget: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(method.icon, size: 14, color: AppColors.primary),
                const SizedBox(width: 4),
                Text(
                  method.title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: context.textPrimaryColor,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          _SummaryRow(
            label: 'Taille totale',
            value: '$totalSize · chiffré AES-256',
          ),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String? value;
  final Widget? valueWidget;
  const _SummaryRow({required this.label, this.value, this.valueWidget})
      : assert(value != null || valueWidget != null);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: context.textSecondaryColor,
          ),
        ),
        if (valueWidget != null)
          valueWidget!
        else
          Text(
            value!,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: context.textPrimaryColor,
            ),
          ),
      ],
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  final bool enabled;
  final bool busy;
  final VoidCallback onPressed;
  const _PrimaryButton({
    required this.enabled,
    required this.busy,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: ElevatedButton(
        onPressed: enabled ? onPressed : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF0F1B3A),
          foregroundColor: Colors.white,
          disabledBackgroundColor:
              const Color(0xFF0F1B3A).withValues(alpha: 0.4),
          disabledForegroundColor: Colors.white70,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: busy
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation(Colors.white),
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(Icons.lock_outline_rounded, size: 20),
                  SizedBox(width: 10),
                  Text(
                    'Démarrer le transfert chiffré',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// Liste cochable des quittances du locataire sélectionné, avec actions
/// rapides "Tout cocher / Tout décocher". Affiche le mois/année,
/// le logement (libellé), le total payé et le statut payé/dû.
class _QuittancePicker extends StatelessWidget {
  final List<Quittance> quittances;
  final Set<String> selectedIds;
  final ValueChanged<String> onToggle;
  final VoidCallback onSelectAll;
  final VoidCallback onSelectNone;

  const _QuittancePicker({
    required this.quittances,
    required this.selectedIds,
    required this.onToggle,
    required this.onSelectAll,
    required this.onSelectNone,
  });

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat.currency(locale: 'fr_FR', symbol: '€');
    final logementSvc = context.watch<LogementService>();
    final all = quittances.every((q) => selectedIds.contains(q.id));
    final none = quittances.every((q) => !selectedIds.contains(q.id));

    return Container(
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.dividerColor),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${selectedIds.length} / ${quittances.length} cochée${selectedIds.length > 1 ? 's' : ''}',
                    style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w600),
                  ),
                ),
                TextButton(
                  onPressed: all ? null : onSelectAll,
                  child: const Text('Tout'),
                ),
                TextButton(
                  onPressed: none ? null : onSelectNone,
                  child: const Text('Aucune'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          ...quittances.asMap().entries.map((entry) {
            final i = entry.key;
            final q = entry.value;
            final logement = logementSvc.byId(q.logementId);
            final checked = selectedIds.contains(q.id);
            return Column(
              children: [
                if (i > 0)
                  Divider(height: 1, color: context.dividerColor),
                CheckboxListTile(
                  value: checked,
                  onChanged: (_) => onToggle(q.id),
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(
                    _formatMonthYear(q.periodMonth, q.periodYear),
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  subtitle: Text(
                    '${logement?.libelle ?? 'Logement inconnu'} · '
                    '${money.format(q.total)}',
                    style: TextStyle(
                      fontSize: 12,
                      color: context.textSecondaryColor,
                    ),
                  ),
                ),
              ],
            );
          }),
        ],
      ),
    );
  }

  String _formatMonthYear(int month, int year) {
    const mois = [
      'janv.',
      'févr.',
      'mars',
      'avr.',
      'mai',
      'juin',
      'juil.',
      'août',
      'sept.',
      'oct.',
      'nov.',
      'déc.',
    ];
    final m = (month >= 1 && month <= 12) ? mois[month - 1] : '?';
    return 'Quittance · $m $year';
  }
}
