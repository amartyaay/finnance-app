import 'package:file_picker/file_picker.dart';

import 'import_parser_service.dart';

abstract class ImportFileService {
  Future<ImportFilePayload?> pickImportFile();
}

class FilePickerImportFileService implements ImportFileService {
  const FilePickerImportFileService();

  @override
  Future<ImportFilePayload?> pickImportFile() async {
    final result = await FilePicker.pickFiles(
      allowMultiple: false,
      type: FileType.custom,
      allowedExtensions: const ['csv', 'pdf', 'png', 'jpg', 'jpeg', 'webp'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) {
      return null;
    }

    final file = result.files.single;
    final bytes = file.bytes;
    if (bytes == null) {
      return null;
    }
    return ImportFilePayload(
      name: file.name,
      bytes: bytes,
    );
  }
}
