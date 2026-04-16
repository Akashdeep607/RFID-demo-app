// import 'dart:typed_data';
// import 'package:flutter/material.dart';
// import 'package:flutter/services.dart';
// import 'package:flutter_nfc_kit/flutter_nfc_kit.dart';
// import 'package:convert/convert.dart';
// import 'package:rfid/app/services/lock_crypto.dart';

// // Transport key for blank cards
// final Uint8List TRANSPORT_KEY = Uint8List.fromList([0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF]);

// // Keys (same as used in write screen)
// final Uint8List _manufacturerKey = Uint8List.fromList(hex.decode('00112233445566778899AABBCCDDEEFF'));
// final Uint8List _lockSecretKey = Uint8List.fromList(hex.decode('E8A763CD2BBB99542D5EB1F8A4ADE54C'));

// class ReadCardScreen extends StatefulWidget {
//   const ReadCardScreen({super.key});

//   @override
//   State<ReadCardScreen> createState() => _ReadCardScreenState();
// }

// class _ReadCardScreenState extends State<ReadCardScreen> {
//   String _status = 'Ready to scan';
//   String _cardData = '';
//   bool _isScanning = false;

//   Future<void> _readCard() async {
//     setState(() {
//       _isScanning = true;
//       _status = 'Waiting for card...';
//       _cardData = '';
//     });

//     try {
//       final availability = await FlutterNfcKit.nfcAvailability;
//       if (availability != NFCAvailability.available) {
//         setState(() => _status = 'NFC not available');
//         return;
//       }

//       NFCTag tag = await FlutterNfcKit.poll(
//         timeout: const Duration(seconds: 10),
//         iosMultipleTagMessage: "Multiple cards detected",
//         iosAlertMessage: "Hold your card",
//       );

//       String uid = tag.id.toUpperCase();
//       setState(() => _status = 'Card detected: $uid');

//       // Try to authenticate sector 1 with all possible keys
//       bool auth1 = await _authenticateSectorWithAllKeys(1);
//       if (!auth1) throw Exception('Sector 1 auth failed');

//       // Read sector 1 blocks
//       Uint8List b4 = await FlutterNfcKit.readBlock(4);
//       Uint8List b5 = await FlutterNfcKit.readBlock(5);
//       Uint8List b6 = await FlutterNfcKit.readBlock(6);
//       Uint8List b7 = await FlutterNfcKit.readBlock(7);

//       // Try sector 2
//       String sector2Data = '';
//       bool auth2 = await _authenticateSectorWithAllKeys(2);
//       if (auth2) {
//         Uint8List b8 = await FlutterNfcKit.readBlock(8);
//         Uint8List b9 = await FlutterNfcKit.readBlock(9);
//         Uint8List b10 = await FlutterNfcKit.readBlock(10);
//         Uint8List b11 = await FlutterNfcKit.readBlock(11);
//         sector2Data =
//             '''
// --- Sector 2 ---
// Block 8:  ${hex.encode(b8).toUpperCase()}
// Block 9:  ${hex.encode(b9).toUpperCase()}
// Block 10: ${hex.encode(b10).toUpperCase()}
// Block 11: ${hex.encode(b11).toUpperCase()}
// ''';
//       } else {
//         sector2Data = '\n--- Sector 2 ---\nAuthentication failed';
//       }

//       setState(() {
//         _cardData =
//             '''
// UID: $uid

// --- Sector 1 ---
// Block 4: ${hex.encode(b4).toUpperCase()}
// Block 5: ${hex.encode(b5).toUpperCase()}
// Block 6: ${hex.encode(b6).toUpperCase()}
// Block 7: ${hex.encode(b7).toUpperCase()}
// $sector2Data
// ''';
//         _status = 'Read successful';
//       });
//     } on PlatformException catch (e) {
//       setState(() => _status = e.code == "500" ? 'Communication error – hold still' : 'NFC Error: ${e.message}');
//     } catch (e) {
//       setState(() => _status = 'Error: $e');
//     } finally {
//       await FlutterNfcKit.finish(iosAlertMessage: "Done");
//       setState(() => _isScanning = false);
//     }
//   }

//   /// Try all possible keys for a sector: derived from both AES keys, then transport.
//   Future<bool> _authenticateSectorWithAllKeys(int sector) async {
//     // Derive possible Key A values
//     final keysToTry = <Uint8List>[
//       LockCrypto.deriveMifareKeyA(_manufacturerKey, sector),
//       LockCrypto.deriveMifareKeyA(_lockSecretKey, sector),
//       TRANSPORT_KEY,
//     ];

