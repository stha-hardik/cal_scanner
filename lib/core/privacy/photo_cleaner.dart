import 'dart:io';

/// Meal photos are a one-time shot: they are sent for analysis and only the
/// resulting text (name, calories, macros) is kept. The camera's temporary
/// copy is deleted after 24 hours.
class PhotoCleaner {
  static const maxAge = Duration(hours: 24);

  /// Keeps a temporary copy of a meal photo so it can be re-analysed after
  /// an edit. It is removed automatically after 24 hours. Returns its path,
  /// or null if it could not be copied.
  static Future<String?> keepCopy(File photo, String id) async {
    try {
      final dir = Directory('${Directory.systemTemp.path}/scan_images');
      await dir.create(recursive: true);
      final copy = await photo.copy('${dir.path}/$id.jpg');
      return copy.path;
    } catch (_) {
      return null;
    }
  }

  /// A kept photo, if it still exists and is younger than [maxAge].
  static File? freshPhoto(String? path) {
    if (path == null) return null;
    try {
      final f = File(path);
      if (!f.existsSync()) return null;
      if (f.statSync().modified.isBefore(DateTime.now().subtract(maxAge))) return null;
      return f;
    } catch (_) {
      return null;
    }
  }

  static Future<void> deleteKept(String? path) async {
    if (path == null) return;
    try {
      final f = File(path);
      if (f.existsSync()) await f.delete();
    } catch (_) {}
  }

  /// Deletes temporary photo copies older than [maxAge]
  /// (or all of them when [all] is true). Returns how many were removed.
  static Future<int> purge({bool all = false}) async {
    var removed = 0;
    try {
      final cutoff = DateTime.now().subtract(maxAge);
      await for (final e in Directory.systemTemp.list(followLinks: false)) {
        final name = e.uri.pathSegments.where((s) => s.isNotEmpty).last;
        if (!name.startsWith('image_picker') && name != 'scan_images') continue;
        final modified = (await e.stat()).modified;
        if (all || modified.isBefore(cutoff)) {
          await e.delete(recursive: true);
          removed++;
        } else if (e is Directory) {
          // Folder is recent, but remove old files inside it.
          await for (final f in e.list(recursive: true, followLinks: false)) {
            if (f is File && (await f.stat()).modified.isBefore(cutoff)) {
              await f.delete();
              removed++;
            }
          }
        }
      }
    } catch (_) {
      // Cleanup is best effort.
    }
    return removed;
  }
}
