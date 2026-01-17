import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

class VideoCacheService {
  static final VideoCacheService _instance = VideoCacheService._internal();
  factory VideoCacheService() => _instance;
  VideoCacheService._internal();

  final Dio _dio = Dio();
  final Map<String, CancelToken> _activeDownloads = {};
  
  // Track ongoing downloads to prevent duplicates
  final Set<String> _downloadingIds = {};

  Future<Directory> get _cacheDir async {
    final tempDir = await getTemporaryDirectory();
    final dir = Directory('${tempDir.path}/video_cache');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<File?> getCachedVideoFile(String songId) async {
    final dir = await _cacheDir;
    final file = File('${dir.path}/$songId.mp4');
    if (await file.exists()) {
      // Simple check: In a real app we might check file size or integrity
      // For now, if it exists, we assume it's good or at least playable
      return file;
    }
    return null;
  }

  Future<void> startDownload({required String url, required String songId}) async {
    if (_downloadingIds.contains(songId)) return; // Already downloading
    if ((await getCachedVideoFile(songId)) != null) return; // Already cached

    final dir = await _cacheDir;
    final filePath = '${dir.path}/$songId.mp4';
    final tempPath = '${dir.path}/$songId.temp'; // Download to temp first

    final cancelToken = CancelToken();
    _activeDownloads[songId] = cancelToken;
    _downloadingIds.add(songId);

    print("[VideoCache] Starting download for $songId");

    try {
      await _dio.download(
        url,
        tempPath,
        cancelToken: cancelToken,
        onReceiveProgress: (received, total) {
          if (total != -1) {
            // Optional: Notify progress
            // print("[VideoCache] $songId: ${(received / total * 100).toStringAsFixed(0)}%");
          }
        },
      );
      
      // Rename temp to final
      final tempFile = File(tempPath);
      if (await tempFile.exists()) {
        await tempFile.rename(filePath);
        print("[VideoCache] Download complete: $filePath");
      }
    } catch (e) {
      print("[VideoCache] Error downloading $songId: $e");
      // Cleanup temp
      try {
        final tempFile = File(tempPath);
        if (await tempFile.exists()) await tempFile.delete();
      } catch (_) {}
    } finally {
      _activeDownloads.remove(songId);
      _downloadingIds.remove(songId);
    }
  }

  void cancelDownload(String songId) {
    if (_activeDownloads.containsKey(songId)) {
      _activeDownloads[songId]?.cancel();
      _activeDownloads.remove(songId);
      _downloadingIds.remove(songId);
    }
  }

  Future<void> clearCache() async {
    try {
      final dir = await _cacheDir;
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    } catch (e) {
      print("Error clearing cache: $e");
    }
  }
}
