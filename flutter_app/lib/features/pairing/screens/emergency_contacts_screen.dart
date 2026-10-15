import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../services/pairing_service.dart';
import 'package:smartdose/shared/widgets/app_avatar.dart';

class EmergencyContactsScreen extends StatefulWidget {
  final bool isCaregiver;
  final String? patientUid;
  const EmergencyContactsScreen({super.key, this.isCaregiver = false, this.patientUid});

  @override
  State<EmergencyContactsScreen> createState() =>
      _EmergencyContactsScreenState();
}

class _EmergencyContactsScreenState extends State<EmergencyContactsScreen> {
  final PairingService _pairingService = PairingService();
  Stream<List<Map<String, dynamic>>>? _caregiversStream;
  Stream<QuerySnapshot<Map<String, dynamic>>>? _contactsStream;

  String? get _targetUid => widget.patientUid ?? FirebaseAuth.instance.currentUser?.uid;
  final _userName =
      FirebaseAuth.instance.currentUser?.displayName ?? 'Patient';

  @override
  void initState() {
    super.initState();
    _initStreams();
  }

  void _initStreams() {
    final uid = _targetUid;
    if (uid != null) {
      _caregiversStream = _pairingService.getConnectedCaregiversStream(uid);
    }
    _contactsStream = FirebaseFirestore.instance.collection('contacts').snapshots();
  }

