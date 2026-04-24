import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../models/user_role.dart';
import '../../services/user_service.dart';
import '../../widgets/immutable_badge.dart';
import '../../widgets/primary_button.dart';
import '../home/home_screen.dart';

class ConfirmationScreen extends StatefulWidget {
  final UserRole role;
  final String firstName;
  final String lastName;
  final String email;

  const ConfirmationScreen({
    super.key,
    required this.role,
    required this.firstName,
    required this.lastName,
    required this.email,
  });

  @override
  State<ConfirmationScreen> createState() => _ConfirmationScreenState();
}

class _ConfirmationScreenState extends State<ConfirmationScreen> {
  bool _acknowledged = false;
  bool _saving = false;

  Future<void> _confirm() async {
    if (!_acknowledged) return;
    setState(() => _saving = true);
    try {
      await context.read<UserService>().createInitialProfile(
            role: widget.role,
            firstName: widget.firstName,
            lastName: widget.lastName,
            email: widget.email,
          );
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
        (_) => false,
      );
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
      appBar: AppBar(title: const Text('Confirmation définitive')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Vérifiez vos informations',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Après validation, ces champs seront figés définitivement et '
                'apparaîtront sur tous vos documents légaux.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
              ),
              const SizedBox(height: 24),
              _buildRow('Rôle', widget.role.label),
              _buildRow('Prénom', widget.firstName),
              _buildRow('Nom', widget.lastName.toUpperCase()),
              _buildRow('Email', widget.email.toLowerCase()),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.error.withValues(alpha: 0.3),
                  ),
                ),
                child: CheckboxListTile(
                  value: _acknowledged,
                  onChanged: (v) => setState(() => _acknowledged = v ?? false),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Je reconnais que ces informations sont définitives '
                    'et ne pourront plus être modifiées.',
                    style: TextStyle(fontSize: 13),
                  ),
                  activeColor: AppColors.error,
                ),
              ),
              const Spacer(),
              PrimaryButton(
                label: 'Figer définitivement',
                icon: Icons.lock_outline,
                loading: _saving,
                onPressed: _acknowledged ? _confirm : null,
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _saving ? null : () => Navigator.of(context).pop(),
                child: const Text('Modifier mes informations'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.divider),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const ImmutableBadge(),
          ],
        ),
      ),
    );
  }
}
