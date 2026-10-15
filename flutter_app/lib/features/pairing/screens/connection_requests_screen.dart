import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../services/pairing_service.dart';
import 'package:smartdose/shared/widgets/smartdose_loading.dart';
import 'package:smartdose/shared/widgets/app_avatar.dart';

class ConnectionRequestsScreen extends StatefulWidget {
  const ConnectionRequestsScreen({super.key});

  @override
  State<ConnectionRequestsScreen> createState() => _ConnectionRequestsScreenState();
}

class _ConnectionRequestsScreenState extends State<ConnectionRequestsScreen> {
  final PairingService _pairingService = PairingService();
  final String? _uid = FirebaseAuth.instance.currentUser?.uid;

  Future<void> _approveRequest(String requestId, Map<String, dynamic> requestData) async {
    try {
      await _pairingService.approvePairingRequest(requestId, requestData);
      if (mounted) {
        _showSuccessAnimation(requestData['caregiverName'] ?? 'Caregiver');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error approving request: $e')),
        );
      }
    }
  }

  Future<void> _rejectRequest(String requestId) async {
    try {
      await _pairingService.rejectPairingRequest(requestId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Connection request declined.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error declining request: $e')),
        );
      }
    }
  }

  void _showSuccessAnimation(String caregiverName) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Success',
      transitionDuration: const Duration(milliseconds: 350),
      pageBuilder: (ctx, anim1, anim2) {
        return const SizedBox.shrink();
      },
      transitionBuilder: (ctx, anim1, anim2, child) {
        return Transform.scale(
          scale: anim1.value,
          child: Opacity(
            opacity: anim1.value,
            child: AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
              contentPadding: const EdgeInsets.all(28),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: const BoxDecoration(
                      color: Color(0xFFD1FAE5),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 48),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Caregiver Connected Successfully',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1F2937)),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '$caregiverName is now connected to your SmartDose account.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 14, color: Color(0xFF6B7280), height: 1.4),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(ctx),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF10B981),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: const Text('Done', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    const emerald = Color(0xFF10B981);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAF8),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Color(0xFF1F2937)),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Connection Requests',
          style: TextStyle(color: Color(0xFF1F2937), fontWeight: FontWeight.bold, fontSize: 18),
        ),
      ),
      body: _uid == null
          ? const Center(child: Text('Please log in first'))
          : StreamBuilder<List<Map<String, dynamic>>>(
              stream: _pairingService.getPendingRequestsStream(_uid!),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: SmartDoseLoading(size: 80));
                }

                final requests = snapshot.data ?? [];
                if (requests.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 80,
                          height: 80,
                          decoration: const BoxDecoration(
                            color: Color(0xFFECFDF5),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.person_add_disabled_outlined, color: emerald, size: 40),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'No Pending Requests',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1F2937)),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Caregiver requests will appear here after they scan your QR code.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 14, color: Color(0xFF6B7280)),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.all(20),
                  itemCount: requests.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 16),
                  itemBuilder: (context, index) {
                    final req = requests[index];
                    final requestId = req['requestId'];
                    final caregiverName = req['caregiverName'] ?? 'Caregiver';
                    final caregiverEmail = req['caregiverEmail'] ?? '';
                    final relationship = req['relationship'] ?? 'Family Member';
                    final requestedAt = req['requestedAt'];

                    String timeStr = 'Just now';
                    if (requestedAt != null) {
                      try {
                        final dt = requestedAt.toDate();
                        timeStr = DateFormat('MMM d, h:mm a').format(dt);
                      } catch (_) {}
                    }

                    return Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              // Caregiver Profile Photo / Avatar
                              AppAvatar(
                                name: caregiverName,
                                photoUrl: req['caregiverPhoto'],
                                radius: 26,
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      caregiverName,
                                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Color(0xFF1F2937)),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      caregiverEmail,
                                      style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          const Divider(height: 1, color: Color(0xFFF3F4F6)),
                          const SizedBox(height: 12),

                          // Relationship & Request Time
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFECFDF5),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  'Relationship: $relationship',
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF047857)),
                                ),
                              ),
                              Text(
                                timeStr,
                                style: const TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),

                          // Action Buttons: Approve / Reject
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () => _rejectRequest(requestId),
                                  style: OutlinedButton.styleFrom(
                                    side: const BorderSide(color: Color(0xFFE5E7EB)),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                  ),
                                  child: const Text('Decline', style: TextStyle(color: Color(0xFF4B5563), fontWeight: FontWeight.bold)),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: () => _approveRequest(requestId, req),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: emerald,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                  ),
                                  child: const Text('Approve', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}
