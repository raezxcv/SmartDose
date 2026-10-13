import 'package:flutter_test/flutter_test.dart';
import 'package:smartdose/features/pairing/services/pairing_service.dart';

void main() {
  group('PairingService QR String Sanitization & Parsing Tests', () {
    test('sanitizeQrString strips leading and trailing quotes', () {
      expect(PairingService.sanitizeQrString('"SD-0119"'), equals('SD-0119'));
      expect(PairingService.sanitizeQrString("'SD-0119'"), equals('SD-0119'));
      expect(PairingService.sanitizeQrString('  "SD-0119"  '), equals('SD-0119'));
    });

    test('sanitizeQrString decodes URL-encoded JSON strings', () {
      const urlEncoded = '%7B%22type%22%3A%22device%22%2C%22deviceId%22%3A%22SD-0119%22%7D';
      expect(PairingService.sanitizeQrString(urlEncoded), equals('{"type":"device","deviceId":"SD-0119"}'));
    });

    test('sanitizeQrString strips UTF-8 Byte Order Mark (BOM)', () {
      const withBom = '\uFEFFSD-0119';
      expect(PairingService.sanitizeQrString(withBom), equals('SD-0119'));
    });

    test('generateDeviceQrPayload produces valid JSON payload', () {
      final payload = PairingService.generateDeviceQrPayload('SD-0119');
      expect(payload, contains('"deviceId":"SD-0119"'));
      expect(payload, contains('"type":"device_link"'));
    });

    test('validatePairingToken recognizes raw hardware serial string', () async {
      final service = PairingService();
      final result = await service.validatePairingToken('SD-0119');
      expect(result['type'], equals('device'));
      expect(result['deviceId'], equals('SD-0119'));
    });

    test('validatePairingToken recognizes custom smartdose URI scheme', () async {
      final service = PairingService();
      final result1 = await service.validatePairingToken('smartdose://device/SD-0119');
      expect(result1['type'], equals('device'));
      expect(result1['deviceId'], equals('SD-0119'));

      final result2 = await service.validatePairingToken('SMARTDOSE:DEVICE:SD-0119');
      expect(result2['type'], equals('device'));
      expect(result2['deviceId'], equals('SD-0119'));
    });

    test('validatePairingToken recognizes device JSON payload', () async {
      final service = PairingService();
      const jsonPayload = '{"type":"device","deviceId":"SD-0119","model":"SmartDose Hub"}';
      final result = await service.validatePairingToken(jsonPayload);
      expect(result['type'], equals('device'));
      expect(result['deviceId'], equals('SD-0119'));
    });

    test('validatePairingToken rejects empty or whitespace string with Exception', () async {
      final service = PairingService();
      expect(
        () async => await service.validatePairingToken('   '),
        throwsA(isA<Exception>()),
      );
    });

    test('validatePairingToken rejects arbitrary non-pairing text with descriptive Exception', () async {
      final service = PairingService();
      expect(
        () async => await service.validatePairingToken('random_invalid_string'),
        throwsA(isA<Exception>()),
      );
    });
  });
}
