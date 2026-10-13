import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';

class PairingTokenModel {
  final String tokenId;
  final String patientUid;
  final String patientName;
  final String patientEmail;
  final String pairingCode;
  final DateTime expiresAt;
  final String qrPayload;

  PairingTokenModel({
    required this.tokenId,
    required this.patientUid,
    required this.patientName,
    required this.patientEmail,
    required this.pairingCode,
    required this.expiresAt,
    required this.qrPayload,
  });
}

class PairingService {
  final FirebaseFirestore? _customDb;
  FirebaseFirestore get _db => _customDb ?? FirebaseFirestore.instance;
  final _uuid = const Uuid();

  PairingService({FirebaseFirestore? firestore}) : _customDb = firestore;

  /// Helper to generate human-readable pairing code (e.g. SPD-8F4K-91XQ)
  String _generatePairingCode() {
    const chars = '23456789ABCDEFGHJKLMNPQRSTUVWXYZ';
    final rnd = Random();
    String code1 = List.generate(4, (_) => chars[rnd.nextInt(chars.length)]).join();
    String code2 = List.generate(4, (_) => chars[rnd.nextInt(chars.length)]).join();
    return 'SPD-$code1-$code2';
  }

  /// Sanitize raw QR scan input by removing outer quotes, URL decodings,
  /// leading/trailing whitespace, newlines, and BOM markers.
  static String sanitizeQrString(String raw) {
    var s = raw.trim();
    // Strip UTF-8 BOM if present
    if (s.startsWith('\uFEFF')) {
      s = s.substring(1).trim();
    }
    // URL-decode if % encoded
    if (s.contains('%')) {
      try {
        s = Uri.decodeComponent(s).trim();
      } catch (_) {}
    }
    // Strip wrapping quotes (single or double)
    while ((s.startsWith('"') && s.endsWith('"')) ||
           (s.startsWith("'") && s.endsWith("'"))) {
      if (s.length >= 2) {
        s = s.substring(1, s.length - 1).trim();
      } else {
        break;
      }
    }
    // Handle escaped quotes
    if (s.startsWith(r'\"') && s.endsWith(r'\"') && s.length >= 4) {
      s = s.substring(2, s.length - 2).trim();
    }
    return s;
  }

  /// Generate a 10-minute expiring QR token for a Patient
  Future<PairingTokenModel> generatePairingToken({
    required String patientUid,
    required String patientName,
    required String patientEmail,
  }) async {
    final tokenId = _uuid.v4();
    final pairingCode = _generatePairingCode();
    final now = DateTime.now();
    final expiresAt = now.add(const Duration(minutes: 10));

    final qrMap = {
      'app': 'SmartDose',
      'type': 'pairing_token',
      'tokenId': tokenId,
      'code': pairingCode,
      'patientUid': patientUid,
      'patientName': patientName,
      'patientEmail': patientEmail,
      'expiresAt': expiresAt.toIso8601String(),
    };

    final qrPayload = jsonEncode(qrMap);

    try {
      await _db.collection('pairing_tokens').doc(tokenId).set({
        'tokenId': tokenId,
        'patientUid': patientUid,
        'patientName': patientName,
        'patientEmail': patientEmail,
        'pairingCode': pairingCode,
        'createdAt': DateTime.now().toIso8601String(),
        'expiresAt': Timestamp.fromDate(expiresAt),
        'expiresAtIso': expiresAt.toIso8601String(),
        'isUsed': false,
      });
    } catch (e) {
      debugPrint('Pairing tokens Firestore write skipped or warning: $e');
    }

    return PairingTokenModel(
      tokenId: tokenId,
      patientUid: patientUid,
      patientName: patientName,
      patientEmail: patientEmail,
      pairingCode: pairingCode,
      expiresAt: expiresAt,
      qrPayload: qrPayload,
    );
  }

  /// Generate standard QR connection string / payload for a SmartDose hardware device
  static String generateDeviceQrPayload(String deviceId) {
    final devMap = {
      'app': 'SmartDose',
      'type': 'device_link',
      'deviceId': deviceId.trim().toUpperCase(),
      'model': 'SmartDose Dispenser Hub',
      'version': '2.5.0',
    };
    return jsonEncode(devMap);
  }

