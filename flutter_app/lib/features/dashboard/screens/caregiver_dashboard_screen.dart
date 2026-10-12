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
//   0 — Dashboard  (PatientHomeTab — same look, live data for current user)
//   1 — Meds       (PatientMedsTab)
//   2 — History    (PatientHistoryTab)
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
  DateTime? _lastBackPressTime;

  @override
  void initState() {
    super.initState();
    _listenToRealtimeUserData();
    _listenToUnreadNotifications();
  }

  @override
  void dispose() {
    _userSub?.cancel();
    _unreadSub?.cancel();
    super.dispose();
  }

  // ── Firestore listeners ───────────────────────────────────────────────────

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
          child: IndexedStack(
            index: _currentIndex,
            children: [
              // ── Tab 0: Dashboard — same PatientHomeTab, same visual
              PatientHomeTab(
                displayName: _displayName,
                userInitials: _userInitials,
                onGoToMeds: () => _switchTab(1),
                onGoToHistory: () => _switchTab(2),
                // Bell icon in header switches to Alerts tab (index 3)
                onGoToAlerts: () => _switchTab(3),
                onGoToProfile: () => _switchTab(4),
                unreadCount: _unreadAlertsCount,
              ),

              // ── Tab 1: Medications — identical to patient
              const PatientMedsTab(),

              // ── Tab 2: History — identical to patient
              const PatientHistoryTab(),

              // ── Tab 3: Alerts — showAppBar: false so it renders inline
              //    (no nested Scaffold/AppBar inside our shell)
              PatientAlertsTab(
                showAppBar: false,
                onMarkAllRead: _markAllNotificationsRead,
              ),

              // ── Tab 4: Profile — identical to patient
              PatientProfileTab(
                fallbackName: _displayName,
                onSignOut: widget.onSignOut,
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
