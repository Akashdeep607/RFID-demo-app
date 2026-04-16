import 'dart:typed_data';
import 'package:convert/convert.dart';
import 'lock_crypto.dart';

class CardParserService {
  final Uint8List manufacturerKey;
  final Uint8List lockSecretKey;

  CardParserService({required this.manufacturerKey, required this.lockSecretKey});

  /// Parse a card from raw sector data
  ParsedCard parseCard({
    required String uidHex,
    required Uint8List sector1Blocks, // 48 bytes (blocks 4,5,6)
    Uint8List? sector2Blocks, // Optional 48 bytes (blocks 8,9,10)
  }) {
    // Determine which AES key to try
    // We try both and see which decrypts to a valid card type
    final keysToTry = [manufacturerKey, lockSecretKey];

    for (final aesKey in keysToTry) {
      try {
        // Build IV from UID
        final iv = LockCrypto.buildCardIV(uidHex);

        // Combine all available ciphertext
        final ciphertextBytes = <int>[...sector1Blocks];
        if (sector2Blocks != null) {
          ciphertextBytes.addAll(sector2Blocks);
        }

        // Decrypt
        final ciphertext = Uint8List.fromList(ciphertextBytes);
        final plaintext = LockCrypto.aesCbcDecrypt(aesKey, iv, ciphertext);

        // Check card type (first byte)
        final cardType = plaintext[0];
        if (cardType >= 0x01 && cardType <= 0x14) {
          return _parseByType(cardType, plaintext, uidHex);
        }
      } catch (e) {
        // Try next key
      }
    }

    throw Exception('Could not decrypt card with any known key');
  }

  ParsedCard _parseByType(int cardType, Uint8List plaintext, String uidHex) {
    final data = ByteData.sublistView(plaintext);

    switch (cardType) {
      case 0x01:
        return _parseGuestCard(data, uidHex);
      case 0x02:
        return _parseStaffCard(data, uidHex, isMaster: false);
      case 0x03:
        return _parseStaffCard(data, uidHex, isMaster: true);
      case 0x04:
        return _parseEmergencyCard(data, uidHex);
      case 0x10:
        return _parseProgrammingCard(data, uidHex);
      case 0x11:
        return _parseConfigGetCard(data, uidHex);
      case 0x12:
        return _parseLogCard(data, uidHex);
      case 0x13:
        return _parseBlockCard(data, uidHex);
      case 0x14:
        return _parseResetCard(data, uidHex);
      default:
        return ParsedCard(
          cardType: 'Unknown (0x${cardType.toRadixString(16).toUpperCase()})',
          rawHex: hex.encode(plaintext).toUpperCase(),
        );
    }
  }

  // -----------------------------------------------------------------------
  // Guest Card (0x01)
  // -----------------------------------------------------------------------
  ParsedCard _parseGuestCard(ByteData data, String uidHex) {
    int offset = 0;
    final cardType = data.getUint8(offset++);
    final storedUid = _formatUid(data.getUint32(offset, Endian.little));
    offset += 4;
    final validFrom = _formatTimestamp(data.getUint32(offset, Endian.little));
    offset += 4;
    final validTo = _formatTimestamp(data.getUint32(offset, Endian.little));
    offset += 4;
    final deadboltAccess = data.getUint8(offset++) == 0x01 ? 'Allowed' : 'Denied';
    final groupBitmask = data.getUint16(offset, Endian.little).toRadixString(16).padLeft(4, '0').toUpperCase();
    offset += 2;
    final reserved = data.getUint16(offset, Endian.little);

    return ParsedCard(
      cardType: 'Guest (0x01)',
      fields: {
        'Card UID': uidHex,
        'Stored UID': storedUid,
        'Valid From': validFrom,
        'Valid To': validTo,
        'Deadbolt Access': deadboltAccess,
        'Group Bitmask': '0x$groupBitmask',
        'Reserved': '0x${reserved.toRadixString(4).padLeft(4, '0')}',
      },
      rawHex: _formatHex(data),
    );
  }