  /// Validate a scanned QR string or typed pairing code / device ID
  Future<Map<String, dynamic>> validatePairingToken(String rawInput) async {
    final clean = sanitizeQrString(rawInput);
    if (clean.isEmpty) {
      throw Exception('Scanned code is empty. Please try scanning again.');
    }

    String? detectedDeviceId;
    String? tokenId;
    String? pairingCode;
    Map<String, dynamic>? directQrPayload;

    // 1. Check if JSON payload
    if ((clean.startsWith('{') && clean.endsWith('}')) ||
        (clean.startsWith('{"') && clean.endsWith('"}'))) {
      try {
        final Map<String, dynamic> parsed = jsonDecode(clean);
        final app = parsed['app']?.toString();
        final type = parsed['type']?.toString();

        if (parsed['deviceId'] != null && parsed['deviceId'].toString().trim().isNotEmpty) {
          detectedDeviceId = parsed['deviceId'].toString().trim().toUpperCase();
        }

        if (type == 'pairing_token' ||
            (app != null && (app.toLowerCase() == 'smartdose' || app.toLowerCase() == 'smartpilldispenser'))) {
          tokenId = parsed['tokenId']?.toString();
          pairingCode = parsed['code']?.toString();
          directQrPayload = parsed;
        }
      } catch (e) {
        if (clean.contains('"app"') || clean.contains('"deviceId"') || clean.contains('"tokenId"')) {
          throw Exception('Malformed QR code JSON data. Please generate a fresh QR code.');
        }
      }
    }

    // 2. Check custom URI format (e.g. smartdose://device/SD-0119 or smartdose://pair?code=...)
    if (clean.toLowerCase().startsWith('smartdose://')) {
      final uri = Uri.tryParse(clean);
      if (uri != null) {
        if (uri.host == 'device' || uri.path.contains('device')) {
          detectedDeviceId = uri.pathSegments.isNotEmpty
              ? uri.pathSegments.last.toUpperCase()
              : uri.queryParameters['id']?.toUpperCase();
        } else if (uri.host == 'pair' || uri.path.contains('pair')) {
          pairingCode = uri.queryParameters['code'];
          tokenId = uri.queryParameters['tokenId'];
        }
      }
    }

    // 3. Check custom delimiter string formats
    if (clean.toUpperCase().startsWith('SMARTDOSE:DEVICE:')) {
      detectedDeviceId = clean.substring(17).trim().toUpperCase();
    } else if (clean.toUpperCase().startsWith('DEVICE:')) {
      detectedDeviceId = clean.substring(7).trim().toUpperCase();
    }

    // 4. Check raw device serial ID format (e.g. SD-0119, SD-0120)
    if (detectedDeviceId == null && RegExp(r'^SD-[A-Z0-9]{3,8}$', caseSensitive: false).hasMatch(clean)) {
      detectedDeviceId = clean.toUpperCase();
    }

    // If Device ID detected, return as device connection payload
    if (detectedDeviceId != null) {
      Map<String, dynamic> devData = {};
      try {
        final devDoc = await _db.collection('devices').doc(detectedDeviceId).get();
        devData = devDoc.data() ?? {};
      } catch (e) {
        debugPrint('Device lookup in validatePairingToken notice: $e');
      }
      return {
        'type': 'device',
        'deviceId': detectedDeviceId,
        'model': devData['model'] ?? 'SmartDose Dispenser Hub',
        'status': devData['status'] ?? 'online',
        'isOnline': devData['isOnline'] ?? true,
        'currentPatientUid': devData['patientUid'],
        'currentPatientName': devData['patientName'],
      };
    }

    // 5. Check pairing code formats (e.g. SPD-8F4K-91XQ or 8F4K91XQ)
    if (tokenId == null && pairingCode == null) {
      var candidate = clean.toUpperCase().replaceAll(' ', '');
      if (candidate.startsWith('SPD-')) {
        pairingCode = candidate;
      } else if (candidate.length == 8 && RegExp(r'^[2-9A-HJ-NP-Z]{8}$').hasMatch(candidate)) {
        pairingCode = 'SPD-${candidate.substring(0, 4)}-${candidate.substring(4)}';
      } else if (candidate.length == 10 && candidate.startsWith('SPD')) {
        pairingCode = 'SPD-${candidate.substring(3, 7)}-${candidate.substring(7)}';
      }
    }

    if (tokenId == null && pairingCode == null) {
      throw Exception('Invalid QR code format. Not a recognized SmartDose device or patient pairing code.');
    }

    // Query pairing_tokens collection
    QuerySnapshot? query;
    try {
      if (tokenId != null) {
        query = await _db.collection('pairing_tokens').where('tokenId', isEqualTo: tokenId).limit(1).get();
      } else if (pairingCode != null) {
        query = await _db.collection('pairing_tokens').where('pairingCode', isEqualTo: pairingCode).limit(1).get();
      }
    } catch (e) {
      debugPrint('Firestore query pairing token notice: $e');
    }

    if (query == null || query.docs.isEmpty) {
      if (directQrPayload != null && directQrPayload['patientUid'] != null) {
        return {
          'type': 'pairing_token',
          'tokenId': directQrPayload['tokenId'] ?? 'token',
          'patientUid': directQrPayload['patientUid'],
          'name': directQrPayload['patientName'] ?? 'Patient',
          'email': '',
          'photoUrl': null,
          'age': null,
        };
      }
      throw Exception('Pairing code or QR token not found. Please verify the code and try again.');
    }

    final doc = query.docs.first;
    final data = doc.data() as Map<String, dynamic>;

    final bool isUsed = data['isUsed'] ?? false;
    if (isUsed) {
      throw Exception('This QR code or pairing code has already been used.');
    }

    // Safely extract expiration date supporting Timestamp, String, or epoch int
    DateTime? expiresAt;
    final rawExpires = data['expiresAt'];
    if (rawExpires is Timestamp) {
      expiresAt = rawExpires.toDate();
    } else if (rawExpires is String) {
      expiresAt = DateTime.tryParse(rawExpires);
    } else if (rawExpires is int) {
      expiresAt = DateTime.fromMillisecondsSinceEpoch(rawExpires);
    }

    if (expiresAt == null && data['expiresAtIso'] != null) {
      expiresAt = DateTime.tryParse(data['expiresAtIso'].toString());
    }

    if (expiresAt != null && expiresAt.isBefore(DateTime.now())) {
      throw Exception('This pairing code has expired. Please ask the patient to generate a new QR code.');
    }

    final patientUid = (data['patientUid'] ?? '').toString();
    if (patientUid.isEmpty) {
      throw Exception('Invalid pairing token record: missing patient identifier.');
    }

    final patientDoc = await _db.collection('users').doc(patientUid).get();
    Map<String, dynamic> patientProfile = {
      'type': 'pairing_token',
      'patientUid': patientUid,
      'name': data['patientName'] ?? 'Patient',
      'email': data['patientEmail'] ?? '',
      'photoUrl': null,
      'age': null,
    };

    if (patientDoc.exists && patientDoc.data() != null) {
      final pData = patientDoc.data()!;
      patientProfile['name'] = pData['name'] ?? patientProfile['name'];
      patientProfile['email'] = pData['email'] ?? patientProfile['email'];
      patientProfile['photoUrl'] = pData['photoUrl'] ?? pData['profilePhotoUrl'];

      if (pData['dateOfBirth'] != null) {
        try {
          final dob = DateTime.parse(pData['dateOfBirth'].toString());
          patientProfile['age'] = DateTime.now().year - dob.year;
        } catch (_) {}
      }
    }

    return {
      'type': 'pairing_token',
      'tokenId': doc.id,
      ...patientProfile,
    };
  }

