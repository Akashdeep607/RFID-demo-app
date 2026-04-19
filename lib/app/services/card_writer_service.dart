// ignore_for_file: avoid_print

import 'dart:typed_data';
import 'package:flutter_nfc_kit/flutter_nfc_kit.dart';
import 'package:convert/convert.dart';
import 'package:rfid/app/services/lock_crypto.dart';

// Transport key for blank cards
final Uint8List TRANSPORT_KEY = Uint8List.fromList([0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF]);

// Access bits
final Uint8List ACCESS_BITS = Uint8List.fromList([0xFF, 0x07, 0x80, 0x69]);

class CardWriterService {
  final Uint8List manufacturerKey;
  final Uint8List lockSecretKey;

  CardWriterService({required this.manufacturerKey, required this.lockSecretKey});

  // -----------------------------------------------------------------------
  // NEW: Write a guest card (two independent sectors)
  // -----------------------------------------------------------------------
  Future<void> writeGuestCard({
    required String uidHex,
    required Uint8List sector1Data, // plaintext, up to 48 bytes
    required Uint8List sector2Data, // plaintext, up to 48 bytes
  }) async {
    print("📱 Writing guest card to UID: $uidHex");

    // Guest card uses the lock secret key
    Uint8List aesKey = lockSecretKey;
    Uint8List iv = LockCrypto.buildCardIV(uidHex);

    // Pad both payloads to exactly 48 bytes (3 blocks)
    Uint8List paddedSector1 = _padTo48(sector1Data);
    Uint8List paddedSector2 = _padTo48(sector2Data);

    // Encrypt both payloads (AES‑CBC)
    Uint8List ciphertext1 = LockCrypto.aesCbcEncrypt(aesKey, iv, paddedSector1);
    Uint8List ciphertext2 = LockCrypto.aesCbcEncrypt(aesKey, iv, paddedSector2);

    print("🔒 Encrypted Sector 1 (48 bytes): ${hex.encode(ciphertext1)}");
    print("🔒 Encrypted Sector 2 (48 bytes): ${hex.encode(ciphertext2)}");

    // Derive Mifare Key A for sectors 1 and 2
    Uint8List keyA1 = LockCrypto.deriveMifareKeyA(aesKey, 0x01);
    Uint8List keyA2 = LockCrypto.deriveMifareKeyA(aesKey, 0x02);
    // Write Sector 1 (blocks 4,5,6 + trailer block 7)
    await _writeSingleSector(sector: 1, derivedKey: keyA1, ciphertext: ciphertext1, physicalStartBlock: 4);

    // Write Sector 2 (blocks 8,9,10 + trailer block 11)
    await _writeSingleSector(sector: 2, derivedKey: keyA2, ciphertext: ciphertext2, physicalStartBlock: 8);

    print("✅ Guest card written successfully!");
  }

