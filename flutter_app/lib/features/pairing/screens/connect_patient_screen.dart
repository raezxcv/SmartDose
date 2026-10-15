import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../services/pairing_service.dart';
import 'confirm_pairing_dialog.dart';
import 'linked_account_screen.dart';
import 'package:smartdose/shared/widgets/smartdose_loading.dart';
import 'package:smartdose/shared/widgets/app_avatar.dart';

/// Formatter that automatically capitalizes and formats code as SPD-XXXX-XXXX
class PairingCodeInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final raw = newValue.text.toUpperCase();
    // Allow hardware IDs like SD-XXXX or alphanumeric codes
    if (!raw.startsWith('SPD') && !raw.startsWith('SD-')) {
      return newValue.copyWith(text: raw);
    }

    if (raw.startsWith('SPD')) {
      // Remove all non-alphanumeric
      final cleaned = raw.replaceAll(RegExp(r'[^A-Z0-9]'), '');
      final buffer = StringBuffer();
      for (int i = 0; i < cleaned.length && i < 11; i++) {
        if (i == 3 || i == 7) {
          buffer.write('-');
        }
        buffer.write(cleaned[i]);
      }
      final formatted = buffer.toString();
      return TextEditingValue(
        text: formatted,
        selection: TextSelection.collapsed(offset: formatted.length),
      );
    }

    return newValue.copyWith(text: raw);
  }
}

class ConnectPatientScreen extends StatefulWidget {
  const ConnectPatientScreen({super.key});

  @override
  State<ConnectPatientScreen> createState() => _ConnectPatientScreenState();
}

class _ConnectPatientScreenState extends State<ConnectPatientScreen> {
  final MobileScannerController _scannerController = MobileScannerController();
  final PairingService _pairingService = PairingService();
  final ImagePicker _imagePicker = ImagePicker();
  final TextEditingController _manualCodeController = TextEditingController();

  bool _isProcessing = false;
  bool _isScanningLocked = false;
  bool _isTorchOn = false;
  bool _hasCameraPermission = false;
  bool _isCheckingPermission = true;

  bool _isCheckingExistingPairing = true;
  Map<String, dynamic>? _existingPairing;

  @override
  void initState() {
    super.initState();
    _checkExistingCaregiverPairing();
    _checkAndRequestCameraPermission();
  }

