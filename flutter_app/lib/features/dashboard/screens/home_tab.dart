import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'compartment_inventory_screen.dart';
import 'camera_feed_screen.dart';
import 'device_connected_screen.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:smartdose/shared/widgets/smartdose_loading.dart';
import '../../pairing/screens/emergency_contacts_screen.dart';

class PatientHomeTab extends StatefulWidget {
  final String displayName;
  final String userInitials;
  final VoidCallback onGoToMeds;
  final VoidCallback onGoToHistory;
  final VoidCallback onGoToAlerts;
  final VoidCallback onGoToProfile;
  final int unreadCount;

  const PatientHomeTab({
    super.key,
    required this.displayName,
    required this.userInitials,
    required this.onGoToMeds,
    required this.onGoToHistory,
    required this.onGoToAlerts,
    required this.onGoToProfile,
    required this.unreadCount,
  });

  @override
  State<PatientHomeTab> createState() => _PatientHomeTabState();
}

class _PatientHomeTabState extends State<PatientHomeTab> {
  Timer? _countdownTimer;
  Map<String, dynamic>? _nextMed;
  bool _dispatchingEmergency = false;
  StreamSubscription? _deviceSub;
  String? _deviceId;

  Stream<QuerySnapshot<Map<String, dynamic>>>? _schedulesStream;
  Stream<QuerySnapshot<Map<String, dynamic>>>? _todayLogsStream;
  Stream<QuerySnapshot<Map<String, dynamic>>>? _compartmentsStream;
  Stream<DocumentSnapshot<Map<String, dynamic>>>? _userDocStream;

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  @override
  void initState() {
    super.initState();
    _initStreams();
    _startCountdown();
    _initDeviceStream();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _deviceSub?.cancel();
    super.dispose();
  }

  Future<void> _initDeviceStream() async {
    final uid = _uid;
    if (uid == null) return;
    try {
      final userDoc =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final deviceId = userDoc.data()?['deviceId'] as String?;
      if (deviceId == null || !mounted) return;
      setState(() => _deviceId = deviceId);
      _deviceSub = FirebaseFirestore.instance
          .collection('devices')
          .doc(deviceId)
          .snapshots()
          .listen((snap) {
        if (mounted) setState(() {});
      });
    } catch (_) {}
  }

