import 'dart:typed_data';

import 'package:flutter/material.dart';

/// Foto de perfil o, sin ella, una silueta genérica teñida con el acento.
class AccountAvatar extends StatelessWidget {
  const AccountAvatar({super.key, this.bytes, this.radius = 40});
  final Uint8List? bytes;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return CircleAvatar(
      radius: radius,
      backgroundColor: accent.withValues(alpha: 0.18),
      backgroundImage: bytes == null ? null : MemoryImage(bytes!),
      child: bytes == null
          ? Icon(Icons.person_rounded, size: radius * 1.2, color: accent)
          : null,
    );
  }
}
