import 'package:flutter/material.dart';

import '../core/rbac.dart';

/// Small pill showing the signed-in user's role, mirrors the reference web
/// app's `<Badge>` in `Header.tsx` - purely informational UI, not the
/// security boundary (see `core/rbac.dart`).
class RoleBadge extends StatelessWidget {
  const RoleBadge({required this.role, super.key});

  final String role;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final (Color background, Color foreground) = switch (role) {
      AppRole.organizer => (colorScheme.primary, colorScheme.onPrimary),
      _ => (colorScheme.secondaryContainer, colorScheme.onSecondaryContainer),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        roleLabel(role),
        style: TextStyle(
          color: foreground,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
