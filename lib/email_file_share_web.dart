import 'dart:js_util' as js;
import 'dart:typed_data';

Future<bool> sharePdfFile(
  List<int> bytes, {
  required String fileName,
  required String subject,
  required String body,
}) {
  try {
    final navigator = js.getProperty(js.globalThis, 'navigator');
    if (!js.hasProperty(navigator, 'share') || !js.hasProperty(navigator, 'canShare')) {
      return Future<bool>.value(false);
    }

    final file = js.callConstructor(
      js.getProperty(js.globalThis, 'File'),
      [
        js.jsify([Uint8List.fromList(bytes)]),
        fileName,
        js.jsify({'type': 'application/pdf'}),
      ],
    );
    final shareData = js.jsify({
      'files': [file],
      'title': subject,
      'text': body,
    });
    final fileData = js.jsify({'files': [file]});
    if (js.callMethod<bool>(navigator, 'canShare', [fileData]) != true) {
      return Future<bool>.value(false);
    }

    final result = js.callMethod<Object?>(navigator, 'share', [shareData]);
    if (result == null) return Future<bool>.value(false);
    return js.promiseToFuture<void>(result).then((_) => true);
  } catch (error, stackTrace) {
    return Future<bool>.error(error, stackTrace);
  }
}
