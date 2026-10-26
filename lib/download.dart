// Pobieranie pliku: na webie przez Blob, gdzie indziej – brak (fallback w UI).
export 'download_stub.dart' if (dart.library.js_interop) 'download_web.dart';