  void _startCountdown() {
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_nextMed != null && mounted) setState(() {});
    });
  }

  void _initStreams() {
    final uid = _uid;
    if (uid == null) return;
    _schedulesStream = FirebaseFirestore.instance
        .collection('schedules')
        .where('patientUid', isEqualTo: uid)
        .snapshots();
    _todayLogsStream = FirebaseFirestore.instance
        .collection('dispensingLogs')
        .where('patientUid', isEqualTo: uid)
        .snapshots();
    _compartmentsStream = FirebaseFirestore.instance
        .collection('compartments')
        .where('patientUid', isEqualTo: uid)
        .snapshots();
    _userDocStream =
        FirebaseFirestore.instance.collection('users').doc(uid).snapshots();
  }

  String get _greeting {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  String _formatCountdown(Duration d) {
    if (d == Duration.zero) return 'Due now';
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    if (h > 0) return 'In ${h}h ${m}m';
    if (m > 0) return 'In ${m}m ${s}s';
    return 'In ${s}s';
  }

  Future<void> _onEmergencyDispense() async {
    final uid = _uid;
    if (uid == null) return;
    setState(() => _dispatchingEmergency = true);
    try {
      if (_deviceId != null) {
        try {
          await FirebaseFirestore.instance
              .collection('devices')
              .doc(_deviceId)
              .update({
            'emergencyDispense': true,
            'emergencyRequestedAt': FieldValue.serverTimestamp(),
            'emergencyRequestedBy': uid,
          });
        } catch (e) {
          debugPrint('Device status update warning: $e');
        }
      }

      // Queue SMS alerts to all contacts for SIM800L module
      await _dispatchSmsAlertsToContacts(
        message:
            'EMERGENCY ALERT: Emergency dispense triggered by ${widget.displayName}. — SmartDose SIM800L',
        triggeredBy: 'emergency',
      );

      // Add emergency request record
      await FirebaseFirestore.instance.collection('emergencyRequests').add({
        'patientId': uid,
        'patientUid': uid,
        'initiatedBy': 'patient',
        'status': 'pending',
        'requestedAt': FieldValue.serverTimestamp(),
      });

      // Add to dispensing logs for history
      await FirebaseFirestore.instance.collection('dispensingLogs').add({
        'patientUid': uid,
        'patientId': uid,
        'medicationName': 'Emergency Request',
        'type': 'emergency',
        'status': 'requested',
        'timestamp': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
      });

      // Add notification item
      try {
        await FirebaseFirestore.instance
            .collection('notifications')
            .doc(uid)
            .collection('items')
            .add({
          'title': 'Emergency dispense requested',
          'body': 'An emergency dispense request was sent to the device.',
          'type': 'emergency',
          'isRead': false,
          'createdAt': FieldValue.serverTimestamp(),
        });
      } catch (e) {
        debugPrint('Notification add warning: $e');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.emergency_rounded, color: Colors.white, size: 18),
                SizedBox(width: 10),
                Text('Emergency dispense signal sent!'),
              ],
            ),
            backgroundColor: const Color(0xFFDC2626),
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error triggering emergency dispense: $e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _dispatchingEmergency = false);
    }
  }

  Future<void> _dispatchSmsAlertsToContacts({
    required String message,
    required String triggeredBy,
  }) async {
    final uid = _uid;
    if (uid == null) return;
    try {
      final contactsSnap = await FirebaseFirestore.instance
          .collection('contacts')
          .where('patientUid', isEqualTo: uid)
          .get();

      for (final doc in contactsSnap.docs) {
        final data = doc.data();
        final phone = data['phone'] as String? ?? '';
        final name = data['name'] as String? ?? 'Contact';
        if (phone.isNotEmpty) {
          await FirebaseFirestore.instance.collection('sms_queue').add({
            'patientUid': uid,
            'patientName': widget.displayName,
            'to': phone,
            'contactName': name,
            'message': message,
            'status': 'pending',
            'triggeredBy': triggeredBy,
            'createdAt': FieldValue.serverTimestamp(),
          });
        }
      }
    } catch (e) {
      debugPrint('SMS queue dispatch warning: $e');
    }
  }

  Future<void> _onDispenseNow(Map<String, dynamic> med) async {
    final uid = _uid;
    if (uid == null) return;
    try {
      final compStr = (med['compartment'] ?? 'C1').toString();
      final slotMatch = RegExp(r'\d+').firstMatch(compStr);
      final slotNum = slotMatch != null ? int.tryParse(slotMatch.group(0)!) ?? 1 : 1;

      if (_deviceId != null) {
        await FirebaseFirestore.instance
            .collection('devices')
            .doc(_deviceId)
            .update({
          'dispenseTriggerSlot': slotNum,
          'pendingDispense': {
            'compartment': 'C$slotNum',
            'medicationName': med['medicationName'] ?? '',
            'requestedAt': FieldValue.serverTimestamp(),
            'requestedBy': uid,
          },
        });
      }

      // Direct Realtime Database Hardware Trigger to ESP32
      final url = Uri.parse(
          'https://smart-pill-dispenser-baa02-default-rtdb.firebaseio.com/hardware/dispense_trigger.json');
      await http.put(url, body: jsonEncode(slotNum));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Hardware dispense signal sent for Slot C$slotNum (${med['medicationName']})!'),
            backgroundColor: const Color(0xFF00A36C),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
        );
      }
    } catch (e) {
      debugPrint('Dispense trigger error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _schedulesStream,
      builder: (context, schedSnap) {
        final allSchedDocs = schedSnap.data?.docs ?? [];
        final now = DateTime.now();
        final todayStart = DateTime(now.year, now.month, now.day);
        final todayEnd = todayStart.add(const Duration(days: 1));

        final schedDocs = allSchedDocs.where((doc) {
          final data = doc.data();
          if ((data['isActive'] ?? true) != true) return false;
          final ts = data['scheduledTime'] as Timestamp?;
          if (ts == null) return false;
          final schedDate = ts.toDate();
          final schedDay =
              DateTime(schedDate.year, schedDate.month, schedDate.day);

          if (todayStart.isBefore(schedDay)) return false;

          final freq =
              (data['frequency'] as String? ?? 'Daily').trim().toLowerCase();
          if (freq == 'daily') {
            return true;
          } else if (freq == 'weekly') {
            return todayStart.weekday == schedDay.weekday;
          } else {
            return todayStart.year == schedDay.year &&
                todayStart.month == schedDay.month &&
                todayStart.day == schedDay.day;
          }
        }).toList();

        schedDocs.sort((a, b) {
          final tsA = a.data()['scheduledTime'] as Timestamp?;
          final tsB = b.data()['scheduledTime'] as Timestamp?;
          if (tsA == null || tsB == null) return 0;
          return tsA.compareTo(tsB);
        });

        // Find next upcoming medication whose scheduled time is strictly in the future
        Map<String, dynamic>? upcomingMed;
        for (final doc in schedDocs) {
          final data = doc.data();
          final ts = data['scheduledTime'] as Timestamp?;
          if (ts != null) {
            final t = ts.toDate();
            final todayTime =
                DateTime(now.year, now.month, now.day, t.hour, t.minute);
            if (todayTime.isAfter(now)) {
              upcomingMed = {
                ...data,
                'id': doc.id,
                'scheduledTime': Timestamp.fromDate(todayTime)
              };
              break;
            }
          }
        }

        if (upcomingMed != null && _nextMed?['id'] != upcomingMed['id']) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _nextMed = upcomingMed);
          });
        } else if (upcomingMed == null && _nextMed != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _nextMed = null);
          });
        }

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _todayLogsStream,
          builder: (context, logsSnap) {
            final allLogsDocs = logsSnap.data?.docs ?? [];
            final logs = allLogsDocs.where((doc) {
              final data = doc.data();
              final ts = data['timestamp'] as Timestamp?;
              if (ts == null) return false;
              final date = ts.toDate();
              return (date.isAfter(
                          todayStart.subtract(const Duration(seconds: 1))) ||
                      date.isAtSameMomentAs(todayStart)) &&
                  date.isBefore(todayEnd);
            }).toList();

            final taken =
                logs.where((d) => d.data()['status'] == 'taken').length;
            final missed =
                logs.where((d) => d.data()['status'] == 'missed').length;
            final total = schedDocs.isEmpty ? 0 : schedDocs.length;
            final progress = total > 0 ? (taken / total).clamp(0.0, 1.0) : 0.0;

            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _compartmentsStream,
              builder: (context, compSnap) {
                final compDocs = compSnap.data?.docs ?? [];
                final lowStockCount = compDocs
                    .where((d) => (d.data()['stockCount'] as int? ?? 0) <= 3)
                    .length;

                return SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildHeader(),
                      const SizedBox(height: 20),
                      if (lowStockCount > 0) ...[
                        _buildLowStockBanner(lowStockCount),
                        const SizedBox(height: 14),
                      ],
                      _buildNextMedCard(upcomingMed),
                      const SizedBox(height: 24),
                      _buildQuickActions(
                          total, compDocs.isEmpty ? 0 : compDocs.length),
                      const SizedBox(height: 24),
                      _buildProgressSection(
                          taken, missed, total, progress, lowStockCount),
                      const SizedBox(height: 24),
                      _buildRecentActivitySection(logs, schedDocs),
                      const SizedBox(height: 20),
                      _buildEmergencyButton(),
                      const SizedBox(height: 16),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  static String _getInitials(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return 'SD';
    final parts =
        trimmed.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (parts.length >= 2) {
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    } else if (parts.isNotEmpty && parts.first.isNotEmpty) {
      return parts.first.length >= 2
          ? parts.first.substring(0, 2).toUpperCase()
          : parts.first[0].toUpperCase();
    }
    return 'SD';
  }

  static const List<List<Color>> _avatarGradients = [
    [Color(0xFF00C882), Color(0xFF00A36C)], // Emerald Mint
    [Color(0xFF06B6D4), Color(0xFF0891B2)], // Ocean Cyan
    [Color(0xFF8B5CF6), Color(0xFF6D28D9)], // Royal Purple
    [Color(0xFFEC4899), Color(0xFFDB2777)], // Vibrant Pink
    [Color(0xFFF43F5E), Color(0xFFE11D48)], // Coral Rose
    [Color(0xFF475569), Color(0xFF1E293B)], // Midnight Slate
  ];

  Widget _buildAvatarImage(String photoVal, String initials, double size) {
    final trimmed = photoVal.trim();
    if (trimmed.isEmpty) {
      return Center(
        child: Text(
          initials,
          style: TextStyle(
              color: Colors.white,
              fontSize: size * 0.38,
              fontWeight: FontWeight.w900),
        ),
      );
    }
    if (trimmed.startsWith('data:image')) {
      try {
        final base64Str =
            trimmed.contains(',') ? trimmed.split(',').last : trimmed;
        final bytes = base64Decode(base64Str);
        return Image.memory(
          bytes,
          width: size,
          height: size,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => Center(
            child: Text(initials,
                style: TextStyle(
                    color: Colors.white,
                    fontSize: size * 0.38,
                    fontWeight: FontWeight.w900)),
          ),
        );
      } catch (_) {}
    }
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return Image.network(
        trimmed,
        width: size,
        height: size,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => Center(
          child: Text(initials,
              style: TextStyle(
                  color: Colors.white,
                  fontSize: size * 0.38,
                  fontWeight: FontWeight.w900)),
        ),
      );
    }
    final file = File(trimmed);
    if (file.existsSync()) {
      return Image.file(
        file,
        width: size,
        height: size,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => Center(
          child: Text(initials,
              style: TextStyle(
                  color: Colors.white,
                  fontSize: size * 0.38,
                  fontWeight: FontWeight.w900)),
        ),
      );
    }
    return Center(
      child: Text(initials,
          style: TextStyle(
              color: Colors.white,
              fontSize: size * 0.38,
              fontWeight: FontWeight.w900)),
    );
  }

  String _cachedHeaderPhotoUrl = '';
  String _cachedHeaderName = '';
  int _cachedAvatarGradIdx = 0;

  Widget _buildHeader() {
    final theme = Theme.of(context);
    final primaryTextColor = theme.colorScheme.onSurface;
    final secondaryTextColor = primaryTextColor.withValues(alpha: 0.65);
    final cardBgColor = theme.cardTheme.color ?? theme.colorScheme.surface;
    final isDark = theme.brightness == Brightness.dark;

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _userDocStream,
      builder: (context, userSnap) {
        if (userSnap.hasData && userSnap.data?.data() != null) {
          final userData = userSnap.data!.data()!;
          _cachedHeaderName = userData['name'] ?? widget.displayName;
          _cachedHeaderPhotoUrl = (userData['photoUrl'] ??
                  userData['profilePhotoUrl'] ??
                  FirebaseAuth.instance.currentUser?.photoURL ??
                  '')
              .toString();
          _cachedAvatarGradIdx = (userData['avatarGradientIndex'] as int? ?? 0)
              .clamp(0, _avatarGradients.length - 1);
        }

        final name = _cachedHeaderName.isNotEmpty
            ? _cachedHeaderName
            : widget.displayName;
        final photoUrl = _cachedHeaderPhotoUrl.isNotEmpty
            ? _cachedHeaderPhotoUrl
            : (FirebaseAuth.instance.currentUser?.photoURL ?? '');
        final initials = _getInitials(name);
        final activeGradient = _avatarGradients[_cachedAvatarGradIdx];

        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _greeting,
                  style: TextStyle(
                      fontSize: 15,
                      color: secondaryTextColor,
                      fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 2),
                Text(
                  name,
                  style: TextStyle(
                      fontSize: 24,
                      color: primaryTextColor,
                      fontWeight: FontWeight.bold),
                ),
              ],
            ),
            Row(
              children: [
                GestureDetector(
                  onTap: widget.onGoToAlerts,
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                        color: cardBgColor,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                              color: Colors.black
                                  .withValues(alpha: isDark ? 0.2 : 0.04),
                              blurRadius: 10)
                        ]),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Icon(LucideIcons.bell,
                            color: primaryTextColor, size: 22),
                        if (widget.unreadCount > 0)
                          Positioned(
                            top: 8,
                            right: 8,
                            child: Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: const Color(0xFFEF4444),
                                shape: BoxShape.circle,
                                border:
                                    Border.all(color: cardBgColor, width: 1.5),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: widget.onGoToProfile,
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(colors: activeGradient),
                      border:
                          Border.all(color: activeGradient.last, width: 1.5),
                      boxShadow: [
                        BoxShadow(
                          color: activeGradient.last.withValues(alpha: 0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(22),
                      child: _buildAvatarImage(photoUrl, initials, 44),
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _buildLowStockBanner(int count) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF3C7),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFBBF24), width: 1),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded,
              color: Color(0xFFF59E0B), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Low stock alert: $count compartment${count > 1 ? 's have' : ' has'} 3 or fewer pills remaining.',
              style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFF92400E),
                  fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNextMedCard(Map<String, dynamic>? med) {
    final ts = med?['scheduledTime'] as Timestamp?;
    final isUpcoming =
        med != null && ts != null && ts.toDate().isAfter(DateTime.now());

    final name = isUpcoming
        ? (med['medicationName'] ?? 'Medication')
        : 'No upcoming medications';
    final dosage = isUpcoming ? (med['dosage'] ?? '') : '';
    final comp = isUpcoming ? (med['compartment'] ?? '') : '';
    final timeStr = isUpcoming ? DateFormat('hh:mm a').format(ts.toDate()) : '';

    String countdownLabel = 'All clear';
    if (isUpcoming) {
      final diff = ts.toDate().difference(DateTime.now());
      countdownLabel = _formatCountdown(diff.isNegative ? Duration.zero : diff);
    }

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: const Color(0xFF00A36C),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
              color: const Color(0xFF00A36C).withValues(alpha: 0.30),
              blurRadius: 16,
              offset: const Offset(0, 6))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('NEXT MEDICATION',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.1)),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20)),
                child: Row(
                  children: [
                    const Icon(Icons.access_time_rounded,
                        color: Colors.white, size: 14),
                    const SizedBox(width: 4),
                    Text(
                      countdownLabel,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    shape: BoxShape.circle),
                child: Icon(
                  isUpcoming ? LucideIcons.pill : LucideIcons.pill,
                  color: Colors.white,
                  size: 26,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold),
                    ),
                    if (isUpcoming &&
                        (dosage.isNotEmpty ||
                            timeStr.isNotEmpty ||
                            comp.isNotEmpty))
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          [
                            if (dosage.isNotEmpty) dosage,
                            if (timeStr.isNotEmpty) timeStr,
                            if (comp.isNotEmpty) comp
                          ].join(' · '),
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 13),
                        ),
                      )
                    else if (!isUpcoming)
                      const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: Text(
                          'No more doses scheduled for today',
                          style: TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (isUpcoming) ...[
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF00A36C),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(26)),
                ),
                onPressed: () => _onDispenseNow(med),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('Dispense now',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                    SizedBox(width: 6),
                    Icon(Icons.arrow_forward_rounded, size: 20),
                  ],
                ),
              ),
            ),
          ] else ...[
            // Empty state CTA — single button
            const SizedBox(height: 20),
            GestureDetector(
              onTap: widget.onGoToMeds,
              child: Container(
                width: double.infinity,
                height: 50,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(25),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add_circle_rounded,
                        color: Color(0xFF00A36C), size: 20),
                    SizedBox(width: 8),
                    Text(
                      'Add Medication',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF00A36C),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEmergencyButton() {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFFEF4444),
          side: const BorderSide(color: Color(0xFFFCA5A5), width: 1.5),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
        ),
        onPressed: _dispatchingEmergency ? null : _onEmergencyDispense,
        icon: _dispatchingEmergency
            ? const SmartDoseLoading(size: 36)
            : const Icon(Icons.notifications_active_outlined, size: 20),
        label: Text(
          _dispatchingEmergency
              ? 'Sending Emergency Request…'
              : 'Emergency Dispense',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _buildProgressSection(
      int taken, int missed, int total, double progress, int lowStock) {
    final pct = total > 0 ? '${(progress * 100).round()}%' : '—';
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cardBgColor = theme.cardTheme.color ?? theme.colorScheme.surface;
    final primaryTextColor = theme.colorScheme.onSurface;
    final secondaryTextColor = primaryTextColor.withValues(alpha: 0.65);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text("Today's progress",
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: primaryTextColor)),
            GestureDetector(
              onTap: widget.onGoToHistory,
              child: const Text('Details',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF00A36C))),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: cardBgColor,
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
                  blurRadius: 12,
                  offset: const Offset(0, 4))
            ],
          ),
          child: Row(
            children: [
              SizedBox(
                width: 110,
                height: 110,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 100,
                      height: 100,
                      child: CircularProgressIndicator(
                        value: progress,
                        strokeWidth: 12,
                        backgroundColor: isDark
                            ? const Color(0xFF064E3B)
                            : const Color(0xFFD1FAE5),
                        valueColor: const AlwaysStoppedAnimation<Color>(
                            Color(0xFF00A36C)),
                        strokeCap: StrokeCap.round,
                      ),
                    ),
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(pct,
                            style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: primaryTextColor)),
                        Text('of today',
                            style: TextStyle(
                                fontSize: 11, color: secondaryTextColor)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 24),
              Expanded(
                child: Column(
                  children: [
                    _buildProgressRow(const Color(0xFF10B981), 'Pills taken',
                        '$taken of $total'),
                    const SizedBox(height: 10),
                    _buildProgressRow(
                        const Color(0xFFEF4444), 'Missed doses', '$missed'),
                    const SizedBox(height: 10),
                    _buildProgressRow(const Color(0xFFF59E0B),
                        'Low stock items', '$lowStock'),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildProgressRow(Color dotColor, String label, String value) {
    final theme = Theme.of(context);
    final primaryTextColor = theme.colorScheme.onSurface;
    final secondaryTextColor = primaryTextColor.withValues(alpha: 0.65);

    return Row(
      children: [
        Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Expanded(
            child: Text(label,
                style: TextStyle(fontSize: 14, color: secondaryTextColor))),
        Text(value,
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: primaryTextColor)),
      ],
    );
  }

  Widget _buildQuickActions(int totalDoses, int compCount) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryTextColor = theme.colorScheme.onSurface;

    final actions = [
      {
        'icon': LucideIcons.scanEye,
        'label': 'Live Camera',
        'cb': () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const CameraFeedScreen())),
      },
      {
        'icon': LucideIcons.usersRound,
        'label': 'Emergency\nContacts',
        'cb': () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => const EmergencyContactsScreen())),
      },
      {
        'icon': Icons.inventory_2_outlined,
        'label': 'Inventory',
        'cb': () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => const CompartmentInventoryScreen())),
      },
      {
        'icon': Icons.wifi_rounded,
        'label': 'Device\nConnected',
        'cb': () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const DeviceConnectedScreen())),
      },
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Quick actions',
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: primaryTextColor)),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: actions.map((a) {
            return Expanded(
              child: GestureDetector(
                onTap: a['cb'] as VoidCallback,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF1E2D25)
                            : const Color(0xFFE8F8F0),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF00A36C)
                                .withValues(alpha: isDark ? 0.18 : 0.12),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Icon(a['icon'] as IconData,
                          color: const Color(0xFF00A36C), size: 24),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      a['label'] as String,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: primaryTextColor,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildRecentActivitySection(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> logs,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> schedDocs,
  ) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cardBgColor = theme.cardTheme.color ?? theme.colorScheme.surface;
    final primaryTextColor = theme.colorScheme.onSurface;
    final secondaryTextColor = primaryTextColor.withValues(alpha: 0.65);
    final now = DateTime.now();

    // Sort logs newest-first and take up to 5
    final sortedLogs = [...logs]..sort((a, b) {
        final tsA = a.data()['timestamp'] as Timestamp?;
        final tsB = b.data()['timestamp'] as Timestamp?;
        if (tsA == null && tsB == null) return 0;
        if (tsA == null) return 1;
        if (tsB == null) return -1;
        return tsB.compareTo(tsA);
      });
    final recentLogs = sortedLogs.take(5).toList();

    // For empty state: find upcoming scheduled doses
    final upcomingSchedDocs = schedDocs.where((doc) {
      final ts = doc.data()['scheduledTime'] as Timestamp?;
      if (ts == null) return false;
      final t = ts.toDate();
      final todayTime = DateTime(now.year, now.month, now.day, t.hour, t.minute);
      return todayTime.isAfter(now);
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Recent Activity',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: primaryTextColor,
              ),
            ),
            GestureDetector(
              onTap: widget.onGoToHistory,
              child: const Text(
                'View History',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF00A36C),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: cardBgColor,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: recentLogs.isNotEmpty
              ? Column(
                  children: List.generate(recentLogs.length, (i) {
                    final doc = recentLogs[i];
                    final data = doc.data();
                    final medName =
                        data['medicationName'] as String? ?? 'Medication';
                    final status = data['status'] as String? ?? '';
                    final type = data['type'] as String? ?? '';
                    final ts = data['timestamp'] as Timestamp?;
                    final timeStr = ts != null
                        ? DateFormat('hh:mm a').format(ts.toDate())
                        : 'Today';

                    // Determine visual treatment based on status/type
                    final bool isTaken = status == 'taken';
                    final bool isMissed = status == 'missed';
                    final bool isEmergency =
                        type == 'emergency' || status == 'requested';

                    Color statusColor;
                    Color statusBg;
                    IconData iconData;
                    String statusLabel;
                    String actionLabel;

                    if (isEmergency) {
                      statusColor = const Color(0xFFDC2626);
                      statusBg = isDark
                          ? const Color(0xFF450A0A)
                          : const Color(0xFFFEF2F2);
                      iconData = Icons.emergency_rounded;
                      statusLabel = 'Emergency';
                      actionLabel = 'Emergency dispense requested';
                    } else if (isTaken) {
                      statusColor = const Color(0xFF10B981);
                      statusBg = isDark
                          ? const Color(0xFF064E3B)
                          : const Color(0xFFECFDF5);
                      iconData = Icons.check_rounded;
                      statusLabel = 'Taken';
                      actionLabel = 'Dose taken';
                    } else {
                      statusColor = const Color(0xFFEF4444);
                      statusBg = isDark
                          ? const Color(0xFF451A1A)
                          : const Color(0xFFFEF2F2);
                      iconData = Icons.close_rounded;
                      statusLabel = isMissed ? 'Missed' : 'Skipped';
                      actionLabel = isMissed ? 'Dose missed' : 'Dose skipped';
                    }

                    return Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 14),
                          child: Row(
                            children: [
                              Container(
                                width: 42,
                                height: 42,
                                decoration: BoxDecoration(
                                  color: statusBg,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(iconData,
                                    color: statusColor, size: 20),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      medName,
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold,
                                        color: primaryTextColor,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '$actionLabel · $timeStr',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: secondaryTextColor,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: statusBg,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  statusLabel,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: statusColor,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (i < recentLogs.length - 1)
                          Divider(
                            height: 1,
                            indent: 72,
                            endIndent: 16,
                            color: theme.dividerColor,
                          ),
                      ],
                    );
                  }),
                )
              : schedDocs.isEmpty
                  // No schedule at all
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Center(
                        child: Column(
                          children: [
                            Container(
                              width: 52,
                              height: 52,
                              decoration: BoxDecoration(
                                color: isDark
                                    ? const Color(0xFF1E2D25)
                                    : const Color(0xFFE8F8F0),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(LucideIcons.pill,
                                  color: Color(0xFF00A36C), size: 24),
                            ),
                            const SizedBox(height: 14),
                            Text(
                              'No activity yet today',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: primaryTextColor,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Add medications to start tracking doses',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontSize: 13, color: secondaryTextColor),
                            ),
                          ],
                        ),
                      ),
                    )
                  // Has schedule but no logs yet — show upcoming doses
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                          child: Text(
                            'Upcoming today',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: secondaryTextColor,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                        ...List.generate(
                          upcomingSchedDocs.take(3).length,
                          (i) {
                            final doc = upcomingSchedDocs[i];
                            final data = doc.data();
                            final medName =
                                data['medicationName'] as String? ?? 'Medication';
                            final dosage =
                                data['dosage'] as String? ?? '';
                            final ts =
                                data['scheduledTime'] as Timestamp?;
                            final t = ts?.toDate();
                            final timeStr = t != null
                                ? DateFormat('hh:mm a').format(DateTime(
                                    now.year,
                                    now.month,
                                    now.day,
                                    t.hour,
                                    t.minute))
                                : '';

                            return Column(
                              children: [
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 12),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 42,
                                        height: 42,
                                        decoration: BoxDecoration(
                                          color: isDark
                                              ? const Color(0xFF1E3A5F)
                                              : const Color(0xFFEFF6FF),
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(LucideIcons.clock,
                                            color: Color(0xFF3B82F6),
                                            size: 20),
                                      ),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              medName,
                                              style: TextStyle(
                                                fontSize: 15,
                                                fontWeight: FontWeight.bold,
                                                color: primaryTextColor,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            if (dosage.isNotEmpty)
                                              Text(
                                                dosage,
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  color: secondaryTextColor,
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                      Text(
                                        timeStr,
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xFF3B82F6),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (i < upcomingSchedDocs.take(3).length - 1)
                                  Divider(
                                    height: 1,
                                    indent: 72,
                                    endIndent: 16,
                                    color: theme.dividerColor,
                                  ),
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 4),
                      ],
                    ),
        ),
      ],
    );
  }
}
