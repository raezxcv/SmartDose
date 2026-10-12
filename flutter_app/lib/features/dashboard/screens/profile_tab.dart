import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../../core/theme/theme_provider.dart';
import 'alerts_tab.dart';
import 'device_connected_screen.dart';
import 'camera_feed_screen.dart';
import 'compartment_inventory_screen.dart';
import '../../pairing/screens/emergency_contacts_screen.dart';
import '../../pairing/screens/pair_caregiver_screen.dart';
import '../../pairing/screens/connect_patient_screen.dart';
import '../../../shared/widgets/smartdose_loading.dart';

class PatientProfileTab extends ConsumerStatefulWidget {
  final VoidCallback onSignOut;
  final String fallbackName;

  const PatientProfileTab({
    super.key,
    required this.onSignOut,
    required this.fallbackName,
  });

  @override
  ConsumerState<PatientProfileTab> createState() => _PatientProfileTabState();
}

class _PatientProfileTabState extends ConsumerState<PatientProfileTab> {
  bool _pushNotificationsEnabled = true;
  bool _smsToCaregiverEnabled = true;
  Stream<DocumentSnapshot<Map<String, dynamic>>>? _userProfileStream;

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  @override
  void initState() {
    super.initState();
    final uid = _uid;
    if (uid != null) {
      _userProfileStream =
          FirebaseFirestore.instance.collection('users').doc(uid).snapshots();
    }
  }

  Future<void> _updatePreferences(String key, bool val) async {
    final uid = _uid;
    if (uid == null) return;
    await FirebaseFirestore.instance.collection('users').doc(uid).update({
      'preferences.$key': val,
    });
  }

  static String _getInitials(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return 'SD';
    final parts =
        trimmed.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (parts.length >= 2) {
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    } else if (parts.isNotEmpty && parts.first.isNotEmpty) {
      return parts.first.length >= 2
          ? parts.first.substring(0, 2).toUpperCase()
          : parts.first[0].toUpperCase();
    }
    return 'SD';
  }

  static const List<List<Color>> _avatarGradients = [
    [Color(0xFF00C882), Color(0xFF00A36C)], // Emerald Mint
    [Color(0xFF06B6D4), Color(0xFF0891B2)], // Ocean Cyan
    [Color(0xFF8B5CF6), Color(0xFF6D28D9)], // Royal Purple
    [Color(0xFFEC4899), Color(0xFFDB2777)], // Vibrant Pink
    [Color(0xFFF43F5E), Color(0xFFE11D48)], // Coral Rose
    [Color(0xFF475569), Color(0xFF1E293B)], // Midnight Slate
  ];

