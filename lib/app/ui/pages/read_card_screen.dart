import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_nfc_kit/flutter_nfc_kit.dart';
import 'package:convert/convert.dart';
import 'package:rfid/app/services/lock_crypto.dart';
import 'package:rfid/app/services/card_parser_service.dart';

final Uint8List TRANSPORT_KEY = Uint8List.fromList([0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF]);
final Uint8List _manufacturerKey = Uint8List.fromList(hex.decode('00112233445566778899AABBCCDDEEFF'));
final String bleMac = "14:E9:F0:84:A9:45";
late Uint8List _lockSecretKey;

class ReadCardScreen extends StatefulWidget {
  const ReadCardScreen({super.key});

  @override
  State<ReadCardScreen> createState() => _ReadCardScreenState();
}

class _ReadCardScreenState extends State<ReadCardScreen> {
  String _status = 'Ready to scan';
  String _cardData = '';
  bool _isScanning = false;

  // Try all possible keys for a sector
  Future<bool> _authenticateSector(int sector) async {
    _lockSecretKey = LockCrypto.deriveLockSecret(_manufacturerKey, bleMac);
    final keysToTry = <Uint8List>[
      LockCrypto.deriveMifareKeyA(_manufacturerKey, sector), //Authenticate MFG Sectors
      LockCrypto.deriveMifareKeyA(_lockSecretKey, sector), // Authenticate LS Sectors
      TRANSPORT_KEY,
    ];
    for (final key in keysToTry) {
      try {
        bool ok = await FlutterNfcKit.authenticateSector(sector, keyA: key);
        if (ok) {
          print("✅ Sector $sector authenticated with key: ${hex.encode(key).toUpperCase()}");
          return true;
        }
      } catch (e) {
        // Continue to next key
      }
    }

    return false;
  }

