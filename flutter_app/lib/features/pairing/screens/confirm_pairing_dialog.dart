import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/pairing_service.dart';
import 'package:smartdose/shared/widgets/smartdose_loading.dart';
import 'package:smartdose/shared/widgets/app_avatar.dart';

class ConfirmPairingDialog extends StatefulWidget {
  final Map<String, dynamic> patientData;

  const ConfirmPairingDialog({super.key, required this.patientData});

  @override
  State<ConfirmPairingDialog> createState() => _ConfirmPairingDialogState();
}

class _ConfirmPairingDialogState extends State<ConfirmPairingDialog> {
  final PairingService _pairingService = PairingService();
  final String? _caregiverUid = FirebaseAuth.instance.currentUser?.uid;
  final String _caregiverName = FirebaseAuth.instance.currentUser?.displayName ?? 'Caregiver';
  final String _caregiverEmail = FirebaseAuth.instance.currentUser?.email ?? '';

  String _selectedRelationship = 'Daughter';
  bool _isSubmitting = false;

  final List<String> _relationships = [
    'Daughter',
    'Son',
    'Spouse',
    'Parent',
    'Sibling',
    'Grandchild',
    'Nurse / Caregiver',
    'Other',
  ];

  Future<void> _sendRequest() async {
    if (_caregiverUid == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please log in to send pairing request.')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      await _pairingService.sendPairingRequest(
        patientUid: widget.patientData['patientUid'],
        patientName: widget.patientData['name'] ?? 'Patient',
        caregiverUid: _caregiverUid!,
        caregiverName: _caregiverName,
        caregiverEmail: _caregiverEmail,
        relationship: _selectedRelationship,
        tokenId: widget.patientData['tokenId'],
      );

      if (mounted) {
        setState(() => _isSubmitting = false);
        Navigator.pop(context); // Close dialog

        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            title: const Text('Pairing Request Sent!'),
            content: Text(
              'A connection request has been sent to ${widget.patientData['name']}. Once the patient approves on their SmartDose app, your accounts will be linked.',
              style: const TextStyle(fontSize: 14, height: 1.4),
            ),
            actions: [
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00A36C),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('OK', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceAll('Exception: ', '')),
            backgroundColor: const Color(0xFFEF4444),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const emerald = Color(0xFF00A36C);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cardBgColor = theme.cardTheme.color ?? theme.colorScheme.surface;
    final primaryTextColor = theme.colorScheme.onSurface;
    final secondaryTextColor = primaryTextColor.withValues(alpha: 0.65);

    final patientName = widget.patientData['name'] ?? 'Patient';
    final patientEmail = widget.patientData['email'] ?? '';
    final age = widget.patientData['age'];
    final bool isAlreadyLinked = widget.patientData['isAlreadyLinked'] == true;
    final photoUrl = widget.patientData['photoUrl'] ??
        widget.patientData['avatarUrl'] ??
        widget.patientData['profileImage'];

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      backgroundColor: cardBgColor,
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Patient Avatar
            AppAvatar(
              name: patientName,
              photoUrl: photoUrl,
              radius: 36,
            ),
            const SizedBox(height: 16),

            // Patient Name & Info
            Text(
              patientName,
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: primaryTextColor),
              textAlign: TextAlign.center,
            ),
            if (patientEmail.isNotEmpty || age != null) ...[
              const SizedBox(height: 4),
              Text(
                '${age != null ? 'Age $age · ' : ''}$patientEmail',
                style: TextStyle(fontSize: 13, color: secondaryTextColor),
                textAlign: TextAlign.center,
              ),
            ],

            const SizedBox(height: 16),

            // Already linked notice
            if (isAlreadyLinked) ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF451A03) : const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFFDE68A)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: Color(0xFFD97706), size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'This patient already has an active caregiver paired. If you need to manage this patient, please ask them to unlink their existing caregiver first.',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? const Color(0xFFFDE68A) : const Color(0xFF92400E),
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ] else ...[
              const Divider(height: 1),
              const SizedBox(height: 18),

              // Relationship Selector Title
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Select Your Relationship',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: primaryTextColor),
                ),
              ),
              const SizedBox(height: 12),

              // Relationship Choice Chips
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _relationships.map((rel) {
                  final isSelected = _selectedRelationship == rel;
                  return ChoiceChip(
                    label: Text(rel),
                    selected: isSelected,
                    selectedColor: emerald,
                    backgroundColor: isDark ? const Color(0xFF27272A) : const Color(0xFFF3F4F6),
                    labelStyle: TextStyle(
                      color: isSelected
                          ? Colors.white
                          : (isDark ? Colors.white70 : const Color(0xFF4B5563)),
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      fontSize: 13,
                    ),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    side: BorderSide.none,
                    onSelected: (selected) {
                      if (selected) {
                        setState(() => _selectedRelationship = rel);
                      }
                    },
                  );
                }).toList(),
              ),

              const SizedBox(height: 24),
            ],

            // Action Button
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: (isAlreadyLinked || _isSubmitting) ? null : _sendRequest,
                style: ElevatedButton.styleFrom(
                  backgroundColor: emerald,
                  disabledBackgroundColor: Colors.grey.shade400,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: _isSubmitting
                    ? const SmartDoseLoading(size: 32, color: Colors.white)
                    : Text(
                        isAlreadyLinked ? 'Patient Already Linked' : 'Send Connection Request',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
