import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:flutter/services.dart';
import '../models.dart';
import '../constants.dart';
import '../api_service.dart';
import '../music_provider.dart';

class VideoProvider with ChangeNotifier {
  VideoPlayerController? _videoPlayerController;
  ChewieController? _chewieController;
  Song? _currentVideo;
  bool _isMinimized = false;
  bool _isLoading = false;

  VideoPlayerController? get videoPlayerController => _videoPlayerController;
  ChewieController? get chewieController => _chewieController;
  Song? get currentVideo => _currentVideo;
  bool get isMinimized => _isMinimized;
  bool get isLoading => _isLoading;
  List<Song> get recommendations => _recommendations;

  List<Song> _recommendations = [];

  Future<void> playVideo(Song video) async {
    // If same video, just maximize and play
    if (_currentVideo?.id == video.id && _videoPlayerController != null) {
      _isMinimized = false;
      _videoPlayerController!.play();
      notifyListeners();
      return;
    }

    // Dispose previous controllers
    _disposeControllers();

    _currentVideo = video;
    _isLoading = true;
    _isMinimized = false;
    notifyListeners();

    try {
      final streamUrl = ApiService.getStreamUrl(video.id, type: 'video');
      
      _videoPlayerController = VideoPlayerController.networkUrl(
        Uri.parse(streamUrl),
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
      );
      await _videoPlayerController!.initialize();

      _chewieController = ChewieController(
        videoPlayerController: _videoPlayerController!,
        autoPlay: true,
        looping: false,
        aspectRatio: _videoPlayerController!.value.aspectRatio,
        allowFullScreen: false, // We handle full screen manually via maximizing
        allowMuting: true,
        allowPlaybackSpeedChanging: true,
        showControls: true,
        errorBuilder: (context, errorMessage) {
          return Center(
            child: Text(
              errorMessage,
              style: const TextStyle(color: Colors.white),
            ),
          );
        },
      );

      _isLoading = false;
      notifyListeners();
      
      // Fetch recommendations
      _recommendations = await ApiService.getRecommendations(limit: 5);
      _recommendations.removeWhere((s) => s.id == video.id);
      notifyListeners();

    } catch (e) {
      print("Error initializing video: $e");
      _isLoading = false;
      // You might want to set error state here
      notifyListeners();
    }
  }

  void minimize() {
    _isMinimized = true;
    notifyListeners();
  }

  void maximize() {
    _isMinimized = false;
    notifyListeners();
  }

  /// Call this to force UI rebuild (e.g., after toggling play state externally)
  void refresh() {
    notifyListeners();
  }

  /// Close video and switch to audio playback in background
  void closeAndSwitchToAudio(MusicProvider musicProvider) {
    if (_videoPlayerController != null && _videoPlayerController!.value.isInitialized) {
      final position = _videoPlayerController!.value.position;
      
      // Resume audio from the same position
      if (_currentVideo != null) {
        musicProvider.seek(position);
        musicProvider.resume();
      }
    }
    
    _disposeControllers();
    _currentVideo = null;
    _isMinimized = false;
    notifyListeners();
  }
  
  /// Close video without switching to audio
  void close() {
    _disposeControllers();
    _currentVideo = null;
    _isMinimized = false;
    notifyListeners();
  }

  void _disposeControllers() {
    _videoPlayerController?.dispose();
    _chewieController?.dispose();
    _videoPlayerController = null;
    _chewieController = null;
  }

  @override
  void dispose() {
    _disposeControllers();
    super.dispose();
  }
}
