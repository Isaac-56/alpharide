import 'package:flutter/material.dart';

final Map<String, ImageProvider<Object>> _ridePhotos =
    <String, ImageProvider<Object>>{};

ImageProvider<Object>? ridePhotoProvider(String? value) {
  if (value == null || value.isEmpty) return null;
  final ImageProvider<Object>? cached = _ridePhotos[value];
  if (cached != null) return cached;
  try {
    final Uri uri = Uri.parse(value);
    if (uri.scheme == 'data' &&
        uri.data?.mimeType.startsWith('image/') == true) {
      final ImageProvider<Object> image = ResizeImage.resizeIfNeeded(
        256,
        null,
        MemoryImage(uri.data!.contentAsBytes()),
      );
      _ridePhotos[value] = image;
      if (_ridePhotos.length > 4) _ridePhotos.remove(_ridePhotos.keys.first);
      return image;
    }
    if (uri.scheme == 'https') return NetworkImage(value);
  } on FormatException {
    return null;
  }
  return null;
}
