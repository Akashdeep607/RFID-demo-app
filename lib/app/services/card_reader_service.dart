// lib/app/services/card_writer.dart
import 'dart:typed_data';
import 'package:flutter_nfc_kit/flutter_nfc_kit.dart';
import 'package:convert/convert.dart';
import 'package:rfid/app/services/lock_crypto.dart';
import 'package:rfid/app/services/card_parser_service.dart';

final Uint8List TRANSPORT_KEY = Uint8List.fromList([0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF]);

class CardReaderService {
  final Uint8List manufacturerKey;
  final Uint8List lockSecretKey;

  CardReaderService({required this.manufacturerKey, required this.lockSecretKey});

  /// Authenticate a sector by trying multiple keys (derived from both master keys + transport)
  Future<bool> authenticateSector(int sector) async {
    final keysToTry = <Uint8List>[
      LockCrypto.deriveMifareKeyA(manufacturerKey, sector),
      LockCrypto.deriveMifareKeyA(lockSecretKey, sector),
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

  /// Read a full sector (4 blocks) starting from the given block number.
  /// Returns a list of 4 Uint8Lists (each 16 bytes) or null if authentication fails.
  Future<List<Uint8List>?> readSector(int sector, int firstBlock) async {
    bool authOk = await authenticateSector(sector);
    if (!authOk) return null;

    List<Uint8List> blocks = [];
    for (int i = 0; i < 4; i++) {
      int blockNum = firstBlock + i;
      Uint8List block = await FlutterNfcKit.readBlock(blockNum);
      blocks.add(block);
    }
    return blocks;
  }

  /// Read sector 1 (blocks 4,5,6,7) and optionally sector 2 (blocks 8,9,10,11)
  /// Returns parsed card data or throws an exception if decryption fails.
  Future<Map<String, dynamic>> readAndParseCard(String uid) async {
    // Read sector 1 (must succeed)
    List<Uint8List>? sector1Blocks = await readSector(1, 4);
    if (sector1Blocks == null) {
      throw Exception('Sector 1 authentication failed');
    }

    // Combine blocks 4,5,6 (48 bytes)
    final sector1Data = Uint8List(48)
      ..setRange(0, 16, sector1Blocks[0])
      ..setRange(16, 32, sector1Blocks[1])
      ..setRange(32, 48, sector1Blocks[2]);

    Uint8List? sector2Data;
    List<Uint8List>? sector2Blocks = await readSector(2, 8);
    if (sector2Blocks != null) {
      sector2Data = Uint8List(48)
        ..setRange(0, 16, sector2Blocks[0])
        ..setRange(16, 32, sector2Blocks[1])
        ..setRange(32, 48, sector2Blocks[2]);
    }

    // Parse using existing CardParserService
    final parser = CardParserService(manufacturerKey: manufacturerKey, lockSecretKey: lockSecretKey);
    final parsed = parser.parseCard(uidHex: uid, sector1Blocks: sector1Data, sector2Blocks: sector2Data);
    return {
      'cardType': parsed.cardType,
      'fields': parsed.fields,
      'rawHex': parsed.rawHex,
      'trailerBlock': sector1Blocks[3], // block 7
    };
  }
}
