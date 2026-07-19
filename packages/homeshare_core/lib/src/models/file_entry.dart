/// A single file entry inside a transfer manifest.
class FileEntry {
  const FileEntry({
    required this.path,
    required this.size,
    this.sha256,
    this.transferredBytes = 0,
    this.completed = false,
  });

  /// Relative path inside the transfer (POSIX-style separators).
  final String path;
  final int size;
  final String? sha256;
  final int transferredBytes;
  final bool completed;

  FileEntry copyWith({
    String? path,
    int? size,
    String? sha256,
    int? transferredBytes,
    bool? completed,
  }) {
    return FileEntry(
      path: path ?? this.path,
      size: size ?? this.size,
      sha256: sha256 ?? this.sha256,
      transferredBytes: transferredBytes ?? this.transferredBytes,
      completed: completed ?? this.completed,
    );
  }

  Map<String, Object?> toJson() => {
        'path': path,
        'size': size,
        if (sha256 != null) 'sha256': sha256,
        'transferred_bytes': transferredBytes,
        'completed': completed,
      };

  factory FileEntry.fromJson(Map<String, Object?> json) {
    return FileEntry(
      path: json['path']! as String,
      size: (json['size'] as num).toInt(),
      sha256: json['sha256'] as String?,
      transferredBytes: (json['transferred_bytes'] as num?)?.toInt() ?? 0,
      completed: json['completed'] as bool? ?? false,
    );
  }
}
