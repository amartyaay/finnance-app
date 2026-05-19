import 'package:flutter/services.dart';

import 'import_parser_service.dart';

abstract class ImportFileService {
  Future<ImportFilePayload?> pickImportFile();
}

class NativeImportFileService implements ImportFileService {
  const NativeImportFileService();

  static const _channel = MethodChannel('finnance_app/import_file');

  @override
  Future<ImportFilePayload?> pickImportFile() async {
    final result = await _channel.invokeMapMethod<String, Object?>(
      'pickImportFile',
    );
    if (result == null) {
      return null;
    }

    final name = result['name'] as String? ?? 'import.csv';
    final bytesValue = result['bytes'];
    final bytes = switch (bytesValue) {
      Uint8List value => value,
      List<int> value => Uint8List.fromList(value),
      _ => null,
    };
    if (bytes == null) {
      return null;
    }
    return ImportFilePayload(
      name: name,
      bytes: bytes,
    );
  }
}

class UnsupportedImportFileService implements ImportFileService {
  const UnsupportedImportFileService();

  @override
  Future<ImportFilePayload?> pickImportFile() async {
    throw UnsupportedError('File import is not available on this platform yet.');
  }
}
