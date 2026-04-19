import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:pointycastle/export.dart';
import 'package:convert/convert.dart';

class LockCrypto {
  // Derive Lock Secret from Manufacturer Key + BLE MAC
  // static Uint8List deriveLockSecret(Uint8List mfgKey, Uint8List bleMac) {
  //   final input = Uint8List(22)
  //     ..setRange(0, 16, mfgKey)
  //     ..setRange(16, 22, bleMac);
  //   final digest = sha256.convert(input);
  //   print("$digest");
  //   return Uint8List.fromList(digest.bytes.sublist(0, 16));
  // }

  static Uint8List deriveLockSecret(Uint8List manufacturerKey, String bleMac) {
    if (manufacturerKey.length != 16) {
      throw ArgumentError('Manufacturer key must be 16 bytes');
    }

    // Step 1: Parse MAC and reverse (little-endian)
    final macBytes = bleMac
        .split(':')
        .map((e) => int.parse(e, radix: 16))
        .toList()
        .reversed
        .toList(); // IMPORTANT: reverse
    if (macBytes.length != 6) {
      throw ArgumentError('Invalid BLE MAC');
    }

    // Step 2: Concatenate ManufacturerKey + MAC
    final input = Uint8List(22)
      ..setRange(0, 16, manufacturerKey)
      ..setRange(16, 22, macBytes);

    // Step 3: SHA-256
    final hash = sha256.convert(input).bytes;

    // Step 4: Take first 16 bytes
    return Uint8List.fromList(hash.sublist(0, 16));
  }

  // Derive Mifare Key A from AES key and sector number
  static Uint8List deriveMifareKeyA(Uint8List aesKey, int sector) {
    final input = Uint8List(17)
      ..setRange(0, 16, aesKey)
      ..[16] = sector;
    final digest = sha256.convert(input);
    return Uint8List.fromList(digest.bytes.sublist(0, 6));
  }

  // Build IV from card UID hex string
  static Uint8List buildCardIV(String uidHex) {
    final uidBytes = Uint8List.fromList(hex.decode(uidHex));
    final iv = Uint8List(16);
    iv.setRange(0, 4, uidBytes);
    return iv; // remaining 12 bytes are zero
  }

  // AES-128-CBC Encrypt (zero padding must be applied before calling)
  static Uint8List aesCbcEncrypt(Uint8List key, Uint8List iv, Uint8List plaintext) {
    final cbc = CBCBlockCipher(AESEngine());
    cbc.init(true, ParametersWithIV(KeyParameter(key), iv));
    final ciphertext = Uint8List(plaintext.length);
    for (int offset = 0; offset < plaintext.length; offset += 16) {
      cbc.processBlock(plaintext, offset, ciphertext, offset);
    }
    return ciphertext;
  }

  // AES-128-CBC Decrypt
  static Uint8List aesCbcDecrypt(Uint8List key, Uint8List iv, Uint8List ciphertext) {
    final cbc = CBCBlockCipher(AESEngine());
    cbc.init(false, ParametersWithIV(KeyParameter(key), iv));
    final plaintext = Uint8List(ciphertext.length);
    for (int offset = 0; offset < ciphertext.length; offset += 16) {
      cbc.processBlock(ciphertext, offset, plaintext, offset);
    }
    return plaintext;
  }

  // Zero pad to 16-byte multiple
  static Uint8List zeroPad(Uint8List data) {
    final paddedLength = ((data.length + 15) ~/ 16) * 16;
    if (paddedLength == data.length) return data;
    final padded = Uint8List(paddedLength);
    padded.setRange(0, data.length, data);
    return padded;
  }
}
