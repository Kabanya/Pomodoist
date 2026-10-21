import 'dart:io';
import 'dart:typed_data';

/// Restores a standard skinned GLB; compression only affects bundled storage.
Uint8List decodePomoModel(Uint8List compressed) {
  final bytes = Uint8List.fromList(gzip.decode(compressed));
  if (bytes.length < 12) {
    throw const FormatException('Truncated Pomo model');
  }
  final header = ByteData.sublistView(bytes);
  if (header.getUint32(0, Endian.little) != 0x46546c67 ||
      header.getUint32(4, Endian.little) != 2 ||
      header.getUint32(8, Endian.little) != bytes.length) {
    throw const FormatException('Invalid Pomo model');
  }
  return bytes;
}
