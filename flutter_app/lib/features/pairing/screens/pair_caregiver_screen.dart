import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../services/pairing_service.dart';
import 'connection_requests_screen.dart';
import 'connect_patient_screen.dart';
import 'package:smartdose/shared/widgets/smartdose_loading.dart';

class PairCaregiverScreen extends StatefulWidget {
  const PairCaregiverScreen({super.key});

  @override
  State<PairCaregiverScreen> createState() => _PairCaregiverScreenState();
}

class _PairCaregiverScreenState extends State<PairCaregiverScreen> {
  final PairingService _pairingService = PairingService();
  final String? _uid = FirebaseAuth.instance.currentUser?.uid;
  final String _userName =
      FirebaseAuth.instance.currentUser?.displayName ?? 'User';
  final String _userEmail = FirebaseAuth.instance.currentUser?.email ?? '';

  // 0 = Patient (I'm the patient, share my QR)
  // 1 = Caregiver (I'm the caregiver, scan patient QR)
  int _selectedRole = 0;

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
        setState(() => _secondsRemaining--);
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

  void _showEnterCodeDialog() {
    final codeController = TextEditingController();
    bool isSubmitting = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final theme = Theme.of(ctx);
          final isDark = theme.brightness == Brightness.dark;
          final sheetBg = theme.cardTheme.color ?? theme.colorScheme.surface;
          final primary = theme.colorScheme.onSurface;
          const emerald = Color(0xFF00A36C);

          return Padding(
            padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: Container(
              decoration: BoxDecoration(
                color: sheetBg,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(28)),
              ),
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 36),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Drag handle
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF1E2D25)
                          : const Color(0xFFE8F8F0),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(LucideIcons.hash,
                        color: emerald, size: 26),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Enter Pairing Code',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: primary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Ask the patient for their code and enter it below.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: primary.withValues(alpha: 0.6),
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: codeController,
                    textCapitalization: TextCapitalization.characters,
                    maxLength: 8,
                    style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 6),
                    textAlign: TextAlign.center,
                    decoration: InputDecoration(
                      hintText: 'ABC-1234',
                      counterText: '',
                      filled: true,
                      fillColor: isDark
                          ? const Color(0xFF1E2D25)
                          : const Color(0xFFF0FDF9),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide:
                            const BorderSide(color: emerald, width: 2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  GestureDetector(
                    onTap: isSubmitting
                        ? null
                        : () async {
                            final code =
                                codeController.text.trim().toUpperCase();
                            if (code.length < 6) return;
                            setSheet(() => isSubmitting = true);
                            final uid = _uid;
                            if (uid != null) {
                              try {
                                final validated = await _pairingService
                                    .validatePairingToken(code);
                                await _pairingService.sendPairingRequest(
                                  patientUid: validated['patientUid'],
                                  patientName:
                                      validated['name'] ?? 'Patient',
                                  caregiverUid: uid,
                                  caregiverName: _userName,
                                  caregiverEmail: _userEmail,
                                  relationship:
                                      'Family Member / Caregiver',
                                );
                                if (mounted) {
                                  Navigator.pop(ctx);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                          'Pairing request sent successfully!'),
                                      backgroundColor: emerald,
                                    ),
                                  );
                                }
                              } catch (e) {
                                setSheet(() => isSubmitting = false);
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Error: $e'),
                                      backgroundColor: Colors.red,
                                    ),
                                  );
                                }
                              }
                            }
                          },
                    child: Container(
                      width: double.infinity,
                      height: 54,
                      decoration: BoxDecoration(
                        gradient: isSubmitting
                            ? null
                            : const LinearGradient(
                                colors: [
                                  Color(0xFF00A36C),
                                  Color(0xFF00C882)
                                ],
                              ),
                        color: isSubmitting ? Colors.grey.shade300 : null,
                        borderRadius: BorderRadius.circular(27),
                        boxShadow: isSubmitting
                            ? null
                            : [
                                BoxShadow(
                                  color:
                                      emerald.withValues(alpha: 0.35),
                                  blurRadius: 14,
                                  offset: const Offset(0, 5),
                                ),
                              ],
                      ),
                      child: isSubmitting
                          ? const Center(
                              child: SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: Colors.white,
                                ),
                              ),
                            )
                          : const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(LucideIcons.link,
                                    color: Colors.white, size: 20),
                                SizedBox(width: 10),
                                Text(
                                  'Connect',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
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
    final secondaryTextColor = primaryTextColor.withValues(alpha: 0.60);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.scaffoldBackgroundColor,
        elevation: 0,
        leading: IconButton(
          icon:
              Icon(Icons.arrow_back_ios_new_rounded, color: primaryTextColor),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Pair Caregiver',
          style: TextStyle(
              color: primaryTextColor,
              fontWeight: FontWeight.bold,
              fontSize: 18),
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
                  MaterialPageRoute(
                      builder: (_) => const ConnectionRequestsScreen()),
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
                        color: Colors.black
                            .withValues(alpha: isDark ? 0.2 : 0.04),
                        blurRadius: 10,
                      ),
                    ],
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Icon(LucideIcons.bell,
                          color: primaryTextColor, size: 20),
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
                              border:
                                  Border.all(color: cardBgColor, width: 1.5),
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
      body: SingleChildScrollView(
        padding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          children: [
            // ── Role Toggle ─────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF1E2D25)
                    : const Color(0xFFE8F8F0),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  _roleTab(
                    label: "I'm a Patient",
                    icon: LucideIcons.user,
                    selected: _selectedRole == 0,
                    isDark: isDark,
                    onTap: () => setState(() => _selectedRole = 0),
                  ),
                  _roleTab(
                    label: "I'm a Caregiver",
                    icon: LucideIcons.heartHandshake,
                    selected: _selectedRole == 1,
                    isDark: isDark,
                    onTap: () => setState(() => _selectedRole = 1),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            if (_selectedRole == 0) ...[
              // ── PATIENT VIEW: Show my QR for caregiver to scan ────────────
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF0D3B2E)
                      : const Color(0xFFE6F7F0),
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
                      child: const Icon(
                        LucideIcons.qrCode,
                        color: emerald,
                        size: 34,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Your Pairing Code',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: isDark
                            ? Colors.white
                            : const Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Show this QR code or share the code below with your caregiver. They will scan or enter it on their device.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.75)
                            : const Color(0xFF475569),
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
                          eyeStyle: const QrEyeStyle(
                            eyeShape: QrEyeShape.square,
                            color: Color(0xFF00A36C),
                          ),
                          dataModuleStyle: const QrDataModuleStyle(
                            dataModuleShape: QrDataModuleShape.square,
                            color: Color(0xFF065F46),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      GestureDetector(
                        onTap: () {
                          Clipboard.setData(ClipboardData(
                              text: _currentToken!.pairingCode));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content:
                                  Text('Pairing code copied to clipboard!'),
                              backgroundColor: emerald,
                            ),
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'CODE: ${_currentToken!.pairingCode}',
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.5,
                                  color: emerald,
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Icon(Icons.copy_rounded,
                                  size: 16, color: emerald),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _secondsRemaining > 0
                            ? 'Expires in $_formattedTimer'
                            : 'Code expired — tap Refresh',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _secondsRemaining < 60
                              ? const Color(0xFFEF4444)
                              : emerald,
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Refresh QR button
              GestureDetector(
                onTap: _generateNewToken,
                child: Container(
                  width: double.infinity,
                  height: 54,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF00A36C), Color(0xFF00C882)],
                    ),
                    borderRadius: BorderRadius.circular(27),
                    boxShadow: [
                      BoxShadow(
                        color: emerald.withValues(alpha: 0.35),
                        blurRadius: 14,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.refresh_rounded,
                          color: Colors.white, size: 22),
                      SizedBox(width: 10),
                      Text(
                        'Refresh QR Code',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 14),

              // Instruction step pills
              _stepRow(
                icon: LucideIcons.smartphone,
                text:
                    'Your caregiver opens SmartDose and taps "I\'m a Caregiver"',
                isDark: isDark,
                primaryTextColor: primaryTextColor,
              ),
              const SizedBox(height: 10),
              _stepRow(
                icon: LucideIcons.qrCode,
                text: 'They scan this QR code or enter the code shown above',
                isDark: isDark,
                primaryTextColor: primaryTextColor,
              ),
              const SizedBox(height: 10),
              _stepRow(
                icon: LucideIcons.shieldCheck,
                text: 'You approve the request and you\'re connected!',
                isDark: isDark,
                primaryTextColor: primaryTextColor,
              ),
            ] else ...[
              // ── CAREGIVER VIEW: Scan or enter patient's code ──────────────
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF1A2040)
                      : const Color(0xFFEEF2FF),
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
                            color: const Color(0xFF6366F1)
                                .withValues(alpha: 0.18),
                            blurRadius: 14,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Icon(
                        LucideIcons.heartHandshake,
                        color: Color(0xFF6366F1),
                        size: 32,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Connect to a Patient',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: isDark
                            ? Colors.white
                            : const Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Ask the patient to open SmartDose and show their QR code or share their pairing code with you.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.75)
                            : const Color(0xFF475569),
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Scan QR button (indigo/violet gradient for caregiver)
              GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const ConnectPatientScreen(),
                    ),
                  );
                },
                child: Container(
                  width: double.infinity,
                  height: 54,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF6366F1), Color(0xFF818CF8)],
                    ),
                    borderRadius: BorderRadius.circular(27),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF6366F1)
                            .withValues(alpha: 0.35),
                        blurRadius: 14,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(LucideIcons.qrCode,
                          color: Colors.white, size: 22),
                      SizedBox(width: 10),
                      Text(
                        'Scan Patient\'s QR Code',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 14),

              // Enter code button
              GestureDetector(
                onTap: _showEnterCodeDialog,
                child: Container(
                  width: double.infinity,
                  height: 54,
                  decoration: BoxDecoration(
                    color: cardBgColor,
                    borderRadius: BorderRadius.circular(27),
                    border: Border.all(
                        color: isDark
                            ? const Color(0xFF334155)
                            : const Color(0xFFE2E8F0),
                        width: 1.5),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black
                            .withValues(alpha: isDark ? 0.2 : 0.03),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(LucideIcons.hash,
                          color: Color(0xFF6366F1), size: 22),
                      const SizedBox(width: 10),
                      Text(
                        'Enter Pairing Code',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: primaryTextColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),

              _stepRow(
                icon: LucideIcons.user,
                text: 'Ask the patient to open SmartDose → Pair Caregiver',
                isDark: isDark,
                primaryTextColor: primaryTextColor,
              ),
              const SizedBox(height: 10),
              _stepRow(
                icon: LucideIcons.qrCode,
                text:
                    'Scan their QR code or ask them to share their pairing code',
                isDark: isDark,
                primaryTextColor: primaryTextColor,
              ),
              const SizedBox(height: 10),
              _stepRow(
                icon: LucideIcons.bell,
                text:
                    'The patient will receive a request to approve your connection',
                isDark: isDark,
                primaryTextColor: primaryTextColor,
              ),
            ],

            const SizedBox(height: 24),

            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(LucideIcons.shieldCheck,
                    color: emerald, size: 18),
                const SizedBox(width: 8),
                Text(
                  'End-to-end encrypted pairing',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: secondaryTextColor,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _roleTab({
    required String label,
    required IconData icon,
    required bool selected,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    const emerald = Color(0xFF00A36C);
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: 44,
          decoration: BoxDecoration(
            color: selected
                ? (isDark ? const Color(0xFF065F46) : Colors.white)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: emerald.withValues(alpha: 0.12),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 16,
                color: selected
                    ? emerald
                    : Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.45),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight:
                      selected ? FontWeight.bold : FontWeight.w500,
                  color: selected
                      ? emerald
                      : Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.45),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _stepRow({
    required IconData icon,
    required String text,
    required bool isDark,
    required Color primaryTextColor,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: isDark
                ? const Color(0xFF1E2D25)
                : const Color(0xFFE8F8F0),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 16, color: const Color(0xFF00A36C)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 7),
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13,
                color: primaryTextColor.withValues(alpha: 0.70),
                height: 1.4,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
