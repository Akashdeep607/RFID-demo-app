import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_nfc_kit/flutter_nfc_kit.dart';
import 'package:intl/intl.dart';
import 'package:convert/convert.dart';
import 'package:rfid/app/services/card_writer_service.dart';
import 'package:rfid/app/services/lock_crypto.dart';

class WriteCardScreen extends StatefulWidget {
  const WriteCardScreen({super.key});

  @override
  State<WriteCardScreen> createState() => _WriteCardScreenState();
}

class _WriteCardScreenState extends State<WriteCardScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _isWriting = false;
  String _status = 'Configure guest card details';

  // ---- Sector 1 fields (main payload) ----
  late DateTime _validFrom;
  late DateTime _validTo;
  final _validFromController = TextEditingController();
  final _validToController = TextEditingController();
  bool _deadboltAccess = false;
  int _groupBitmask = 0;

  // ---- Sector 2 fields (additional guest data) ----
  final _guestNameController = TextEditingController();
  final _roomNumberController = TextEditingController();
  bool _isVIP = false;
  int _accessLevel = 1;

  // Keys (hardcoded for demo – replace with secure storage)
  final Uint8List _manufacturerKey = Uint8List.fromList(hex.decode('00112233445566778899AABBCCDDEEFF'));

  // final Uint8List bleMac = Uint8List.fromList([0x11, 0x22, 0x33, 0x44, 0x55, 0x66]);
  final String bleMac = '14:E9:F0:84:A9:45';

  late Uint8List _lockSecretKey;

  @override
  void initState() {
    super.initState();
    _validFrom = DateTime.now();
    _validTo = DateTime.now().add(const Duration(days: 30));
    _updateDateControllers();
    _lockSecretKey = LockCrypto.deriveLockSecret(_manufacturerKey, bleMac);

    print(
      _lockSecretKey.map((e) => e.toRadixString(16).padLeft(2, '0')).join().toUpperCase(),
    ); //or logs, APIs, manual verification
  }

  void _updateDateControllers() {
    _validFromController.text = DateFormat('yyyy-MM-dd').format(_validFrom);
    _validToController.text = DateFormat('yyyy-MM-dd').format(_validTo);
  }

  Future<void> _selectValidFrom(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _validFrom,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null && picked != _validFrom) {
      setState(() {
        _validFrom = picked;
        if (_validTo.isBefore(_validFrom)) {
          _validTo = _validFrom;
        }
        _updateDateControllers();
      });
    }
  }

  Future<void> _selectValidTo(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _validTo,
      firstDate: _validFrom,
      lastDate: DateTime(2100),
    );
    if (picked != null && picked != _validTo) {
      setState(() {
        _validTo = picked;
        _updateDateControllers();
      });
    }
  }

  @override
  void dispose() {
    _validFromController.dispose();
    _validToController.dispose();
    _guestNameController.dispose();
    _roomNumberController.dispose();
    super.dispose();
  }

  // Build the 18-byte payload for Sector 1
  Uint8List _buildSector1Payload(String uidHex) {
    final uidBytes = Uint8List.fromList(hex.decode(uidHex));
    final payload = ByteData(18);
    int offset = 0;

    // Card type (0x01 = guest)
    payload.setUint8(offset++, 0x01);

    // UID (little-endian, 4 bytes)
    int uidLe = uidBytes.buffer.asByteData().getUint32(0, Endian.little);
    payload.setUint32(offset, uidLe, Endian.little);
    offset += 4;

    // Valid from (Unix timestamp, little-endian)
    payload.setUint32(offset, _validFrom.millisecondsSinceEpoch ~/ 1000, Endian.little);
    offset += 4;

    // Valid to
    payload.setUint32(offset, _validTo.millisecondsSinceEpoch ~/ 1000, Endian.little);
    offset += 4;

    // Deadbolt access
    payload.setUint8(offset++, _deadboltAccess ? 0x01 : 0x00);

    // Group bitmask (16-bit)
    payload.setUint16(offset, _groupBitmask, Endian.little);
    offset += 2;

    // Reserved
    payload.setUint16(offset, 0x0000, Endian.little);

    return payload.buffer.asUint8List();
  }

  // Build the Sector 2 payload (48 bytes)
  Uint8List _buildSector2Payload() {
    final payload = ByteData(48);
    int offset = 0;

    // Guest name (fixed 32 bytes, padded with zeros)
    String name = _guestNameController.text.trim();
    if (name.length > 32) name = name.substring(0, 32);
    final nameBytes = Uint8List.fromList(name.codeUnits);
    for (int i = 0; i < 32; i++) {
      payload.setUint8(offset + i, i < nameBytes.length ? nameBytes[i] : 0);
    }
    offset += 32;

    // Room number (as 32-bit integer, little-endian)
    int room = int.tryParse(_roomNumberController.text) ?? 0;
    payload.setUint32(offset, room, Endian.little);
    offset += 4;

    // VIP flag
    payload.setUint8(offset++, _isVIP ? 1 : 0);

    // Access level
    payload.setUint8(offset++, _accessLevel);

    // Reserved (remaining 10 bytes set to 0)
    for (int i = offset; i < 48; i++) {
      payload.setUint8(i, 0);
    }

    return payload.buffer.asUint8List();
  }

  Future<void> _writeCard() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isWriting = true;
      _status = 'Waiting for card...';
    });

    try {
      final tag = await FlutterNfcKit.poll(timeout: const Duration(seconds: 10), iosAlertMessage: "Hold card to write");
      final uidHex = tag.id.toUpperCase();

      setState(() => _status = 'Building payloads...');

      final sector1Payload = _buildSector1Payload(uidHex);
      final sector2Payload = _buildSector2Payload();

      setState(() => _status = 'Writing to card (Sector 1 & 2)...');

      final writer = CardWriterService(manufacturerKey: _manufacturerKey, lockSecretKey: _lockSecretKey);

      await writer.writeGuestCard(uidHex: uidHex, sector1Data: sector1Payload, sector2Data: sector2Payload);

      setState(() => _status = '✅ Card written successfully!');
    } on PlatformException catch (e) {
      setState(() => _status = 'NFC error: ${e.message}');
    } catch (e) {
      setState(() => _status = 'Write failed: $e');
    } finally {
      await FlutterNfcKit.finish(iosAlertMessage: "Done");
      setState(() => _isWriting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Write Guest Card')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              children: [
                // Status card
                Card(
                  color: Colors.grey[900],
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        const Icon(Icons.edit_note, size: 48),
                        const SizedBox(height: 8),
                        Text(_status, textAlign: TextAlign.center),
                        if (_isWriting) const LinearProgressIndicator(),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // ---- Sector 1 fields ----
                const Text('Sector 1 – Main Credentials', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 8),

                // Valid From (Date Picker)
                GestureDetector(
                  onTap: () => _selectValidFrom(context),
                  child: AbsorbPointer(
                    child: TextFormField(
                      controller: _validFromController,
                      decoration: const InputDecoration(
                        labelText: 'Valid From',
                        labelStyle: TextStyle(color: Colors.orange),

                        border: OutlineInputBorder(),
                        suffixIcon: Icon(Icons.calendar_today),
                      ),
                      validator: (v) => v == null || v.isEmpty ? 'Required' : null,
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Valid To (Date Picker)
                GestureDetector(
                  onTap: () => _selectValidTo(context),
                  child: AbsorbPointer(
                    child: TextFormField(
                      controller: _validToController,
                      decoration: const InputDecoration(
                        labelText: 'Valid To',
                        labelStyle: TextStyle(color: Colors.orange),

                        border: OutlineInputBorder(),
                        suffixIcon: Icon(Icons.calendar_today),
                      ),
                      validator: (v) => v == null || v.isEmpty ? 'Required' : null,
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                SwitchListTile(
                  title: const Text('Deadbolt Access', style: TextStyle(color: Colors.white)),
                  value: _deadboltAccess,
                  onChanged: (val) => setState(() => _deadboltAccess = val),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        initialValue: _groupBitmask.toString(),
                        decoration: const InputDecoration(
                          labelText: 'Group Bitmask (0-65535)',
                          labelStyle: TextStyle(color: Colors.orange),

                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                        onChanged: (val) => _groupBitmask = int.tryParse(val) ?? 0,
                        validator: (v) {
                          if (v == null || v.isEmpty) return null;
                          final val = int.tryParse(v);
                          if (val == null || val < 0 || val > 65535) return 'Enter 0-65535';
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // ---- Sector 2 fields ----
                const Text(
                  'Sector 2 – Additional Information',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _guestNameController,
                  decoration: const InputDecoration(
                    labelText: 'Guest Name (max 32 chars)',
                    labelStyle: TextStyle(color: Colors.orange),

                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _roomNumberController,
                  decoration: const InputDecoration(
                    labelText: 'Room Number',
                    labelStyle: TextStyle(color: Colors.orange),

                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  title: const Text('VIP Guest', style: TextStyle(color: Colors.white)),
                  value: _isVIP,
                  onChanged: (val) => setState(() => _isVIP = val),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        initialValue: _accessLevel.toString(),
                        decoration: const InputDecoration(
                          labelText: 'Access Level (1-255)',
                          labelStyle: TextStyle(color: Colors.orange),
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                        onChanged: (val) => _accessLevel = int.tryParse(val) ?? 1,
                        validator: (v) {
                          final val = int.tryParse(v ?? '');
                          if (val == null || val < 1 || val > 255) return 'Enter 1-255';
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 30),

                // Write button
                ElevatedButton.icon(
                  onPressed: _isWriting ? null : _writeCard,
                  icon: const Icon(Icons.nfc),
                  label: Text(_isWriting ? 'Writing...' : 'Write to Card'),
                  style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