  // -----------------------------------------------------------------------
  // Staff / Master Card (0x02 / 0x03)
  // -----------------------------------------------------------------------
  ParsedCard _parseStaffCard(ByteData data, String uidHex, {required bool isMaster}) {
    int offset = 0;
    final cardType = data.getUint8(offset++);
    final storedUid = _formatUid(data.getUint32(offset, Endian.little));
    offset += 4;
    final validFrom = _formatTimestamp(data.getUint32(offset, Endian.little));
    offset += 4;
    final validTo = _formatTimestamp(data.getUint32(offset, Endian.little));
    offset += 4;
    final buildingBitmask = data.getUint32(offset, Endian.little);
    offset += 4;
    final floorHeader = data.getUint8(offset++);

    // Parse floor ranges
    final allFloors = (floorHeader & 0x80) != 0;
    final numRanges = floorHeader & 0x07;
    final floorRanges = <String>[];
    for (int i = 0; i < 4; i++) {
      final from = data.getInt16(offset, Endian.little);
      offset += 2;
      final to = data.getInt16(offset, Endian.little);
      offset += 2;
      if (i < numRanges) {
        floorRanges.add('$from to $to');
      }
    }

    final groupBitmask = data.getUint16(offset, Endian.little);
    offset += 2;
    final timeStartHour = data.getUint8(offset++);
    final timeStartMin = data.getUint8(offset++);
    final timeEndHour = data.getUint8(offset++);
    final timeEndMin = data.getUint8(offset++);
    final deadboltAccess = data.getUint8(offset++) == 0x01 ? 'Allowed' : 'Denied';
    final reserved = data.getUint16(offset, Endian.little);

    final timeRestriction = (timeStartHour == 0xFF)
        ? 'None'
        : '${timeStartHour.toString().padLeft(2, '0')}:${timeStartMin.toString().padLeft(2, '0')} - ${timeEndHour.toString().padLeft(2, '0')}:${timeEndMin.toString().padLeft(2, '0')}';

    return ParsedCard(
      cardType: isMaster ? 'Master (0x03)' : 'Staff (0x02)',
      fields: {
        'Card UID': uidHex,
        'Stored UID': storedUid,
        'Valid From': validFrom,
        'Valid To': validTo,
        'Building Bitmask': '0x${buildingBitmask.toRadixString(8).padLeft(8, '0').toUpperCase()}',
        'All Floors': allFloors ? 'Yes' : 'No',
        'Floor Ranges': floorRanges.isEmpty ? 'None' : floorRanges.join(', '),
        'Group Bitmask': '0x${groupBitmask.toRadixString(4).padLeft(4, '0').toUpperCase()}',
        'Time Restriction': timeRestriction,
        'Deadbolt Access': deadboltAccess,
        'Reserved': '0x${reserved.toRadixString(4).padLeft(4, '0')}',
      },
      rawHex: _formatHex(data),
    );
  }

  // -----------------------------------------------------------------------
  // Emergency Card (0x04)
  // -----------------------------------------------------------------------
  ParsedCard _parseEmergencyCard(ByteData data, String uidHex) {
    int offset = 0;
    final cardType = data.getUint8(offset++);
    final storedUid = _formatUid(data.getUint32(offset, Endian.little));
    offset += 4;
    final propertyId = data.getUint16(offset, Endian.little);
    offset += 2;
    final validFrom = _formatTimestamp(data.getUint32(offset, Endian.little));
    offset += 4;
    final reserved = data.getUint32(offset, Endian.little);

    return ParsedCard(
      cardType: 'Emergency (0x04)',
      fields: {
        'Card UID': uidHex,
        'Stored UID': storedUid,
        'Property ID': propertyId.toString(),
        'Valid From': validFrom,
        'Valid For': '24 hours',
        'Reserved': '0x${reserved.toRadixString(8).padLeft(8, '0')}',
      },
      rawHex: _formatHex(data),
    );
  }

