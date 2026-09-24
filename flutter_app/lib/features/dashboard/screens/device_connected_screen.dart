import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;

class DeviceConnectedScreen extends StatefulWidget {
  const DeviceConnectedScreen({super.key});

  @override
  State<DeviceConnectedScreen> createState() => _DeviceConnectedScreenState();
}

class _DeviceConnectedScreenState extends State<DeviceConnectedScreen> {
  Map<String, dynamic>? _deviceData;
  String? _deviceId;
  bool _loading = true;
  StreamSubscription? _deviceSubscription;
  int _targetServoAngle = 0;
  bool _sendingServo = false;

  Future<void> _sendServoCommand(int angle) async {
    setState(() {
      _targetServoAngle = angle;
      _sendingServo = true;
    });

    try {
      if (_deviceId != null) {
        await FirebaseFirestore.instance
            .collection('devices')
            .doc(_deviceId)
            .update({
          'servoAngle': angle,
          'lastServoCommandAt': FieldValue.serverTimestamp(),
        });
      }

      final url = Uri.parse(
          'https://smart-pill-dispenser-baa02-default-rtdb.firebaseio.com/hardware/servo1.json');
      await http.put(url, body: jsonEncode(angle));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('ESP32 Servo command sent: $angle°'),
            backgroundColor: const Color(0xFF00A36C),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update servo: $e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sendingServo = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _listenToDevice();
  }

  @override
  void dispose() {
    _deviceSubscription?.cancel();
    super.dispose();
  }

  Future<void> _listenToDevice() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final userDoc =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final deviceId = userDoc.data()?['deviceId'] as String?;
      if (deviceId == null) {
        if (mounted) setState(() => _loading = false);
        return;
      }

      if (mounted) {
        setState(() => _deviceId = deviceId);
      }

      // Realtime listener for live updates
      _deviceSubscription = FirebaseFirestore.instance
          .collection('devices')
          .doc(deviceId)
          .snapshots()
          .listen((snapshot) {
        if (mounted) {
          setState(() {
            _deviceData = snapshot.data();
            _loading = false;
          });
        }
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    await _deviceSubscription?.cancel();
    await _listenToDevice();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bg = theme.scaffoldBackgroundColor;
    final cardBg = theme.cardTheme.color ?? theme.colorScheme.surface;
    final primaryText = theme.colorScheme.onSurface;
    final secondaryText = primaryText.withValues(alpha: 0.6);

    final isOnline = _deviceData?['isOnline'] as bool? ?? true;
    final battery = _deviceData?['batteryPercent'] as int? ?? 92;
    final modelName =
        _deviceData?['model'] as String? ?? 'SmartDose Dispenser Hub';
    final firmware =
        _deviceData?['firmwareVersion'] as String? ?? 'v2.4.1';
    final ssid = _deviceData?['wifiSSID'] as String? ?? 'Home_WiFi_5G';
    final rssi = _deviceData?['wifiRSSI'] as int? ?? -48;
    final lastSync = _deviceData?['lastSyncAt'] as Timestamp?;
    final syncStr = lastSync != null
        ? DateFormat('MMM d, hh:mm a').format(lastSync.toDate())
        : 'Just now';
    final ip = _deviceData?['ipAddress'] as String? ?? '192.168.1.142';
    final compartments = _deviceData?['compartmentCount'] as int? ?? 10;
    final uptime = _deviceData?['uptimeHours'] as int? ?? 142;

    String wifiStrength = 'Excellent';
    IconData wifiIcon = Icons.wifi_rounded;
    Color wifiColor = const Color(0xFF00A36C);
    if (rssi != 0) {
      if (rssi >= -50) {
        wifiStrength = 'Excellent';
        wifiIcon = Icons.wifi_rounded;
        wifiColor = const Color(0xFF00A36C);
      } else if (rssi >= -65) {
        wifiStrength = 'Good';
        wifiIcon = Icons.wifi_rounded;
        wifiColor = const Color(0xFF10B981);
      } else {
        wifiStrength = 'Fair';
        wifiIcon = Icons.wifi_2_bar_rounded;
        wifiColor = const Color(0xFFF59E0B);
      }
    }

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded,
              color: primaryText, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Device Status',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: primaryText,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Color(0xFF00A36C)),
            onPressed: _refresh,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF00A36C)))
          : RefreshIndicator(
              onRefresh: _refresh,
              color: const Color(0xFF00A36C),
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Status Banner Card ─────────────────────────────
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(22),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: isOnline
                              ? [
                                  const Color(0xFF00A36C),
                                  const Color(0xFF00C882)
                                ]
                              : [
                                  const Color(0xFF475569),
                                  const Color(0xFF64748B)
                                ],
                        ),
                        borderRadius: BorderRadius.circular(28),
                        boxShadow: [
                          BoxShadow(
                            color: (isOnline
                                    ? const Color(0xFF00A36C)
                                    : const Color(0xFF475569))
                                .withValues(alpha: 0.3),
                            blurRadius: 16,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 50,
                                height: 50,
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.2),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(LucideIcons.cpu,
                                    color: Colors.white, size: 26),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(modelName,
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold)),
                                    const SizedBox(height: 2),
                                    Text(
                                      _deviceId != null
                                          ? 'ID: ${_deviceId!.substring(0, _deviceId!.length > 8 ? 8 : _deviceId!.length).toUpperCase()}'
                                          : 'Raspberry Pi Hub',
                                      style: const TextStyle(
                                          color: Colors.white70, fontSize: 13),
                                    ),
                                  ],
                                ),
                              ),
                              // Online/Offline Pill Badge
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 8,
                                      height: 8,
                                      decoration: BoxDecoration(
                                        color: isOnline
                                            ? Colors.greenAccent
                                            : Colors.white54,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      isOnline ? 'Online' : 'Offline',
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 13,
                                          fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          // Stats row
                          Row(
                            children: [
                              _statItem(Icons.battery_full_rounded, '$battery%', 'Battery', Colors.white),
                              _vDivider(),
                              _statItem(wifiIcon, wifiStrength, 'Signal', Colors.white),
                              _vDivider(),
                              _statItem(LucideIcons.box, '$compartments', 'Slots', Colors.white),
                              _vDivider(),
                              _statItem(Icons.access_time_rounded, '${uptime}h', 'Uptime', Colors.white),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // ── Hardware & System Info ─────────────────────────────
                    Text('Hardware & System',
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: primaryText)),
                    const SizedBox(height: 12),
                    _cardWrapper(cardBg, isDark, [
                      _rowTile(
                        icon: LucideIcons.cpu,
                        label: 'Main Controller',
                        value: 'ESP32 Dual-Core',
                        primaryText: primaryText,
                        secondaryText: secondaryText,
                        showDivider: true,
                      ),
                      _rowTile(
                        icon: LucideIcons.box,
                        label: 'System Host',
                        value: 'Raspberry Pi 4B',
                        primaryText: primaryText,
                        secondaryText: secondaryText,
                        showDivider: true,
                      ),
                      _rowTile(
                        icon: Icons.system_update_rounded,
                        label: 'Firmware Version',
                        value: firmware,
                        primaryText: primaryText,
                        secondaryText: secondaryText,
                        showDivider: false,
                      ),
                    ]),

                    const SizedBox(height: 24),

                    // ── Network Details ───────────────────────────────────
                    Text('Network Details',
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: primaryText)),
                    const SizedBox(height: 12),
                    _cardWrapper(cardBg, isDark, [
                      _rowTile(
                        icon: Icons.wifi_rounded,
                        label: 'Wi-Fi Network',
                        value: ssid,
                        primaryText: primaryText,
                        secondaryText: secondaryText,
                        showDivider: true,
                      ),
                      _rowTile(
                        icon: wifiIcon,
                        label: 'Signal Quality',
                        value: '$wifiStrength ($rssi dBm)',
                        primaryText: primaryText,
                        secondaryText: secondaryText,
                        valueColor: wifiColor,
                        showDivider: true,
                      ),
                      _rowTile(
                        icon: Icons.lan_outlined,
                        label: 'IP Address',
                        value: ip,
                        primaryText: primaryText,
                        secondaryText: secondaryText,
                        showDivider: true,
                      ),
                      _rowTile(
                        icon: Icons.sync_rounded,
                        label: 'Last Synced',
                        value: syncStr,
                        primaryText: primaryText,
                        secondaryText: secondaryText,
                        showDivider: false,
                      ),
                    ]),

                    const SizedBox(height: 24),

                    // ── ESP32 Servo Motor Control & Calibration ─────────────────
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('ESP32 Servo Motor Control',
                            style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: primaryText)),
                        if (_sendingServo)
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Color(0xFF00A36C),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: cardBg,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black
                                .withValues(alpha: isDark ? 0.18 : 0.03),
                            blurRadius: 12,
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
                                width: 42,
                                height: 42,
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? const Color(0xFF1E2D25)
                                      : const Color(0xFFE8F8F0),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(LucideIcons.rotateCw,
                                    color: Color(0xFF00A36C), size: 22),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Target Angle: ${_targetServoAngle.toInt()}°',
                                        style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                            color: primaryText)),
                                    const SizedBox(height: 2),
                                    Text('Realtime Database path: /hardware/servo1',
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: secondaryText)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          SliderTheme(
                            data: SliderThemeData(
                              activeTrackColor: const Color(0xFF00A36C),
                              inactiveTrackColor: isDark
                                  ? Colors.grey.shade800
                                  : Colors.grey.shade200,
                              thumbColor: const Color(0xFF00A36C),
                              overlayColor:
                                  const Color(0xFF00A36C).withValues(alpha: 0.2),
                              trackHeight: 6,
                            ),
                            child: Slider(
                              value: _targetServoAngle.toDouble(),
                              min: 0,
                              max: 180,
                              divisions: 36,
                              label: '${_targetServoAngle.toInt()}°',
                              onChanged: (val) {
                                setState(() => _targetServoAngle = val.round());
                              },
                              onChangeEnd: (val) {
                                _sendServoCommand(val.round());
                              },
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [0, 45, 90, 135, 180].map((angle) {
                              final isSelected = _targetServoAngle == angle;
                              return OutlinedButton(
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 8),
                                  minimumSize: Size.zero,
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  backgroundColor: isSelected
                                      ? const Color(0xFF00A36C)
                                      : Colors.transparent,
                                  side: BorderSide(
                                    color: isSelected
                                        ? const Color(0xFF00A36C)
                                        : (isDark
                                            ? Colors.grey.shade800
                                            : Colors.grey.shade300),
                                  ),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12)),
                                ),
                                onPressed: () => _sendServoCommand(angle),
                                child: Text(
                                  '$angle°',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: isSelected
                                        ? Colors.white
                                        : primaryText,
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // ── Quick Controls ───────────────────────────────────
                    Text('Device Controls',
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: primaryText)),
                    const SizedBox(height: 12),
                    _cardWrapper(cardBg, isDark, [
                      _actionTile(
                        icon: Icons.sync_rounded,
                        title: 'Force Sync Data',
                        subtitle: 'Request immediate status sync from dispenser',
                        primaryText: primaryText,
                        secondaryText: secondaryText,
                        showDivider: true,
                        onTap: () async {
                          if (_deviceId != null) {
                            await FirebaseFirestore.instance
                                .collection('devices')
                                .doc(_deviceId)
                                .update({
                              'forceSync': true,
                              'lastSyncAt': FieldValue.serverTimestamp(),
                            });
                          }
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content:
                                    const Text('Force sync command sent to dispenser'),
                                backgroundColor: const Color(0xFF00A36C),
                                behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16)),
                              ),
                            );
                          }
                        },
                      ),
                      _actionTile(
                        icon: Icons.restart_alt_rounded,
                        title: 'Restart System',
                        subtitle: 'Soft restart ESP32 dispenser controller',
                        primaryText: primaryText,
                        secondaryText: secondaryText,
                        showDivider: true,
                        onTap: () async {
                          if (_deviceId != null) {
                            await FirebaseFirestore.instance
                                .collection('devices')
                                .doc(_deviceId)
                                .update({'restartRequested': true});
                          }
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content:
                                    const Text('Restart command sent to dispenser'),
                                backgroundColor: const Color(0xFF00A36C),
                                behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16)),
                              ),
                            );
                          }
                        },
                      ),
                      _actionTile(
                        icon: Icons.link_off_rounded,
                        title: 'Unpair Device',
                        subtitle: 'Disconnect this SmartDose unit',
                        primaryText: primaryText,
                        secondaryText: secondaryText,
                        showDivider: false,
                        isDestructive: true,
                        onTap: () => _confirmUnpair(context),
                      ),
                    ]),

                    const SizedBox(height: 30),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _statItem(
      IconData icon, String value, String label, Color color) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(height: 4),
          Text(value,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold)),
          Text(label,
              style: const TextStyle(color: Colors.white70, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _vDivider() {
    return Container(
        width: 1, height: 32, color: Colors.white.withValues(alpha: 0.2));
  }

  Widget _cardWrapper(Color cardBg, bool isDark, List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.18 : 0.03),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(children: children),
    );
  }

  Widget _rowTile({
    required IconData icon,
    required String label,
    required String value,
    required Color primaryText,
    required Color secondaryText,
    required bool showDivider,
    Color? valueColor,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E2D25) : const Color(0xFFE8F8F0),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: const Color(0xFF00A36C), size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                flex: 4,
                child: Text(
                  label,
                  style: TextStyle(fontSize: 14, color: secondaryText),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 5,
                child: Text(
                  value,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: valueColor ?? primaryText,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (showDivider)
          Divider(
              height: 1,
              indent: 72,
              endIndent: 18,
              color: Theme.of(context).dividerColor),
      ],
    );
  }

  Widget _actionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color primaryText,
    required Color secondaryText,
    required bool showDivider,
    bool isDestructive = false,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final iconColor =
        isDestructive ? const Color(0xFFEF4444) : const Color(0xFF00A36C);
    final iconBg = isDestructive
        ? (isDark ? const Color(0xFF3B1212) : const Color(0xFFFEE2E2))
        : (isDark ? const Color(0xFF1E2D25) : const Color(0xFFE8F8F0));

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
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(color: iconBg, shape: BoxShape.circle),
                  child: Icon(icon, color: iconColor, size: 20),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: isDestructive
                                  ? const Color(0xFFEF4444)
                                  : primaryText)),
                      const SizedBox(height: 2),
                      Text(subtitle,
                          style: TextStyle(fontSize: 12, color: secondaryText)),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded,
                    color: secondaryText, size: 22),
              ],
            ),
          ),
        ),
        if (showDivider)
          Divider(
              height: 1,
              indent: 72,
              endIndent: 18,
              color: Theme.of(context).dividerColor),
      ],
    );
  }

  void _confirmUnpair(BuildContext context) {
    final cardBg =
        Theme.of(context).cardTheme.color ?? Theme.of(context).colorScheme.surface;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: cardBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        contentPadding: const EdgeInsets.all(24),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: const BoxDecoration(
                  color: Color(0xFFFEE2E2), shape: BoxShape.circle),
              child: const Icon(Icons.link_off_rounded,
                  color: Color(0xFFEF4444), size: 28),
            ),
            const SizedBox(height: 16),
            const Text('Unpair Device?',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(
              'This will disconnect SmartDose from your account. You can re-pair it at any time.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 14,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.65),
                  height: 1.4),
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                    ),
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFEF4444),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                    ),
                    onPressed: () async {
                      Navigator.pop(ctx);
                      final uid = FirebaseAuth.instance.currentUser?.uid;
                      if (uid == null) return;
                      await FirebaseFirestore.instance
                          .collection('users')
                          .doc(uid)
                          .update({'deviceId': FieldValue.delete()});
                      if (mounted) Navigator.pop(context);
                    },
                    child: const Text('Unpair',
                        style: TextStyle(color: Colors.white)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
