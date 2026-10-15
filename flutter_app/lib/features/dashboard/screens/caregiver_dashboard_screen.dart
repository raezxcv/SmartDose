import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'meds_tab.dart';
import 'history_tab.dart';
import 'alerts_tab.dart';
import 'profile_tab.dart';
import 'compartment_inventory_screen.dart';
import '../../pairing/services/pairing_service.dart';
import '../../pairing/screens/connect_patient_screen.dart';
import '../../pairing/screens/linked_account_screen.dart';
import '../../pairing/screens/emergency_contacts_screen.dart';
import 'package:smartdose/shared/widgets/app_avatar.dart';


class CaregiverHomeScreen extends StatefulWidget {
  final String userName;
  final VoidCallback onSignOut;

  const CaregiverHomeScreen({
    super.key,
    this.userName = 'Caregiver',
    required this.onSignOut,
  });

  @override
  State<CaregiverHomeScreen> createState() => _CaregiverHomeScreenState();
}

class _CaregiverHomeScreenState extends State<CaregiverHomeScreen> {
  int _currentIndex = 0;
  int _unreadAlertsCount = 0;
  Map<String, dynamic>? _userFirestoreData;
  StreamSubscription? _userSub;
  StreamSubscription? _unreadSub;
  StreamSubscription? _patientSub;

  Map<String, dynamic>? _linkedPatient;
  String? _linkedPatientUid;

  DateTime? _lastBackPressTime;

  @override
  void initState() {
    super.initState();
    _listenToRealtimeUserData();
    _listenToUnreadNotifications();
    _listenToLinkedPatient();
  }

  @override
  void dispose() {
    _userSub?.cancel();
    _unreadSub?.cancel();
    _patientSub?.cancel();
    super.dispose();
  }

