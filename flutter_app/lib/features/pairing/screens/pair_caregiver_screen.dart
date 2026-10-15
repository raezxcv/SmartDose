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
import 'package:smartdose/shared/widgets/app_avatar.dart';

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
  final ValueNotifier<int> _secondsRemaining = ValueNotifier<int>(600);

  Stream<List<Map<String, dynamic>>>? _caregiversStream;
  Stream<List<Map<String, dynamic>>>? _pendingRequestsStream;

  @override
  void initState() {
    super.initState();
    final uid = _uid;
    if (uid != null && uid.isNotEmpty) {
      _caregiversStream = _pairingService.getConnectedCaregiversStream(uid);
      _pendingRequestsStream = _pairingService.getPendingRequestsStream(uid);
    }
    _generateNewToken();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _secondsRemaining.dispose();
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    _secondsRemaining.value = 600;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsRemaining.value > 0) {
        _secondsRemaining.value--;
      } else {
        timer.cancel();
      }
    });
  }

  String _formatTimer(int seconds) {
    final m = (seconds / 60).floor().toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
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

  void _saveQrCode() {
    if (_currentToken == null) return;
    Clipboard.setData(ClipboardData(text: _currentToken!.pairingCode));
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Row(
          children: [
            Icon(LucideIcons.checkCircle2, color: Color(0xFF00A36C)),
            SizedBox(width: 10),
            Text('QR Code Ready'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Your pairing QR code and code text have been prepared and copied to your clipboard.',
              style: TextStyle(fontSize: 14, height: 1.4),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFE8F8F0),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _currentToken!.pairingCode,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                      color: Color(0xFF00A36C),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'You can share this code with your caregiver or display it anytime from this screen.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00A36C),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
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
            stream: _pendingRequestsStream ?? const Stream.empty(),
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
              stream: _caregiversStream,
              builder: (context, snapshot) {
                if (!snapshot.hasData && snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: SmartDoseLoading(size: 80));
                }

                final pairings = snapshot.data ?? [];
                if (pairings.isNotEmpty) {
                  return _buildAlreadyLinkedView(pairings.first, theme, isDark, cardBgColor, primaryTextColor, emerald);
                }

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
    final photoUrl = active['caregiverPhoto'] as String?;

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
                  'Caregiver Connected',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: primaryTextColor,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Your account is currently linked with $caregiverName. Pairing connects a patient and caregiver so they can access the appropriate medication information and features based on their roles.',
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
                      AppAvatar(
                        name: caregiverName,
                        photoUrl: photoUrl,
                        size: 48,
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
                      dataModuleStyle: const QrDataModuleStyle(
                        dataModuleShape: QrDataModuleShape.square,
                        color: Color(0xFF0F172A),
                      ),
                      eyeStyle: const QrEyeStyle(
                        eyeShape: QrEyeShape.square,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Timer Badge (uses ValueListenableBuilder to avoid rebuilding whole widget)
                  ValueListenableBuilder<int>(
                    valueListenable: _secondsRemaining,
                    builder: (context, seconds, _) {
                      return Container(
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
                              'Expires in ${_formatTimer(seconds)}',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: emerald,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
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

                  // Action buttons: Save QR and Regenerate QR Code
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ElevatedButton.icon(
                        onPressed: _saveQrCode,
                        icon: const Icon(LucideIcons.download, size: 16, color: Colors.white),
                        label: const Text(
                          'Save QR',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: emerald,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      OutlinedButton.icon(
                        onPressed: _generateNewToken,
                        icon: Icon(LucideIcons.refreshCw, size: 16, color: emerald),
                        label: Text(
                          'Regenerate',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: emerald),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: emerald,
                          side: BorderSide(color: emerald.withValues(alpha: 0.4)),
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Pairing Explanation Banner
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
                    'Pairing connects a patient and caregiver so they can access the appropriate medication information and features based on their roles.',
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
