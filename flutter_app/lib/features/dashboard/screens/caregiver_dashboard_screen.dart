import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'home_tab.dart';
import 'meds_tab.dart';
import 'history_tab.dart';
import 'alerts_tab.dart';
import 'profile_tab.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../pairing/services/pairing_service.dart';
import '../../pairing/screens/connect_patient_screen.dart';

// ---------------------------------------------------------------------------
// CaregiverHomeScreen
//
// Visual shell pixel-for-pixel identical to PatientHomeScreen:
//   • Same scaffold background
//   • Same bottom nav container, shadow, colors, AnimatedScale icon effect
//   • Same double-tap-back-to-exit behavior
//   • Same unread badge (red dot with white border)
//   • Same real-time Firestore listeners
//
// Content difference: 5 tabs instead of 4
//   0 — Dashboard  (PatientHomeTab — scoped to connected patient)
//   1 — Meds       (PatientMedsTab — scoped to connected patient)
//   2 — History    (PatientHistoryTab — scoped to connected patient)
//   3 — Alerts     (PatientAlertsTab, showAppBar: false so it fits inline)
//   4 — Profile    (PatientProfileTab)
//
// The badge count is shown on the Alerts tab (index 3), exactly the same
// way PatientHomeScreen shows it — a 10×10 red circle with a white border.
// ---------------------------------------------------------------------------

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
  StreamSubscription? _patientsSub;
  List<Map<String, dynamic>> _connectedPatients = [];
  String? _selectedPatientUid;
  String? _selectedPatientName;
  DateTime? _lastBackPressTime;

  @override
  void initState() {
    super.initState();
    _listenToRealtimeUserData();
    _listenToUnreadNotifications();
    _listenToConnectedPatients();
  }

  @override
  void dispose() {
    _userSub?.cancel();
    _unreadSub?.cancel();
    _patientsSub?.cancel();
    super.dispose();
  }

  // ── Firestore listeners ───────────────────────────────────────────────────

  void _listenToConnectedPatients() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    _patientsSub =
        PairingService().getConnectedPatientsStream(user.uid).listen((patients) {
      if (!mounted) return;
      setState(() {
        _connectedPatients = patients;
        if (patients.isNotEmpty) {
          if (_selectedPatientUid == null ||
              !patients.any((p) => p['patientUid'] == _selectedPatientUid)) {
            _selectedPatientUid = patients.first['patientUid'] as String?;
            _selectedPatientName = patients.first['patientName'] as String?;
          } else {
            final cur =
                patients.firstWhere((p) => p['patientUid'] == _selectedPatientUid);
            _selectedPatientName = cur['patientName'] as String?;
          }
        } else {
          _selectedPatientUid = null;
          _selectedPatientName = null;
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

  // ── Helpers ───────────────────────────────────────────────────────────────

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
    final parts = name.split(' ');
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    if (parts.isNotEmpty && parts[0].isNotEmpty) return parts[0][0].toUpperCase();
    return 'CG';
  }

  final List<int> _tabHistory = [0];

  void _switchTab(int index) {
    if (_currentIndex != index) {
      setState(() {
        _currentIndex = index;
        _tabHistory.add(index);
      });
    }
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

  String _getInitials(String name) {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    if (parts.isNotEmpty && parts[0].isNotEmpty) return parts[0][0].toUpperCase();
    return 'PT';
  }

  Widget _buildPatientSelectorHeader(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    if (_connectedPatients.isEmpty) {
      return Container(
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF451A03) : const Color(0xFFFEF3C7),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFFDE68A)),
        ),
        child: Row(
          children: [
            const Icon(Icons.link_off_rounded, color: Color(0xFFD97706), size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'No patient linked',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: isDark ? const Color(0xFFFDE68A) : const Color(0xFF92400E),
                    ),
                  ),
                  Text(
                    'Scan QR or enter PIN to view patient data',
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? const Color(0xFFFCD34D) : const Color(0xFFB45309),
                    ),
                  ),
                ],
              ),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ConnectPatientScreen()),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFD97706),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Connect', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E2D25) : const Color(0xFFE8F8F0),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF00A36C).withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.supervised_user_circle_rounded, color: Color(0xFF00A36C), size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: _connectedPatients.length == 1
                ? Text(
                    'Patient: ${_selectedPatientName ?? 'Linked Patient'}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: theme.colorScheme.onSurface,
                    ),
                  )
                : DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedPatientUid,
                      isDense: true,
                      icon: const Icon(Icons.arrow_drop_down, color: Color(0xFF00A36C)),
                      items: _connectedPatients.map((p) {
                        final pUid = p['patientUid'] as String? ?? '';
                        final pName = p['patientName'] as String? ?? 'Patient';
                        return DropdownMenuItem<String>(
                          value: pUid,
                          child: Text(
                            'Patient: $pName',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                        );
                      }).toList(),
                      onChanged: (newUid) {
                        if (newUid != null) {
                          final found = _connectedPatients.firstWhere((p) => p['patientUid'] == newUid);
                          setState(() {
                            _selectedPatientUid = newUid;
                            _selectedPatientName = found['patientName'] as String?;
                          });
                        }
                      },
                    ),
                  ),
          ),
          IconButton(
            icon: const Icon(Icons.qr_code_scanner_rounded, color: Color(0xFF00A36C), size: 20),
            tooltip: 'Link Another Patient',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ConnectPatientScreen()),
              );
            },
          ),
        ],
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

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
          setState(() {
            _currentIndex = 0;
            _tabHistory.clear();
            _tabHistory.add(0);
          });
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
          child: Column(
            children: [
              _buildPatientSelectorHeader(theme),
              Expanded(
                child: IndexedStack(
                  index: _currentIndex,
                  children: [
                    // ── Tab 0: Dashboard — scoped to linked patient
                    PatientHomeTab(
                      displayName: _selectedPatientName ?? _displayName,
                      userInitials: _selectedPatientName != null
                          ? _getInitials(_selectedPatientName!)
                          : _userInitials,
                      onGoToMeds: () => _switchTab(1),
                      onGoToHistory: () => _switchTab(2),
                      onGoToAlerts: () => _switchTab(3),
                      onGoToProfile: () => _switchTab(4),
                      unreadCount: _unreadAlertsCount,
                      isCaregiver: true,
                      patientUid: _selectedPatientUid,
                    ),

                    // ── Tab 1: Medications — scoped to linked patient
                    PatientMedsTab(
                      isCaregiver: true,
                      patientUid: _selectedPatientUid,
                    ),

                    // ── Tab 2: History — scoped to linked patient
                    PatientHistoryTab(
                      patientUid: _selectedPatientUid,
                    ),

                    // ── Tab 3: Alerts — inline alerts
                    PatientAlertsTab(
                      showAppBar: false,
                      onMarkAllRead: _markAllNotificationsRead,
                      patientUid: _selectedPatientUid,
                    ),

                    // ── Tab 4: Profile — caregiver profile
                    PatientProfileTab(
                      fallbackName: _displayName,
                      onSignOut: widget.onSignOut,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // ── Bottom nav — identical implementation to PatientHomeScreen ──────
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
              _buildNavItem(0, LucideIcons.layoutDashboard, 'Dashboard'),
              _buildNavItem(1, LucideIcons.pill, 'Meds'),
              _buildNavItem(2, LucideIcons.libraryBig, 'History'),
              _buildNavItem(3, LucideIcons.bell, 'Alerts',
                  badgeCount: _unreadAlertsCount),
              _buildNavItem(4, LucideIcons.userRound, 'Profile'),
            ],
          ),
        ),
      ),
    );
  }

  // ── _buildNavItem — copy of PatientHomeScreen._buildNavItem ──────────────
  // Identical logic: AnimatedScale on selection, red badge dot, same colors.
  Widget _buildNavItem(int index, IconData icon, String label,
      {int badgeCount = 0}) {
    final isSelected = _currentIndex == index;
    final theme = Theme.of(context);
    const primaryColor = Color(0xFF00A36C);
    final unselectedColor = theme.colorScheme.onSurface.withValues(alpha: 0.5);

    return InkWell(
      onTap: () => _switchTab(index),
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        // Slightly less horizontal padding than Patient (14→10) to
        // fit 5 items comfortably without shrinking the icons.
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
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
                if (badgeCount > 0)
                  Positioned(
                    top: -3,
                    right: -3,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: const Color(0xFFEF4444),
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: theme.colorScheme.surface, width: 1.5),
                      ),
                    ),
                  ),
              ],
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
}
