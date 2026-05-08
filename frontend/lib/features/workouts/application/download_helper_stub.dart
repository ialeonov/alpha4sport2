import 'dart:io';
import 'dart:typed_data';

Future<void> platformSavePng(Uint8List bytes, String filename) async {
  // На Android сохраняем в папку Downloads
  final dir = Directory('/storage/emulated/0/Download');
  if (!dir.existsSync()) dir.createSync(recursive: true);
  final file = File('${dir.path}/$filename');
  await file.writeAsBytes(bytes);
}