  // -----------------------------------------------------------------------
  // Programming Card (0x10)
  // -----------------------------------------------------------------------
  ParsedCard _parseProgrammingCard(ByteData data, String uidHex) {
    int offset = 0;
    final cardType = data.getUint8(offset++);
    final storedUid = _formatUid(data.getUint32(offset, Endian.little));
    offset += 4;
    final propertyId = data.getUint16(offset, Endian.little);
    offset += 2;
    final buildingId = data.getUint8(offset++);
    final floorNumber = data.getInt16(offset, Endian.little);
    offset += 2;
    final utcDateTime = _formatTimestamp(data.getUint32(offset, Endian.little));
    offset += 4;
    final lockType = data.getUint8(offset++) == 0x00 ? 'Room' : 'Common Area';
    final groupId = data.getUint8(offset++);
    final btEnable = data.getUint8(offset++) == 0x01 ? 'Enabled' : 'Disabled';
    final deadboltEnable = data.getUint8(offset++) == 0x01 ? 'Enabled' : 'Disabled';

    // Manufacturer Key (16 bytes)
    final mfgKeyBytes = Uint8List(16);
    for (int i = 0; i < 16; i++) {
      mfgKeyBytes[i] = data.getUint8(offset++);
    }
    final manufacturerKey = hex.encode(mfgKeyBytes).toUpperCase();

    // Lock Secret Key (16 bytes)
    final lsKeyBytes = Uint8List(16);
    for (int i = 0; i < 16; i++) {
      lsKeyBytes[i] = data.getUint8(offset++);
    }
    final lockSecretKey = hex.encode(lsKeyBytes).toUpperCase();
    final lockSecretSource = lsKeyBytes.every((b) => b == 0) ? 'Derived from BLE MAC' : 'Explicitly set';

    final validFrom = _formatTimestamp(data.getUint32(offset, Endian.little));
    offset += 4;
    final validTo = _formatTimestamp(data.getUint32(offset, Endian.little));
    offset += 4;
    final batteryInterval = data.getUint8(offset++);

    return ParsedCard(
      cardType: 'Programming (0x10)',
      fields: {
        'Card UID': uidHex,
        'Stored UID': storedUid,
        'Property ID': propertyId.toString(),
        'Building ID': buildingId.toString(),
        'Floor Number': floorNumber.toString(),
        'Set Clock To': utcDateTime,
        'Lock Type': lockType,
        'Group ID': groupId.toString(),
        'Bluetooth': btEnable,
        'Deadbolt': deadboltEnable,
        'Manufacturer Key': manufacturerKey,
        'Lock Secret Key': '$lockSecretKey ($lockSecretSource)',
        'Valid From': validFrom,
        'Valid To': validTo,
        'Battery Report Interval': batteryInterval == 0 ? 'Never' : '$batteryInterval hours',
      },
      rawHex: _formatHex(data),
    );
  }

  // -----------------------------------------------------------------------
  // Config-Get Card (0x11)
  // -----------------------------------------------------------------------
  ParsedCard _parseConfigGetCard(ByteData data, String uidHex) {
    int offset = 0;
    final cardType = data.getUint8(offset++);
    final storedUid = _formatUid(data.getUint32(offset, Endian.little));
    offset += 4;
    final propertyId = data.getUint16(offset, Endian.little);
    offset += 2;
    final validFrom = _formatTimestamp(data.getUint32(offset, Endian.little));
    offset += 4;
    final validTo = _formatTimestamp(data.getUint32(offset, Endian.little));
    offset += 4;

    return ParsedCard(
      cardType: 'Config-Get (0x11)',
      fields: {
        'Card UID': uidHex,
        'Stored UID': storedUid,
        'Property ID': propertyId.toString(),
        'Valid From': validFrom,
        'Valid To': validTo,
      },
      rawHex: _formatHex(data),
    );
  }

  // -----------------------------------------------------------------------
  // Log Card (0x12)
  // -----------------------------------------------------------------------
  ParsedCard _parseLogCard(ByteData data, String uidHex) {
    int offset = 0;
    final cardType = data.getUint8(offset++);
    final storedUid = _formatUid(data.getUint32(offset, Endian.little));
    offset += 4;
    final validFrom = _formatTimestamp(data.getUint32(offset, Endian.little));
    offset += 4;
    final validTo = _formatTimestamp(data.getUint32(offset, Endian.little));
    offset += 4;

    return ParsedCard(
      cardType: 'Log (0x12)',
      fields: {
        'Card UID': uidHex,
        'Stored UID': storedUid,
        'Valid From': validFrom,
        'Valid To': validTo,
        'Note': 'When tapped on lock, this card will collect up to 42 transaction log records.',
      },
      rawHex: _formatHex(data),
    );
  }

