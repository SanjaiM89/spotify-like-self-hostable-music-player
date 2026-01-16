import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'models.dart';
import 'api_service.dart';

import 'package:just_audio_background/just_audio_background.dart';

class MusicProvider with ChangeNotifier {
  final AudioPlayer _audioPlayer = AudioPlayer();
  // ... existing fields ...
  Song? _currentSong;
  bool _isPlaying = false;
  List<Song> _playlist = [];
  int _currentIndex = -1;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  MusicProvider() {
    _audioPlayer.setLoopMode(LoopMode.all); // Enable looping by default
    
    _audioPlayer.playerStateStream.listen((state) {
      _isPlaying = state.playing;
      notifyListeners();
    });

    _audioPlayer.currentIndexStream.listen((index) {
      if (index != null && _playlist.isNotEmpty && index < _playlist.length) {
        _currentIndex = index;
        _currentSong = _playlist[index];
        notifyListeners();
      }
    });

    _audioPlayer.positionStream.listen((pos) {
      _position = pos;
      notifyListeners();
    });
    
    _audioPlayer.durationStream.listen((dur) {
      _duration = dur ?? Duration.zero;
      notifyListeners();
    });
  }

  Song? get currentSong => _currentSong;
  bool get isPlaying => _isPlaying;
  Duration get position => _position;
  Duration get duration => _duration;

  void setPlaylist(List<Song> songs) {
    _playlist = songs;
    // Don't necessarily reset current index if we just want to update the context,
    // but usually setting a new playlist implies a fresh start or context switch.
    // For now, simple assignment.
    notifyListeners();
  }

  Future<void> playSong(Song song, List<Song> playlist) async {
    final bool isSamePlaylist = _playlist.length == playlist.length && 
                                _playlist.every((s) => playlist.any((p) => p.id == s.id));
    
    _playlist = playlist;
    _currentSong = song;
    _currentIndex = _playlist.indexWhere((s) => s.id == song.id);
    
    if (_currentIndex == -1) {
      // Song not in playlist? Add it or fallback
      print("Warning: Song not found in playlist, adding it momentarily");
      _playlist.insert(0, song);
      _currentIndex = 0;
    }
    notifyListeners();

    try {
      if (!isSamePlaylist || _audioPlayer.audioSource == null) {
        // Build playlist source for pre-buffering
        final sources = _playlist.map((s) {
          return AudioSource.uri(
            Uri.parse(ApiService.getStreamUrl(s.id)),
            tag: MediaItem(
              id: s.id,
              title: s.title,
              artist: s.artist,
              artUri: s.coverArt != null ? Uri.parse(s.coverArt!) : null,
              album: s.album,
            ),
          );
        }).toList();

        final playlistSource = ConcatenatingAudioSource(children: sources);
        await _audioPlayer.setAudioSource(playlistSource, initialIndex: _currentIndex);
      } else {
        // Just seek if playlist is same
        await _audioPlayer.seek(Duration.zero, index: _currentIndex);
      }
      
      await _audioPlayer.play();
      ApiService.recordPlay(song.id);
    } catch (e) {
      print("Error playing song: $e");
    }
  }

  Future<void> pause() async {
    await _audioPlayer.pause();
  }

  Future<void> resume() async {
    await _audioPlayer.play();
  }
  
  Future<void> seek(Duration position) async {
    await _audioPlayer.seek(position);
  }

  /// Track if user listened > 60 seconds before skipping
  Future<void> _reportListenSignal() async {
    if (_currentSong == null) return;
    
    final listenedSeconds = _position.inSeconds;
    if (listenedSeconds >= 60) {
      // Positive signal: listened for > 1 minute
      try {
        await ApiService.sendSignal(_currentSong!.id, "listen", durationSeconds: listenedSeconds);
        await ApiService.markSongPlayed(_currentSong!.id);
      } catch (e) {
        print("Error sending listen signal: $e");
      }
    } else if (listenedSeconds > 0 && listenedSeconds < 30) {
      // Skip signal: listened < 30 seconds
      try {
        await ApiService.sendSignal(_currentSong!.id, "skip", durationSeconds: listenedSeconds);
      } catch (e) {
        print("Error sending skip signal: $e");
      }
    }
  }

  Future<void> next() async {
    // Report listen signal before moving to next
    await _reportListenSignal();
    
    if (_audioPlayer.hasNext) {
      await _audioPlayer.seekToNext();
    } else if (_playlist.isNotEmpty) {
      // Loop manually if needed (though LoopMode.all handles it)
      await _audioPlayer.seek(Duration.zero, index: 0);
    }
  }

  Future<void> previous() async {
    // Report listen signal before going back
    await _reportListenSignal();
    
    if (_audioPlayer.hasPrevious) {
      await _audioPlayer.seekToPrevious();
    } else if (_playlist.isNotEmpty) {
      await _audioPlayer.seek(Duration.zero, index: _playlist.length - 1);
    }
  }
}