  void _listenToLinkedPatient() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    _patientSub = PairingService()
        .getConnectedPatientsStream(user.uid)
        .listen((patients) {
      if (!mounted) return;
      setState(() {
        if (patients.isNotEmpty) {
          _linkedPatient = patients.first;
          _linkedPatientUid = patients.first['patientUid'] as String?;
        } else {
          _linkedPatient = null;
          _linkedPatientUid = null;
        }
      });
    });
  }

  void _listenToRealtimeUserData() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    _userSub = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .snapshots()
        .listen((doc) {
      if (doc.exists && doc.data() != null && mounted) {
        setState(() => _userFirestoreData = doc.data());
      }
    });
  }

  void _listenToUnreadNotifications() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    _unreadSub = FirebaseFirestore.instance
        .collection('notifications')
        .doc(user.uid)
        .collection('items')
        .where('isRead', isEqualTo: false)
        .snapshots()
        .listen((snapshot) {
      if (mounted) {
        setState(() => _unreadAlertsCount = snapshot.docs.length);
      }
    });
  }

  String get _displayName {
    if (_userFirestoreData != null &&
        _userFirestoreData!['name'] != null &&
        (_userFirestoreData!['name'] as String).trim().isNotEmpty) {
      return _userFirestoreData!['name'];
    }
    return widget.userName;
  }

  String get _userInitials {
    final name = _displayName.trim();
    final parts = name.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    if (parts.isNotEmpty && parts[0].isNotEmpty) return parts[0][0].toUpperCase();
    return 'CG';
  }

  String _patientTabSection = 'schedule';

  void _switchTab(int index, {String section = 'schedule'}) {
    setState(() {
      _currentIndex = index;
      if (index == 1) {
        _patientTabSection = section;
      }
    });
  }

  Future<void> _markAllNotificationsRead() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _unreadAlertsCount = 0);
      return;
    }
    final batch = FirebaseFirestore.instance.batch();
    final unreadDocs = await FirebaseFirestore.instance
        .collection('notifications')
        .doc(user.uid)
        .collection('items')
        .where('isRead', isEqualTo: false)
        .get();
    for (var doc in unreadDocs.docs) {
      batch.update(doc.reference, {'isRead': true});
    }
    await batch.commit();
    if (mounted) {
      setState(() => _unreadAlertsCount = 0);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('All notifications marked as read.'),
          backgroundColor: Color(0xFF00A36C),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
          return;
        }
        if (_currentIndex != 0) {
          setState(() => _currentIndex = 0);
        } else {
          final now = DateTime.now();
          if (_lastBackPressTime == null ||
              now.difference(_lastBackPressTime!) > const Duration(seconds: 2)) {
            _lastBackPressTime = now;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Row(
                  children: [
                    Icon(Icons.touch_app_rounded, color: Colors.white, size: 18),
                    SizedBox(width: 8),
                    Text('Press back again to exit'),
                  ],
                ),
                backgroundColor: const Color(0xFF374151),
                duration: const Duration(seconds: 2),
                behavior: SnackBarBehavior.floating,
                margin: const EdgeInsets.only(bottom: 80, left: 40, right: 40),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              ),
            );
          } else {
            SystemNavigator.pop();
          }
        }
      },
      child: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        body: SafeArea(
          child: IndexedStack(
            index: _currentIndex,
            children: [
              // Tab 0: Dedicated Caregiver Home
              CaregiverHomeTab(
                caregiverName: _displayName,
                caregiverInitials: _userInitials,
                linkedPatient: _linkedPatient,
                patientUid: _linkedPatientUid,
                unreadCount: _unreadAlertsCount,
                onGoToPatient: () => _switchTab(1, section: 'schedule'),
                onGoToInventory: () => _switchTab(1, section: 'inventory'),
                onGoToHistory: () => _switchTab(2),
                onGoToProfile: () => _switchTab(3),
                onGoToAlerts: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PatientAlertsTab(
                      patientUid: _linkedPatientUid,
                      onMarkAllRead: _markAllNotificationsRead,
                    ),
                  ),
                ),
              ),

              // Tab 1: Patient Screen (Schedules & Inventory for linked patient)
              _linkedPatientUid != null
                  ? PatientMedsTab(
                      key: ValueKey('$_linkedPatientUid-$_patientTabSection'),
                      isCaregiver: true,
                      patientUid: _linkedPatientUid,
                      initialSection: _patientTabSection,
                    )
                  : _buildNoPatientView(theme, isDark),

              // Tab 2: History (Adherence and dose logs for linked patient)
              _linkedPatientUid != null
                  ? PatientHistoryTab(
                      patientUid: _linkedPatientUid,
                    )
                  : _buildNoPatientView(theme, isDark),

              // Tab 3: Caregiver Profile
              PatientProfileTab(
                fallbackName: _displayName,
                onSignOut: widget.onSignOut,
              ),
            ],
          ),
        ),

        // Caregiver Bottom Navigation (Home, Patient, History, Profile)
        bottomNavigationBar: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.05),
                blurRadius: 16,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildNavItem(0, LucideIcons.home, 'Home'),
              _buildNavItem(1, LucideIcons.heartPulse, 'Patient'),
              _buildNavItem(2, LucideIcons.libraryBig, 'History'),
              _buildNavItem(3, LucideIcons.userRound, 'Profile'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label) {
    final isSelected = _currentIndex == index;
    final theme = Theme.of(context);
    const primaryColor = Color(0xFF00A36C);
    final unselectedColor = theme.colorScheme.onSurface.withValues(alpha: 0.5);

    return InkWell(
      onTap: () => _switchTab(index),
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedScale(
              scale: isSelected ? 1.15 : 1.0,
              duration: const Duration(milliseconds: 200),
              child: Icon(
                icon,
                color: isSelected ? primaryColor : unselectedColor,
                size: 24,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected ? primaryColor : unselectedColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoPatientView(ThemeData theme, bool isDark) {
    const emerald = Color(0xFF00A36C);
    final primaryTextColor = theme.colorScheme.onSurface;
    final secondaryTextColor = primaryTextColor.withValues(alpha: 0.65);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E2D25) : const Color(0xFFE8F8F0),
                shape: BoxShape.circle,
              ),
              child: const Icon(LucideIcons.userX, color: emerald, size: 38),
            ),
            const SizedBox(height: 20),
            Text(
              'No Linked Patient',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: primaryTextColor),
            ),
            const SizedBox(height: 10),
            Text(
              'Connect with your patient by scanning their QR code to access their medication schedule, dispenser status, and activity logs.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: secondaryTextColor, height: 1.45),
            ),
            const SizedBox(height: 28),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ConnectPatientScreen()),
                );
              },
              icon: const Icon(LucideIcons.scanLine, color: Colors.white, size: 18),
              label: const Text('Connect to Patient', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
              style: ElevatedButton.styleFrom(
                backgroundColor: emerald,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Dedicated Caregiver Home Tab
// ─────────────────────────────────────────────────────────────────────────────

class CaregiverHomeTab extends StatefulWidget {
  final String caregiverName;
  final String caregiverInitials;
  final Map<String, dynamic>? linkedPatient;
  final String? patientUid;
  final int unreadCount;
  final VoidCallback onGoToPatient;
  final VoidCallback onGoToInventory;
  final VoidCallback onGoToHistory;
  final VoidCallback onGoToProfile;
  final VoidCallback onGoToAlerts;

  const CaregiverHomeTab({
    super.key,
    required this.caregiverName,
    required this.caregiverInitials,
    required this.linkedPatient,
    required this.patientUid,
    required this.unreadCount,
    required this.onGoToPatient,
    required this.onGoToInventory,
    required this.onGoToHistory,
    required this.onGoToProfile,
    required this.onGoToAlerts,
  });

  @override
  State<CaregiverHomeTab> createState() => _CaregiverHomeTabState();
}

class _CaregiverHomeTabState extends State<CaregiverHomeTab> {
  Stream<QuerySnapshot<Map<String, dynamic>>>? _schedulesStream;
  Stream<QuerySnapshot<Map<String, dynamic>>>? _todayLogsStream;
  Stream<QuerySnapshot<Map<String, dynamic>>>? _compartmentsStream;
  Stream<DocumentSnapshot<Map<String, dynamic>>>? _patientUserDocStream;
  Stream<DocumentSnapshot<Map<String, dynamic>>>? _deviceStream;

  String? _deviceId;
  StreamSubscription? _userSub;

  Future<void> _onCaregiverEmergencyDispense() async {
    final uid = widget.patientUid;
    if (uid == null) return;
    final patientName = widget.linkedPatient?['patientName'] ?? 'your patient';

    final theme = Theme.of(context);
    final cardBgColor = theme.cardTheme.color ?? theme.colorScheme.surface;
    final primaryTextColor = theme.colorScheme.onSurface;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        backgroundColor: cardBgColor,
        contentPadding: const EdgeInsets.all(24),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444).withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.emergency_rounded, color: Color(0xFFEF4444), size: 28),
            ),
            const SizedBox(height: 16),
            Text(
              'Emergency Dispense',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: primaryTextColor,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Trigger an immediate emergency medication dispense on $patientName\'s SmartDose dispenser? This will alert all emergency contacts and log the incident.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                height: 1.4,
                color: primaryTextColor.withValues(alpha: 0.65),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                    ),
                    child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFDC2626),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                    ),
                    child: const Text('Dispense', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) return;

    final caregiverUid = FirebaseAuth.instance.currentUser?.uid;

    try {
      if (_deviceId != null) {
        try {
          await FirebaseFirestore.instance.collection('devices').doc(_deviceId).update({
            'status': 'dispensing',
            'emergencyDispense': true,
            'emergencyRequestedAt': FieldValue.serverTimestamp(),
            'emergencyRequestedBy': caregiverUid,
          });
        } catch (_) {}
      }

      // Hardware trigger via RTDB
      try {
        final url = Uri.parse(
            'https://smart-pill-dispenser-baa02-default-rtdb.firebaseio.com/hardware/emergency_trigger.json');
        await http.put(url, body: jsonEncode(true));
      } catch (_) {}

      // Queue SMS alerts to contacts
      try {
        final contactsSnap = await FirebaseFirestore.instance
            .collection('contacts')
            .where('patientUid', isEqualTo: uid)
            .get();
        for (final doc in contactsSnap.docs) {
          final phone = doc.data()['phone'] as String? ?? '';
          final name = doc.data()['name'] as String? ?? 'Contact';
          if (phone.isNotEmpty) {
            await FirebaseFirestore.instance.collection('sms_queue').add({
              'patientUid': uid,
              'patientName': patientName,
              'to': phone,
              'contactName': name,
              'message': 'EMERGENCY ALERT: Caregiver ${widget.caregiverName} initiated emergency dispensing for $patientName. — SmartDose',
              'status': 'pending',
              'triggeredBy': 'caregiver_emergency',
              'createdAt': FieldValue.serverTimestamp(),
            });
          }
        }
      } catch (_) {}

      // Add emergency request record
      await FirebaseFirestore.instance.collection('emergencyRequests').add({
        'patientId': uid,
        'patientUid': uid,
        'initiatedBy': 'caregiver',
        'caregiverUid': caregiverUid,
        'caregiverName': widget.caregiverName,
        'status': 'dispensed',
        'requestedAt': FieldValue.serverTimestamp(),
      });

      // Add to dispensingLogs
      await FirebaseFirestore.instance.collection('dispensingLogs').add({
        'patientUid': uid,
        'patientId': uid,
        'deviceId': _deviceId ?? '',
        'medicationName': 'Emergency Dose',
        'type': 'emergency',
        'status': 'dispensed',
        'initiatedBy': 'caregiver',
        'timestamp': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
      });

      // Patient in-app notification
      await FirebaseFirestore.instance
          .collection('notifications')
          .doc(uid)
          .collection('items')
          .add({
        'title': 'Emergency dose triggered by Caregiver',
        'body': '${widget.caregiverName} initiated an emergency dispense on your SmartDose dispenser.',
        'type': 'emergency',
        'isRead': false,
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Emergency dispensing signal transmitted to hardware dispenser!'),
            backgroundColor: Color(0xFF00A36C),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error triggering emergency dispense: $e'),
            backgroundColor: const Color(0xFFEF4444),
          ),
        );
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _initStreams();
  }

  @override
  void didUpdateWidget(CaregiverHomeTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.patientUid != widget.patientUid) {
      _initStreams();
    }
  }

  @override
  void dispose() {
    _userSub?.cancel();
    super.dispose();
  }

  void _initStreams() {
    final uid = widget.patientUid;
    if (uid == null || uid.isEmpty) {
      _schedulesStream = null;
      _todayLogsStream = null;
      _compartmentsStream = null;
      _patientUserDocStream = null;
      _deviceStream = null;
      return;
    }

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

    _patientUserDocStream =
        FirebaseFirestore.instance.collection('users').doc(uid).snapshots();

    _userSub?.cancel();
    _userSub = _patientUserDocStream?.listen((doc) {
      if (doc.exists && doc.data() != null && mounted) {
        final dId = doc.data()?['deviceId'] as String?;
        if (dId != null && dId != _deviceId) {
          setState(() {
            _deviceId = dId;
            _deviceStream = FirebaseFirestore.instance
                .collection('devices')
                .doc(dId)
                .snapshots();
          });
        }
      }
    });
  }

  String get _greeting {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }



  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryTextColor = theme.colorScheme.onSurface;
    final secondaryTextColor = primaryTextColor.withValues(alpha: 0.65);
    const emerald = Color(0xFF00A36C);

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Caregiver Header ──────────────────────────────────────────────
          _buildCaregiverHeader(theme, isDark, primaryTextColor, secondaryTextColor, emerald),
          const SizedBox(height: 20),

          // If no linked patient -> Empty state card with action
          if (widget.patientUid == null) ...[
            _buildEmptyPatientCard(theme, isDark, primaryTextColor, secondaryTextColor, emerald),
            const SizedBox(height: 24),
            _buildCaregiverGuidanceCard(theme, isDark, primaryTextColor, secondaryTextColor, emerald),
          ] else ...[
            // ── Linked Patient Overview Card ─────────────────────────────────
            _buildLinkedPatientCard(theme, isDark, primaryTextColor, secondaryTextColor, emerald),
            const SizedBox(height: 20),

            // ── Actionable Alerts & Attention Banner ─────────────────────────
            _buildActionableAlertsBanner(theme, isDark, primaryTextColor, secondaryTextColor, emerald),
            const SizedBox(height: 20),

            // ── Medication Monitoring & Adherence ────────────────────────────
            _buildMedicationMonitoringSection(theme, isDark, primaryTextColor, secondaryTextColor, emerald),
            const SizedBox(height: 24),

            // ── Dispenser Pill Inventory Overview ────────────────────────────
            _buildInventoryOverviewSection(theme, isDark, primaryTextColor, secondaryTextColor, emerald),
            const SizedBox(height: 24),

            // ── Caregiver Quick Actions ──────────────────────────────────────
            _buildCaregiverQuickActions(theme, isDark, primaryTextColor, emerald),
            const SizedBox(height: 24),

            // ── Patient Recent Medication Activity ───────────────────────────
            _buildRecentActivitySection(theme, isDark, primaryTextColor, secondaryTextColor, emerald),
            const SizedBox(height: 16),
          ],
        ],
      ),
    );
  }

  Widget _buildCaregiverHeader(
    ThemeData theme,
    bool isDark,
    Color primaryTextColor,
    Color secondaryTextColor,
    Color emerald,
  ) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  _greeting,
                  style: TextStyle(
                    fontSize: 14,
                    color: secondaryTextColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: 8),
                // Clear but subtle Role Indicator Badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E2D25) : const Color(0xFFE8F8F0),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: emerald.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    'Caregiver',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: emerald,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              widget.caregiverName,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: primaryTextColor,
                letterSpacing: -0.5,
              ),
            ),
          ],
        ),

        // Notification Bell & Profile Avatar
        Row(
          children: [
            GestureDetector(
              onTap: widget.onGoToAlerts,
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: theme.cardTheme.color ?? theme.colorScheme.surface,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
                      blurRadius: 10,
                    ),
                  ],
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Icon(LucideIcons.bell, color: primaryTextColor, size: 20),
                    if (widget.unreadCount > 0)
                      Positioned(
                        top: 10,
                        right: 10,
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Color(0xFFEF4444),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            GestureDetector(
              onTap: widget.onGoToProfile,
              child: AppAvatar(
                name: widget.caregiverName,
                size: 44,
                showGradientBorder: true,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildEmptyPatientCard(
    ThemeData theme,
    bool isDark,
    Color primaryTextColor,
    Color secondaryTextColor,
    Color emerald,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(26),
      decoration: BoxDecoration(
        color: emerald,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: emerald.withValues(alpha: 0.32),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(LucideIcons.scanLine, color: Colors.white, size: 32),
          ),
          const SizedBox(height: 16),
          const Text(
            'No Patient Linked Yet',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 8),
          const Text(
            'Pair your caregiver account with your patient by scanning their account QR code. Once paired, you can view their medication adherence and dispenser connectivity.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Colors.white70, height: 1.45),
          ),
          const SizedBox(height: 22),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ConnectPatientScreen()),
                );
              },
              icon: const Icon(LucideIcons.scanLine, color: Color(0xFF00A36C), size: 18),
              label: const Text(
                'Scan a Patient',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF00A36C)),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: emerald,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCaregiverGuidanceCard(
    ThemeData theme,
    bool isDark,
    Color primaryTextColor,
    Color secondaryTextColor,
    Color emerald,
  ) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E2D25) : const Color(0xFFE8F8F0),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: emerald.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(LucideIcons.info, color: emerald, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Caregiver & Patient Pairing',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : const Color(0xFF065F46),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Pairing connects a patient and caregiver so they can access the appropriate medication information and features based on their roles.',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? const Color(0xFFA7F3D0) : const Color(0xFF047857),
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLinkedPatientCard(
    ThemeData theme,
    bool isDark,
    Color primaryTextColor,
    Color secondaryTextColor,
    Color emerald,
  ) {
    final patientName = widget.linkedPatient?['patientName'] ?? 'Linked Patient';
    final patientEmail = widget.linkedPatient?['patientEmail'] ?? '';

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _deviceStream,
      builder: (context, devSnap) {
        final devData = devSnap.data?.data();
        final bool isOnline = devData?['isOnline'] == true || devData?['status'] == 'online';
        final String deviceId = _deviceId ?? (devData?['deviceId'] as String? ?? 'Not paired');

        return Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: emerald,
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: emerald.withValues(alpha: 0.32),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'LINKED PATIENT',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.1,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: isOnline ? const Color(0xFF6EE7B7) : const Color(0xFFFCD34D),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          isOnline ? 'Online ($deviceId)' : 'Offline ($deviceId)',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  AppAvatar(
                    name: patientName,
                    size: 52,
                    showGradientBorder: true,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          patientName,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        if (patientEmail.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              patientEmail,
                              style: const TextStyle(fontSize: 13, color: Colors.white70),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(LucideIcons.userCog, color: Colors.white, size: 20),
                    tooltip: 'Manage Pairing',
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const LinkedAccountScreen(isCaregiver: true)),
                      );
                    },
                  ),
                ],
              ),
              const SizedBox(height: 20),
              // Capsule button "Manage Patient"
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: emerald,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
                  ),
                  onPressed: widget.onGoToPatient,
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Manage Patient',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                      SizedBox(width: 6),
                      Icon(Icons.arrow_forward_rounded, size: 18),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildActionableAlertsBanner(
    ThemeData theme,
    bool isDark,
    Color primaryTextColor,
    Color secondaryTextColor,
    Color emerald,
  ) {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _todayLogsStream,
      builder: (context, logsSnap) {
        final logs = (logsSnap.data?.docs ?? []).where((d) {
          final ts = d.data()['timestamp'] as Timestamp?;
          if (ts == null) return false;
          return ts.toDate().isAfter(todayStart);
        }).toList();

        final missedLogs = logs.where((d) => d.data()['status'] == 'missed').toList();

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _compartmentsStream,
          builder: (context, compSnap) {
            final comps = compSnap.data?.docs ?? [];
            final lowStockComps = comps.where((d) => (d.data()['stockCount'] as int? ?? 0) <= 3).toList();

            final hasMissed = missedLogs.isNotEmpty;
            final hasLowStock = lowStockComps.isNotEmpty;

            if (hasMissed) {
              final lastMissed = missedLogs.first.data();
              final medName = lastMissed['medicationName'] ?? 'Medication';
              return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF451A1A) : const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: const Color(0xFFFCA5A5)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: const BoxDecoration(color: Color(0xFFFEE2E2), shape: BoxShape.circle),
                      child: const Icon(LucideIcons.alertTriangle, color: Color(0xFFEF4444), size: 20),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Action Required: Missed Dose',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFFDC2626)),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Patient missed $medName scheduled for today.',
                            style: TextStyle(fontSize: 12, color: primaryTextColor.withValues(alpha: 0.75)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }

            if (hasLowStock) {
              final lowCount = lowStockComps.length;
              return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF451A03) : const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: const Color(0xFFFDE68A)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: const BoxDecoration(color: Color(0xFFFEF3C7), shape: BoxShape.circle),
                      child: const Icon(Icons.inventory_2_outlined, color: Color(0xFFD97706), size: 20),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Refill Needed: $lowCount Low Compartment${lowCount > 1 ? 's' : ''}',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFFB45309)),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Pills are running low in the SmartDose dispenser.',
                            style: TextStyle(fontSize: 12, color: primaryTextColor.withValues(alpha: 0.75)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }

            // All clear banner
            return Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E2D25) : const Color(0xFFE8F8F0),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: emerald.withValues(alpha: 0.25)),
              ),
              child: Row(
                children: [
                  const Icon(LucideIcons.checkCircle2, color: Color(0xFF10B981), size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'All on track: Patient medication routine is up to date today.',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: isDark ? const Color(0xFFA7F3D0) : const Color(0xFF065F46),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildMedicationMonitoringSection(
    ThemeData theme,
    bool isDark,
    Color primaryTextColor,
    Color secondaryTextColor,
    Color emerald,
  ) {
    final cardBgColor = theme.cardTheme.color ?? theme.colorScheme.surface;
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _schedulesStream,
      builder: (context, schedSnap) {
        final schedDocs = schedSnap.data?.docs ?? [];
        final totalScheduled = schedDocs.length;

        // Upcoming dose
        Map<String, dynamic>? nextDose;
        for (final doc in schedDocs) {
          final data = doc.data();
          final ts = data['scheduledTime'] as Timestamp?;
          if (ts != null) {
            final t = ts.toDate();
            final todayTime = DateTime(now.year, now.month, now.day, t.hour, t.minute);
            if (todayTime.isAfter(now)) {
              nextDose = data;
              break;
            }
          }
        }

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _todayLogsStream,
          builder: (context, logsSnap) {
            final logs = (logsSnap.data?.docs ?? []).where((d) {
              final ts = d.data()['timestamp'] as Timestamp?;
              if (ts == null) return false;
              return ts.toDate().isAfter(todayStart);
            }).toList();

            final taken = logs.where((d) => d.data()['status'] == 'taken').length;
            final missed = logs.where((d) => d.data()['status'] == 'missed').length;
            final progress = totalScheduled > 0 ? (taken / totalScheduled).clamp(0.0, 1.0) : 0.0;
            final pct = totalScheduled > 0 ? '${(progress * 100).round()}%' : '—';

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Today\'s Adherence',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: primaryTextColor),
                    ),
                    GestureDetector(
                      onTap: widget.onGoToHistory,
                      child: Text(
                        'Detailed Logs',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: emerald),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Adherence card with circular progress
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: cardBgColor,
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.04),
                        blurRadius: 14,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 95,
                        height: 95,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            SizedBox(
                              width: 85,
                              height: 85,
                              child: CircularProgressIndicator(
                                value: progress,
                                strokeWidth: 10,
                                backgroundColor: isDark ? const Color(0xFF064E3B) : const Color(0xFFD1FAE5),
                                valueColor: AlwaysStoppedAnimation<Color>(emerald),
                                strokeCap: StrokeCap.round,
                              ),
                            ),
                            Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  pct,
                                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: primaryTextColor),
                                ),
                                Text(
                                  'Taken',
                                  style: TextStyle(fontSize: 11, color: secondaryTextColor),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 20),
                      Expanded(
                        child: Column(
                          children: [
                            _buildProgressRow(const Color(0xFF10B981), 'Doses Taken', '$taken of $totalScheduled', primaryTextColor, secondaryTextColor),
                            const SizedBox(height: 10),
                            _buildProgressRow(const Color(0xFFEF4444), 'Missed Doses', '$missed', primaryTextColor, secondaryTextColor),
                            const SizedBox(height: 10),
                            _buildProgressRow(
                              const Color(0xFF3B82F6),
                              'Next Dose',
                              nextDose != null ? (nextDose['medicationName'] ?? 'Scheduled') : 'None remaining',
                              primaryTextColor,
                              secondaryTextColor,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // Next scheduled dose card (read-only for caregiver, NO Dispense Now button)
                if (nextDose != null) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E2D25) : const Color(0xFFE8F8F0),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: emerald.withValues(alpha: 0.25)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(LucideIcons.clock, color: emerald, size: 22),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                nextDose['medicationName'] ?? 'Medication',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: isDark ? Colors.white : const Color(0xFF1F2937),
                                ),
                              ),
                              Text(
                                '${nextDose['dosage'] ?? ''} · ${nextDose['compartment'] ?? 'C1'}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isDark ? Colors.white70 : const Color(0xFF4B5563),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: emerald,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Text(
                            'Scheduled',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildProgressRow(Color dotColor, String label, String value, Color primaryTextColor, Color secondaryTextColor) {
    return Row(
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Expanded(child: Text(label, style: TextStyle(fontSize: 13, color: secondaryTextColor))),
        Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: primaryTextColor)),
      ],
    );
  }

  Widget _buildInventoryOverviewSection(
    ThemeData theme,
    bool isDark,
    Color primaryTextColor,
    Color secondaryTextColor,
    Color emerald,
  ) {
    final cardBgColor = theme.cardTheme.color ?? theme.colorScheme.surface;

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _compartmentsStream,
      builder: (context, compSnap) {
        final comps = compSnap.data?.docs ?? [];
        final total = comps.length;
        final lowStock = comps.where((d) => (d.data()['stockCount'] as int? ?? 0) <= 3 && (d.data()['stockCount'] as int? ?? 0) > 0).length;
        final empty = comps.where((d) => (d.data()['stockCount'] as int? ?? 0) == 0).length;
        final wellStocked = total - lowStock - empty;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Dispenser Pill Inventory',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: primaryTextColor),
                ),
                GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => CompartmentInventoryScreen(
                          isCaregiver: true,
                          patientUid: widget.patientUid,
                        ),
                      ),
                    );
                  },
                  child: Text(
                    'Manage & Refill',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: emerald),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: cardBgColor,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.04),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _summaryPill('$total', 'Total', LucideIcons.layers, primaryTextColor, secondaryTextColor),
                  _summaryDivider(),
                  _summaryPill('$wellStocked', 'Good', LucideIcons.checkCheck, const Color(0xFF10B981), secondaryTextColor),
                  _summaryDivider(),
                  _summaryPill('$lowStock', 'Low', LucideIcons.alertCircle, const Color(0xFFF59E0B), secondaryTextColor),
                  _summaryDivider(),
                  _summaryPill('$empty', 'Empty', LucideIcons.xCircle, const Color(0xFFEF4444), secondaryTextColor),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _summaryPill(String count, String label, IconData icon, Color color, Color secondaryTextColor) {
    return Column(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(height: 4),
        Text(count, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: color)),
        Text(label, style: TextStyle(fontSize: 11, color: secondaryTextColor)),
      ],
    );
  }

  Widget _summaryDivider() {
    return Container(width: 1, height: 36, color: Colors.grey.withValues(alpha: 0.25));
  }

  Widget _buildCaregiverQuickActions(
    ThemeData theme,
    bool isDark,
    Color primaryTextColor,
    Color emerald,
  ) {
    final actions = [
      {
        'icon': LucideIcons.calendarDays,
        'label': 'Medication\nSchedule',
        'color': emerald,
        'cb': widget.onGoToPatient,
      },
      {
        'icon': Icons.inventory_2_outlined,
        'label': 'Pill\nInventory',
        'color': emerald,
        'cb': widget.onGoToInventory,
      },
      {
        'icon': Icons.emergency_rounded,
        'label': 'Emergency\nDispense',
        'color': const Color(0xFFEF4444),
        'cb': _onCaregiverEmergencyDispense,
      },
      {
        'icon': LucideIcons.libraryBig,
        'label': 'Adherence\nHistory',
        'color': emerald,
        'cb': widget.onGoToHistory,
      },
      {
        'icon': LucideIcons.usersRound,
        'label': 'Emergency\nContacts',
        'color': emerald,
        'cb': () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => EmergencyContactsScreen(patientUid: widget.patientUid, isCaregiver: true),
          ),
        ),
      },
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Caregiver Quick Actions',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: primaryTextColor),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: actions.map((a) {
            return Expanded(
              child: GestureDetector(
                onTap: a['cb'] as VoidCallback,
                child: Column(
                  children: [
                    Builder(
                      builder: (context) {
                        final color = a['color'] as Color? ?? emerald;
                        final isRed = color == const Color(0xFFEF4444);
                        return Container(
                          width: 58,
                          height: 58,
                          decoration: BoxDecoration(
                            color: isRed
                                ? (isDark ? const Color(0xFF381212) : const Color(0xFFFEE2E2))
                                : (isDark ? const Color(0xFF1E2D25) : const Color(0xFFE8F8F0)),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: color.withValues(alpha: isDark ? 0.2 : 0.12),
                                blurRadius: 10,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: Icon(a['icon'] as IconData, color: color, size: 24),
                        );
                      },
                    ),
                    const SizedBox(height: 8),
                    Text(
                      a['label'] as String,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: primaryTextColor,
                        height: 1.25,
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
    ThemeData theme,
    bool isDark,
    Color primaryTextColor,
    Color secondaryTextColor,
    Color emerald,
  ) {
    final cardBgColor = theme.cardTheme.color ?? theme.colorScheme.surface;

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _todayLogsStream,
      builder: (context, logsSnap) {
        final allLogs = [...(logsSnap.data?.docs ?? [])]..sort((a, b) {
          final tsA = a.data()['timestamp'] as Timestamp?;
          final tsB = b.data()['timestamp'] as Timestamp?;
          if (tsA == null && tsB == null) return 0;
          if (tsA == null) return 1;
          if (tsB == null) return -1;
          return tsB.compareTo(tsA);
        });

        final recentLogs = allLogs.take(4).toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Patient Activity Logs',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: primaryTextColor),
                ),
                GestureDetector(
                  onTap: widget.onGoToHistory,
                  child: Text(
                    'Full History',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: emerald),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              decoration: BoxDecoration(
                color: cardBgColor,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.04),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: recentLogs.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Center(
                        child: Text(
                          'No recent activity logs recorded yet today.',
                          style: TextStyle(fontSize: 13, color: secondaryTextColor),
                        ),
                      ),
                    )
                  : Column(
                      children: List.generate(recentLogs.length, (i) {
                        final doc = recentLogs[i];
                        final data = doc.data();
                        final medName = data['medicationName'] as String? ?? 'Medication';
                        final status = data['status'] as String? ?? 'taken';
                        final ts = data['timestamp'] as Timestamp?;
                        final timeStr = ts != null ? DateFormat('hh:mm a').format(ts.toDate()) : 'Today';

                        final isTaken = status == 'taken';
                        final color = isTaken ? const Color(0xFF10B981) : const Color(0xFFEF4444);

                        return Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              child: Row(
                                children: [
                                  Container(
                                    width: 38,
                                    height: 38,
                                    decoration: BoxDecoration(
                                      color: color.withValues(alpha: 0.12),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      isTaken ? Icons.check_rounded : Icons.close_rounded,
                                      color: color,
                                      size: 18,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          medName,
                                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: primaryTextColor),
                                        ),
                                        Text(
                                          isTaken ? 'Dose taken at $timeStr' : 'Dose missed at $timeStr',
                                          style: TextStyle(fontSize: 12, color: secondaryTextColor),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: color.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      isTaken ? 'Taken' : 'Missed',
                                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (i < recentLogs.length - 1)
                              Divider(height: 1, indent: 64, endIndent: 16, color: theme.dividerColor),
                          ],
                        );
                      }),
                    ),
            ),
          ],
        );
      },
    );
  }
}
