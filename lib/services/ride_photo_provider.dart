import 'package:flutter/material.dart';

ImageProvider<Object>? ridePhotoProvider(String? value) {
  if (value == null || value.isEmpty) return null;
  try {
    final Uri uri = Uri.parse(value);
    if (uri.scheme == 'data' &&
        uri.data?.mimeType.startsWith('image/') == true) {
      return MemoryImage(uri.data!.contentAsBytes());
    }
    if (uri.scheme == 'https') return NetworkImage(value);
  } on FormatException {
    return null;
  }
  return null;
}
