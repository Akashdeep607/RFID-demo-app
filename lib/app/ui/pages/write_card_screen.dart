import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_nfc_kit/flutter_nfc_kit.dart';
import 'package:intl/intl.dart';
import 'package:convert/convert.dart';
import 'package:rfid/app/services/card_writer.dart';

class WriteCardScreen extends StatefulWidget {
  const WriteCardScreen({super.key});

  @override
  State<WriteCardScreen> createState() => _WriteCardScreenState();
}

class _WriteCardScreenState extends State<WriteCardScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _isWriting = false;
  String _status = 'Configure card details';

  // Form controllers
  final _validFromController = TextEditingController(text: DateFormat('yyyy-MM-dd').format(DateTime.now()));
  final _validToController = TextEditingController(
    text: DateFormat('yyyy-MM-dd').format(DateTime.now().add(const Duration(days: 30))),
  );
  bool _deadboltAccess = false;
  final int _groupBitmask = 0;

  // Keys (hardcoded for demo – replace with secure storage)
  final Uint8List _manufacturerKey = Uint8List.fromList(hex.decode('00112233445566778899AABBCCDDEEFF'));
  final Uint8List _lockSecretKey = Uint8List.fromList(hex.decode('E8A763CD2BBB99542D5EB1F8A4ADE54C'));

  Future<void> _writeCard() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isWriting = true;
      _status = 'Waiting for card...';
    });

    try {
      // 1. Poll card to get UID
      final tag = await FlutterNfcKit.poll(timeout: const Duration(seconds: 10), iosAlertMessage: "Hold card to write");
      final uidHex = tag.id.toUpperCase();
      final Uint8List uidBytes = Uint8List.fromList(hex.decode(uidHex));

      // 2. Build Guest payload (18 bytes)
      final payload = ByteData(18);
      int offset = 0;
      payload.setUint8(offset++, 0x01); // card type

      // UID (little-endian) – read as little-endian from uidBytes buffer
      int uidLe = uidBytes.buffer.asByteData().getUint32(0, Endian.little);
      payload.setUint32(offset, uidLe, Endian.little);
      offset += 4;

      // Valid from
      final fromDate = DateTime.parse(_validFromController.text);
      payload.setUint32(offset, fromDate.millisecondsSinceEpoch ~/ 1000, Endian.little);
      offset += 4;

      // Valid to
      final toDate = DateTime.parse(_validToController.text);
      payload.setUint32(offset, toDate.millisecondsSinceEpoch ~/ 1000, Endian.little);
      offset += 4;

      // Deadbolt access
      payload.setUint8(offset++, _deadboltAccess ? 0x01 : 0x00);

      // Group bitmask
      payload.setUint16(offset, _groupBitmask, Endian.little);
      offset += 2;

      // Reserved
      payload.setUint16(offset, 0x0000, Endian.little);

      setState(() => _status = 'Writing to card...');

      // 3. Write using CardWriter
      final writer = CardWriter(manufacturerKey: _manufacturerKey, lockSecretKey: _lockSecretKey);
      await writer.writeApplicationCard(cardType: 0x01, payload: payload.buffer.asUint8List(), uidHex: uidHex);

      setState(() => _status = 'Card written successfully!');
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
          child: Column(
            children: [
              // Status Card
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

              // Form fields
              TextFormField(
                controller: _validFromController,
                decoration: const InputDecoration(labelText: 'Valid From (YYYY-MM-DD)', border: OutlineInputBorder()),
                validator: (v) => v == null || v.isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _validToController,
                decoration: const InputDecoration(labelText: 'Valid To (YYYY-MM-DD)', border: OutlineInputBorder()),
                validator: (v) => v == null || v.isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                title: const Text('Deadbolt Access', style: TextStyle(color: Colors.white)),
                value: _deadboltAccess,
                onChanged: (val) => setState(() => _deadboltAccess = val),
                controlAffinity: ListTileControlAffinity.leading,
              ),
              const SizedBox(height: 20),

              // Write Button
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
    );
  }

  @override
  void dispose() {
    _validFromController.dispose();
    _validToController.dispose();
    super.dispose();
  }
}
