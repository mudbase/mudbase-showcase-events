import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../models/event.dart';
import '../../widgets/async_value_view.dart';
import 'event_detail_controller.dart';
import 'events_controller.dart';

/// Create-or-edit form for an event - which mode it's in is determined by
/// whether [eventId] is present, mirroring the reference web app's separate
/// `/events/new` and `/events/[id]/edit` pages sharing one `EventForm`
/// component. Organizer-only; the router only ever routes here for an
/// organizer viewing (for edit) their own event - see `router/app_router.dart`.
class EventFormScreen extends ConsumerStatefulWidget {
  const EventFormScreen({this.eventId, super.key});

  final String? eventId;

  bool get isEditing => eventId != null;

  @override
  ConsumerState<EventFormScreen> createState() => _EventFormScreenState();
}

class _EventFormScreenState extends ConsumerState<EventFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _locationController = TextEditingController();
  final _capacityController = TextEditingController(text: '20');
  DateTime? _startsAt;
  bool _submitting = false;
  String? _error;
  bool _prefilled = false;

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _locationController.dispose();
    _capacityController.dispose();
    super.dispose();
  }

  void _prefillFrom(EventDoc event) {
    if (_prefilled) return;
    _prefilled = true;
    _titleController.text = event.title;
    _descriptionController.text = event.description ?? '';
    _locationController.text = event.location;
    _capacityController.text = event.capacity.toString();
    _startsAt = event.startsAt;
  }

  Future<void> _pickStartsAt() async {
    final now = DateTime.now();
    final initialDate = _startsAt ?? now.add(const Duration(days: 1));
    final date = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now.add(const Duration(days: 365 * 3)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initialDate),
    );
    if (time == null) return;
    setState(() {
      _startsAt = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_startsAt == null) {
      setState(() => _error = 'Pick a date and time.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });

    final title = _titleController.text.trim();
    final description = _descriptionController.text.trim();
    final location = _locationController.text.trim();
    final capacity = int.parse(_capacityController.text.trim());

    try {
      if (widget.isEditing) {
        await ref
            .read(eventDetailControllerProvider(widget.eventId!).notifier)
            .updateEvent(
              title: title,
              description: description.isEmpty ? null : description,
              startsAt: _startsAt!,
              location: location,
              capacity: capacity,
            );
        if (mounted) context.pop();
      } else {
        final created = await ref
            .read(eventsListControllerProvider.notifier)
            .createEvent(
              title: title,
              description: description.isEmpty ? null : description,
              startsAt: _startsAt!,
              location: location,
              capacity: capacity,
            );
        if (mounted) context.pushReplacement('/events/${created.id}');
      }
    } on Object catch (error) {
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEditing ? 'Edit event' : 'New event'),
      ),
      body: widget.isEditing ? _buildEditingBody() : _buildForm(),
    );
  }

  Widget _buildEditingBody() {
    final detailState = ref.watch(
      eventDetailControllerProvider(widget.eventId!),
    );
    return AsyncValueView<EventDetailData>(
      value: detailState,
      onRetry: () =>
          ref.invalidate(eventDetailControllerProvider(widget.eventId!)),
      data: (context, data) {
        _prefillFrom(data.event);
        return _buildForm();
      },
    );
  }

  Widget _buildForm() {
    final dateLabel = _startsAt == null
        ? 'Pick a date and time'
        : DateFormat('MMM d, y • h:mm a').format(_startsAt!);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.isEditing)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'Changes to capacity are re-checked against existing bookings.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'Set a capacity — bookings beyond it are automatically waitlisted.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            if (_error != null) ...[
              _ErrorBanner(message: _error!),
              const SizedBox(height: 12),
            ],
            TextFormField(
              controller: _titleController,
              decoration: const InputDecoration(labelText: 'Title'),
              maxLength: 200,
              validator: (value) => (value == null || value.trim().isEmpty)
                  ? 'Title is required'
                  : null,
            ),
            TextFormField(
              controller: _descriptionController,
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
              ),
              maxLength: 2000,
              maxLines: 4,
            ),
            const SizedBox(height: 8),
            InkWell(
              onTap: _pickStartsAt,
              borderRadius: BorderRadius.circular(12),
              child: InputDecorator(
                decoration: const InputDecoration(labelText: 'Date & time'),
                child: Text(dateLabel),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _capacityController,
              decoration: const InputDecoration(labelText: 'Capacity'),
              keyboardType: TextInputType.number,
              validator: (value) {
                final parsed = int.tryParse(value?.trim() ?? '');
                if (parsed == null) return 'Capacity must be a whole number';
                if (parsed < 1) return 'Capacity must be at least 1';
                if (parsed > 100000) return 'Capacity is unrealistically large';
                return null;
              },
            ),
            TextFormField(
              controller: _locationController,
              decoration: const InputDecoration(labelText: 'Location'),
              maxLength: 200,
              validator: (value) => (value == null || value.trim().isEmpty)
                  ? 'Location is required'
                  : null,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _submitting ? null : _submit,
              child: _submitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(widget.isEditing ? 'Save changes' : 'Create event'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        message,
        style: TextStyle(color: colorScheme.onErrorContainer),
      ),
    );
  }
}