  Widget _buildPinnedCaregiverCard(
    Map<String, dynamic> caregiver,
    ThemeData theme,
    bool isDark,
    Color cardBgColor,
    Color primaryTextColor,
    Color secondaryTextColor,
    Color emerald,
  ) {
    final name = caregiver['caregiverName'] as String? ?? 'Caregiver';
    final email = caregiver['caregiverEmail'] as String? ?? '';
    final phone = caregiver['caregiverPhone'] as String? ?? caregiver['phone'] as String? ?? '';
    final relationship = caregiver['relationship'] as String? ?? 'Primary Caregiver';
    final photo = caregiver['caregiverPhoto'] as String? ?? caregiver['photoUrl'] as String?;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cardBgColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: emerald.withValues(alpha: 0.4),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: emerald.withValues(alpha: isDark ? 0.15 : 0.08),
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
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E2D25) : const Color(0xFFE8F8F0),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: emerald.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(LucideIcons.shieldCheck, color: emerald, size: 13),
                    const SizedBox(width: 5),
                    Text(
                      'PRIMARY EMERGENCY CAREGIVER',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        color: emerald,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.link_rounded, size: 12, color: Color(0xFF10B981)),
                    SizedBox(width: 3),
                    Text(
                      'Linked',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF10B981)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              AppAvatar(
                name: name,
                photoUrl: photo,
                radius: 26,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: primaryTextColor,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      relationship,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: emerald,
                      ),
                    ),
                    if (phone.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Icon(Icons.phone_outlined, size: 13, color: secondaryTextColor),
                          const SizedBox(width: 4),
                          Text(
                            phone,
                            style: TextStyle(fontSize: 12, color: secondaryTextColor),
                          ),
                        ],
                      ),
                    ] else if (email.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Icon(Icons.mail_outline_rounded, size: 13, color: secondaryTextColor),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              email,
                              style: TextStyle(fontSize: 12, color: secondaryTextColor),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              if (phone.isNotEmpty)
                IconButton(
                  icon: Icon(LucideIcons.send, size: 18, color: emerald),
                  tooltip: 'Send Test SMS',
                  onPressed: () => _sendTestSms({
                    'name': name,
                    'phone': phone,
                    'relationship': relationship,
                  }),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF131D18) : const Color(0xFFF0FDF4),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(LucideIcons.info, size: 14, color: emerald.withValues(alpha: 0.8)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Automatically notified via SIM800L SMS during missed doses & emergencies.',
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? const Color(0xFFA7F3D0) : const Color(0xFF065F46),
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

  Future<void> _showAddContactDialog({Map<String, dynamic>? existingContact}) async {
    final uid = _targetUid;
    if (uid == null) return;

    final nameCtrl =
        TextEditingController(text: existingContact?['name'] ?? '');
    final phoneCtrl =
        TextEditingController(text: existingContact?['phone'] ?? '');
    String relationship = existingContact?['relationship'] ?? 'Caregiver';
    bool isSaving = false;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final theme = Theme.of(ctx);
          final isDark = theme.brightness == Brightness.dark;
          final sheetBg = theme.cardTheme.color ?? theme.colorScheme.surface;
          final primaryTextColor = theme.colorScheme.onSurface;
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
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Handle
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: primaryTextColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: isDark
                                ? const Color(0xFF1E2D25)
                                : const Color(0xFFE8F8F0),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(LucideIcons.userPlus,
                              color: emerald, size: 22),
                        ),
                        const SizedBox(width: 14),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              existingContact != null
                                  ? 'Edit Emergency Contact'
                                  : 'Add Emergency Contact',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: primaryTextColor,
                              ),
                            ),
                            Text(
                              'SIM800L module will send SMS to this contact',
                              style: TextStyle(
                                fontSize: 12,
                                color: primaryTextColor.withValues(alpha: 0.6),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Contact Name',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: primaryTextColor.withValues(alpha: 0.8),
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: nameCtrl,
                      style: TextStyle(color: primaryTextColor),
                      decoration: InputDecoration(
                        hintText: 'e.g. Dr. Sarah Jenkins or Mom',
                        filled: true,
                        fillColor: isDark
                            ? const Color(0xFF1E2D25)
                            : const Color(0xFFF8FAFC),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Phone Number (SIM800L Target)',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: primaryTextColor.withValues(alpha: 0.8),
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: phoneCtrl,
                      keyboardType: TextInputType.phone,
                      style: TextStyle(color: primaryTextColor),
                      decoration: InputDecoration(
                        hintText: 'e.g. +639171234567',
                        filled: true,
                        fillColor: isDark
                            ? const Color(0xFF1E2D25)
                            : const Color(0xFFF8FAFC),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Relationship',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: primaryTextColor.withValues(alpha: 0.8),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        'Primary Caregiver',
                        'Family Member',
                        'Doctor / Nurse',
                        'Friend'
                      ].map((rel) {
                        final isSel = relationship == rel;
                        return ChoiceChip(
                          label: Text(rel),
                          selected: isSel,
                          onSelected: (_) {
                            setSheetState(() => relationship = rel);
                          },
                          selectedColor: emerald,
                          labelStyle: TextStyle(
                            color: isSel ? Colors.white : primaryTextColor,
                            fontWeight: isSel
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                          backgroundColor: isDark
                              ? const Color(0xFF1E2D25)
                              : const Color(0xFFF1F5F9),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                            side: BorderSide.none,
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 28),
                    GestureDetector(
                      onTap: isSaving
                          ? null
                          : () async {
                              final name = nameCtrl.text.trim();
                              final phone = phoneCtrl.text.trim();
                              if (name.isEmpty || phone.isEmpty) {
                                ScaffoldMessenger.of(ctx).showSnackBar(
                                  const SnackBar(
                                      content: Text(
                                          'Please enter both name and phone number')),
                                );
                                return;
                              }

                              setSheetState(() => isSaving = true);
                              try {
                                final contactData = {
                                  'name': name,
                                  'phone': phone,
                                  'relationship': relationship,
                                  'patientUid': uid,
                                  'updatedAt': FieldValue.serverTimestamp(),
                                };

                                if (existingContact != null &&
                                    existingContact['id'] != null) {
                                  await FirebaseFirestore.instance
                                      .collection('contacts')
                                      .doc(existingContact['id'])
                                      .update(contactData);
                                } else {
                                  contactData['createdAt'] =
                                      FieldValue.serverTimestamp();
                                  await FirebaseFirestore.instance
                                      .collection('contacts')
                                      .add(contactData);
                                }

                                if (mounted) {
                                  Navigator.pop(ctx);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(existingContact != null
                                          ? 'Contact updated'
                                          : 'Contact added successfully'),
                                      backgroundColor: emerald,
                                    ),
                                  );
                                }
                              } catch (e) {
                                setSheetState(() => isSaving = false);
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Error saving contact: $e'),
                                      backgroundColor: Colors.red,
                                    ),
                                  );
                                }
                              }
                            },
                      child: Container(
                        width: double.infinity,
                        height: 52,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF00A36C), Color(0xFF00C882)],
                          ),
                          borderRadius: BorderRadius.circular(26),
                          boxShadow: [
                            BoxShadow(
                              color: emerald.withValues(alpha: 0.3),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Center(
                          child: isSaving
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white),
                                )
                              : Text(
                                  existingContact != null
                                      ? 'Update Contact'
                                      : 'Save Contact',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _sendTestSms(Map<String, dynamic> contact) async {
    final uid = _targetUid;
    if (uid == null) return;

    final phone = contact['phone'] as String? ?? '';
    final name = contact['name'] as String? ?? 'Caregiver';

    if (phone.isEmpty) return;

    try {
      await FirebaseFirestore.instance.collection('sms_queue').add({
        'patientUid': uid,
        'patientName': _userName,
        'to': phone,
        'contactName': name,
        'message':
            'SmartDose SIM800L Test: Emergency alert system active for $_userName.',
        'status': 'pending',
        'triggeredBy': 'manual_test',
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.send_rounded, color: Colors.white, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('Test SMS queued for $name ($phone) via SIM800L'),
                ),
              ],
            ),
            backgroundColor: const Color(0xFF00A36C),
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error queuing SMS: $e')),
        );
      }
    }
  }

  Future<void> _deleteContact(String contactId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Remove Contact'),
        content:
            const Text('Are you sure you want to remove this emergency contact?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await FirebaseFirestore.instance
          .collection('contacts')
          .doc(contactId)
          .delete();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Contact removed')),
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
          'Emergency Contacts',
          style: TextStyle(
              color: primaryTextColor,
              fontWeight: FontWeight.bold,
              fontSize: 18),
        ),
        actions: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
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
              child: Icon(LucideIcons.bell, color: primaryTextColor, size: 20),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Banner card introducing SIM800L hardware SMS
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF0D3B2E)
                    : const Color(0xFFE6F7F0),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Row(
                children: [
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: emerald.withValues(alpha: 0.15),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: const Icon(LucideIcons.radio,
                        color: emerald, size: 26),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'SIM800L Hardware SMS',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: isDark
                                ? Colors.white
                                : const Color(0xFF0F172A),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'When a dose is missed or emergency dispense is pressed, the dispenser sends direct SMS alerts to these contacts.',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.75)
                                : const Color(0xFF475569),
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Contact List',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: primaryTextColor,
                  ),
                ),
                if (widget.isCaregiver)
                  GestureDetector(
                    onTap: () => _showAddContactDialog(),
                    child: const Text(
                      '+ Add New',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: emerald,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),

            // Linked Caregiver + Contacts
            StreamBuilder<List<Map<String, dynamic>>>(
              stream: _caregiversStream,
              builder: (context, caregiverSnap) {
                final caregivers = caregiverSnap.data ?? [];
                final primaryCaregiver = caregivers.isNotEmpty ? caregivers.first : null;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (primaryCaregiver != null)
                      _buildPinnedCaregiverCard(
                        primaryCaregiver,
                        theme,
                        isDark,
                        cardBgColor,
                        primaryTextColor,
                        secondaryTextColor,
                        emerald,
                      ),

                    // Custom Contacts Stream
                    StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: _contactsStream,
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting && primaryCaregiver == null) {
                          return const Padding(
                            padding: EdgeInsets.all(32),
                            child: Center(
                              child: CircularProgressIndicator(color: emerald),
                            ),
                          );
                        }

                        final allDocs = snapshot.data?.docs ?? [];
                        final targetUid = _targetUid;
                        final docs = allDocs.where((doc) {
                          final data = doc.data();
                          final pUid = (data['patientUid'] ?? data['patientId'] ?? '').toString();
                          if (targetUid == null) return false;
                          return pUid == targetUid;
                        }).toList();

                        if (docs.isEmpty) {
                          if (primaryCaregiver != null) {
                            return Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: cardBgColor,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: isDark ? const Color(0xFF27272A) : const Color(0xFFE2E8F0),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(LucideIcons.users, size: 20, color: secondaryTextColor),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      'No additional emergency contacts added yet.',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: secondaryTextColor,
                                      ),
                                    ),
                                  ),
                                  if (widget.isCaregiver)
                                    TextButton(
                                      onPressed: () => _showAddContactDialog(),
                                      child: const Text('Add', style: TextStyle(fontWeight: FontWeight.bold, color: emerald)),
                                    ),
                                ],
                              ),
                            );
                          }

                          return Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(28),
                            decoration: BoxDecoration(
                              color: cardBgColor,
                              borderRadius: BorderRadius.circular(24),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black
                                      .withValues(alpha: isDark ? 0.2 : 0.03),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Column(
                              children: [
                                Container(
                                  width: 56,
                                  height: 56,
                                  decoration: BoxDecoration(
                                    color: isDark
                                        ? const Color(0xFF1E2D25)
                                        : const Color(0xFFE8F8F0),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(LucideIcons.usersRound,
                                      color: emerald, size: 28),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'No Emergency Contacts Yet',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: primaryTextColor,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Add trusted caregivers or family members to receive direct SMS alerts from your SmartDose dispenser.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: secondaryTextColor,
                                    height: 1.4,
                                  ),
                                ),
                                const SizedBox(height: 20),
                                if (widget.isCaregiver)
                                  GestureDetector(
                                    onTap: () => _showAddContactDialog(),
                                    child: Container(
                                      width: double.infinity,
                                      height: 50,
                                      decoration: BoxDecoration(
                                        gradient: const LinearGradient(
                                          colors: [Color(0xFF00A36C), Color(0xFF00C882)],
                                        ),
                                        borderRadius: BorderRadius.circular(25),
                                        boxShadow: [
                                          BoxShadow(
                                            color: emerald.withValues(alpha: 0.35),
                                            blurRadius: 12,
                                            offset: const Offset(0, 4),
                                          ),
                                        ],
                                      ),
                                      child: const Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(Icons.add_rounded,
                                              color: Colors.white, size: 22),
                                          SizedBox(width: 8),
                                          Text(
                                            'Add Emergency Contact',
                                            style: TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  )
                                else
                                  Text(
                                    'Emergency contacts are managed by your caregiver.',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: secondaryTextColor,
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                              ],
                            ),
                          );
                        }

                        return Column(
                          children: [
                            ...docs.map((doc) {
                              final data = doc.data();
                              final id = doc.id;
                              final name = data['name'] as String? ?? 'Contact';
                              final phone = data['phone'] as String? ?? '';
                              final relationship =
                                  data['relationship'] as String? ?? 'Caregiver';

                              return Container(
                                margin: const EdgeInsets.only(bottom: 14),
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: cardBgColor,
                                  borderRadius: BorderRadius.circular(24),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black
                                          .withValues(alpha: isDark ? 0.2 : 0.03),
                                      blurRadius: 12,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  children: [
                                    AppAvatar(
                                      name: name,
                                      radius: 24,
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  name,
                                                  style: TextStyle(
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.bold,
                                                    color: primaryTextColor,
                                                  ),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                              Container(
                                                padding: const EdgeInsets.symmetric(
                                                    horizontal: 8, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: emerald.withValues(alpha: 0.12),
                                                  borderRadius: BorderRadius.circular(10),
                                                ),
                                                child: Text(
                                                  relationship,
                                                  style: const TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.bold,
                                                    color: emerald,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          Row(
                                            children: [
                                              Icon(Icons.phone_outlined,
                                                  size: 14, color: secondaryTextColor),
                                              const SizedBox(width: 4),
                                              Text(
                                                phone,
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  color: secondaryTextColor,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    // Test SMS action
                                    IconButton(
                                      icon: const Icon(LucideIcons.send,
                                          size: 18, color: emerald),
                                      tooltip: 'Send Test SMS',
                                      onPressed: () => _sendTestSms({...data, 'id': id}),
                                    ),
                                    if (widget.isCaregiver)
                                      PopupMenuButton<String>(
                                        icon: Icon(Icons.more_vert_rounded,
                                            color: secondaryTextColor, size: 20),
                                        onSelected: (val) {
                                          if (val == 'edit') {
                                            _showAddContactDialog(
                                                existingContact: {...data, 'id': id});
                                          } else if (val == 'delete') {
                                            _deleteContact(id);
                                          }
                                        },
                                        itemBuilder: (ctx) => [
                                          const PopupMenuItem(
                                            value: 'edit',
                                            child: Row(
                                              children: [
                                                Icon(Icons.edit_outlined, size: 18),
                                                SizedBox(width: 10),
                                                Text('Edit Contact'),
                                              ],
                                            ),
                                          ),
                                          const PopupMenuItem(
                                            value: 'delete',
                                            child: Row(
                                              children: [
                                                Icon(Icons.delete_outline_rounded,
                                                    size: 18, color: Colors.red),
                                                SizedBox(width: 10),
                                                Text('Remove Contact',
                                                    style: TextStyle(color: Colors.red)),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                  ],
                                ),
                              );
                            }),
                            if (docs.isNotEmpty && widget.isCaregiver) ...[
                              const SizedBox(height: 10),
                              GestureDetector(
                                onTap: () => _showAddContactDialog(),
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
                                      Icon(Icons.add_rounded,
                                          color: Colors.white, size: 22),
                                      SizedBox(width: 8),
                                      Text(
                                        'Add Emergency Contact',
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
                          ],
                        );
                      },
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
