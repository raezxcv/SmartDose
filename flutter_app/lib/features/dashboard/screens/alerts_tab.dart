import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class PatientAlertsTab extends StatefulWidget {
  final VoidCallback? onMarkAllRead;
  final bool showAppBar;
  final String? patientUid;

  const PatientAlertsTab({
    super.key,
    this.onMarkAllRead,
    this.showAppBar = true,
    this.patientUid,
  });

  @override
  State<PatientAlertsTab> createState() => _PatientAlertsTabState();
}

class _PatientAlertsTabState extends State<PatientAlertsTab> {
  String? get _uid => widget.patientUid ?? FirebaseAuth.instance.currentUser?.uid;

  Stream<QuerySnapshot<Map<String, dynamic>>>? get _notificationsStream {
    final uid = _uid;
    if (uid == null) return null;
    return FirebaseFirestore.instance
        .collection('notifications')
        .doc(uid)
        .collection('items')
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  Future<void> _markSingleRead(String docId) async {
    final uid = _uid;
    if (uid == null) return;
    await FirebaseFirestore.instance
        .collection('notifications')
        .doc(uid)
        .collection('items')
        .doc(docId)
        .update({'isRead': true});
  }

  Future<void> _markAllReadInternal() async {
    if (widget.onMarkAllRead != null) {
      widget.onMarkAllRead!();
      return;
    }
    final uid = _uid;
    if (uid == null) return;
    final batch = FirebaseFirestore.instance.batch();
    final unreadDocs = await FirebaseFirestore.instance
        .collection('notifications')
        .doc(uid)
        .collection('items')
        .where('isRead', isEqualTo: false)
        .get();

    for (var doc in unreadDocs.docs) {
      batch.update(doc.reference, {'isRead': true});
    }
    await batch.commit();
  }

  String _formatTimestamp(dynamic createdAt) {
    if (createdAt == null) return 'Just now';
    DateTime dt;
    if (createdAt is Timestamp) {
      dt = createdAt.toDate();
    } else {
      return 'Just now';
    }
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'Yesterday, ${DateFormat('hh:mm a').format(dt)}';
    if (diff.inDays < 7) return '${diff.inDays} days ago';
    return DateFormat('MMM d, hh:mm a').format(dt);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cardBgColor = theme.cardTheme.color ?? theme.colorScheme.surface;
    final primaryTextColor = theme.colorScheme.onSurface;
    final secondaryTextColor = primaryTextColor.withValues(alpha: 0.65);

    final content = StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _notificationsStream,
      builder: (context, snapshot) {
        final docs = snapshot.data?.docs ?? [];
        final unreadCount = docs.where((d) => !(d.data()['isRead'] as bool? ?? false)).length;

        return SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Notifications',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                          color: primaryTextColor,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        unreadCount > 0
                            ? '$unreadCount unread alert${unreadCount == 1 ? '' : 's'}'
                            : 'All caught up!',
                        style: TextStyle(fontSize: 15, color: secondaryTextColor),
                      ),
                    ],
                  ),
                  if (unreadCount > 0)
                    GestureDetector(
                      onTap: _markAllReadInternal,
                      child: const Text(
                        'Mark all read',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF00A36C)),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              if (docs.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(40),
                  decoration: BoxDecoration(color: cardBgColor, borderRadius: BorderRadius.circular(24)),
                  child: Column(
                    children: [
                      Icon(LucideIcons.bell, size: 48, color: secondaryTextColor.withValues(alpha: 0.4)),
                      const SizedBox(height: 16),
                      Text('No notifications yet',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: primaryTextColor)),
                      const SizedBox(height: 8),
                      Text('Dispensing events, missed doses, and low stock alerts will appear here.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 14, color: secondaryTextColor)),
                    ],
                  ),
                )
              else
                Column(
                  children: docs.map((doc) {
                    final data = doc.data();
                    final docId = doc.id;
                    final title = data['title'] as String? ?? 'Alert';
                    final body = data['body'] ?? data['desc'] ?? '';
                    final type = data['type'] as String? ?? 'info';
                    final isRead = data['isRead'] as bool? ?? false;
                    final createdAt = data['createdAt'];
                    final timeStr = _formatTimestamp(createdAt);

                    Color color;
                    Color bgColor;
                    IconData icon;

                    switch (type) {
                      case 'missed':
                        color = const Color(0xFFEF4444);
                        bgColor = isDark ? const Color(0xFF7F1D1D) : const Color(0xFFFEE2E2);
                        icon = LucideIcons.xCircle;
                        break;
                      case 'stock':
                        color = const Color(0xFFF59E0B);
                        bgColor = isDark ? const Color(0xFF78350F) : const Color(0xFFFEF3C7);
                        icon = LucideIcons.package;
                        break;
                      case 'device':
                        color = const Color(0xFF10B981);
                        bgColor = isDark ? const Color(0xFF064E3B) : const Color(0xFFD1FAE5);
                        icon = LucideIcons.wifi;
                        break;
                      case 'emergency':
                        color = const Color(0xFFEF4444);
                        bgColor = isDark ? const Color(0xFF7F1D1D) : const Color(0xFFFEE2E2);
                        icon = LucideIcons.siren;
                        break;
                      case 'taken':
                        color = const Color(0xFF10B981);
                        bgColor = isDark ? const Color(0xFF064E3B) : const Color(0xFFD1FAE5);
                        icon = LucideIcons.checkCircle;
                        break;
                      default: // 'ready', 'info', etc.
                        color = const Color(0xFF10B981);
                        bgColor = isDark ? const Color(0xFF064E3B) : const Color(0xFFD1FAE5);
                        icon = LucideIcons.bell;
                    }

                    final unreadCardBg = isDark ? const Color(0xFF1E293B) : const Color(0xFFF0FDF9);
                    final readCardBg = isDark ? const Color(0xFF1E293B) : Colors.white;

                    return GestureDetector(
                      onTap: () {
                        if (!isRead) _markSingleRead(docId);
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.only(bottom: 14),
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: isRead ? readCardBg : unreadCardBg,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: isRead ? theme.dividerColor : const Color(0xFF00A36C).withValues(alpha: 0.5),
                            width: isRead ? 1 : 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 46,
                              height: 46,
                              decoration: BoxDecoration(color: bgColor, shape: BoxShape.circle),
                              child: Icon(icon, color: color, size: 22),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          title,
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: isRead ? FontWeight.w600 : FontWeight.bold,
                                            color: primaryTextColor,
                                          ),
                                        ),
                                      ),
                                      if (!isRead)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: isDark ? const Color(0xFF064E3B) : const Color(0xFFD1FAE5),
                                            borderRadius: BorderRadius.circular(10),
                                          ),
                                          child: const Text(
                                            'New',
                                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF00A36C)),
                                          ),
                                        ),
                                    ],
                                  ),
                                  if (body.isNotEmpty) ...[
                                    const SizedBox(height: 6),
                                    Text(
                                      body,
                                      style: TextStyle(fontSize: 13, height: 1.4, color: secondaryTextColor),
                                    ),
                                  ],
                                  const SizedBox(height: 8),
                                  Text(
                                    timeStr,
                                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: secondaryTextColor.withValues(alpha: 0.8)),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
            ],
          ),
        );
      },
    );

    if (!widget.showAppBar) return content;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: cardBgColor,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: primaryTextColor),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Notifications',
          style: TextStyle(color: primaryTextColor, fontWeight: FontWeight.bold, fontSize: 18),
        ),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.checkCheck, color: Color(0xFF00A36C)),
            onPressed: _markAllReadInternal,
            tooltip: 'Mark all read',
          ),
        ],
      ),
      body: content,
    );
  }
}
