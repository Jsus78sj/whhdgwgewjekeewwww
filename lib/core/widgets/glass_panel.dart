import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/nexus_colors.dart';

/// Ambient dark gradient backdrop matching the radial CSS background.
class NexusAmbientBackground extends StatelessWidget {
  final Widget child;

  const NexusAmbientBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(color: NexusColors.bgDeep),
      child: Stack(
        children: [
          Positioned(
            top: -120,
            left: -80,
            child: _AmbientGlowOrb(
              size: 360,
              color: NexusColors.primary.withOpacity(0.16),
            ),
          ),
          Positioned(
            bottom: -140,
            right: -100,
            child: _AmbientGlowOrb(
              size: 380,
              color: NexusColors.violet.withOpacity(0.12),
            ),
          ),
          Positioned.fill(child: child),
        ],
      ),
    );
  }
}

class _AmbientGlowOrb extends StatelessWidget {
  final double size;
  final Color color;

  const _AmbientGlowOrb({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color, Colors.transparent],
            stops: const [0.0, 0.7],
          ),
        ),
      ),
    );
  }
}

/// Frosted glass container mirroring `.glass-panel` and `.glass-panel-strong`.
class GlassPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double borderRadius;
  final bool strong;
  final Color? borderColor;

  const GlassPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.borderRadius = 20,
    this.strong = false,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: strong ? 22 : 16,
          sigmaY: strong ? 22 : 16,
        ),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: NexusColors.bgSurface.withOpacity(strong ? 0.86 : 0.62),
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(
              color: borderColor ??
                  (strong
                      ? NexusColors.borderAccent
                      : NexusColors.borderSubtle),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(strong ? 0.42 : 0.22),
                blurRadius: strong ? 28 : 16,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Primary gradient button matching `.btn-primary`.
class NexusGradientButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final Widget child;
  final LinearGradient gradient;
  final double height;
  final double borderRadius;

  const NexusGradientButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.gradient = NexusColors.primaryGradient,
    this.height = 52,
    this.borderRadius = 14,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 180),
      opacity: enabled ? 1.0 : 0.55,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: BorderRadius.circular(borderRadius),
          boxShadow: enabled
              ? [
                  BoxShadow(
                    color: gradient.colors.first.withOpacity(0.35),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ]
              : null,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(borderRadius),
            child: SizedBox(
              height: height,
              width: double.infinity,
              child: Center(
                child: DefaultTextStyle.merge(
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                  child: child,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