  // -----------------------------------------------------------------------
  // Block Card (0x13)
  // -----------------------------------------------------------------------
  ParsedCard _parseBlockCard(ByteData data, String uidHex) {
    int offset = 0;
    final cardType = data.getUint8(offset++);
    final storedUid = _formatUid(data.getUint32(offset, Endian.little));
    offset += 4;
    final propertyId = data.getUint16(offset, Endian.little);
    offset += 2;
    final validFrom = _formatTimestamp(data.getUint32(offset, Endian.little));
    offset += 4;
    final validTo = _formatTimestamp(data.getUint32(offset, Endian.little));
    offset += 4;
    final action = data.getUint8(offset++);
    final count = data.getUint8(offset++);

    final actionName = action == 0x01
        ? 'Add'
        : action == 0x02
        ? 'Remove'
        : 'Clear All';
    final blockedUids = <String>[];
    for (int i = 0; i < count; i++) {
      blockedUids.add(_formatUid(data.getUint32(offset, Endian.little)));
      offset += 4;
    }

    return ParsedCard(
      cardType: 'Block (0x13)',
      fields: {
        'Card UID': uidHex,
        'Stored UID': storedUid,
        'Property ID': propertyId.toString(),
        'Valid From': validFrom,
        'Valid To': validTo,
        'Action': actionName,
        'Count': count.toString(),
        'Blocked UIDs': blockedUids.isEmpty ? 'None' : blockedUids.join(', '),
      },
      rawHex: _formatHex(data),
    );
  }

  // -----------------------------------------------------------------------
  // Reset Card (0x14)
  // -----------------------------------------------------------------------
  ParsedCard _parseResetCard(ByteData data, String uidHex) {
    int offset = 0;
    final cardType = data.getUint8(offset++);
    final storedUid = _formatUid(data.getUint32(offset, Endian.little));
    offset += 4;
    final propertyId = data.getUint16(offset, Endian.little);
    offset += 2;
    final validFrom = _formatTimestamp(data.getUint32(offset, Endian.little));
    offset += 4;
    final validTo = _formatTimestamp(data.getUint32(offset, Endian.little));
    offset += 4;

    return ParsedCard(
      cardType: 'Reset (0x14)',
      fields: {
        'Card UID': uidHex,
        'Stored UID': storedUid,
        'Property ID': propertyId.toString(),
        'Valid From': validFrom,
        'Valid To': validTo,
        'Warning': 'This card will factory reset the lock!',
      },
      rawHex: _formatHex(data),
    );
  }

  // -----------------------------------------------------------------------
  // Helper Functions
  // -----------------------------------------------------------------------
  String _formatUid(int uid) {
    final bytes = Uint8List(4);
    bytes.buffer.asByteData().setUint32(0, uid, Endian.little);
    return hex.encode(bytes).toUpperCase();
  }

  String _formatTimestamp(int timestamp) {
    if (timestamp == 0) return 'Not set';
    final dt = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000, isUtc: true);
    return '${dt.toLocal()}'.substring(0, 19);
  }

  String _formatHex(ByteData data) {
    final bytes = Uint8List.view(data.buffer, 0, data.lengthInBytes);
    return hex.encode(bytes).toUpperCase();
  }
}

/// Container for parsed card data
class ParsedCard {
  final String cardType;
  final Map<String, String> fields;
  final String rawHex;

  ParsedCard({required this.cardType, this.fields = const {}, required this.rawHex});

  @override
  String toString() {
    final buffer = StringBuffer();
    buffer.writeln('=== $cardType ===');
    for (final entry in fields.entries) {
      buffer.writeln('${entry.key}: ${entry.value}');
    }
    buffer.writeln('\nRaw Hex: $rawHex');
    return buffer.toString();
  }
}
