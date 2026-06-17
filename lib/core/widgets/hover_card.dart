import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Carte interactive avec effet hover « Card premium » + Blob reveal + Press.
///
/// - Hover (desktop) : lift -6px, ombre + glow coloré, blob coloré dans le coin.
/// - Press (mobile)  : scale 0.96 immédiat puis afterglow ~700 ms après le
///   relâchement pour rendre l'effet visible au tap.
class HoverCard extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final Color accent;
  final BorderRadius borderRadius;
  final Color? background;
  final EdgeInsetsGeometry? padding;
  final Color? borderColor;
  final bool clip;

  const HoverCard({
    super.key,
    required this.child,
    this.onTap,
    this.accent = const Color(0xFF7C3AED),
    this.borderRadius = const BorderRadius.all(Radius.circular(20)),
    this.background,
    this.padding,
    this.borderColor,
    this.clip = true,
  });

  @override
  State<HoverCard> createState() => _HoverCardState();
}

class _HoverCardState extends State<HoverCard> {
  bool _hover = false;
  bool _pressed = false;
  bool _afterglow = false;
  Timer? _afterglowTimer;

  static const _hairlineLight = Color(0xFFE3E5EE);
  static const _hairlineDark = Color(0xFF1E2A48);

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
    final dy = _pressed ? 0.0 : (_hover || _afterglow ? -6.0 : 0.0);
    final scale = _pressed ? 0.96 : 1.0;

    final isDark = context.isDark;
    final bg = widget.background ??
        (isDark ? AppColors.darkSurface : Colors.white);
    final defaultBorder = isDark ? _hairlineDark : _hairlineLight;

    final card = AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      transform: Matrix4.identity()
        ..translateByDouble(0.0, dy, 0.0, 1.0)
        ..scaleByDouble(scale, scale, 1.0, 1.0),
      transformAlignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: widget.borderRadius,
        border: Border.all(
          color: lifted
              ? widget.accent.withValues(alpha: 0.35)
              : (widget.borderColor ?? defaultBorder),
        ),
        boxShadow: lifted
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ]
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: widget.clip
          ? ClipRRect(
              borderRadius: widget.borderRadius,
              child: _buildInner(lifted),
            )
          : _buildInner(lifted),
    );

    return MouseRegion(
      cursor: widget.onTap != null
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTapDown: widget.onTap == null
            ? null
            : (_) => setState(() => _pressed = true),
        onTapUp: widget.onTap == null
            ? null
            : (_) {
                setState(() => _pressed = false);
                _triggerAfterglow();
              },
        onTapCancel: widget.onTap == null
            ? null
            : () => setState(() => _pressed = false),
        onTap: widget.onTap,
        child: card,
      ),
    );
  }

  Widget _buildInner(bool lifted) {
    return Stack(
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
                  widget.accent.withValues(alpha: lifted ? 0.32 : 0.0),
                  widget.accent.withValues(alpha: 0.0),
                ],
              ),
            ),
          ),
        ),
        if (widget.padding != null)
          Padding(padding: widget.padding!, child: widget.child)
        else
          widget.child,
      ],
    );
  }
}
