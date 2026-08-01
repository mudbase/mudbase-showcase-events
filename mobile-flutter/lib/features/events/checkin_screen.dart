import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'event_detail_controller.dart';

/// Organizer-only manual QR-token check-in - mirrors the reference web
/// app's `/events/[id]/checkin` page + `CheckInForm.tsx`: a single text
/// input for a pasted/typed `qrToken`, submitted against
/// `EventDetailController.checkIn`. See `plan/build-plan.md` "Check-In Flow"
/// for the full outcome table this screen renders.
class CheckInScreen extends ConsumerStatefulWidget {
  const CheckInScreen({required this.eventId, super.key});

  final String eventId;

  @override
  ConsumerState<CheckInScreen> createState() => _CheckInScreenState();
}

class _CheckInScreenState extends ConsumerState<CheckInScreen> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _submitting = false;
  CheckInResult? _result;
  String? _validationError;

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final value = _controller.text.trim();
    if (value.isEmpty) {
      setState(() => _validationError = 'Paste or type the scanned code');
      return;
    }
    setState(() {
      _submitting = true;
      _validationError = null;
    });
    try {
      final result = await ref
          .read(eventDetailControllerProvider(widget.eventId).notifier)
          .checkIn(value);
      setState(() => _result = result);
      _controller.clear();
    } on Object catch (error) {
      setState(() => _result = null);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
        _focusNode.requestFocus();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Check-in')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    autofocus: true,
                    decoration: InputDecoration(
                      labelText: 'Scanned / pasted code',
                      hintText: 'e.g. 9f2c1a4b…',
                      errorText: _validationError,
                    ),
                    onSubmitted: (_) => _submit(),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: _submitting ? null : _submit,
                  child: Text(_submitting ? 'Checking…' : 'Check in'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_result != null) _ResultBanner(result: _result!),
          ],
        ),
      ),
    );
  }
}

class _ResultBanner extends StatelessWidget {
  const _ResultBanner({required this.result});

  final CheckInResult result;

  @override
  Widget build(BuildContext context) {
    final guestName = result.booking?.userName;
    final (
      IconData icon,
      Color tone,
      String message,
    ) = switch (result.outcome) {
      CheckInOutcome.checkedIn => (
        Icons.check_circle_outline,
        Colors.green.shade700,
        '${guestName ?? "Guest"} is checked in.',
      ),
      CheckInOutcome.alreadyCheckedIn => (
        Icons.warning_amber_outlined,
        Colors.amber.shade800,
        '${guestName ?? "This guest"} was already checked in.',
      ),
      CheckInOutcome.waitlisted => (
        Icons.warning_amber_outlined,
        Colors.amber.shade800,
        '${guestName ?? "This guest"} is on the waitlist, not confirmed — cannot check in.',
      ),
      CheckInOutcome.cancelled => (
        Icons.cancel_outlined,
        Theme.of(context).colorScheme.error,
        '${guestName ?? "This booking"} was cancelled.',
      ),
      CheckInOutcome.notFound => (
        Icons.cancel_outlined,
        Theme.of(context).colorScheme.error,
        'No booking found for this code at this event.',
      ),
    };

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: tone, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message, style: TextStyle(color: tone)),
          ),
        ],
      ),
    );
  }
}
