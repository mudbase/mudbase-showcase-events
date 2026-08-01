import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/mudbase_exception.dart';
import '../../widgets/async_value_view.dart';
import '../../widgets/empty_state.dart';
import 'my_bookings_controller.dart';
import 'widgets/booking_card.dart';

/// The signed-in attendee's own bookings across every event - mirrors the
/// reference web app's `/bookings` page.
class MyBookingsScreen extends ConsumerStatefulWidget {
  const MyBookingsScreen({super.key});

  @override
  ConsumerState<MyBookingsScreen> createState() => _MyBookingsScreenState();
}

class _MyBookingsScreenState extends ConsumerState<MyBookingsScreen> {
  String? _cancellingBookingId;

  Future<void> _cancel(BookingWithEvent item) async {
    setState(() => _cancellingBookingId = item.booking.id);
    try {
      await ref.read(myBookingsControllerProvider.notifier).cancelBooking(item);
    } on MudbaseException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _cancellingBookingId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bookingsState = ref.watch(myBookingsControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('My bookings')),
      body: RefreshIndicator(
        onRefresh: () =>
            ref.read(myBookingsControllerProvider.notifier).refresh(),
        child: AsyncValueView<List<BookingWithEvent>>(
          value: bookingsState,
          onRetry: () => ref.invalidate(myBookingsControllerProvider),
          data: (context, items) {
            if (items.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 120),
                  EmptyState(
                    icon: Icons.confirmation_num_outlined,
                    message: "You haven't booked anything yet.",
                  ),
                ],
              );
            }
            return ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              itemCount: items.length,
              separatorBuilder: (context, index) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final item = items[index];
                return BookingCard(
                  item: item,
                  busy: _cancellingBookingId == item.booking.id,
                  onCancel: () => _cancel(item),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
