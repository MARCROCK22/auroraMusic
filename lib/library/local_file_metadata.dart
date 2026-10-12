import 'dart:io';

/// Measures only explicitly known library files; never traverses a directory.
Future<Map<String, int>> localFileSizes(Iterable<String> paths) async {
  final sizes = <String, int>{};
  for (final path in paths.where((path) => path.trim().isNotEmpty).toSet()) {
    try {
      final stat = await File(path).stat();
      if (stat.type == FileSystemEntityType.file) sizes[path] = stat.size;
    } on FileSystemException {
      // A missing or inaccessible file remains unmeasured.
    }
  }
  return sizes;
}
