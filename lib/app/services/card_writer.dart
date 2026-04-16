import 'dart:typed_data';
import 'package:flutter_nfc_kit/flutter_nfc_kit.dart';
import 'package:convert/convert.dart';
import 'package:rfid/app/services/lock_crypto.dart';

// Transport key for blank cards
final Uint8List TRANSPORT_KEY = Uint8List.fromList([0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF]);

// Access bits
final Uint8List ACCESS_BITS = Uint8List.fromList([0xFF, 0x07, 0x80, 0x69]);

class CardWriter {
  final Uint8List manufacturerKey;
  final Uint8List lockSecretKey;

  CardWriter({required this.manufacturerKey, required this.lockSecretKey});

  Future<void> writeApplicationCard({required int cardType, required Uint8List payload, required String uidHex}) async {
    print("📱 Writing to UID: $uidHex");

    // 1. Determine AES key
    bool useLockSecret = _cardUsesLockSecret(cardType);
    Uint8List aesKey = useLockSecret ? lockSecretKey : manufacturerKey;
    print("🔑 Using ${useLockSecret ? 'Lock Secret' : 'Manufacturer'} key");

    // 2. Build IV and encrypt payload
    Uint8List iv = LockCrypto.buildCardIV(uidHex);
    Uint8List paddedPayload = LockCrypto.zeroPad(payload);
    int numBlocks = paddedPayload.length ~/ 16;
    Uint8List ciphertext = LockCrypto.aesCbcEncrypt(aesKey, iv, paddedPayload);
    print("🔒 Encrypted ${payload.length} bytes → ${ciphertext.length} bytes ($numBlocks blocks)");

    // 3. Derive Mifare keys
    Uint8List keyaS1 = LockCrypto.deriveMifareKeyA(aesKey, 1);
    Uint8List keyaS2 = LockCrypto.deriveMifareKeyA(aesKey, 2);
    print("🔐 Derived KeyA S1: ${hex.encode(keyaS1).toUpperCase()}");
    print("🔐 Derived KeyA S2: ${hex.encode(keyaS2).toUpperCase()}");

    // 4. Write sector 1
    await _writeSectorData(
      sector: 1,
      derivedKey: keyaS1,
      blocks: ciphertext,
      startBlock: 0,
      maxDataBlocks: 3,
      physicalStartBlock: 4,
    );

    // 5. Write sector 2 if needed
    if (numBlocks > 3) {
      await _writeSectorData(
        sector: 2,
        derivedKey: keyaS2,
        blocks: ciphertext,
        startBlock: 3,
        maxDataBlocks: 3,
        physicalStartBlock: 8,
      );
    }

    print("✅ Card written successfully!");
  }

  // -----------------------------------------------------------------------
  // Write a single sector (data blocks + trailer)
  // -----------------------------------------------------------------------
  Future<void> _writeSectorData({
    required int sector,
    required Uint8List derivedKey,
    required Uint8List blocks,
    required int startBlock,
    required int maxDataBlocks,
    required int physicalStartBlock,
  }) async {
    // Authenticate with fallback
    await _authenticateSectorWithFallback(sector, derivedKey);

    int numBlocksToWrite = ((blocks.length ~/ 16) - startBlock).clamp(0, maxDataBlocks);
    print("📝 Writing $numBlocksToWrite blocks to sector $sector");

    // Write data blocks using plugin's writeBlock
    for (int i = 0; i < numBlocksToWrite; i++) {
      int blockIdx = startBlock + i;
      Uint8List blockData = blocks.sublist(blockIdx * 16, (blockIdx + 1) * 16);
      await FlutterNfcKit.writeBlock(physicalStartBlock + i, blockData);
      print("  ✍️ Block ${physicalStartBlock + i}: ${hex.encode(blockData).toUpperCase()}");
    }

    // Zero-fill remaining data blocks in this sector
    for (int i = numBlocksToWrite; i < maxDataBlocks; i++) {
      await FlutterNfcKit.writeBlock(physicalStartBlock + i, Uint8List(16));
      print("  🧹 Zeroed block ${physicalStartBlock + i}");
    }

    // Write trailer
    int trailerBlock = sector * 4 + 3;
    await _writeSectorTrailerBlock(trailerBlock, derivedKey);
    print("  🔒 Trailer block $trailerBlock written");
  }

  // -----------------------------------------------------------------------
  // Authenticate: try derived key, fallback to transport key
  // -----------------------------------------------------------------------
  Future<void> _authenticateSectorWithFallback(int sector, Uint8List derivedKey) async {
    // Try derived key first
    bool authSuccess = false;
    try {
      authSuccess = await FlutterNfcKit.authenticateSector(sector, keyA: derivedKey);
      if (authSuccess) {
        print("✅ Auth sector $sector with derived key OK");
        return;
      }
    } catch (e) {
      print("⚠️ Derived key exception for sector $sector: $e");
    }

    // Fallback to transport key
    try {
      authSuccess = await FlutterNfcKit.authenticateSector(sector, keyA: TRANSPORT_KEY);
      if (authSuccess) {
        print("✅ Auth sector $sector with transport key OK");
        return;
      }
    } catch (e) {
      print("⚠️ Transport key exception for sector $sector: $e");
    }

    throw Exception("Authentication failed for sector $sector");
  }

  // -----------------------------------------------------------------------
  // Write sector trailer using plugin's writeBlock
  // -----------------------------------------------------------------------
  Future<void> _writeSectorTrailerBlock(int blockNumber, Uint8List newKeyA) async {
    Uint8List trailer = Uint8List(16);
    trailer.setRange(0, 6, newKeyA);
    trailer.setRange(6, 10, ACCESS_BITS);
    trailer.setRange(10, 16, [0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF]); // Key B
    await FlutterNfcKit.writeBlock(blockNumber, trailer);
  }

  bool _cardUsesLockSecret(int cardType) {
    return cardType == 0x01 || cardType == 0x12;
  }
}
