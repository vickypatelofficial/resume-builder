import 'dart:typed_data';

import 'resume_pdf_attachment_stub.dart'
    if (dart.library.io) 'resume_pdf_attachment_io.dart' as platform;

Future<String?> writeResumePdfAttachment(Uint8List bytes, String fileName) =>
    platform.writeResumePdfAttachment(bytes, fileName);
