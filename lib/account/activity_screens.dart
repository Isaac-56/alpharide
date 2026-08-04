import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../models/ride_option.dart';
import '../services/firestore_service.dart';
import 'account_ui.dart';

class NotificationsScreen extends StatelessWidget {
  final String phoneNumber;
  final FirestoreService firestoreService;

  const NotificationsScreen({
    super.key,
    required this.phoneNumber,
    required this.firestoreService,
  });

  @override
  Widget build(BuildContext context) {
    return AlphaPageScaffold(
      title: 'Notifications',
      scrollable: false,
      child: StreamBuilder<List<Map<String, dynamic>>>(
        stream: firestoreService.watchNotifications(phoneNumber),
        builder: (
          BuildContext context,
          AsyncSnapshot<List<Map<String, dynamic>>> snapshot,
        ) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: AlphaColors.primary),
            );
          }

          if (snapshot.hasError) {
            return const AlphaEmptyState(
              icon: Icons.cloud_off_outlined,
              title: 'Notifications are unavailable',
              message: 'Check your connection and open this page again.',
            );
          }

          final List<Map<String, dynamic>> notifications =
              snapshot.data ?? <Map<String, dynamic>>[];

          if (notifications.isEmpty) {
            return const AlphaEmptyState(
              icon: Icons.notifications_none_rounded,
              title: 'You are all caught up',
              message:
                  'Ride updates, account notices, and important AlphaRide news will appear here.',
            );
          }

