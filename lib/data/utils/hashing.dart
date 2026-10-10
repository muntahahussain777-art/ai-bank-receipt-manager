import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

String sha256Hex(List<int> bytes) => sha256.convert(bytes).toString();

String sha256HexOfString(String value) => sha256Hex(utf8.encode(value));

String sha256HexOfBytes(Uint8List bytes) => sha256Hex(bytes);
