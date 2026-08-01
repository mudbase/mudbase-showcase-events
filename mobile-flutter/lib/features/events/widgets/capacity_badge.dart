import 'dart:math';

import 'package:flutter/material.dart';

/// Mirrors the reference web app's `CapacityBadge.tsx`: a live
/// confirmed-vs-capacity indicator whose color escalates as an event fills
/// up (success -> warning within the last 10% of seats -> destructive once
/// full).
class CapacityBadge extends StatelessWidget {
  const CapacityBadge({
    required this.confirmed,
    required this.capacity,
    this.isLoading = false,
    super.key,
  });

  final int? confirmed;
  final int capacity;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (isLoading || confirmed == null) {
      return _pill(
        label: '…/$capacity',
        background: colorScheme.surfaceContainerHighest,
        foreground: colorScheme.onSurfaceVariant,
      );
    }

    final remaining = capacity - confirmed!;
    final lowSeatsThreshold = max(1, (capacity * 0.1).ceil());
    final (Color background, Color foreground) = switch (remaining) {
      <= 0 => (colorScheme.errorContainer, colorScheme.onErrorContainer),
      _ when remaining <= lowSeatsThreshold => (
        Colors.amber.shade100,
        Colors.amber.shade900,
      ),
      _ => (Colors.green.shade100, Colors.green.shade900),
    };
    final label = remaining <= 0
        ? 'Full · $confirmed/$capacity'
        : '$confirmed/$capacity booked';

    return _pill(label: label, background: background, foreground: foreground);
  }

  Widget _pill({
    required String label,
    required Color background,
    required Color foreground,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: foreground,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
