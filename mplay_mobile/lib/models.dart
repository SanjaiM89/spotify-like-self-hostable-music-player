class Song {
  final String id;
  final String title;
  final String artist;
  final String album;
  final double duration;
  final String? coverArt;
  final String fileName;

  Song({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.duration,
    this.coverArt,
    required this.fileName,
  });

  factory Song.fromJson(Map<String, dynamic> json) {
    return Song(
      id: json['id'] ?? '',
      title: json['title'] ?? 'Unknown Title',
      artist: json['artist'] ?? 'Unknown Artist',
      album: json['album'] ?? '',
      duration: (json['duration'] ?? 0).toDouble(),
      coverArt: json['cover_art'],
      fileName: json['file_name'] ?? '',
    );
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
  final int songCount;
  final List<String> songIds;

  Playlist({
    required this.id,
    required this.name,
    required this.songCount,
    required this.songIds,
  });

  factory Playlist.fromJson(Map<String, dynamic> json) {
    return Playlist(
      id: json['id'],
      name: json['name'],
      songCount: json['song_count'] ?? 0,
      songIds: List<String>.from(json['songs'] ?? []),
    );
  }
}