//     for (final key in keysToTry) {
//       try {
//         bool ok = await FlutterNfcKit.authenticateSector(sector, keyA: key);
//         if (ok) {
//           print("✅ Sector $sector authenticated with key: ${hex.encode(key).toUpperCase()}");
//           return true;
//         }
//       } catch (e) {
//         // Try next key
//       }
//     }
//     return false;
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(title: const Text('Read Card')),
//       body: Padding(
//         padding: const EdgeInsets.all(16),
//         child: Column(
//           children: [
//             Card(
//               color: Colors.grey[900],
//               child: Padding(
//                 padding: const EdgeInsets.all(16),
//                 child: Column(
//                   children: [
//                     const Icon(Icons.nfc, size: 48),
//                     const SizedBox(height: 8),
//                     Text(_status, textAlign: TextAlign.center),
//                   ],
//                 ),
//               ),
//             ),
//             const SizedBox(height: 20),
//             ElevatedButton.icon(
//               onPressed: _isScanning ? null : _readCard,
//               icon: const Icon(Icons.sensors),
//               label: Text(_isScanning ? 'Scanning...' : 'Scan Card'),
//               style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
//             ),
//             const SizedBox(height: 20),
//             Expanded(
//               child: Container(
//                 width: double.infinity,
//                 padding: const EdgeInsets.all(12),
//                 decoration: BoxDecoration(color: Colors.grey[900], borderRadius: BorderRadius.circular(8)),
//                 child: SingleChildScrollView(
//                   child: Text(
//                     _cardData.isEmpty ? 'Tap "Scan Card" to read' : _cardData,
//                     style: const TextStyle(fontFamily: 'monospace'),
//                   ),
//                 ),
//               ),
//             ),
//           ],
//         ),
//       ),
//     );
//   }
// }

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_nfc_kit/flutter_nfc_kit.dart';
import 'package:convert/convert.dart';
import 'package:rfid/app/services/card_parser_service.dart';
import 'package:rfid/app/services/lock_crypto.dart';

final Uint8List TRANSPORT_KEY = Uint8List.fromList([0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF]);

final Uint8List _manufacturerKey = Uint8List.fromList(hex.decode('00112233445566778899AABBCCDDEEFF'));
final Uint8List _lockSecretKey = Uint8List.fromList(hex.decode('E8A763CD2BBB99542D5EB1F8A4ADE54C'));

class ReadCardScreen extends StatefulWidget {
  const ReadCardScreen({super.key});

  @override
  State<ReadCardScreen> createState() => _ReadCardScreenState();
}

class _ReadCardScreenState extends State<ReadCardScreen> {
  String _status = 'Ready to scan';
  String _cardData = '';
  bool _isScanning = false;

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
      setState(() => _status = 'Card detected: $uid\nAuthenticating...');

      // Authenticate sector 1
      bool auth1 = await _authenticateSectorWithAllKeys(1);
      if (!auth1) throw Exception('Sector 1 auth failed');

      // Read sector 1 blocks (4,5,6)
      Uint8List b4 = await FlutterNfcKit.readBlock(4);
      Uint8List b5 = await FlutterNfcKit.readBlock(5);
      Uint8List b6 = await FlutterNfcKit.readBlock(6);
      Uint8List b7 = await FlutterNfcKit.readBlock(7);

      // Combine sector 1 data
      final sector1Data = Uint8List(48)
        ..setRange(0, 16, b4)
        ..setRange(16, 32, b5)
        ..setRange(32, 48, b6);

      // Try sector 2
      Uint8List? sector2Data;
      bool auth2 = await _authenticateSectorWithAllKeys(2);
      if (auth2) {
        Uint8List b8 = await FlutterNfcKit.readBlock(8);
        Uint8List b9 = await FlutterNfcKit.readBlock(9);
        Uint8List b10 = await FlutterNfcKit.readBlock(10);
        sector2Data = Uint8List(48)
          ..setRange(0, 16, b8)
          ..setRange(16, 32, b9)
          ..setRange(32, 48, b10);
      }

      setState(() => _status = 'Decrypting data...');

      // Parse and decrypt
      final parser = CardParserService(manufacturerKey: _manufacturerKey, lockSecretKey: _lockSecretKey);

      String result;
      try {
        final parsed = parser.parseCard(uidHex: uid, sector1Blocks: sector1Data, sector2Blocks: sector2Data);

        // Build display string
        final buffer = StringBuffer();
        buffer.writeln('=== ${parsed.cardType} ===');
        buffer.writeln();
        for (final entry in parsed.fields.entries) {
          buffer.writeln('${entry.key}: ${entry.value}');
        }
        buffer.writeln();
        buffer.writeln('--- Raw Data ---');
        buffer.writeln('UID: $uid');
        buffer.writeln('Sector 1 Trailer: ${hex.encode(b7).toUpperCase()}');
        buffer.writeln();
        buffer.writeln('Raw Hex:');
        buffer.writeln(_formatHexWithBreaks(parsed.rawHex));

        result = buffer.toString();
      } catch (e) {
        // If decryption fails, show raw data
        result =
            '''
⚠️ Could not decrypt (blank or unknown key)

UID: $uid

--- Sector 1 Raw ---
Block 4: ${hex.encode(b4).toUpperCase()}
Block 5: ${hex.encode(b5).toUpperCase()}
Block 6: ${hex.encode(b6).toUpperCase()}
Block 7: ${hex.encode(b7).toUpperCase()}
${sector2Data != null ? '''
--- Sector 2 Raw ---
Block 8: ${hex.encode(sector2Data.sublist(0, 16)).toUpperCase()}
Block 9: ${hex.encode(sector2Data.sublist(16, 32)).toUpperCase()}
Block 10: ${hex.encode(sector2Data.sublist(32, 48)).toUpperCase()}
''' : ''}
''';
      }

      setState(() {
        _cardData = result;
        _status = 'Read successful';
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

  Future<bool> _authenticateSectorWithAllKeys(int sector) async {
    final keysToTry = <Uint8List>[
      LockCrypto.deriveMifareKeyA(_manufacturerKey, sector),
      LockCrypto.deriveMifareKeyA(_lockSecretKey, sector),
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
        // Try next key
      }
    }
    return false;
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