  Future<void> _readCard() async {
    setState(() {
      _isScanning = true;
      _status = 'Waiting for card...';
      _cardData = '';
    });

    try {
      final availability = await FlutterNfcKit.nfcAvailability;
      if (availability != NFCAvailability.available) {
        setState(() => _status = 'NFC not available');
        return;
      }

      NFCTag tag = await FlutterNfcKit.poll(
        timeout: const Duration(seconds: 10),
        iosMultipleTagMessage: "Multiple cards detected",
        iosAlertMessage: "Hold your card",
      );

      String uid = tag.id.toUpperCase();
      setState(() => _status = 'Card detected: $uid\nReading Sector 1...');

      // ---- Sector 1 ----
      bool auth1 = await _authenticateSector(1);
      if (!auth1) throw Exception('Sector 1 authentication failed');

      Uint8List b4 = await FlutterNfcKit.readBlock(4);
      Uint8List b5 = await FlutterNfcKit.readBlock(5);
      Uint8List b6 = await FlutterNfcKit.readBlock(6);
      Uint8List b7 = await FlutterNfcKit.readBlock(7);

      // ---- Sector 2 ----
      setState(() => _status = 'Reading Sector 2...');
      bool auth2 = await _authenticateSector(2);
      Uint8List? b8, b9, b10, b11;
      if (auth2) {
        b8 = await FlutterNfcKit.readBlock(8);
        b9 = await FlutterNfcKit.readBlock(9);
        b10 = await FlutterNfcKit.readBlock(10);
        b11 = await FlutterNfcKit.readBlock(11);
      } else {
        print("⚠️ Sector 2 authentication failed – skipping");
      }

      setState(() => _status = 'Parsing / decrypting...');

      // Build raw data display
      final buffer = StringBuffer();
      buffer.writeln('UID: $uid\n');
      buffer.writeln('--- Sector 1 ---');
      buffer.writeln('Block 4: ${hex.encode(b4).toUpperCase()}');
      buffer.writeln('Block 5: ${hex.encode(b5).toUpperCase()}');
      buffer.writeln('Block 6: ${hex.encode(b6).toUpperCase()}');
      buffer.writeln('Block 7 (trailer): ${hex.encode(b7).toUpperCase()}');
      buffer.writeln();

      if (auth2 && b8 != null) {
        buffer.writeln('--- Sector 2 ---');
        buffer.writeln('Block 8:  ${hex.encode(b8).toUpperCase()}');
        buffer.writeln('Block 9:  ${hex.encode(b9!).toUpperCase()}');
        buffer.writeln('Block 10: ${hex.encode(b10!).toUpperCase()}');
        buffer.writeln('Block 11 (trailer): ${hex.encode(b11!).toUpperCase()}');
      } else {
        buffer.writeln('--- Sector 2 ---\n⚠️ Authentication failed – cannot read');
      }
      buffer.writeln();
      // print('UID: $uid\n');

      // print('--- Sector 1 ---');
      // print('Block 4: ${hex.encode(b4).toUpperCase()}');
      // print('Block 5: ${hex.encode(b5).toUpperCase()}');
      // print('Block 6: ${hex.encode(b6).toUpperCase()}');
      // print('Block 7 (trailer): ${hex.encode(b7).toUpperCase()}');
      // print('');

      // if (auth2 && b8 != null) {
      //   print('--- Sector 2 ---');
      //   print('Block 8:  ${hex.encode(b8).toUpperCase()}');
      //   print('Block 9:  ${hex.encode(b9!).toUpperCase()}');
      //   print('Block 10: ${hex.encode(b10!).toUpperCase()}');
      //   print('Block 11 (trailer): ${hex.encode(b11!).toUpperCase()}');
      // } else {
      //   print('--- Sector 2 ---');
      //   print('⚠️ Authentication failed – cannot read');
      // }

      // print('');
      // ---- Decrypt & parse (using existing parser service) ----
      final sector1Data = Uint8List(48)
        ..setRange(0, 16, b4)
        ..setRange(16, 32, b5)
        ..setRange(32, 48, b6);

      Uint8List? sector2Data;
      if (auth2 && b8 != null) {
        sector2Data = Uint8List(48)
          ..setRange(0, 16, b8)
          ..setRange(16, 32, b9!)
          ..setRange(32, 48, b10!);
      }

      final parser = CardParserService(manufacturerKey: _manufacturerKey, lockSecretKey: _lockSecretKey);

      try {
        final parsed = parser.parseCard(uidHex: uid, sector1Blocks: sector1Data, sector2Blocks: sector2Data);
        buffer.writeln('=== ${parsed.cardType} ===');
        for (final entry in parsed.fields.entries) {
          buffer.writeln('${entry.key}: ${entry.value}');
        }
        buffer.writeln('\n--- Encrypted/Decrypted Raw Hex ---');
        buffer.writeln(_formatHexWithBreaks(parsed.rawHex));
      } catch (e) {
        buffer.writeln('⚠️ Could not decrypt data (maybe blank card or unknown key)');
        buffer.writeln('Error: $e');
      }

      setState(() {
        _cardData = buffer.toString();
        _status = 'Read completed';
      });
    } on PlatformException catch (e) {
      setState(() => _status = e.code == "500" ? 'Communication error – hold still' : 'NFC Error: ${e.message}');
    } catch (e) {
      setState(() => _status = 'Error: $e');
    } finally {
      await FlutterNfcKit.finish(iosAlertMessage: "Done");
      setState(() => _isScanning = false);
    }
  }

  String _formatHexWithBreaks(String hex) {
    final buffer = StringBuffer();
    for (int i = 0; i < hex.length; i += 32) {
      final end = (i + 32 < hex.length) ? i + 32 : hex.length;
      buffer.writeln(hex.substring(i, end));
    }
    return buffer.toString().trim();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Read Card')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Card(
              color: Colors.grey[900],
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    const Icon(Icons.nfc, size: 48),
                    const SizedBox(height: 8),
                    Text(_status, textAlign: TextAlign.center),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _isScanning ? null : _readCard,
              icon: const Icon(Icons.sensors),
              label: Text(_isScanning ? 'Scanning...' : 'Scan Card'),
              style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.grey[900], borderRadius: BorderRadius.circular(8)),
                child: SingleChildScrollView(
                  child: SelectableText(
                    _cardData.isEmpty ? 'Tap "Scan Card" to read' : _cardData,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
