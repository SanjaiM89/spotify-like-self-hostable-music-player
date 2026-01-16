import 'dart:convert';
import 'package:http/http.dart' as http;
import 'models.dart';
import 'constants.dart';

class ApiService {
  static Future<List<Song>> getSongs() async {
    final response = await http.get(Uri.parse('$baseUrl/api/songs'));
    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      return data.map((json) => Song.fromJson(json)).toList();
    } else {
      throw Exception('Failed to load songs');
    }
  }

  static Future<Map<String, dynamic>> getHomepage() async {
    final response = await http.get(Uri.parse('$baseUrl/api/home'));
    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to load homepage');
    }
  }
  
  static Future<void> recordPlay(String songId) async {
    await http.post(Uri.parse('$baseUrl/api/songs/$songId/play'));
  }

  // YouTube
  static Future<String> submitYoutubeUrl(String url, String quality) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/youtube'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'url': url, 'quality': quality}),
    );
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return data['task_id'];
    } else {
      throw Exception('Failed to submit YouTube URL');
    }
  }

  static Future<List<YouTubeTask>> getYoutubeTasks({int page = 1, int limit = 10}) async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/youtube/tasks?page=$page&limit=$limit'),
    );
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final List<dynamic> tasks = data['tasks'];
      return tasks.map((json) => YouTubeTask.fromJson(json)).toList();
    } else {
      throw Exception('Failed to load tasks');
    }
  }

  static Future<void> cancelYoutubeTask(String taskId) async {
    await http.post(Uri.parse('$baseUrl/api/youtube/cancel/$taskId'));
  }
  
  static Future<void> deleteYoutubeTask(String taskId) async {
      await http.delete(Uri.parse('$baseUrl/api/youtube/tasks/$taskId'));
  }
  
  static Future<void> clearAllYoutubeTasks() async {
    await http.delete(Uri.parse('$baseUrl/api/youtube/tasks'));
  }
  
  static Future<void> uploadFiles(List<String> filePaths) async {
    final request = http.MultipartRequest('POST', Uri.parse('$baseUrl/api/upload'));
    for (String path in filePaths) {
      request.files.add(await http.MultipartFile.fromPath('files', path));
    }
    final response = await request.send();
    if (response.statusCode != 200) {
      throw Exception('Failed to upload files');
    }
  }

  // Playlists
  static Future<List<dynamic>> getPlaylists() async {
    final response = await http.get(Uri.parse('$baseUrl/api/playlists'));
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return data['playlists'] ?? [];
    }
    return [];
  }
  
  static Future<String> createPlaylist(String name) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/playlists'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'name': name, 'songs': []}),
    );
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return data['id'] ?? '';
    }
    throw Exception('Failed to create playlist');
  }
  
  static Future<void> addSongToPlaylist(String playlistId, String songId) async {
    await http.post(
      Uri.parse('$baseUrl/api/playlists/$playlistId/songs?song_id=$songId'),
    );
  }
  
  static Future<void> deletePlaylist(String playlistId) async {
    await http.delete(Uri.parse('$baseUrl/api/playlists/$playlistId'));
  }
  
  static Future<void> updateSong(String songId, {String? title, String? artist}) async {
    final body = <String, dynamic>{};
    if (title != null) body['title'] = title;
    if (artist != null) body['artist'] = artist;
    await http.patch(
      Uri.parse('$baseUrl/api/songs/$songId'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode(body),
    );
  }
  
  static Future<void> deleteSong(String songId) async {
    await http.delete(Uri.parse('$baseUrl/api/songs/$songId'));
  }

  static String getStreamUrl(String songId) {
    return '$baseUrl/api/stream/$songId';
  }

  // Like/Dislike
  static Future<void> likeSong(String songId) async {
    await http.post(Uri.parse('$baseUrl/api/songs/$songId/like'));
  }

  static Future<void> dislikeSong(String songId) async {
    await http.post(Uri.parse('$baseUrl/api/songs/$songId/dislike'));
  }

  static Future<bool?> getLikeStatus(String songId) async {
    final response = await http.get(Uri.parse('$baseUrl/api/songs/$songId/like-status'));
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return data['liked']; // true, false, or null
    }
    return null;
  }

  static Future<List<Song>> getRecommendations({int limit = 10}) async {
    final response = await http.get(Uri.parse('$baseUrl/api/recommendations?limit=$limit'));
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final List<dynamic> recs = data['recommendations'] ?? [];
      return recs.map((j) => Song.fromJson(j)).toList();
    }
    return [];
  }

  /// Get LLM-generated upcoming queue based on current song
  static Future<Map<String, dynamic>> getUpcomingQueue(String songId) async {
    final response = await http.get(Uri.parse('$baseUrl/api/upcoming-queue/$songId'));
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final List<dynamic> queue = data['queue'] ?? [];
      final List<String> suggestions = (data['ai_suggestions'] as List<dynamic>?)
          ?.map((e) => e.toString())
          .toList() ?? [];
      return {
        'queue': queue.map((j) => Song.fromJson(j)).toList(),
        'suggestions': suggestions,
      };
    }
    return {'queue': <Song>[], 'suggestions': <String>[]};
  }

  // ==================== Persistent AI Queue ====================

  /// Get persistent AI queue from MongoDB
  static Future<List<Song>> getAIQueue() async {
    final response = await http.get(Uri.parse('$baseUrl/api/ai-queue'));
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final List<dynamic> songs = data['songs'] ?? [];
      return songs.map((j) => Song.fromJson(j)).toList();
    }
    return [];
  }

  /// Refresh AI queue using LLM and save to MongoDB
  static Future<List<Song>> refreshAIQueue() async {
    final response = await http.post(Uri.parse('$baseUrl/api/ai-queue/refresh'));
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final List<dynamic> songs = data['songs'] ?? [];
      return songs.map((j) => Song.fromJson(j)).toList();
    }
    return [];
  }

  /// Mark song as played (removes from queue)
  static Future<void> markSongPlayed(String songId) async {
    await http.post(Uri.parse('$baseUrl/api/ai-queue/mark-played/$songId'));
  }

  /// Send behavior signal (listen, skip, like, dislike)
  static Future<void> sendSignal(String songId, String signalType, {int durationSeconds = 0}) async {
    await http.post(
      Uri.parse('$baseUrl/api/ai-queue/signal/$songId'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'signal_type': signalType,
        'duration_seconds': durationSeconds,
      }),
    );
  }

  // ==================== App Playlists ====================

  /// Get all app playlists
  static Future<List<Playlist>> getAppPlaylists() async {
    final response = await http.get(Uri.parse('$baseUrl/api/app-playlists'));
    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      return data.map((j) => Playlist.fromJson(j)).toList();
    }
    return [];
  }

  /// Get specific playlist with songs
  static Future<Playlist?> getAppPlaylist(String id) async {
    final response = await http.get(Uri.parse('$baseUrl/api/app-playlists/$id'));
    if (response.statusCode == 200) {
      return Playlist.fromJson(json.decode(response.body));
    }
    return null;
  }

  /// Generate new random playlist
  static Future<void> generateAppPlaylist() async {
    await http.post(
      Uri.parse('$baseUrl/api/app-playlists/generate'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'name': 'Discovery Mix'}),
    );
  }

  /// Import App Playlist to User Library
  static Future<bool> importAppPlaylist(String playlistId) async {
    final response = await http.post(Uri.parse('$baseUrl/api/playlists/import-app-playlist/$playlistId'));
    return response.statusCode == 200;
  }
}
