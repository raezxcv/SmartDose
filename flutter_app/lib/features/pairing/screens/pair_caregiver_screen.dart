import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../services/pairing_service.dart';
import 'connection_requests_screen.dart';
import 'linked_account_screen.dart';
import 'package:smartdose/shared/widgets/smartdose_loading.dart';

class PairCaregiverScreen extends StatefulWidget {
  const PairCaregiverScreen({super.key});

  @override
  State<PairCaregiverScreen> createState() => _PairCaregiverScreenState();
}

class _PairCaregiverScreenState extends State<PairCaregiverScreen> {
  final PairingService _pairingService = PairingService();
  final String? _uid = FirebaseAuth.instance.currentUser?.uid;
  final String _userName = FirebaseAuth.instance.currentUser?.displayName ?? 'Patient';
  final String _userEmail = FirebaseAuth.instance.currentUser?.email ?? '';

  PairingTokenModel? _currentToken;
  bool _isLoading = false;
  Timer? _timer;
  int _secondsRemaining = 600;

  @override
  void initState() {
    super.initState();
    _generateNewToken();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    setState(() => _secondsRemaining = 600);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsRemaining > 0) {
        if (mounted) setState(() => _secondsRemaining--);
      } else {
        timer.cancel();
      }
    });
  }

  String get _formattedTimer {
    final m = (_secondsRemaining / 60).floor().toString().padLeft(2, '0');
    final s = (_secondsRemaining % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Future<void> _generateNewToken() async {
    final uid = _uid;
    if (uid == null) return;
    setState(() => _isLoading = true);
    try {
      final token = await _pairingService.generatePairingToken(
        patientUid: uid,
        patientName: _userName,
        patientEmail: _userEmail,
      );
      if (mounted) {
        setState(() {
          _currentToken = token;
          _isLoading = false;
        });
        _startTimer();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error generating QR code: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const emerald = Color(0xFF00A36C);
    final currentUid = _uid;

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cardBgColor = theme.cardTheme.color ?? theme.colorScheme.surface;
    final primaryTextColor = theme.colorScheme.onSurface;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.scaffoldBackgroundColor,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: primaryTextColor),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Pair Caregiver',
          style: TextStyle(
            color: primaryTextColor,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        actions: [
          StreamBuilder<List<Map<String, dynamic>>>(
            stream: currentUid != null
                ? _pairingService.getPendingRequestsStream(currentUid)
                : const Stream.empty(),
            builder: (context, snapshot) {
              final pendingCount = snapshot.data?.length ?? 0;
              return GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ConnectionRequestsScreen()),
                ),
                child: Container(
                  width: 44,
                  height: 44,
                  margin: const EdgeInsets.only(right: 12),
                  decoration: BoxDecoration(
                    color: cardBgColor,
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
                      if (pendingCount > 0)
                        Positioned(
                          top: 8,
                          right: 8,
                          child: Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: const Color(0xFFEF4444),
                              shape: BoxShape.circle,
                              border: Border.all(color: cardBgColor, width: 1.5),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: currentUid == null
          ? const Center(child: Text('Please sign in to manage account pairing.'))
          : StreamBuilder<List<Map<String, dynamic>>>(
              stream: _pairingService.getConnectedCaregiversStream(currentUid),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: SmartDoseLoading(size: 80));
                }

                final pairings = snapshot.data ?? [];
                if (pairings.isNotEmpty) {
                  // Patient already has an active linked caregiver -> enforce 1-to-1
                  return _buildAlreadyLinkedView(pairings.first, theme, isDark, cardBgColor, primaryTextColor, emerald);
                }

                // Patient is not linked -> display dedicated pairing QR code
                return _buildPairingQrView(theme, isDark, cardBgColor, primaryTextColor, emerald);
              },
            ),
    );
  }

  Widget _buildAlreadyLinkedView(
    Map<String, dynamic> active,
    ThemeData theme,
    bool isDark,
    Color cardBgColor,
    Color primaryTextColor,
    Color emerald,
  ) {
    final secondaryTextColor = primaryTextColor.withValues(alpha: 0.65);
    final caregiverName = active['caregiverName'] ?? 'Caregiver';
    final caregiverEmail = active['caregiverEmail'] ?? '';
    final role = active['role'] ?? 'Primary Caregiver';

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: cardBgColor,
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.04),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E2D25) : const Color(0xFFE8F8F0),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(LucideIcons.userCheck, color: emerald, size: 34),
                ),
                const SizedBox(height: 18),
                Text(
                  'Caregiver Already Linked',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: primaryTextColor,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Your account is currently linked with $caregiverName. SmartDose enforces a strict 1-to-1 relationship. You cannot generate a new pairing code while your account remains linked.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: secondaryTextColor, height: 1.45),
                ),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E1E22) : const Color(0xFFF9FAFB),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isDark ? const Color(0xFF27272A) : const Color(0xFFE5E7EB),
                    ),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 24,
                        backgroundColor: isDark ? const Color(0xFF1E2D25) : const Color(0xFFE8F8F0),
                        child: Text(
                          caregiverName.isNotEmpty ? caregiverName[0].toUpperCase() : 'C',
                          style: TextStyle(fontWeight: FontWeight.bold, color: emerald, fontSize: 18),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              caregiverName,
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: primaryTextColor),
                            ),
                            if (caregiverEmail.isNotEmpty)
                              Text(caregiverEmail, style: TextStyle(fontSize: 12, color: secondaryTextColor)),
                            const SizedBox(height: 4),
                            Text(role, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: emerald)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(builder: (_) => const LinkedAccountScreen(isCaregiver: false)),
                      );
                    },
                    icon: const Icon(LucideIcons.userRound, color: Colors.white, size: 18),
                    label: const Text(
                      'Manage Linked Account',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: emerald,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 0,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPairingQrView(
    ThemeData theme,
    bool isDark,
    Color cardBgColor,
    Color primaryTextColor,
    Color emerald,
  ) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0D3B2E) : const Color(0xFFE6F7F0),
              borderRadius: BorderRadius.circular(28),
            ),
            child: Column(
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: emerald.withValues(alpha: 0.15),
                        blurRadius: 14,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Icon(LucideIcons.qrCode, color: emerald, size: 34),
                ),
                const SizedBox(height: 18),
                Text(
                  'Your Pairing Code',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Show this QR code or share the code below with your caregiver. They will scan or enter it on their device.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.white.withValues(alpha: 0.75) : const Color(0xFF475569),
                    height: 1.4,
                  ),
                ),

                if (_isLoading)
                  const Padding(
                    padding: EdgeInsets.only(top: 24),
                    child: SmartDoseLoading(size: 44),
                  )
                else if (_currentToken != null) ...[
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.06),
                          blurRadius: 12,
                        ),
                      ],
                    ),
                    child: QrImageView(
                      data: _currentToken!.qrPayload,
                      version: QrVersions.auto,
                      size: 180.0,
                      foregroundColor: const Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Timer Badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E2D25) : Colors.white,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(LucideIcons.timer, size: 14, color: emerald),
                        const SizedBox(width: 6),
                        Text(
                          'Expires in $_formattedTimer',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: emerald,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Human-readable code box
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E2D25) : Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: emerald.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          _currentToken!.pairingCode,
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 2,
                            color: isDark ? Colors.white : const Color(0xFF0F172A),
                          ),
                        ),
                        const SizedBox(width: 12),
                        IconButton(
                          icon: Icon(LucideIcons.copy, size: 18, color: emerald),
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: _currentToken!.pairingCode));
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: const Text('Pairing code copied to clipboard!'),
                                backgroundColor: emerald,
                                duration: const Duration(seconds: 2),
                              ),
                            );
                          },
                          tooltip: 'Copy Code',
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Regenerate Button
                  TextButton.icon(
                    onPressed: _generateNewToken,
                    icon: Icon(LucideIcons.refreshCw, size: 16, color: emerald),
                    label: Text(
                      'Regenerate QR Code',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: emerald),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),

          // 1-to-1 Pairing Reminder
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF18221E) : const Color(0xFFF9FAFB),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isDark ? const Color(0xFF27272A) : const Color(0xFFE5E7EB),
              ),
            ),
            child: Row(
              children: [
                Icon(LucideIcons.shieldCheck, color: emerald, size: 20),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'SmartDose links one patient with one caregiver. Connecting automatically grants your caregiver access to your adherence logs and alerts.',
                    style: TextStyle(fontSize: 12, height: 1.35),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
