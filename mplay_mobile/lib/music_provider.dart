import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'models.dart';
import 'api_service.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

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
    _loadState(); // Load saved state
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

  // Sync with running audio service if app is restarted
  Future<void> _syncWithAudioService() async {
    // If we're already playing but currentSong is null (restart case)
    if (_audioPlayer.playing && _currentSong == null) {
      if (_audioPlayer.sequenceState != null && 
          _audioPlayer.sequenceState!.currentSource != null) {
          
          final source = _audioPlayer.sequenceState!.currentSource;
          if (source is UriAudioSource && source.tag is MediaItem) {
            final item = source.tag as MediaItem;
            
            // Try to find in playlist first
            if (_playlist.isNotEmpty) {
               final index = _playlist.indexWhere((s) => s.id == item.id);
               if (index != -1) {
                 _currentIndex = index;
                 _currentSong = _playlist[index];
                 notifyListeners();
                 return;
               }
            }
            
            // Fallback: Reconstruct minimal Song from MediaItem
            _currentSong = Song(
              id: item.id,
              title: item.title,
              artist: item.artist ?? 'Unknown Artist',
              album: item.album ?? '',
              duration: item.duration?.inSeconds.toDouble() ?? 0,
              coverArt: item.artUri?.toString(),
              fileName: '',
              hasVideo: false,
            );
            _playlist = [_currentSong!];
            _currentIndex = 0;
            notifyListeners();
          }
      }
    }
  }

  Song? get currentSong => _currentSong;
  bool get isPlaying => _isPlaying;
  Duration get position => _position;
  Duration get duration => _duration;
  List<Song> get playlist => _playlist;

  void setPlaylist(List<Song> songs) {
    _playlist = songs;
    // Don't necessarily reset current index if we just want to update the context,
    // but usually setting a new playlist implies a fresh start or context switch.
    // For now, simple assignment.
    notifyListeners();
    _saveState();
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
    _saveState();
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
  Future<void> stop() async {
    await _audioPlayer.stop();
    _isPlaying = false;
    _currentSong = null;
    _saveState(); // Clear state or save null
    notifyListeners();
  }

  // Persistence Methods
  Future<void> _saveState() async {
    final prefs = await SharedPreferences.getInstance();
    if (_currentSong != null) {
      prefs.setString('current_song', jsonEncode(_currentSong!.toJson()));
    } else {
      prefs.remove('current_song');
    }
    
    if (_playlist.isNotEmpty) {
      final playlistJson = _playlist.map((s) => s.toJson()).toList();
      prefs.setString('playlist', jsonEncode(playlistJson));
    } else {
      prefs.remove('playlist');
    }
    
    prefs.setInt('current_index', _currentIndex);
    prefs.setInt('last_playback_mode', _lastPlaybackMode);
    prefs.setBool('should_restore_player', _shouldRestorePlayer);
  }

  // Playback mode: 0 = audio, 1 = video
  int _lastPlaybackMode = 0;
  bool _shouldRestorePlayer = false;
  
  int get lastPlaybackMode => _lastPlaybackMode;
  bool get shouldRestorePlayer => _shouldRestorePlayer;
  
  void setPlaybackMode(int mode, {bool shouldRestore = true}) {
    _lastPlaybackMode = mode;
    _shouldRestorePlayer = shouldRestore;
    _saveState();
  }
  
  void clearRestoreFlag() {
    _shouldRestorePlayer = false;
    _saveState();
  }

  Future<void> _loadState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      final String? songJson = prefs.getString('current_song');
      if (songJson != null) {
        _currentSong = Song.fromJson(jsonDecode(songJson));
      }
      
      final String? playlistJson = prefs.getString('playlist');
      if (playlistJson != null) {
        final List<dynamic> decoded = jsonDecode(playlistJson);
        _playlist = decoded.map((j) => Song.fromJson(j)).toList();
      }
      
      _currentIndex = prefs.getInt('current_index') ?? -1;
      _lastPlaybackMode = prefs.getInt('last_playback_mode') ?? 0;
      _shouldRestorePlayer = prefs.getBool('should_restore_player') ?? false;
      
      if (_currentSong != null) {
        notifyListeners();
      }
      
      // Sync with active session
      _syncWithAudioService();
    } catch (e) {
      print("Error loading state: $e");
    }
  }
}
