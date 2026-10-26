import 'dart:convert';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Zapisuje tekst jako plik (UTF-8 z BOM, żeby Excel poprawnie czytał polskie znaki).
bool downloadText(String fileName, String content) {
  final bytes = utf8.encode('﻿$content');
  final blob = web.Blob(
    <JSAny>[bytes.toJS].toJS,
    web.BlobPropertyBag(type: 'text/csv;charset=utf-8'),
  );
  final url = web.URL.createObjectURL(blob);
  final a = web.HTMLAnchorElement()
    ..href = url
    ..download = fileName;
  web.document.body?.appendChild(a);
  a.click();
  a.remove();
  Future<void>.delayed(
      const Duration(seconds: 2), () => web.URL.revokeObjectURL(url));
  return true;
}
