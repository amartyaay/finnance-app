import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

abstract class CsvExportService {
  Future<String> exportCsv({required String fileName, required String csv});
}

class MethodChannelCsvExportService implements CsvExportService {
  const MethodChannelCsvExportService({
    this._channel = const MethodChannel('finnance_app/export'),
  });

  final MethodChannel _channel;

  @override
  Future<String> exportCsv({
    required String fileName,
    required String csv,
  }) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      throw UnsupportedError('CSV export is available on Android only.');
    }

    final uri = await _channel.invokeMethod<String>('exportCsv', {
      'fileName': fileName,
      'csv': csv,
    });
    return uri ?? fileName;
  }
}
