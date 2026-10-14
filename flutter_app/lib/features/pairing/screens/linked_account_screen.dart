import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../services/pairing_service.dart';
import 'pair_caregiver_screen.dart';
import 'connect_patient_screen.dart';
import 'package:smartdose/shared/widgets/smartdose_loading.dart';

class LinkedAccountScreen extends StatefulWidget {
  final bool isCaregiver;

  const LinkedAccountScreen({super.key, this.isCaregiver = false});

  @override
  State<LinkedAccountScreen> createState() => _LinkedAccountScreenState();
}

class _LinkedAccountScreenState extends State<LinkedAccountScreen> {
  final PairingService _pairingService = PairingService();
  final String? _uid = FirebaseAuth.instance.currentUser?.uid;
  bool _isUnlinking = false;

  String _getInitials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    } else if (parts.isNotEmpty && parts[0].isNotEmpty) {
      return parts[0][0].toUpperCase();
    }
    return widget.isCaregiver ? 'PT' : 'CG';
  }

  void _confirmUnlink(Map<String, dynamic> pairing) {
    final pairingId = pairing['pairingId'] as String? ?? '';
    final patientUid = pairing['patientUid'] as String? ?? '';
    final caregiverUid = pairing['caregiverUid'] as String? ?? '';
    final targetName = widget.isCaregiver
        ? (pairing['patientName'] ?? 'Patient')
        : (pairing['caregiverName'] ?? 'Caregiver');

    final theme = Theme.of(context);
    final cardBgColor = theme.cardTheme.color ?? theme.colorScheme.surface;
    final primaryTextColor = theme.colorScheme.onSurface;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        backgroundColor: cardBgColor,
        contentPadding: const EdgeInsets.all(24),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                color: Color(0xFFFEE2E2),
                shape: BoxShape.circle,
              ),
              child: const Icon(LucideIcons.userMinus, color: Color(0xFFEF4444), size: 30),
            ),
            const SizedBox(height: 18),
            Text(
              'Unlink $targetName?',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: primaryTextColor,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              widget.isCaregiver
                  ? 'Are you sure you want to unlink from $targetName? You will no longer receive alerts or view their medication schedule. All patient records will remain safe.'
                  : 'Are you sure you want to unlink your caregiver ($targetName)? They will immediately lose access to your medication schedule and alerts. Your records and dispenser pairing will remain intact.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                height: 1.45,
                color: primaryTextColor.withValues(alpha: 0.70),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    ),
                    child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () async {
                      Navigator.pop(ctx);
                      setState(() => _isUnlinking = true);
                      try {
                        await _pairingService.unlinkPairing(
                          pairingId: pairingId,
                          patientUid: patientUid,
                          caregiverUid: caregiverUid,
                        );
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('$targetName has been successfully unlinked.'),
                              backgroundColor: const Color(0xFF00A36C),
                              behavior: SnackBarBehavior.floating,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            ),
                          );
                        }
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Error unlinking: $e'),
                              backgroundColor: const Color(0xFFEF4444),
                            ),
                          );
                        }
                      } finally {
                        if (mounted) setState(() => _isUnlinking = false);
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFEF4444),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    ),
                    child: const Text('Unlink', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cardBgColor = theme.cardTheme.color ?? theme.colorScheme.surface;
    final primaryTextColor = theme.colorScheme.onSurface;
    final secondaryTextColor = primaryTextColor.withValues(alpha: 0.65);
    const emerald = Color(0xFF00A36C);

    final stream = widget.isCaregiver
        ? _pairingService.getConnectedPatientsStream(_uid ?? '')
        : _pairingService.getConnectedCaregiversStream(_uid ?? '');

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          widget.isCaregiver ? 'Linked Patient' : 'Linked Caregiver',
          style: TextStyle(fontWeight: FontWeight.bold, color: primaryTextColor),
        ),
        backgroundColor: cardBgColor,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: primaryTextColor),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Stack(
        children: [
          StreamBuilder<List<Map<String, dynamic>>>(
            stream: stream,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: SmartDoseLoading(size: 80));
              }

              final pairings = snapshot.data ?? [];
              final hasActive = pairings.isNotEmpty;

              if (!hasActive) {
                return _buildEmptyState(theme, isDark, primaryTextColor, secondaryTextColor, emerald);
              }

              final pairing = pairings.first;
              return _buildActivePairingView(pairing, theme, isDark, cardBgColor, primaryTextColor, secondaryTextColor, emerald);
            },
          ),
          if (_isUnlinking)
            Container(
              color: Colors.black.withValues(alpha: 0.45),
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SmartDoseLoading(size: 60, color: Colors.white),
                    SizedBox(height: 16),
                    Text(
                      'Unlinking account...',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(
    ThemeData theme,
    bool isDark,
    Color primaryTextColor,
    Color secondaryTextColor,
    Color emerald,
  ) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E2D25) : const Color(0xFFE8F8F0),
              shape: BoxShape.circle,
            ),
            child: Icon(
              widget.isCaregiver ? LucideIcons.userX : LucideIcons.heartHandshake,
              color: emerald,
              size: 38,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            widget.isCaregiver ? 'No Patient Linked' : 'No Caregiver Linked',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: primaryTextColor),
          ),
          const SizedBox(height: 10),
          Text(
            widget.isCaregiver
                ? 'Under SmartDose 1-to-1 pairing rules, each caregiver is linked to exactly one patient. Scan your patient\'s QR code to begin monitoring.'
                : 'Under SmartDose 1-to-1 pairing rules, you can connect one dedicated caregiver to help oversee your medication routine and receive alerts.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: secondaryTextColor, height: 1.45),
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              onPressed: () {
                if (widget.isCaregiver) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ConnectPatientScreen()),
                  );
                } else {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const PairCaregiverScreen()),
                  );
                }
              },
              icon: Icon(
                widget.isCaregiver ? LucideIcons.scanLine : LucideIcons.qrCode,
                color: Colors.white,
                size: 20,
              ),
              label: Text(
                widget.isCaregiver ? 'Scan Patient QR Code' : 'Display Pairing QR Code',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: emerald,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
                elevation: 0,
              ),
            ),
          ),
          const SizedBox(height: 36),
          _buildPairingPolicyCard(theme, isDark, primaryTextColor, secondaryTextColor, emerald),
        ],
      ),
    );
  }

  Widget _buildActivePairingView(
    Map<String, dynamic> pairing,
    ThemeData theme,
    bool isDark,
    Color cardBgColor,
    Color primaryTextColor,
    Color secondaryTextColor,
    Color emerald,
  ) {
    final name = widget.isCaregiver
        ? (pairing['patientName'] ?? 'Patient')
        : (pairing['caregiverName'] ?? 'Caregiver');
    final email = widget.isCaregiver
        ? (pairing['patientEmail'] ?? '')
        : (pairing['caregiverEmail'] ?? '');
    final relationship = pairing['relationship'] ?? (widget.isCaregiver ? 'Primary Patient' : 'Primary Caregiver');
    final role = pairing['role'] ?? (widget.isCaregiver ? 'Patient' : 'Primary Caregiver');

    final createdAt = pairing['createdAt'];
    String formattedDate = 'Recently';
    if (createdAt is Timestamp) {
      formattedDate = DateFormat('MMMM d, yyyy').format(createdAt.toDate());
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Subtle active pill indicator
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E2D25) : const Color(0xFFE8F8F0),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: emerald.withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Color(0xFF10B981),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '1-to-1 Account Pairing Active',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: isDark ? const Color(0xFFA7F3D0) : const Color(0xFF065F46),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Main Account Details Card
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: cardBgColor,
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.04),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 32,
                      backgroundColor: isDark ? const Color(0xFF1E2D25) : const Color(0xFFE8F8F0),
                      child: Text(
                        _getInitials(name),
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: emerald,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.bold,
                              color: primaryTextColor,
                            ),
                          ),
                          if (email.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              email,
                              style: TextStyle(fontSize: 13, color: secondaryTextColor),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                            decoration: BoxDecoration(
                              color: emerald.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              relationship,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: emerald,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                const Divider(height: 1),
                const SizedBox(height: 16),
                _buildInfoRow('Role Designation', role, primaryTextColor, secondaryTextColor),
                const SizedBox(height: 10),
                _buildInfoRow('Linked Since', formattedDate, primaryTextColor, secondaryTextColor),
                const SizedBox(height: 10),
                _buildInfoRow('Status', 'Active & Synchronized', primaryTextColor, secondaryTextColor, isStatus: true),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Policy Card
          _buildPairingPolicyCard(theme, isDark, primaryTextColor, secondaryTextColor, emerald),

          const SizedBox(height: 28),

          // Unlink Button
          SizedBox(
            width: double.infinity,
            height: 52,
            child: OutlinedButton.icon(
              onPressed: () => _confirmUnlink(pairing),
              icon: const Icon(LucideIcons.unlink, size: 18),
              label: Text(
                widget.isCaregiver ? 'Unlink Patient' : 'Unlink Caregiver',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFEF4444),
                side: const BorderSide(color: Color(0xFFFCA5A5), width: 1.5),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(
    String label,
    String value,
    Color primaryTextColor,
    Color secondaryTextColor, {
    bool isStatus = false,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(fontSize: 13, color: secondaryTextColor, fontWeight: FontWeight.w500)),
        if (isStatus)
          Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 16),
              const SizedBox(width: 4),
              Text(
                value,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF10B981)),
              ),
            ],
          )
        else
          Text(
            value,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: primaryTextColor),
          ),
      ],
    );
  }

  Widget _buildPairingPolicyCard(
    ThemeData theme,
    bool isDark,
    Color primaryTextColor,
    Color secondaryTextColor,
    Color emerald,
  ) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF17252A) : const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: emerald.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(LucideIcons.shieldCheck, color: emerald, size: 22),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Strict 1-to-1 Relationship',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : const Color(0xFF065F46),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'SmartDose guarantees patient privacy by enforcing that one patient is linked with only one caregiver. Unlinking immediately revokes caregiver access while safeguarding medication schedules and device configuration.',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.4,
                    color: isDark ? const Color(0xFFD1FAE5) : const Color(0xFF047857),
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