  // -----------------------------------------------------------------------
  // Original method (writes a single payload that may span sectors)
  // -----------------------------------------------------------------------
  Future<void> writeApplicationCard({required int cardType, required Uint8List payload, required String uidHex}) async {
    print("📱 Writing to UID: $uidHex");

    bool useLockSecret = _cardUsesLockSecret(cardType);
    Uint8List aesKey = useLockSecret ? lockSecretKey : manufacturerKey;
    print("🔑 Using ${useLockSecret ? 'Lock Secret' : 'Manufacturer'} key");

    Uint8List iv = LockCrypto.buildCardIV(uidHex);
    Uint8List paddedPayload = LockCrypto.zeroPad(payload);
    int numBlocks = paddedPayload.length ~/ 16;
    Uint8List ciphertext = LockCrypto.aesCbcEncrypt(aesKey, iv, paddedPayload);
    print("🔒 Encrypted ${payload.length} bytes → ${ciphertext.length} bytes ($numBlocks blocks)");

    Uint8List keyaS1 = LockCrypto.deriveMifareKeyA(aesKey, 1);
    Uint8List keyaS2 = LockCrypto.deriveMifareKeyA(aesKey, 2);
    print("🔐 Derived KeyA S1: ${hex.encode(keyaS1).toUpperCase()}");
    print("🔐 Derived KeyA S2: ${hex.encode(keyaS2).toUpperCase()}");

    // Write sector 1
    await _writeSectorData(
      sector: 1,
      derivedKey: keyaS1,
      blocks: ciphertext,
      startBlock: 0,
      maxDataBlocks: 3,
      physicalStartBlock: 4,
    );

    // Write sector 2 if needed
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
  // Helper: pad a Uint8List to exactly 48 bytes with zeros
  // -----------------------------------------------------------------------
  Uint8List _padTo48(Uint8List data) {
    if (data.length >= 48) return data.sublist(0, 48);
    final padded = Uint8List(48);
    padded.setRange(0, data.length, data);
    return padded;
  }

  // -----------------------------------------------------------------------
  // Write a single sector's 3 data blocks + trailer
  // -----------------------------------------------------------------------
  Future<void> _writeSingleSector({
    required int sector,
    required Uint8List derivedKey,
    required Uint8List ciphertext, // must be exactly 48 bytes
    required int physicalStartBlock,
  }) async {
    if (ciphertext.length != 48) {
      throw Exception("Ciphertext must be exactly 48 bytes for a single sector");
    }

    // Authenticate
    await _authenticateSectorWithFallback(sector, derivedKey);

    // Write the 3 data blocks
    for (int i = 0; i < 3; i++) {
      int blockNum = physicalStartBlock + i;
      Uint8List blockData = ciphertext.sublist(i * 16, (i + 1) * 16);
      await FlutterNfcKit.writeBlock(blockNum, blockData);
      print("  ✍️ Block $blockNum: ${hex.encode(blockData).toUpperCase()}");
    }

    // Write trailer block
    int trailerBlock = sector * 4 + 3;
    await _writeSectorTrailerBlock(trailerBlock, derivedKey);
    print("  🔒 Trailer block $trailerBlock written");
  }

  // -----------------------------------------------------------------------
  // Legacy helper (kept for writeApplicationCard)
  // -----------------------------------------------------------------------
  Future<void> _writeSectorData({
    required int sector,
    required Uint8List derivedKey,
    required Uint8List blocks,
    required int startBlock,
    required int maxDataBlocks,
    required int physicalStartBlock,
  }) async {
    await _authenticateSectorWithFallback(sector, derivedKey);

    int numBlocksToWrite = ((blocks.length ~/ 16) - startBlock).clamp(0, maxDataBlocks);
    print("📝 Writing $numBlocksToWrite blocks to sector $sector");

    for (int i = 0; i < numBlocksToWrite; i++) {
      int blockIdx = startBlock + i;
      Uint8List blockData = blocks.sublist(blockIdx * 16, (blockIdx + 1) * 16);
      await FlutterNfcKit.writeBlock(physicalStartBlock + i, blockData);
      print("  ✍️ Block ${physicalStartBlock + i}: ${hex.encode(blockData).toUpperCase()}");
    }

    for (int i = numBlocksToWrite; i < maxDataBlocks; i++) {
      await FlutterNfcKit.writeBlock(physicalStartBlock + i, Uint8List(16));
      print("  🧹 Zeroed block ${physicalStartBlock + i}");
    }

    int trailerBlock = sector * 4 + 3;
    await _writeSectorTrailerBlock(trailerBlock, derivedKey);
    print("  🔒 Trailer block $trailerBlock written");
  }

  // -----------------------------------------------------------------------
  // Authenticate with fallback to transport key
  // -----------------------------------------------------------------------
  Future<void> _authenticateSectorWithFallback(int sector, Uint8List derivedKey) async {
    bool authSuccess = false;
    try {
      authSuccess = await FlutterNfcKit.authenticateSector(sector, keyA: derivedKey);
      if (authSuccess) {
        print("✅ Auth sector $sector with ${hex.encode(derivedKey)} derived key OK");
        return;
      }
    } catch (e) {
      print("⚠️ Derived key exception for sector $sector: $e");
    }

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
  // Write sector trailer block (Key A, access bits, Key B)
  // -----------------------------------------------------------------------
  Future<void> _writeSectorTrailerBlock(int blockNumber, Uint8List newKeyA) async {
    Uint8List trailer = Uint8List(16);
    trailer.setRange(0, 6, newKeyA);
    trailer.setRange(6, 10, ACCESS_BITS);
    trailer.setRange(10, 16, [0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF]); // Key B
    // print("S$blockNumber KeyA - ${hex.encode(newKeyA)} || S$blockNumber KeyA - ${hex.encode(newKeyA)}");
    await FlutterNfcKit.writeBlock(blockNumber, trailer);
  }

  bool _cardUsesLockSecret(int cardType) {
    return cardType == 0x01 || cardType == 0x12;
  }
}
