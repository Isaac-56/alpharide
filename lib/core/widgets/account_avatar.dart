import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';

/// Loads a private account photo once per path/version, without signed URLs.
class AccountAvatar extends StatefulWidget {
  const AccountAvatar({
    this.photo = '',
    this.radius = 28,
    this.loadBytes,
    super.key,
  });

  final String photo;
  final double radius;
  final Future<Uint8List?> Function(String)? loadBytes;

  @override
  State<AccountAvatar> createState() => _AccountAvatarState();
}

class _AccountAvatarState extends State<AccountAvatar> {
  Future<Uint8List?>? _bytes;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant AccountAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.photo != widget.photo ||
        oldWidget.loadBytes != widget.loadBytes) {
      _load();
    }
  }

  void _load() {
    _bytes = widget.photo.trim().isEmpty ? null : _read();
  }

  Future<Uint8List?> _read() async {
    final String photo = widget.photo.trim();
    if (widget.loadBytes != null) return widget.loadBytes!(photo);
    final Reference ref =
        photo.startsWith('https://') || photo.startsWith('gs://')
        ? FirebaseStorage.instance.refFromURL(photo)
        : FirebaseStorage.instance.ref(photo);
    return ref.getData(6 * 1024 * 1024);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List?>(
    future: _bytes,
    builder: (BuildContext context, AsyncSnapshot<Uint8List?> snapshot) {
      final Uint8List? bytes = snapshot.data;
      final ImageProvider<Object>? image = bytes == null || bytes.isEmpty
          ? null
          : ResizeImage.resizeIfNeeded(256, null, MemoryImage(bytes));
      return GestureDetector(
        onTap: snapshot.hasError ? () => setState(_load) : null,
        child: CircleAvatar(
          radius: widget.radius,
          foregroundImage: image,
          onForegroundImageError: image == null
              ? null
              : (Object error, StackTrace? stack) {},
          child: const Icon(Icons.person_rounded),
        ),
      );
    },
  );
}
