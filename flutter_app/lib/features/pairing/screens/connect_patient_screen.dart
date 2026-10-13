import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/pairing_service.dart';
import 'confirm_pairing_dialog.dart';
import 'package:smartdose/shared/widgets/smartdose_loading.dart';

class ConnectPatientScreen extends StatefulWidget {
  const ConnectPatientScreen({super.key});

  @override
  State<ConnectPatientScreen> createState() => _ConnectPatientScreenState();
}

class _ConnectPatientScreenState extends State<ConnectPatientScreen> {
  final MobileScannerController _scannerController = MobileScannerController();
  final PairingService _pairingService = PairingService();
  bool _isProcessing = false;
  bool _isTorchOn = false;
  bool _hasCameraPermission = false;
  bool _isCheckingPermission = true;

  @override
  void initState() {
    super.initState();
    _checkAndRequestCameraPermission();
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
    _scannerController.dispose();
    super.dispose();
  }

  void _showDeviceConnectDialog(String deviceId) {
    final user = FirebaseAuth.instance.currentUser;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            const Icon(Icons.router_rounded, color: Color(0xFF10B981)),
            const SizedBox(width: 10),
            Text('Connect $deviceId?'),
          ],
        ),
        content: Text(
          'SmartDose Dispenser ($deviceId) detected. Would you like to connect this unit to your account?',
          style: const TextStyle(fontSize: 14, color: Color(0xFF4B5563)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF6B7280))),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              if (user == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please sign in to link device.')),
                );
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
                  setState(() => _isProcessing = false);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('SmartDose Dispenser $deviceId connected successfully!'),
                      backgroundColor: const Color(0xFF10B981),
                    ),
                  );
                  Navigator.pop(context);
                }
              } catch (e) {
                if (mounted) {
                  setState(() => _isProcessing = false);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(e.toString().replaceAll('Exception: ', '')),
                      backgroundColor: Colors.redAccent,
                    ),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
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
    setState(() => _isProcessing = true);

    try {
      final result = await _pairingService.validatePairingToken(rawCode);
      if (mounted) {
        setState(() => _isProcessing = false);
        if (result['type'] == 'device') {
          _showDeviceConnectDialog(result['deviceId'] as String);
        } else {
          showDialog(
            context: context,
            builder: (_) => ConfirmPairingDialog(patientData: result),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceAll('Exception: ', '')),
            backgroundColor: Colors.redAccent,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  void _showManualEntryDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: const Text('Enter Code or Device ID'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Enter the patient\'s pairing code (e.g. SPD-8F4K-91XQ) or SmartDose hardware device ID (e.g. SD-0119).',
                style: TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  hintText: 'e.g. SPD-8F4K-91XQ or SD-0119',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: Color(0xFF10B981), width: 2),
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
                final code = controller.text.trim();
                if (code.isNotEmpty) {
                  Navigator.pop(ctx);
                  _handleScannedCode(code);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10B981),
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
    const emerald = Color(0xFF10B981);

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
          ? const Center(
              child: SmartDoseLoading(size: 80),
            )
          : !_hasCameraPermission
              ? _buildPermissionDeniedState(emerald)
              : Stack(
                  children: [
                    // Mobile Scanner Camera Viewfinder
                    MobileScanner(
                      controller: _scannerController,
                      onDetect: (capture) {
                        final List<Barcode> barcodes = capture.barcodes;
                        for (final barcode in barcodes) {
                          if (barcode.rawValue != null && !_isProcessing) {
                            _handleScannedCode(barcode.rawValue!);
                            break;
                          }
                        }
                      },
                    ),

                    // Camera Viewfinder Frame Overlay
                    Center(
                      child: Container(
                        width: 260,
                        height: 260,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: emerald, width: 3),
                        ),
                      ),
                    ),

                    // Instruction & Manual Entry Button Bottom Bar
                    Positioned(
                      bottom: 30,
                      left: 24,
                      right: 24,
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.7),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: const Text(
                              'Position the patient\'s QR code within the frame to scan',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.white, fontSize: 13),
                            ),
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            height: 50,
                            child: ElevatedButton.icon(
                              onPressed: _showManualEntryDialog,
                              icon: const Icon(Icons.keyboard_outlined, color: Colors.white),
                              label: const Text(
                                'Enter Pairing Code Manually',
                                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: emerald,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    if (_isProcessing)
                      Container(
                        color: Colors.black54,
                        child: const Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SmartDoseLoading(size: 80),
                              SizedBox(height: 16),
                              Text(
                                'Validating QR code...',
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
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
                  onPressed: _showManualEntryDialog,
                  icon: Icon(Icons.keyboard_outlined, color: primaryTextColor),
                  label: Text(
                    'Enter Pairing Code Manually',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: primaryTextColor),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: theme.dividerColor, width: 1.5),
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