  void _showEditProfileSheet(Map<String, dynamic>? data) {
    final nameCtrl =
        TextEditingController(text: data?['name'] ?? widget.fallbackName);
    final phoneCtrl = TextEditingController(text: data?['phone'] ?? '');
    final initialDobStr =
        (data?['dob'] ?? data?['dateOfBirth'] ?? '').toString().trim();
    final dobCtrl = TextEditingController(text: initialDobStr);
    final photoUrlCtrl = TextEditingController(
      text: data?['photoUrl'] ??
          data?['profilePhotoUrl'] ??
          FirebaseAuth.instance.currentUser?.photoURL ??
          '',
    );
    int selectedGradientIdx = (data?['avatarGradientIndex'] as int? ?? 0)
        .clamp(0, _avatarGradients.length - 1);
    final cardColor = Theme.of(context).colorScheme.surface;
    final textColor = Theme.of(context).colorScheme.onSurface;

    DateTime? initialDob;
    if (dobCtrl.text.isNotEmpty) {
      try {
        initialDob = DateTime.parse(dobCtrl.text.trim());
      } catch (_) {}
    }

    bool isSaving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final initials = _getInitials(
              nameCtrl.text.isEmpty ? widget.fallbackName : nameCtrl.text);
          final activeGradient = _avatarGradients[selectedGradientIdx];

          return Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.88,
            ),
            padding: EdgeInsets.fromLTRB(
                24, 24, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Edit Profile',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: textColor,
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.close_rounded,
                            color: textColor.withValues(alpha: 0.6)),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Avatar Preview with Dynamic Gradient & Initials
                  Center(
                    child: Stack(
                      children: [
                        Container(
                          width: 92,
                          height: 92,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(colors: activeGradient),
                            boxShadow: [
                              BoxShadow(
                                color:
                                    activeGradient.last.withValues(alpha: 0.35),
                                blurRadius: 14,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(46),
                            child: _buildAvatarImage(
                                photoUrlCtrl.text, initials, 92),
                          ),
                        ),
                        // Upload Camera Icon Button on Bottom Right
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: GestureDetector(
                            onTap: () => _showUploadImageDialog(
                                ctx, photoUrlCtrl, setSheetState),
                            child: Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: const Color(0xFF00A36C),
                                shape: BoxShape.circle,
                                border:
                                    Border.all(color: cardColor, width: 2.5),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.25),
                                    blurRadius: 6,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: const Icon(Icons.camera_alt_rounded,
                                  color: Colors.white, size: 16),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Avatar Gradient Picker
                  Text(
                    'Avatar Background Color',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: textColor.withValues(alpha: 0.7)),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(_avatarGradients.length, (i) {
                      final isSelected = selectedGradientIdx == i;
                      return GestureDetector(
                        onTap: () =>
                            setSheetState(() => selectedGradientIdx = i),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          margin: const EdgeInsets.symmetric(horizontal: 5),
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient:
                                LinearGradient(colors: _avatarGradients[i]),
                            border: Border.all(
                              color: isSelected
                                  ? Colors.white
                                  : Colors.transparent,
                              width: 2.5,
                            ),
                            boxShadow: isSelected
                                ? [
                                    BoxShadow(
                                      color: _avatarGradients[i]
                                          .last
                                          .withValues(alpha: 0.5),
                                      blurRadius: 8,
                                    ),
                                  ]
                                : [],
                          ),
                          child: isSelected
                              ? const Icon(Icons.check_rounded,
                                  color: Colors.white, size: 18)
                              : null,
                        ),
                      );
                    }),
                  ),

                  const SizedBox(height: 20),

                  TextField(
                    controller: nameCtrl,
                    style: TextStyle(color: textColor),
                    onChanged: (_) => setSheetState(() {}),
                    decoration: InputDecoration(
                      labelText: 'Full Name',
                      prefixIcon: const Icon(Icons.person_outline_rounded,
                          color: Color(0xFF00A36C)),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16)),
                    ),
                  ),
                  const SizedBox(height: 14),

                  TextField(
                    controller: phoneCtrl,
                    keyboardType: TextInputType.phone,
                    style: TextStyle(color: textColor),
                    decoration: InputDecoration(
                      labelText: 'Phone Number',
                      prefixIcon: const Icon(Icons.phone_outlined,
                          color: Color(0xFF00A36C)),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16)),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Date of Birth Date Picker
                  InkWell(
                    onTap: () async {
                      final now = DateTime.now();
                      final picked = await showDatePicker(
                        context: ctx,
                        initialDate: initialDob ?? DateTime(now.year - 30),
                        firstDate: DateTime(1920),
                        lastDate: now,
                        builder: (c, child) => Theme(
                          data: Theme.of(context).copyWith(
                            colorScheme: Theme.of(context).colorScheme.copyWith(
                                  primary: const Color(0xFF00A36C),
                                ),
                          ),
                          child: child!,
                        ),
                      );
                      if (picked != null) {
                        final formatted =
                            DateFormat('yyyy-MM-dd').format(picked);
                        setSheetState(() {
                          dobCtrl.text = formatted;
                          initialDob = picked;
                        });
                      }
                    },
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 16),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade400),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.cake_outlined,
                              color: Color(0xFF00A36C)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Date of Birth',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: textColor.withValues(alpha: 0.6)),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  dobCtrl.text.isEmpty
                                      ? 'Select Date of Birth'
                                      : dobCtrl.text,
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: dobCtrl.text.isEmpty
                                        ? textColor.withValues(alpha: 0.4)
                                        : textColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(Icons.calendar_today_rounded,
                              size: 20,
                              color: textColor.withValues(alpha: 0.6)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Container(
                    width: double.infinity,
                    height: 52,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: [Color(0xFF00C882), Color(0xFF00A36C)],
                      ),
                      borderRadius: BorderRadius.circular(26),
                      boxShadow: [
                        BoxShadow(
                          color:
                              const Color(0xFF00A36C).withValues(alpha: 0.35),
                          blurRadius: 14,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(26),
                        onTap: isSaving
                            ? null
                            : () async {
                                setSheetState(() => isSaving = true);
                                final messenger = ScaffoldMessenger.of(context);
                                final uid = _uid;
                                final newPhoto = photoUrlCtrl.text.trim();
                                try {
                                  if (uid != null) {
                                    await FirebaseFirestore.instance
                                        .collection('users')
                                        .doc(uid)
                                        .set({
                                      'name': nameCtrl.text.trim(),
                                      'phone': phoneCtrl.text.trim(),
                                      'dob': dobCtrl.text.trim(),
                                      'dateOfBirth': dobCtrl.text.trim(),
                                      'photoUrl': newPhoto,
                                      'profilePhotoUrl': newPhoto,
                                      'avatarGradientIndex':
                                          selectedGradientIdx,
                                    }, SetOptions(merge: true));
                                    try {
                                      await FirebaseAuth.instance.currentUser
                                          ?.updatePhotoURL(newPhoto);
                                    } catch (_) {}
                                  }
                                  if (mounted) {
                                    Navigator.pop(ctx);
                                    messenger.showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                            'Profile updated successfully!'),
                                        backgroundColor: Color(0xFF00A36C),
                                      ),
                                    );
                                  }
                                } catch (e) {
                                  if (ctx.mounted) {
                                    setSheetState(() => isSaving = false);
                                    messenger.showSnackBar(
                                      SnackBar(
                                        content: Text(
                                            'Failed to update profile: $e'),
                                        backgroundColor:
                                            const Color(0xFFEF4444),
                                      ),
                                    );
                                  }
                                }
                              },
                        child: Center(
                          child: isSaving
                              ? const SmartDoseLoading(
                                  size: 38, color: Colors.white)
                              : const Text(
                                  'Save Changes',
                                  style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white),
                                ),
                        ),
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

  String _calculateAgeString(String rawDob) {
    final trimmed = rawDob.trim();
    if (trimmed.isEmpty) return 'Age: —';
    try {
      final parsed = DateTime.parse(trimmed);
      final now = DateTime.now();
      int age = now.year - parsed.year;
      if (now.month < parsed.month ||
          (now.month == parsed.month && now.day < parsed.day)) {
        age--;
      }
      return age > 0 ? 'Age: $age' : 'Age: —';
    } catch (_) {
      try {
        final match = RegExp(r'\b(19|20)\d{2}\b').firstMatch(trimmed);
        if (match != null) {
          final year = int.parse(match.group(0)!);
          final age = DateTime.now().year - year;
          return age > 0 ? 'Age: $age' : 'Age: —';
        }
      } catch (_) {}
      return 'Age: —';
    }
  }

  Widget _buildAvatarImage(String photoVal, String initials, double size) {
    final trimmed = photoVal.trim();
    if (trimmed.isEmpty) {
      return Center(
        child: Text(
          initials,
          style: TextStyle(
              color: Colors.white,
              fontSize: size * 0.35,
              fontWeight: FontWeight.w900),
        ),
      );
    }
    if (trimmed.startsWith('data:image')) {
      try {
        final base64Str =
            trimmed.contains(',') ? trimmed.split(',').last : trimmed;
        final bytes = base64Decode(base64Str);
        return Image.memory(
          bytes,
          width: size,
          height: size,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => Center(
            child: Text(initials,
                style: TextStyle(
                    color: Colors.white,
                    fontSize: size * 0.35,
                    fontWeight: FontWeight.w900)),
          ),
        );
      } catch (_) {}
    }
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return Image.network(
        trimmed,
        width: size,
        height: size,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => Center(
          child: Text(initials,
              style: TextStyle(
                  color: Colors.white,
                  fontSize: size * 0.35,
                  fontWeight: FontWeight.w900)),
        ),
      );
    }
    final file = File(trimmed);
    if (file.existsSync()) {
      return Image.file(
        file,
        width: size,
        height: size,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => Center(
          child: Text(initials,
              style: TextStyle(
                  color: Colors.white,
                  fontSize: size * 0.35,
                  fontWeight: FontWeight.w900)),
        ),
      );
    }
    return Center(
      child: Text(initials,
          style: TextStyle(
              color: Colors.white,
              fontSize: size * 0.35,
              fontWeight: FontWeight.w900)),
    );
  }

  void _showUploadImageDialog(
    BuildContext parentCtx,
    TextEditingController photoCtrl,
    StateSetter parentSetState,
  ) {
    final cardColor = Theme.of(parentCtx).colorScheme.surface;
    final textColor = Theme.of(parentCtx).colorScheme.onSurface;

    showModalBottomSheet(
      context: parentCtx,
      backgroundColor: Colors.transparent,
      builder: (dlgCtx) => Container(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Change Profile Picture',
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: textColor),
                ),
                IconButton(
                  icon: Icon(Icons.close_rounded,
                      color: textColor.withValues(alpha: 0.6)),
                  onPressed: () => Navigator.pop(dlgCtx),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Choose from Gallery Tile
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF00A36C).withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.photo_library_rounded,
                    color: Color(0xFF00A36C)),
              ),
              title: Text('Choose from Gallery',
                  style:
                      TextStyle(fontWeight: FontWeight.bold, color: textColor)),
              subtitle: Text('Pick an image from your device photos',
                  style: TextStyle(
                      fontSize: 12, color: textColor.withValues(alpha: 0.6))),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              onTap: () async {
                Navigator.pop(dlgCtx);
                final picker = ImagePicker();
                final picked = await picker.pickImage(
                  source: ImageSource.gallery,
                  maxWidth: 512,
                  maxHeight: 512,
                  imageQuality: 80,
                );
                if (picked != null) {
                  final uid =
                      FirebaseAuth.instance.currentUser?.uid ?? _uid ?? 'user';
                  try {
                    final ref = FirebaseStorage.instance
                        .ref()
                        .child('avatars/$uid.jpg');
                    await ref.putFile(File(picked.path));
                    final downloadUrl = await ref.getDownloadURL();
                    final timestampedUrl = downloadUrl.contains('?')
                        ? '$downloadUrl&t=${DateTime.now().millisecondsSinceEpoch}'
                        : '$downloadUrl?t=${DateTime.now().millisecondsSinceEpoch}';
                    parentSetState(() => photoCtrl.text = timestampedUrl);
                  } catch (e) {
                    debugPrint(
                        'Storage upload warning, fallback to Cloud Base64: $e');
                    try {
                      final bytes = await File(picked.path).readAsBytes();
                      final base64Url =
                          'data:image/jpeg;base64,${base64Encode(bytes)}';
                      parentSetState(() => photoCtrl.text = base64Url);
                    } catch (_) {}
                  }
                }
              },
            ),
            const SizedBox(height: 8),

            // Take Photo Tile
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF06B6D4).withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.camera_alt_rounded,
                    color: Color(0xFF06B6D4)),
              ),
              title: Text('Take a Photo',
                  style:
                      TextStyle(fontWeight: FontWeight.bold, color: textColor)),
              subtitle: Text('Use camera to take a new picture',
                  style: TextStyle(
                      fontSize: 12, color: textColor.withValues(alpha: 0.6))),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              onTap: () async {
                Navigator.pop(dlgCtx);
                final picker = ImagePicker();
                final picked = await picker.pickImage(
                  source: ImageSource.camera,
                  maxWidth: 512,
                  maxHeight: 512,
                  imageQuality: 80,
                );
                if (picked != null) {
                  final uid =
                      FirebaseAuth.instance.currentUser?.uid ?? _uid ?? 'user';
                  try {
                    final ref = FirebaseStorage.instance
                        .ref()
                        .child('avatars/$uid.jpg');
                    await ref.putFile(File(picked.path));
                    final downloadUrl = await ref.getDownloadURL();
                    final timestampedUrl = downloadUrl.contains('?')
                        ? '$downloadUrl&t=${DateTime.now().millisecondsSinceEpoch}'
                        : '$downloadUrl?t=${DateTime.now().millisecondsSinceEpoch}';
                    parentSetState(() => photoCtrl.text = timestampedUrl);
                  } catch (e) {
                    debugPrint(
                        'Storage upload warning, fallback to Cloud Base64: $e');
                    try {
                      final bytes = await File(picked.path).readAsBytes();
                      final base64Url =
                          'data:image/jpeg;base64,${base64Encode(bytes)}';
                      parentSetState(() => photoCtrl.text = base64Url);
                    } catch (_) {}
                  }
                }
              },
            ),

            if (photoCtrl.text.isNotEmpty) ...[
              const SizedBox(height: 8),
              // Remove Photo Tile
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444).withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.delete_outline_rounded,
                      color: Color(0xFFEF4444)),
                ),
                title: const Text('Remove Photo',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, color: Color(0xFFEF4444))),
                subtitle: Text('Use colorful initials avatar instead',
                    style: TextStyle(
                        fontSize: 12, color: textColor.withValues(alpha: 0.6))),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                onTap: () {
                  Navigator.pop(dlgCtx);
                  parentSetState(() => photoCtrl.clear());
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);
    final isDarkMode = themeMode == ThemeMode.dark;

    final cardBgColor = Theme.of(context).cardTheme.color ??
        Theme.of(context).colorScheme.surface;
    final primaryTextColor = Theme.of(context).colorScheme.onSurface;
    final secondaryTextColor = primaryTextColor.withValues(alpha: 0.65);

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _userProfileStream,
      builder: (context, snapshot) {
        final userData = snapshot.data?.data();
        final name = userData?['name'] ?? widget.fallbackName;
        final phone = (userData?['phone'] as String? ?? '').isNotEmpty
            ? userData!['phone']
            : 'No phone';
        final rawDob = (userData?['dob'] ?? userData?['dateOfBirth'] ?? '')
            .toString()
            .trim();
        final email = userData?['email'] ??
            FirebaseAuth.instance.currentUser?.email ??
            '';

        final initials = _getInitials(name);
        final avatarGradIdx = (userData?['avatarGradientIndex'] as int? ?? 0)
            .clamp(0, _avatarGradients.length - 1);
        final userAvatarGradient = _avatarGradients[avatarGradIdx];

        final prefs = userData?['preferences'] as Map<String, dynamic>?;
        if (prefs != null) {
          _pushNotificationsEnabled = prefs['pushNotifications'] ?? true;
          _smsToCaregiverEnabled = prefs['smsToCaregiver'] ?? true;
          if (prefs.containsKey('darkMode')) {
            final fsDark = prefs['darkMode'] as bool;
            if (fsDark != isDarkMode) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                ref.read(themeModeProvider.notifier).syncFromFirestore(fsDark);
              });
            }
          }
        }

        return SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Profile',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                          color: primaryTextColor,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Account & device settings',
                        style: TextStyle(
                          fontSize: 15,
                          color: secondaryTextColor,
                        ),
                      ),
                    ],
                  ),
                  GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const PatientAlertsTab()),
                      );
                    },
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: cardBgColor,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black
                                .withValues(alpha: isDarkMode ? 0.2 : 0.04),
                            blurRadius: 10,
                          ),
                        ],
                      ),
                      child: Icon(LucideIcons.bell,
                          color: primaryTextColor, size: 20),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // User Card
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: cardBgColor,
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black
                          .withValues(alpha: isDarkMode ? 0.2 : 0.04),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => _showEditProfileSheet(userData),
                      child: Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: userAvatarGradient,
                          ),
                          border: Border.all(
                              color: userAvatarGradient.last, width: 2),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(32),
                          child: _buildAvatarImage(
                            (userData?['photoUrl'] ??
                                    userData?['profilePhotoUrl'] ??
                                    FirebaseAuth
                                        .instance.currentUser?.photoURL ??
                                    '')
                                .toString(),
                            initials,
                            64,
                          ),
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
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: primaryTextColor,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${_calculateAgeString(rawDob)} · $phone',
                            style: TextStyle(
                              fontSize: 13,
                              color: secondaryTextColor,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                            decoration: BoxDecoration(
                              color: (userData?['role'] == 'caregiver')
                                  ? const Color(0xFF3B82F6).withValues(alpha: 0.12)
                                  : const Color(0xFF00A36C).withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              (userData?['role'] == 'caregiver') ? 'Caregiver / Family' : 'Patient',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: (userData?['role'] == 'caregiver')
                                    ? const Color(0xFF2563EB)
                                    : const Color(0xFF00A36C),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(LucideIcons.edit,
                          color: Color(0xFF00A36C)),
                      onPressed: () => _showEditProfileSheet(userData),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // ── Account Section ──────────────────────────────────────
              Text('Account',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: primaryTextColor)),
              const SizedBox(height: 12),
              Container(
                decoration: BoxDecoration(
                  color: cardBgColor,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black
                          .withValues(alpha: isDarkMode ? 0.2 : 0.03),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    _buildNavTile(
                      icon: LucideIcons.lock,
                      title: 'Change Password',
                      subtitle: 'Update your login password',
                      showDivider: true,
                      onTap: () => _showChangePasswordDialog(),
                    ),
                    _buildNavTile(
                      icon: LucideIcons.mail,
                      title: 'Email Address',
                      subtitle: email.isNotEmpty ? email : 'Not set',
                      showDivider: true,
                    ),
                    _buildNavTile(
                      icon: LucideIcons.userCheck,
                      title: 'Account Role',
                      subtitle: (userData?['role'] == 'caregiver')
                          ? 'Caregiver / Family (Full Management)'
                          : 'Patient (View-only schedule)',
                      showDivider: false,
                      onTap: () => _showSwitchRoleDialog(userData?['role'] ?? 'patient'),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // ── Preferences Section ──────────────────────────────────
              Text(
                'Preferences',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: primaryTextColor,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                decoration: BoxDecoration(
                  color: cardBgColor,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black
                          .withValues(alpha: isDarkMode ? 0.2 : 0.03),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    _buildProfileSwitchTile(
                      icon: LucideIcons.bell,
                      title: 'Push Notifications',
                      subtitle: 'Dose reminders & alerts',
                      value: _pushNotificationsEnabled,
                      onChanged: (val) {
                        setState(() => _pushNotificationsEnabled = val);
                        _updatePreferences('pushNotifications', val);
                      },
                      showDivider: true,
                    ),
                    _buildProfileSwitchTile(
                      icon: LucideIcons.messageSquare,
                      title: 'SMS Alert',
                      subtitle: 'Notify emergency contacts via SIM800L',
                      value: _smsToCaregiverEnabled,
                      onChanged: (val) {
                        setState(() => _smsToCaregiverEnabled = val);
                        _updatePreferences('smsToCaregiver', val);
                      },
                      showDivider: true,
                    ),
                    _buildProfileSwitchTile(
                      icon: LucideIcons.moon,
                      title: 'Dark Mode',
                      subtitle: 'Easier on the eyes at night',
                      value: isDarkMode,
                      onChanged: (val) {
                        ref.read(themeModeProvider.notifier).toggleTheme(val);
                        _updatePreferences('darkMode', val);
                      },
                      showDivider: false,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // ── Care Circle / Emergency Contacts Section ─────────────
              Text('Emergency Contacts',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: primaryTextColor)),
              const SizedBox(height: 12),
              Container(
                decoration: BoxDecoration(
                  color: cardBgColor,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black
                          .withValues(alpha: isDarkMode ? 0.2 : 0.03),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    _buildNavTile(
                      icon: LucideIcons.usersRound,
                      title: 'Emergency Contacts',
                      subtitle: 'Phone numbers for SIM800L SMS alerts',
                      showDivider: true,
                      onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => EmergencyContactsScreen(isCaregiver: userData?['role'] == 'caregiver'))),
                    ),
                    if (userData?['role'] == 'caregiver')
                      _buildNavTile(
                        icon: LucideIcons.userPlus,
                        title: 'Link a Patient',
                        subtitle: 'Enter pairing code or scan patient QR code',
                        showDivider: false,
                        onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const ConnectPatientScreen())),
                      )
                    else
                      _buildNavTile(
                        icon: LucideIcons.qrCode,
                        title: 'Link a Caregiver',
                        subtitle: 'Generate pairing code or QR code',
                        showDivider: false,
                        onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const PairCaregiverScreen())),
                      ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // ── Device & Monitoring Section ──────────────────────────
              Text('Device & Monitoring',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: primaryTextColor)),
              const SizedBox(height: 12),
              Container(
                decoration: BoxDecoration(
                  color: cardBgColor,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black
                          .withValues(alpha: isDarkMode ? 0.2 : 0.03),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    _buildNavTile(
                      icon: Icons.wifi_rounded,
                      title: 'Device Connected',
                      subtitle: 'Status, firmware & controls',
                      showDivider: true,
                      onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const DeviceConnectedScreen())),
                    ),
                    _buildNavTile(
                      icon: LucideIcons.scanEye,
                      title: 'Live Camera Feed',
                      subtitle: 'Visual check of pill tray',
                      showDivider: true,
                      onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const CameraFeedScreen())),
                    ),
                    _buildNavTile(
                      icon: Icons.inventory_2_outlined,
                      title: 'Medicine Inventory',
                      subtitle: 'Compartment stock levels',
                      showDivider: false,
                      onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) =>
                                  CompartmentInventoryScreen(isCaregiver: userData?['role'] == 'caregiver'))),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // ── About Section ─────────────────────────────────────────
              Text('About',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: primaryTextColor)),
              const SizedBox(height: 12),
              Container(
                decoration: BoxDecoration(
                  color: cardBgColor,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black
                          .withValues(alpha: isDarkMode ? 0.2 : 0.03),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    _buildNavTile(
                      icon: LucideIcons.info,
                      title: 'App Version',
                      subtitle: 'SmartDose v1.0.0',
                      showDivider: true,
                      onTap: null,
                    ),
                    _buildNavTile(
                      icon: LucideIcons.cpu,
                      title: 'Device Firmware',
                      subtitle: 'SmartDose ESP32 · v2.4.1',
                      showDivider: false,
                      onTap: null,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 28),

              // Log Out Button
              SizedBox(
                width: double.infinity,
                height: 52,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFEF4444),
                    side:
                        const BorderSide(color: Color(0xFFFCA5A5), width: 1.5),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(26)),
                  ),
                  onPressed: () => _confirmSignOut(context),
                  icon: const Icon(LucideIcons.logOut, size: 20),
                  label: const Text(
                    'Log Out',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }

  void _showSwitchRoleDialog(String currentRole) {
    final targetRole = (currentRole == 'caregiver') ? 'patient' : 'caregiver';
    final targetLabel = (targetRole == 'caregiver') ? 'Caregiver / Family' : 'Patient';
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
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: const Color(0xFF00A36C).withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(LucideIcons.refreshCw, color: Color(0xFF00A36C), size: 28),
            ),
            const SizedBox(height: 18),
            Text(
              'Switch to $targetLabel?',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: primaryTextColor,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Switching will change your account permissions between Patient (View-only schedule) and Caregiver (Full management).',
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
                    onPressed: () => Navigator.pop(ctx),
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
                    onPressed: () async {
                      final uid = _uid;
                      if (uid != null) {
                        await FirebaseFirestore.instance.collection('users').doc(uid).set({
                          'role': targetRole,
                          'updatedAt': FieldValue.serverTimestamp(),
                        }, SetOptions(merge: true));
                      }
                      if (ctx.mounted) Navigator.pop(ctx);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Switched to $targetLabel! Logging out to apply...'),
                            backgroundColor: const Color(0xFF00A36C),
                          ),
                        );
                        Future.delayed(const Duration(milliseconds: 600), () {
                          widget.onSignOut();
                        });
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00A36C),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                    ),
                    child: const Text('Switch Role', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _confirmSignOut(BuildContext context) {
    final theme = Theme.of(context);
    final cardBgColor = theme.cardTheme.color ?? theme.colorScheme.surface;
    final primaryTextColor = theme.colorScheme.onSurface;
    final secondaryTextColor = primaryTextColor.withValues(alpha: 0.65);

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
              child: const Icon(Icons.logout_rounded,
                  color: Color(0xFFEF4444), size: 32),
            ),
            const SizedBox(height: 18),
            Text(
              'Log Out of SmartDose?',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: primaryTextColor,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Are you sure you want to log out? You will need to sign in again to access your account.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: secondaryTextColor,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: BorderSide(color: theme.dividerColor, width: 1.5),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                    ),
                    onPressed: () => Navigator.pop(ctx),
                    child: Text(
                      'Cancel',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: primaryTextColor,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFEF4444),
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                    ),
                    onPressed: () {
                      Navigator.pop(ctx);
                      widget.onSignOut();
                    },
                    child: const Text(
                      'Log Out',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileSwitchTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    required bool showDivider,
  }) {
    final primaryTextColor = Theme.of(context).colorScheme.onSurface;
    final secondaryTextColor = primaryTextColor.withValues(alpha: 0.65);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF064E3B)
                      : const Color(0xFFE6F7F0),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: const Color(0xFF00A36C), size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: primaryTextColor,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 13,
                        color: secondaryTextColor,
                      ),
                    ),
                  ],
                ),
              ),
              Switch.adaptive(
                value: value,
                activeTrackColor: const Color(0xFF00A36C),
                onChanged: onChanged,
              ),
            ],
          ),
        ),
        if (showDivider)
          Divider(
            height: 1,
            indent: 74,
            endIndent: 18,
            color: Theme.of(context).dividerColor,
          ),
      ],
    );
  }

  Widget _buildNavTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool showDivider,
    VoidCallback? onTap,
  }) {
    final primaryTextColor = Theme.of(context).colorScheme.onSurface;
    final secondaryTextColor = primaryTextColor.withValues(alpha: 0.65);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF064E3B)
                        : const Color(0xFFE6F7F0),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: const Color(0xFF00A36C), size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: primaryTextColor,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 13,
                          color: secondaryTextColor,
                        ),
                      ),
                    ],
                  ),
                ),
                if (onTap != null)
                  Icon(Icons.chevron_right_rounded,
                      color: secondaryTextColor, size: 24),
              ],
            ),
          ),
        ),
        if (showDivider)
          Divider(
            height: 1,
            indent: 74,
            endIndent: 18,
            color: Theme.of(context).dividerColor,
          ),
      ],
    );
  }

  void _showChangePasswordDialog() {
    final user = FirebaseAuth.instance.currentUser;
    final emailCtrl = TextEditingController(text: user?.email ?? '');
    bool isSending = false;

    final cardBgColor = Theme.of(context).cardTheme.color ??
        Theme.of(context).colorScheme.surface;
    final primaryTextColor = Theme.of(context).colorScheme.onSurface;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Container(
          padding: EdgeInsets.fromLTRB(
              24, 24, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
          decoration: BoxDecoration(
            color: cardBgColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: const Color(0xFFF0FDF4),
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: const Color(0xFF00A36C).withValues(alpha: 0.3),
                      width: 1.5),
                ),
                child: const Icon(
                  LucideIcons.keyRound,
                  color: Color(0xFF00A36C),
                  size: 30,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Reset Password',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: primaryTextColor,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                "Enter your registered email address below and we'll send you a link to reset your password.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: primaryTextColor.withValues(alpha: 0.6),
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 20),
              Align(
                alignment: Alignment.centerLeft,
                child: Row(
                  children: [
                    const Icon(Icons.email_rounded,
                        size: 16, color: Color(0xFF00A36C)),
                    const SizedBox(width: 6),
                    Text(
                      'EMAIL ADDRESS',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: primaryTextColor.withValues(alpha: 0.65),
                        letterSpacing: 1.1,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: emailCtrl,
                keyboardType: TextInputType.emailAddress,
                style: TextStyle(
                    color: primaryTextColor,
                    fontSize: 15,
                    fontWeight: FontWeight.w700),
                decoration: InputDecoration(
                  hintText: 'you@example.com',
                  hintStyle: TextStyle(
                      color: primaryTextColor.withValues(alpha: 0.4),
                      fontSize: 15,
                      fontWeight: FontWeight.w500),
                  filled: true,
                  fillColor: Theme.of(context).brightness == Brightness.dark
                      ? const Color(0xFF1E293B)
                      : const Color(0xFFF9FAFB),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(28),
                      borderSide:
                          BorderSide(color: Theme.of(context).dividerColor)),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(28),
                      borderSide:
                          BorderSide(color: Theme.of(context).dividerColor)),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(28),
                      borderSide:
                          const BorderSide(color: Color(0xFF00A36C), width: 2)),
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
                        side: BorderSide(
                            color: Theme.of(context).dividerColor, width: 1.5),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(25)),
                      ),
                      child: Text('Cancel',
                          style: TextStyle(
                              color: primaryTextColor.withValues(alpha: 0.6),
                              fontWeight: FontWeight.w800,
                              fontSize: 15)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Container(
                      height: 48,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                            colors: [Color(0xFF00C882), Color(0xFF00A36C)]),
                        borderRadius: BorderRadius.circular(25),
                        boxShadow: [
                          BoxShadow(
                              color: const Color(0xFF00A36C)
                                  .withValues(alpha: 0.35),
                              blurRadius: 12,
                              offset: const Offset(0, 4))
                        ],
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: isSending
                              ? null
                              : () async {
                                  final text = emailCtrl.text.trim();
                                  if (text.contains('@')) {
                                    setSheetState(() => isSending = true);
                                    try {
                                      await FirebaseAuth.instance
                                          .sendPasswordResetEmail(email: text);
                                      if (ctx.mounted) Navigator.pop(ctx);
                                      if (mounted) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                                'Password reset link sent! Check your inbox.'),
                                            backgroundColor: Color(0xFF00A36C),
                                          ),
                                        );
                                      }
                                    } catch (e) {
                                      setSheetState(() => isSending = false);
                                      if (mounted) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          SnackBar(
                                            content: Text('Error: $e'),
                                            backgroundColor: Colors.red,
                                          ),
                                        );
                                      }
                                    }
                                  }
                                },
                          borderRadius: BorderRadius.circular(25),
                          child: Center(
                            child: isSending
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                        color: Colors.white, strokeWidth: 2),
                                  )
                                : const Text(
                                    'Send Link',
                                    style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 15),
                                  ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