  /// Link a SmartDose hardware device to a Patient Account
  Future<Map<String, dynamic>> linkDeviceToPatient({
    required String deviceId,
    required String patientUid,
    required String patientName,
  }) async {
    final cleanId = deviceId.trim().toUpperCase();
    if (!RegExp(r'^SD-[A-Z0-9]{3,8}$').hasMatch(cleanId)) {
      throw Exception('Invalid SmartDose device identifier format ($cleanId). Expected format like SD-0119.');
    }

    final devDocRef = _db.collection('devices').doc(cleanId);
    final devDoc = await devDocRef.get();

    // Check if device is already linked to another patient
    if (devDoc.exists && devDoc.data() != null) {
      final existingPatientUid = devDoc.data()?['patientUid'] as String?;
      if (existingPatientUid != null &&
          existingPatientUid.isNotEmpty &&
          existingPatientUid != patientUid) {
        debugPrint('Device $cleanId transferring from $existingPatientUid to $patientUid');
      }
    }

    // Set or merge device document in devices collection
    await devDocRef.set({
      'deviceId': cleanId,
      'patientUid': patientUid,
      'patientName': patientName,
      'status': 'online',
      'isOnline': true,
      'model': devDoc.data()?['model'] ?? 'SmartDose Dispenser Hub',
      'firmwareVersion': devDoc.data()?['firmwareVersion'] ?? 'v2.5.0',
      'lastHeartbeat': FieldValue.serverTimestamp(),
      'linkedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    // Update users and patients collections
    await _db.collection('users').doc(patientUid).set({
      'deviceId': cleanId,
      'updatedAt': DateTime.now().toIso8601String(),
    }, SetOptions(merge: true));

    await _db.collection('patients').doc(patientUid).set({
      'deviceId': cleanId,
      'updatedAt': DateTime.now().toIso8601String(),
    }, SetOptions(merge: true));

    return {
      'deviceId': cleanId,
      'status': 'online',
      'isOnline': true,
      'patientUid': patientUid,
      'patientName': patientName,
    };
  }

  /// Unpair a SmartDose hardware device from a Patient Account
  Future<void> unpairDevice({
    required String deviceId,
    required String patientUid,
  }) async {
    final cleanId = deviceId.trim().toUpperCase();
    await _db.collection('users').doc(patientUid).update({
      'deviceId': FieldValue.delete(),
    });
    await _db.collection('patients').doc(patientUid).update({
      'deviceId': FieldValue.delete(),
    });
    await _db.collection('devices').doc(cleanId).set({
      'patientUid': null,
      'patientName': null,
      'unpairedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Caregiver sends a connection request to Patient
  Future<void> sendPairingRequest({
    required String patientUid,
    required String patientName,
    required String caregiverUid,
    required String caregiverName,
    required String caregiverEmail,
    required String relationship,
    String? caregiverPhoto,
  }) async {
    // Check if pending request already exists
    final existing = await _db
        .collection('pairing_requests')
        .where('patientUid', isEqualTo: patientUid)
        .where('caregiverUid', isEqualTo: caregiverUid)
        .where('status', isEqualTo: 'pending')
        .get();

    if (existing.docs.isNotEmpty) {
      throw Exception('A connection request is already pending approval by the patient.');
    }

    await _db.collection('pairing_requests').add({
      'patientUid': patientUid,
      'patientName': patientName,
      'caregiverUid': caregiverUid,
      'caregiverName': caregiverName,
      'caregiverEmail': caregiverEmail,
      'caregiverPhoto': caregiverPhoto,
      'relationship': relationship,
      'status': 'pending',
      'requestedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Stream incoming pending caregiver requests for a patient
  Stream<List<Map<String, dynamic>>> getPendingRequestsStream(String patientUid) {
    return _db
        .collection('pairing_requests')
        .where('patientUid', isEqualTo: patientUid)
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        return {
          'requestId': doc.id,
          ...doc.data(),
        };
      }).toList();
    });
  }

  /// Patient approves a caregiver request
  Future<void> approvePairingRequest(String requestId, Map<String, dynamic> requestData) async {
    await _db.collection('pairing_requests').doc(requestId).update({
      'status': 'approved',
      'approvedAt': FieldValue.serverTimestamp(),
    });

    final patientUid = requestData['patientUid']?.toString() ?? '';
    final caregiverUid = requestData['caregiverUid']?.toString() ?? '';
    final caregiverName = requestData['caregiverName'] ?? 'Caregiver';
    final caregiverEmail = requestData['caregiverEmail'] ?? '';
    final relationship = requestData['relationship'] ?? 'Caregiver';

    // 1. Add to active pairings collection
    await _db.collection('pairings').add({
      'patientUid': patientUid,
      'patientName': requestData['patientName'] ?? 'Patient',
      'caregiverUid': caregiverUid,
      'caregiverName': caregiverName,
      'caregiverEmail': caregiverEmail,
      'caregiverPhoto': requestData['caregiverPhoto'],
      'relationship': relationship,
      'role': 'Primary Caregiver',
      'createdAt': FieldValue.serverTimestamp(),
      'lastActive': FieldValue.serverTimestamp(),
    });

    // 2. Mark pairing token as used if tokenId provided
    if (requestData['tokenId'] != null) {
      try {
        await _db.collection('pairing_tokens').doc(requestData['tokenId']).update({
          'isUsed': true,
          'usedByUid': caregiverUid,
          'usedAt': FieldValue.serverTimestamp(),
        });
      } catch (_) {}
    }

    // 3. Update patient's caregiverIds array
    if (patientUid.isNotEmpty && caregiverUid.isNotEmpty) {
      try {
        await _db.collection('patients').doc(patientUid).set({
          'caregiverIds': FieldValue.arrayUnion([caregiverUid]),
        }, SetOptions(merge: true));
      } catch (_) {}

      // 4. Also register caregiver in contacts collection for SMS alerts
      try {
        await _db.collection('contacts').add({
          'patientUid': patientUid,
          'patientName': requestData['patientName'] ?? 'Patient',
          'name': caregiverName,
          'phone': caregiverEmail,
          'email': caregiverEmail,
          'relationship': relationship,
          'caregiverUid': caregiverUid,
          'isPrimary': true,
          'createdAt': FieldValue.serverTimestamp(),
        });
      } catch (_) {}
    }
  }

  /// Patient rejects a caregiver request
  Future<void> rejectPairingRequest(String requestId) async {
    await _db.collection('pairing_requests').doc(requestId).update({
      'status': 'rejected',
      'rejectedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Stream of active connected caregivers for a patient (strictly scoped by patientUid)
  Stream<List<Map<String, dynamic>>> getConnectedCaregiversStream(String patientUid) {
    if (patientUid.isEmpty) return Stream.value([]);
    return _db
        .collection('pairings')
        .where('patientUid', isEqualTo: patientUid)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'pairingId': doc.id,
          'caregiverName': data['caregiverName'] ?? 'Caregiver',
          'caregiverEmail': data['caregiverEmail'] ?? '',
          'relationship': data['relationship'] ?? 'Primary Caregiver',
          'role': data['role'] ?? 'Primary Caregiver',
          'lastActive': data['lastActive'] ?? data['createdAt'],
          ...data,
        };
      }).toList();
    });
  }

  /// Stream of active connected patients for a caregiver (strictly scoped by caregiverUid)
  Stream<List<Map<String, dynamic>>> getConnectedPatientsStream(String caregiverUid) {
    if (caregiverUid.isEmpty) return Stream.value([]);
    return _db
        .collection('pairings')
        .where('caregiverUid', isEqualTo: caregiverUid)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        return {
          'pairingId': doc.id,
          ...doc.data(),
        };
      }).toList();
    });
  }

  /// Remove a connected pairing
  Future<void> removePairing(String pairingId) async {
    await _db.collection('pairings').doc(pairingId).delete();
  }

  /// Update caregiver role (Primary Caregiver vs Family Member)
  Future<void> updateCaregiverRole(String pairingId, String newRole) async {
    await _db.collection('pairings').doc(pairingId).update({
      'role': newRole,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}