  Future<void> _checkExistingCaregiverPairing() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      if (mounted) setState(() => _isCheckingExistingPairing = false);
      return;
    }

    try {
      final active = await _pairingService.getActivePairingForCaregiver(uid);
      if (mounted) {
        setState(() {
          _existingPairing = active;
          _isCheckingExistingPairing = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isCheckingExistingPairing = false);
    }
  }

  Future<void> _checkAndRequestCameraPermission() async {
    setState(() => _isCheckingPermission = true);
    final status = await Permission.camera.status;

    if (status.isGranted) {
      if (mounted) {
        setState(() {
          _hasCameraPermission = true;
          _isCheckingPermission = false;
        });
      }
    } else {
      final requestStatus = await Permission.camera.request();
      if (mounted) {
        setState(() {
          _hasCameraPermission = requestStatus.isGranted;
          _isCheckingPermission = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _manualCodeController.dispose();
    _scannerController.dispose();
    super.dispose();
  }

  Future<void> _pickImageFromGallery() async {
    if (_isProcessing || _isScanningLocked) return;

    try {
      final XFile? file = await _imagePicker.pickImage(source: ImageSource.gallery);
      if (file == null) return;

      setState(() {
        _isProcessing = true;
        _isScanningLocked = true;
      });

      final BarcodeCapture? capture = await _scannerController.analyzeImage(file.path);
      final barcode = capture?.barcodes.firstOrNull;

      if (barcode != null && barcode.rawValue != null && barcode.rawValue!.trim().isNotEmpty) {
        await _handleScannedCode(barcode.rawValue!);
      } else {
        if (mounted) {
          setState(() {
            _isProcessing = false;
            _isScanningLocked = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Row(
                children: [
                  Icon(Icons.info_outline_rounded, color: Colors.white, size: 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text('No SmartDose QR code detected in the selected image. Please try another image.'),
                  ),
                ],
              ),
              backgroundColor: Color(0xFFEF4444),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _isScanningLocked = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to read image: $e'),
            backgroundColor: const Color(0xFFEF4444),
          ),
        );
      }
    }
  }

  void _showDeviceConnectDialog(String deviceId) {
    final user = FirebaseAuth.instance.currentUser;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            const Icon(Icons.router_rounded, color: Color(0xFF00A36C)),
            const SizedBox(width: 10),
            Text('Connect $deviceId?'),
          ],
        ),
        content: Text(
          'SmartDose Dispenser ($deviceId) detected. Would you like to connect this unit to the patient account?',
          style: const TextStyle(fontSize: 14, color: Color(0xFF4B5563)),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              setState(() => _isScanningLocked = false);
            },
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF6B7280))),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              if (user == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please sign in to link device.')),
                );
                setState(() => _isScanningLocked = false);
                return;
              }
              setState(() => _isProcessing = true);
              try {
                await _pairingService.linkDeviceToPatient(
                  deviceId: deviceId,
                  patientUid: user.uid,
                  patientName: user.displayName ?? 'Patient',
                );
                if (mounted) {
                  setState(() {
                    _isProcessing = false;
                    _isScanningLocked = false;
                  });
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('SmartDose Dispenser $deviceId connected successfully!'),
                      backgroundColor: const Color(0xFF00A36C),
                    ),
                  );
                  Navigator.pop(context);
                }
              } catch (e) {
                if (mounted) {
                  setState(() {
                    _isProcessing = false;
                    _isScanningLocked = false;
                  });
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(e.toString().replaceAll('Exception: ', '')),
                      backgroundColor: const Color(0xFFEF4444),
                    ),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00A36C),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Connect Device', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _handleScannedCode(String rawCode) async {
    if (_isProcessing) return;
    setState(() {
      _isProcessing = true;
      _isScanningLocked = true;
    });

    try {
      final result = await _pairingService.validatePairingToken(rawCode);
      if (!mounted) return;

      setState(() => _isProcessing = false);

      if (result['type'] == 'device') {
        _showDeviceConnectDialog(result['deviceId'] as String);
        return;
      }

      // Check if patient is already paired with another caregiver
      if (result['isAlreadyLinked'] == true) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            title: const Row(
              children: [
                Icon(Icons.info_outline_rounded, color: Color(0xFF00A36C), size: 24),
                SizedBox(width: 8),
                Text('Pairing Connection'),
              ],
            ),
            content: Text(
              '${result['name'] ?? 'This patient'} is currently linked with ${result['existingCaregiverName'] ?? 'a caregiver'}. Pairing connects a patient and caregiver so they can access the appropriate medication information and features based on their roles.',
              style: const TextStyle(fontSize: 14, height: 1.45),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  setState(() => _isScanningLocked = false);
                },
                child: const Text('OK', style: TextStyle(color: Color(0xFF00A36C), fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ).then((_) {
          if (mounted) setState(() => _isScanningLocked = false);
        });
        return;
      }

      // Patient is eligible for pairing: show confirmation dialog
      showDialog(
        context: context,
        builder: (_) => ConfirmPairingDialog(patientData: result),
      ).then((_) {
        if (mounted) setState(() => _isScanningLocked = false);
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _isScanningLocked = false;
        });
        final errorMsg = e.toString().replaceAll('Exception: ', '');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline_rounded, color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Expanded(child: Text(errorMsg)),
              ],
            ),
            backgroundColor: const Color(0xFFDC2626),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  void _showManualEntryDialog() {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: const Text('Enter Code Manually'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Enter the patient\'s pairing code (e.g. SPD-8F4K-91XQ) or SmartDose hardware device ID (e.g. SD-0119).',
                style: TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _manualCodeController,
                textCapitalization: TextCapitalization.characters,
                inputFormatters: [
                  PairingCodeInputFormatter(),
                ],
                decoration: InputDecoration(
                  hintText: 'e.g. SPD-8F4K-91XQ',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: Color(0xFF00A36C), width: 2),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel', style: TextStyle(color: Color(0xFF6B7280))),
            ),
            ElevatedButton(
              onPressed: () {
                final code = _manualCodeController.text.trim();
                if (code.isNotEmpty) {
                  Navigator.pop(ctx);
                  _handleScannedCode(code);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00A36C),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Submit', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    const emerald = Color(0xFF00A36C);

    if (_isCheckingExistingPairing) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: SmartDoseLoading(size: 80)),
      );
    }

    // Caregiver Already Has an Active Patient -> Prevent 2nd active pairing
    if (_existingPairing != null) {
      return _buildAlreadyLinkedCaregiverState(emerald);
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Connect to Patient',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
        ),
        actions: [
          // Select Image From Gallery Action
          IconButton(
            icon: const Icon(Icons.photo_library_outlined, color: Colors.white),
            onPressed: _isProcessing ? null : _pickImageFromGallery,
            tooltip: 'Select QR Image from Gallery',
          ),
          // Torch Flashlight Toggle
          if (_hasCameraPermission)
            IconButton(
              icon: Icon(
                _isTorchOn ? Icons.flash_on_rounded : Icons.flash_off_rounded,
                color: _isTorchOn ? Colors.amber : Colors.white,
              ),
              onPressed: () async {
                await _scannerController.toggleTorch();
                setState(() => _isTorchOn = !_isTorchOn);
              },
              tooltip: 'Toggle Flashlight',
            ),
        ],
      ),
      body: _isCheckingPermission
          ? const Center(child: SmartDoseLoading(size: 80))
          : !_hasCameraPermission
              ? _buildPermissionDeniedState(emerald)
              : Stack(
                  children: [
                    // Mobile Scanner Camera Viewfinder
                    MobileScanner(
                      controller: _scannerController,
                      onDetect: (capture) {
                        if (_isProcessing || _isScanningLocked) return;
                        final List<Barcode> barcodes = capture.barcodes;
                        for (final barcode in barcodes) {
                          if (barcode.rawValue != null && barcode.rawValue!.trim().isNotEmpty) {
                            _handleScannedCode(barcode.rawValue!.trim());
                            break;
                          }
                        }
                      },
                    ),

                    // Camera Viewfinder Frame Overlay (shifted slightly upward and horizontally centered)
                    Align(
                      alignment: const Alignment(0, -0.22),
                      child: Container(
                        width: 260,
                        height: 260,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: emerald, width: 3.5),
                          boxShadow: [
                            BoxShadow(
                              color: emerald.withValues(alpha: 0.25),
                              blurRadius: 18,
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Instruction & Action Bottom Bar
                    Positioned(
                      bottom: 30,
                      left: 24,
                      right: 24,
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.75),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(color: Colors.white12),
                            ),
                            child: const Text(
                              'Position the patient\'s QR code within the frame or choose an image from gallery',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.white, fontSize: 13, height: 1.3),
                            ),
                          ),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              Expanded(
                                child: SizedBox(
                                  height: 50,
                                  child: OutlinedButton.icon(
                                    onPressed: _pickImageFromGallery,
                                    icon: const Icon(Icons.photo_library_outlined, color: Colors.white, size: 20),
                                    label: const Text(
                                      'Gallery',
                                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                                    ),
                                    style: OutlinedButton.styleFrom(
                                      side: const BorderSide(color: Colors.white30, width: 1.5),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: SizedBox(
                                  height: 50,
                                  child: ElevatedButton.icon(
                                    onPressed: _showManualEntryDialog,
                                    icon: const Icon(Icons.keyboard_outlined, color: Colors.white, size: 20),
                                    label: const Text(
                                      'Enter Code',
                                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: emerald,
                                      elevation: 0,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    if (_isProcessing)
                      Container(
                        color: Colors.black.withValues(alpha: 0.65),
                        child: const Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SmartDoseLoading(size: 80, color: Colors.white),
                              SizedBox(height: 18),
                              Text(
                                'Validating SmartDose QR code...',
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

  Widget _buildAlreadyLinkedCaregiverState(Color emerald) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cardBgColor = theme.cardTheme.color ?? theme.colorScheme.surface;
    final primaryTextColor = theme.colorScheme.onSurface;
    final secondaryTextColor = primaryTextColor.withValues(alpha: 0.65);
    final patientName = _existingPairing?['patientName'] ?? 'your patient';

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text('Connect Patient', style: TextStyle(fontWeight: FontWeight.bold, color: primaryTextColor)),
        backgroundColor: cardBgColor,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: primaryTextColor),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28.0),
          child: Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: cardBgColor,
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.05),
                  blurRadius: 18,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppAvatar(
                  name: patientName,
                  size: 72,
                  showGradientBorder: true,
                ),
                const SizedBox(height: 20),
                Text(
                  'Patient Already Linked',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: primaryTextColor),
                ),
                const SizedBox(height: 12),
                Text(
                  'You are actively paired with $patientName. Pairing connects a patient and caregiver so they can access the appropriate medication information and features based on their roles.\n\nTo connect with another patient, please manage your linked patient profile.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: secondaryTextColor, height: 1.5),
                ),
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(builder: (_) => const LinkedAccountScreen(isCaregiver: true)),
                      );
                    },
                    icon: const Icon(LucideIcons.userRound, color: Colors.white, size: 18),
                    label: const Text(
                      'Manage Linked Patient',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: emerald,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: const Text('Back to Home', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPermissionDeniedState(Color emerald) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cardBgColor = theme.cardTheme.color ?? theme.colorScheme.surface;
    final primaryTextColor = theme.colorScheme.onSurface;
    final secondaryTextColor = primaryTextColor.withValues(alpha: 0.65);

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28.0),
        child: Container(
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: cardBgColor,
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.08),
                blurRadius: 20,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF374151) : const Color(0xFFFEF3C7),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.camera_alt_outlined, color: Colors.amber, size: 36),
              ),
              const SizedBox(height: 20),
              Text(
                'Camera Permission Required',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: primaryTextColor),
              ),
              const SizedBox(height: 10),
              Text(
                'To scan QR codes and connect to patients, SmartDose needs camera access.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: secondaryTextColor, height: 1.4),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    final status = await Permission.camera.request();
                    if (status.isPermanentlyDenied) {
                      await openAppSettings();
                    }
                    _checkAndRequestCameraPermission();
                  },
                  icon: const Icon(Icons.security_rounded, color: Colors.white),
                  label: const Text(
                    'Grant Camera Permission',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: emerald,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: OutlinedButton.icon(
                  onPressed: _pickImageFromGallery,
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text(
                    'Choose Image from Gallery',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
