class Song {
  final String id;
  final String title;
  final String artist;
  final String album;
  final double duration;
  final String? coverArt;
  final String? thumbnail;
  final String fileName;
  final String? mediaType; // 'audio' or 'video'
  final String? audioTelegramId;
  final String? videoTelegramId;
  final bool hasVideo;

  Song({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.duration,
    this.coverArt,
    this.thumbnail,
    required this.fileName,
    this.mediaType,
    this.audioTelegramId,
    this.videoTelegramId,
    this.hasVideo = false,
  });

  bool get isVideo => mediaType == 'video' || 
    fileName.toLowerCase().endsWith('.mp4') ||
    fileName.toLowerCase().endsWith('.mkv') ||
    fileName.toLowerCase().endsWith('.webm');

  factory Song.fromJson(Map<String, dynamic> json) {
    return Song(
      id: json['id'] ?? '',
      title: json['title'] ?? 'Unknown Title',
      artist: json['artist'] ?? 'Unknown Artist',
      album: json['album'] ?? '',
      duration: (json['duration'] ?? 0).toDouble(),
      coverArt: json['cover_art'],
      thumbnail: json['thumbnail'],
      fileName: json['file_name'] ?? '',
      mediaType: json['media_type'],
      audioTelegramId: json['audio_telegram_id'],
      videoTelegramId: json['video_telegram_id'],
      hasVideo: json['has_video'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'artist': artist,
      'album': album,
      'duration': duration,
      'cover_art': coverArt,
      'thumbnail': thumbnail,
      'file_name': fileName,
      'media_type': mediaType,
      'audio_telegram_id': audioTelegramId,
      'video_telegram_id': videoTelegramId,
      'has_video': hasVideo,
    };
  }
}


class YouTubeTask {
  final String taskId;
  final String url;
  final String status;
  final double progress;
  final String? title;
  final String? error;
  final Map<String, dynamic>? uploadInfo;
  final String? speed;
  final String? eta;
  final int? totalBytes;
  final int? downloadedBytes;
  final String? songId;
  final String? mediaType; // 'audio' or 'video'
  final String? quality;

  YouTubeTask({
    required this.taskId,
    required this.url,
    required this.status,
    required this.progress,
    this.title,
    this.error,
    this.uploadInfo,
    this.speed,
    this.eta,
    this.totalBytes,
    this.downloadedBytes,
    this.songId,
    this.mediaType,
    this.quality,
  });

  factory YouTubeTask.fromJson(Map<String, dynamic> json) {
    return YouTubeTask(
      taskId: json['task_id'],
      url: json['url'],
      status: json['status'],
      progress: (json['progress'] ?? 0).toDouble(),
      title: json['title'],
      error: json['error'],
      uploadInfo: json['upload_info'],
      speed: json['speed'],
      eta: json['eta'],
      totalBytes: json['total'],
      downloadedBytes: json['downloaded'],
      songId: json['song_id'],
      mediaType: json['media_type'],
      quality: json['quality'],
    );
  }
}

class Playlist {
  final String id;
  final String name;
  final String? description;
  final int songCount;
  final List<String> songIds;
  final String? coverImage;
  final List<Song>? songs; // Full song objects if available

  Playlist({
    required this.id,
    required this.name,
    this.description,
    required this.songCount,
    required this.songIds,
    this.coverImage,
    this.songs,
  });

  factory Playlist.fromJson(Map<String, dynamic> json) {
    var rawSongs = json['songs'];
    List<Song>? parsedSongs;
    
    if (rawSongs is List) {
      if (rawSongs.isNotEmpty && rawSongs.first is Map) {
        // It's a list of Song objects
        parsedSongs = rawSongs.map((j) => Song.fromJson(j)).toList();
      } 
      // If it's a list of Strings, it's just IDs, so parsedSongs remains null
      // The IDs are captured in songIds below
    }

    return Playlist(
      id: json['id'] ?? '',
      name: json['name'] ?? 'Unknown Playlist',
      description: json['description'],
      songCount: (json['song_ids'] as List?)?.length ?? (json['songs'] as List?)?.length ?? 0,
      songIds: json['song_ids'] != null 
          ? List<String>.from(json['song_ids'])
          : (rawSongs is List && rawSongs.isNotEmpty && rawSongs.first is String)
              ? List<String>.from(rawSongs)
              : [],
      coverImage: json['cover_image'],
      songs: parsedSongs,
    );
  }
}
