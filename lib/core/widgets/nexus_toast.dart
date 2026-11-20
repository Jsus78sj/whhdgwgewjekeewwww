import 'package:flutter/material.dart';
import '../theme/nexus_colors.dart';

enum NexusToastType { info, success, warning, error }

void showNexusToast(
  BuildContext context,
  String message, {
  NexusToastType type = NexusToastType.info,
}) {
  final (Color accent, IconData icon) = switch (type) {
    NexusToastType.success => (
        NexusColors.successSoft,
        Icons.check_circle_outline_rounded,
      ),
    NexusToastType.error => (
        NexusColors.roseSoft,
        Icons.error_outline_rounded,
      ),
    NexusToastType.warning => (
        NexusColors.warningSoft,
        Icons.warning_amber_rounded,
      ),
    NexusToastType.info => (
        NexusColors.primarySoft,
        Icons.info_outline_rounded,
      ),
  };

  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: Colors.transparent,
      elevation: 0,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      padding: EdgeInsets.zero,
      duration: const Duration(seconds: 4),
      content: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        decoration: BoxDecoration(
          color: NexusColors.bgSurface.withOpacity(0.95),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: accent.withOpacity(0.4)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.4),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(icon, color: accent, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: NexusColors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
