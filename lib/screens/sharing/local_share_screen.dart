import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/theme/app_theme.dart';
import '../../services/local_share_service.dart';

class LocalShareScreen extends StatefulWidget {
  final String title;
  final List<ShareableFile> files;
  /// Code à 8 caractères à communiquer au locataire pour déchiffrer un
  /// fichier `.adls`. Affiché en évidence quand non null.
  final String? sharedCode;

  const LocalShareScreen({
    super.key,
    required this.title,
    required this.files,
    this.sharedCode,
  });

  @override
  State<LocalShareScreen> createState() => _LocalShareScreenState();
}

class _LocalShareScreenState extends State<LocalShareScreen> {
  LocalShareSession? _session;
  String? _error;
  bool _starting = true;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      final s = await LocalShareService.start(
        title: widget.title,
        files: widget.files,
      );
      if (!mounted) {
        await s.stop();
        return;
      }
      setState(() {
        _session = s;
        _starting = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _starting = false;
      });
    }
  }

  @override
  void dispose() {
    _session?.stop();
    super.dispose();
  }

  void _copyUrl() {
    final s = _session;
    if (s == null) return;
    Clipboard.setData(ClipboardData(text: s.indexUrl));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Lien copié')),
    );
  }

  void _copyCode() {
    final code = widget.sharedCode;
    if (code == null) return;
    Clipboard.setData(ClipboardData(text: code));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Code copié')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Partage Wi-Fi local')),
      body: SafeArea(
        top: false,
        bottom: false,
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            24,
            24,
            24,
            24 + MediaQuery.viewPaddingOf(context).bottom,
          ),
          children: [
            if (_starting)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 64),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              _ErrorBox(message: _error!)
            else if (_session != null)
              ..._buildSessionView(_session!),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildSessionView(LocalShareSession s) {
    final code = widget.sharedCode;
    return [
      const Text(
        'Le locataire scanne ce QR code',
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        ),
      ),
      const SizedBox(height: 6),
      const Text(
        'Vous devez être sur le même Wi-Fi (ou via votre partage de connexion). Aucun cloud, aucun internet.',
        style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
      ),
      const SizedBox(height: 20),
      if (code != null) ...[
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: AppColors.accent.withValues(alpha: 0.4),
            ),
          ),
          child: Column(
            children: [
              const Text(
                'CODE À COMMUNIQUER AU LOCATAIRE',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              SelectableText(
                code,
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 4,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 4),
              TextButton.icon(
                onPressed: _copyCode,
                icon: const Icon(Icons.copy, size: 16),
                label: const Text('Copier le code'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
      ],
      Center(
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.divider),
          ),
          child: QrImageView(
            data: s.indexUrl,
            size: 240,
            backgroundColor: Colors.white,
          ),
        ),
      ),
      const SizedBox(height: 20),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.divider),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Lien direct (si le QR ne marche pas)',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
              ),
            ),
            const SizedBox(height: 6),
            SelectableText(
              s.indexUrl,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _copyUrl,
              icon: const Icon(Icons.copy, size: 16),
              label: const Text('Copier le lien'),
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${s.files.length} fichier(s) partagé(s)',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 8),
            ...s.files.map((f) => Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.insert_drive_file_outlined,
                        size: 14,
                        color: AppColors.textSecondary,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          f.filename,
                          style: const TextStyle(fontSize: 12),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                )),
          ],
        ),
      ),
      const SizedBox(height: 20),
      const Text(
        'Le partage s\'arrête automatiquement quand vous quittez cet écran.',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 12,
          color: AppColors.textSecondary,
          fontStyle: FontStyle.italic,
        ),
      ),
    ];
  }
}

class _ErrorBox extends StatelessWidget {
  final String message;
  const _ErrorBox({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.wifi_off, color: AppColors.error),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: AppColors.error, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