          return ListView.separated(
            itemCount: notifications.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (BuildContext context, int index) {
              final Map<String, dynamic> notification = notifications[index];

              return _NotificationCard(
                data: notification,
                onTap: () async {
                  final String? id = notification['id']?.toString();

                  if (id != null && notification['isRead'] != true) {
                    await firestoreService.markNotificationRead(
                      phoneNumber,
                      id,
                    );
                  }

                  if (!context.mounted) return;
                  _showNotification(context, notification);
                },
              );
            },
          );
        },
      ),
    );
  }

  void _showNotification(
    BuildContext context,
    Map<String, dynamic> notification,
  ) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (BuildContext sheetContext) {
        return SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.fromLTRB(22, 12, 22, 28),
            decoration: BoxDecoration(
              color: AlphaColors.surface(sheetContext),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(26),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Align(
                  alignment: Alignment.center,
                  child: Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AlphaColors.border(sheetContext),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  notification['title']?.toString() ?? 'AlphaRide update',
                  style: TextStyle(
                    color: AlphaColors.text(sheetContext),
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  notification['message']?.toString() ??
                      'Open AlphaRide for more information.',
                  style: TextStyle(
                    color: AlphaColors.muted(sheetContext),
                    fontSize: 15,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 22),
                AlphaPrimaryButton(
                  label: 'Got it',
                  onPressed: () => Navigator.pop(sheetContext),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _NotificationCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final VoidCallback onTap;

  const _NotificationCard({
    required this.data,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bool unread = data['isRead'] != true;
    final Timestamp? timestamp = data['createdAt'] as Timestamp?;
    final DateTime? date = timestamp?.toDate();

    return Material(
      color: AlphaColors.surface(context),
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: unread
                  ? AlphaColors.primary.withValues(alpha: 0.48)
                  : AlphaColors.border(context),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                width: 46,
                height: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AlphaColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.notifications_active_outlined,
                  color: AlphaColors.primary,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            data['title']?.toString() ?? 'AlphaRide update',
                            style: TextStyle(
                              color: AlphaColors.text(context),
                              fontSize: 15.5,
                              fontWeight:
                                  unread ? FontWeight.w800 : FontWeight.w700,
                            ),
                          ),
                        ),
                        if (unread)
                          Container(
                            width: 9,
                            height: 9,
                            decoration: const BoxDecoration(
                              color: AlphaColors.primary,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      data['message']?.toString() ?? 'Open to see this update.',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AlphaColors.muted(context),
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                    if (date != null) ...<Widget>[
                      const SizedBox(height: 8),
                      Text(
                        _compactDate(date),
                        style: TextStyle(
                          color: AlphaColors.muted(context),
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class OrderHistoryScreen extends StatefulWidget {
  final String phoneNumber;
  final FirestoreService firestoreService;

  const OrderHistoryScreen({
    super.key,
    required this.phoneNumber,
    required this.firestoreService,
  });

  @override
  State<OrderHistoryScreen> createState() => _OrderHistoryScreenState();
}

class _OrderHistoryScreenState extends State<OrderHistoryScreen> {
  _OrderFilter _filter = _OrderFilter.all;

  @override
  Widget build(BuildContext context) {
    return AlphaPageScaffold(
      title: 'My orders',
      scrollable: false,
      child: Column(
        children: <Widget>[
          SizedBox(
            height: 42,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: _OrderFilter.values.map(
                (_OrderFilter filter) {
                  final bool selected = _filter == filter;

                  return Padding(
                    padding: const EdgeInsets.only(right: 9),
                    child: ChoiceChip(
                      selected: selected,
                      label: Text(filter.label),
                      onSelected: (_) => setState(() => _filter = filter),
                      selectedColor: AlphaColors.primary,
                      backgroundColor: AlphaColors.surface(context),
                      side: BorderSide(
                        color: selected
                            ? AlphaColors.primary
                            : AlphaColors.border(context),
                      ),
                      labelStyle: TextStyle(
                        color: selected
                            ? AlphaColors.ink
                            : AlphaColors.text(context),
                        fontWeight: FontWeight.w700,
                      ),
                      showCheckmark: false,
                    ),
                  );
                },
              ).toList(growable: false),
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: widget.firestoreService.watchOrders(widget.phoneNumber),
              builder: (
                BuildContext context,
                AsyncSnapshot<List<Map<String, dynamic>>> snapshot,
              ) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(
                      color: AlphaColors.primary,
                    ),
                  );
                }

                if (snapshot.hasError) {
                  return const AlphaEmptyState(
                    icon: Icons.cloud_off_outlined,
                    title: 'Order history is unavailable',
                    message: 'Check your connection and open this page again.',
                  );
                }

                final List<Map<String, dynamic>> allOrders =
                    snapshot.data ?? <Map<String, dynamic>>[];
                final List<Map<String, dynamic>> visibleOrders = allOrders
                    .where((Map<String, dynamic> order) => _filter.matches(
                          order['status']?.toString() ?? '',
                        ))
                    .toList(growable: false);

                if (visibleOrders.isEmpty) {
                  return AlphaEmptyState(
                    icon: Icons.route_outlined,
                    title: _filter == _OrderFilter.all
                        ? 'No rides yet'
                        : 'No ${_filter.label.toLowerCase()} rides',
                    message: _filter == _OrderFilter.all
                        ? 'Completed and cancelled AlphaRide trips will appear here.'
                        : 'Trips matching this filter will appear here.',
                  );
                }

                return ListView.separated(
                  itemCount: visibleOrders.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 14),
                  itemBuilder: (BuildContext context, int index) {
                    return _OrderCard(order: visibleOrders[index]);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

enum _OrderFilter {
  all('All'),
  completed('Completed'),
  cancelled('Cancelled');

  final String label;

  const _OrderFilter(this.label);

  bool matches(String status) {
    final String normalized = status.toLowerCase();

    return switch (this) {
      _OrderFilter.all => true,
      _OrderFilter.completed => normalized == 'completed',
      _OrderFilter.cancelled => normalized.contains('cancel'),
    };
  }
}

class _OrderCard extends StatelessWidget {
  final Map<String, dynamic> order;

  const _OrderCard({required this.order});

  @override
  Widget build(BuildContext context) {
    final String status = order['status']?.toString() ?? 'Completed';
    final String normalizedStatus = status.toLowerCase();
    final bool cancelled = normalizedStatus.contains('cancel');
    final int? fare = (order['fare'] as num?)?.round();
    final Timestamp? timestamp = order['createdAt'] as Timestamp?;
    final DateTime? createdAt = timestamp?.toDate();

    return Container(
      decoration: BoxDecoration(
        color: AlphaColors.surface(context),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AlphaColors.border(context)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: <Widget>[
          SizedBox(
            height: 132,
            width: double.infinity,
            child: CustomPaint(
              painter: _RoutePreviewPainter(
                background: Theme.of(context).brightness == Brightness.dark
                    ? const Color(0xFF1A1D1A)
                    : const Color(0xFFEFF3EF),
                road: Theme.of(context).brightness == Brightness.dark
                    ? const Color(0xFF343934)
                    : const Color(0xFFD6DDD6),
              ),
              child: const Stack(
                children: <Widget>[
                  Positioned(
                    left: 30,
                    bottom: 22,
                    child: _MapPoint(label: 'A', highlighted: false),
                  ),
                  Positioned(
                    right: 36,
                    top: 20,
                    child: _MapPoint(label: 'B', highlighted: true),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            _statusLabel(status),
                            style: TextStyle(
                              color: cancelled
                                  ? AlphaColors.danger
                                  : AlphaColors.text(context),
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          if (createdAt != null) ...<Widget>[
                            const SizedBox(height: 3),
                            Text(
                              _fullDate(createdAt),
                              style: TextStyle(
                                color: AlphaColors.muted(context),
                                fontSize: 12.5,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (fare != null)
                      Text(
                        '${RideOption.formatAmount(fare)} SSP',
                        style: TextStyle(
                          color: AlphaColors.text(context),
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                _AddressLine(
                  label: 'A',
                  address: order['pickupAddress']?.toString() ??
                      'Pickup location unavailable',
                  highlighted: false,
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 13),
                  child: Container(
                    width: 1,
                    height: 14,
                    color: AlphaColors.border(context),
                  ),
                ),
                _AddressLine(
                  label: 'B',
                  address: order['destinationAddress']?.toString() ??
                      'Destination unavailable',
                  highlighted: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RoutePreviewPainter extends CustomPainter {
  final Color background;
  final Color road;

  const _RoutePreviewPainter({
    required this.background,
    required this.road,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = background);

    final Paint roadPaint = Paint()
      ..color = road
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;

    final List<Path> roads = <Path>[
      Path()
        ..moveTo(-20, size.height * 0.25)
        ..cubicTo(
          size.width * 0.22,
          size.height * 0.08,
          size.width * 0.45,
          size.height * 0.65,
          size.width + 20,
          size.height * 0.38,
        ),
      Path()
        ..moveTo(size.width * 0.16, -10)
        ..cubicTo(
          size.width * 0.24,
          size.height * 0.3,
          size.width * 0.18,
          size.height * 0.72,
          size.width * 0.38,
          size.height + 10,
        ),
      Path()
        ..moveTo(size.width * 0.7, -10)
        ..cubicTo(
          size.width * 0.56,
          size.height * 0.35,
          size.width * 0.86,
          size.height * 0.72,
          size.width * 0.78,
          size.height + 10,
        ),
    ];

    for (final Path path in roads) {
      canvas.drawPath(path, roadPaint);
    }

    final Paint routePaint = Paint()
      ..color = AlphaColors.primary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;

    canvas.drawPath(
      Path()
        ..moveTo(42, size.height - 30)
        ..cubicTo(
          size.width * 0.28,
          size.height * 0.75,
          size.width * 0.55,
          size.height * 0.22,
          size.width - 48,
          32,
        ),
      routePaint,
    );
  }

  @override
  bool shouldRepaint(_RoutePreviewPainter oldDelegate) =>
      oldDelegate.background != background || oldDelegate.road != road;
}

class _MapPoint extends StatelessWidget {
  final String label;
  final bool highlighted;

  const _MapPoint({
    required this.label,
    required this.highlighted,
  });

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: 17,
      backgroundColor: highlighted ? AlphaColors.primary : Colors.white,
      child: Text(
        label,
        style: const TextStyle(
          color: AlphaColors.ink,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _AddressLine extends StatelessWidget {
  final String label;
  final String address;
  final bool highlighted;

  const _AddressLine({
    required this.label,
    required this.address,
    required this.highlighted,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _MapPoint(label: label, highlighted: highlighted),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              address,
              style: TextStyle(
                color: AlphaColors.text(context),
                fontSize: 14,
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class InviteFriendsScreen extends StatelessWidget {
  const InviteFriendsScreen({super.key});

  Future<void> _share(BuildContext context) async {
    final RenderBox? box = context.findRenderObject() as RenderBox?;

    try {
      await SharePlus.instance.share(
        ShareParams(
          title: 'AlphaRide South Sudan',
          subject: 'Ride with AlphaRide',
          text:
              'Try AlphaRide for simple, reliable rides across South Sudan. AlphaRide passenger app is launching soon.',
          sharePositionOrigin:
              box == null ? null : box.localToGlobal(Offset.zero) & box.size,
        ),
      );
    } catch (error) {
      if (!context.mounted) return;
      showAlphaMessage(
        context,
        'Unable to open sharing on this device.',
        error: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlphaPageScaffold(
      title: 'Invite friends',
      child: Builder(
        builder: (BuildContext buttonContext) {
          return Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: AlphaColors.surface(context),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: AlphaColors.border(context)),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 24,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 42, 24, 36),
                  child: Column(
                    children: <Widget>[
                      Stack(
                        alignment: Alignment.center,
                        children: <Widget>[
                          Container(
                            width: 120,
                            height: 120,
                            decoration: BoxDecoration(
                              color:
                                  AlphaColors.primary.withValues(alpha: 0.12),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const Icon(
                            Icons.group_add_rounded,
                            color: AlphaColors.primary,
                            size: 58,
                          ),
                        ],
                      ),
                      const SizedBox(height: 26),
                      Text(
                        'Bring your people along',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AlphaColors.text(context),
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 9),
                      Text(
                        'Share AlphaRide with friends and family who need a simpler way to move around South Sudan.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AlphaColors.muted(context),
                          fontSize: 14,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  width: double.infinity,
                  height: 58,
                  child: ElevatedButton.icon(
                    onPressed: () => _share(buttonContext),
                    icon: const Icon(Icons.share_rounded),
                    label: const Text('Share AlphaRide'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AlphaColors.primary,
                      foregroundColor: AlphaColors.ink,
                      elevation: 0,
                      shape: const RoundedRectangleBorder(),
                      textStyle: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

String _statusLabel(String status) {
  if (status.trim().isEmpty) return 'Completed';

  return status
      .replaceAll('_', ' ')
      .split(' ')
      .where((String part) => part.isNotEmpty)
      .map(
        (String part) =>
            '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}',
      )
      .join(' ');
}

String _compactDate(DateTime date) {
  const List<String> months = <String>[
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  return '${months[date.month - 1]} ${date.day}, ${date.year}';
}

String _fullDate(DateTime date) {
  final int hour = date.hour == 0
      ? 12
      : date.hour > 12
          ? date.hour - 12
          : date.hour;
  final String minute = date.minute.toString().padLeft(2, '0');
  final String period = date.hour >= 12 ? 'PM' : 'AM';

  return '${_compactDate(date)} • $hour:$minute $period';
}
