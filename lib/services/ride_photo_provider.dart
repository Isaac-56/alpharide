import 'package:flutter/material.dart';

final Map<String, ImageProvider<Object>> _ridePhotos =
    <String, ImageProvider<Object>>{};

ImageProvider<Object>? ridePhotoProvider(String? value) {
  if (value == null || value.isEmpty) return null;
  final ImageProvider<Object>? cached = _ridePhotos.remove(value);
  if (cached != null) {
    _ridePhotos[value] = cached;
    return cached;
  }
  try {
    final Uri uri = Uri.parse(value);
    final ImageProvider<Object> source;
    if (uri.scheme == 'data' &&
        uri.data?.mimeType.startsWith('image/') == true) {
      source = MemoryImage(uri.data!.contentAsBytes());
    } else if (uri.scheme == 'https' && uri.host.isNotEmpty) {
      source = NetworkImage(value);
    } else {
      return null;
    }
    // Bound decoded avatar memory for remote photos as well as inline photos.
    final ImageProvider<Object> image = ResizeImage.resizeIfNeeded(256, null, source);
    _ridePhotos[value] = image;
    if (_ridePhotos.length > 4) _ridePhotos.remove(_ridePhotos.keys.first);
    return image;
  } on FormatException {
    return null;
  }
}
