import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import '../music_provider.dart';
import '../providers/video_provider.dart';
import '../constants.dart';
import '../api_service.dart';
import '../models.dart';

import '../library_provider.dart';
import '../services/video_cache_service.dart';
import 'dart:io';

/// Unified Player Screen - YouTube Music Style
/// Features Song/Video toggle, unified controls, and tabs
class UnifiedPlayerScreen extends StatefulWidget {
  final Song song;
  final bool startWithVideo;

  const UnifiedPlayerScreen({
    super.key,
    required this.song,
    this.startWithVideo = false,
  });

  @override
  State<UnifiedPlayerScreen> createState() => _UnifiedPlayerScreenState();
}

class _UnifiedPlayerScreenState extends State<UnifiedPlayerScreen>
    with TickerProviderStateMixin {
  // Mode: 0 = Song (Audio), 1 = Video
  int _mode = 0;
  
  // Video player for video mode
  VideoPlayerController? _videoController;
  ChewieController? _chewieController;
  bool _isVideoLoading = false;
  String? _videoError; // Holds error message if video fails
  
  // Like status
  bool? _likeStatus;
  
  // Tab controller for UP NEXT / LYRICS / RELATED
  late TabController _tabController;
  
  // Recommendations
  List<Song> _recommendations = [];

  @override
  void initState() {
    super.initState();
    _mode = widget.startWithVideo && widget.song.hasVideo ? 1 : 0;
    _tabController = TabController(length: 3, vsync: this);
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchLikeStatus();
      _loadRecommendations();
      if (_mode == 1) {
        _initVideoPlayer();
      }
    });
  }

  @override
  void dispose() {
    _videoController?.dispose();
    _chewieController?.dispose();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _fetchLikeStatus() async {
    try {
      final status = await ApiService.getLikeStatus(widget.song.id);
      if (mounted) setState(() => _likeStatus = status);
    } catch (e) {
      print("Error fetching like status: $e");
    }
  }

  Future<void> _loadRecommendations() async {
    try {
      final recs = await ApiService.getRecommendations(limit: 5);
      if (mounted) {
        setState(() {
          _recommendations = recs.where((s) => s.id != widget.song.id).toList();
        });
      }
    } catch (e) {
      print("Error loading recommendations: $e");
    }
  }

  Future<void> _initVideoPlayer() async {
    if (!widget.song.hasVideo) return;
    
    setState(() => _isVideoLoading = true);
    
    try {
      final streamUrl = ApiService.getStreamUrl(widget.song.id, type: 'video');
      
      // Check cache first
      final cacheService = VideoCacheService();
      final File? cachedFile = await cacheService.getCachedVideoFile(widget.song.id);
      
      if (cachedFile != null) {
        print("Playing from cache: ${cachedFile.path}");
        _videoController = VideoPlayerController.file(cachedFile);
      } else {
        print("Playing from network: $streamUrl");
        _videoController = VideoPlayerController.networkUrl(
          Uri.parse(streamUrl),
          videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
        );
        // Start background download
        cacheService.startDownload(url: streamUrl, songId: widget.song.id);
      }
      
      await _videoController!.initialize();
      
      // Add listener to sync UI and audio, and check for errors
      _videoController!.addListener(() {
        if (_mode == 1 && mounted) {
           // Check for errors
           if (_videoController!.value.hasError) {
              print("VideoPlayer Error: ${_videoController!.value.errorDescription}");
              setState(() {
                _isVideoLoading = false;
                _videoError = _videoController!.value.errorDescription ?? "Video playback error";
              });
              return;
           }
           
           // Auto-next: Check if video has completed
           final pos = _videoController!.value.position;
           final dur = _videoController!.value.duration;
           // If position is at or past duration and video is not playing, trigger next
           if (dur.inMilliseconds > 0 && pos >= dur && !_videoController!.value.isPlaying) {
              print("Video completed, triggering next...");
              final music = Provider.of<MusicProvider>(context, listen: false);
              music.next();
              return;
           }
           
           // Update for buffering changes
           if (_videoController!.value.isBuffering != _isVideoLoading) {
              setState(() {}); 
           }
           setState(() {});
        }
      });
      
      // Get current audio position to sync
      final musicProvider = Provider.of<MusicProvider>(context, listen: false);
      final audioPosition = musicProvider.position;
      
      _chewieController = ChewieController(
        videoPlayerController: _videoController!,
        autoPlay: false,
        looping: false,
        aspectRatio: _videoController!.value.aspectRatio,
        allowFullScreen: true, // Enable native full screen as backup
        allowMuting: true,
        allowPlaybackSpeedChanging: true,
        showControls: false, // We use our own controls
        customControls: null, // We build our own overlay
        placeholder: _buildDefaultAlbumArt(),
      );
      
      // Seek to current audio position
      if (audioPosition.inSeconds > 0) {
        await _videoController!.seekTo(audioPosition);
      }
      
      if (mounted) {
        setState(() => _isVideoLoading = false);
      }
    } catch (e) {
      print("Error initializing video: $e");
      if (mounted) {
        setState(() => _isVideoLoading = false);
      }
    }
  }

  void _onModeChanged(int newMode) {
    if (newMode == _mode) return;
    
    final musicProvider = Provider.of<MusicProvider>(context, listen: false);
    
    if (newMode == 1 && widget.song.hasVideo) {
      // Switching to Video mode
      final currentPosition = musicProvider.position;
      musicProvider.stop(); // Stop audio (releases resources better than pause)
      
      if (_videoController == null) {
        _initVideoPlayer().then((_) {
          if (_videoController != null) {
            _videoController!.seekTo(currentPosition);
            _videoController!.play();
          }
        });
      } else {
        _videoController!.seekTo(currentPosition);
        _videoController!.play();
      }
    } else if (newMode == 0) {
      // Switching to Song (Audio) mode
      Duration? videoPosition;
      if (_videoController != null && _videoController!.value.isInitialized) {
        videoPosition = _videoController!.value.position;
        // Optimization: Dispose video to stop buffering/downloading
        _videoController!.pause();
        _chewieController?.dispose();
        _videoController!.dispose();
        _chewieController = null;
        _videoController = null;
        _isVideoLoading = false;
      }
      
      if (videoPosition != null) {
        musicProvider.seek(videoPosition);
      }
      musicProvider.resume();
    }
    
    setState(() => _mode = newMode);
  }

  // Retry video after error
  void _retryVideo() {
    print("Retrying video...");
    // Dispose current controllers
    _chewieController?.dispose();
    _videoController?.dispose();
    _chewieController = null;
    _videoController = null;
    _videoError = null;
    
    // Re-initialize
    _initVideoPlayer().then((_) {
      if (_videoController != null) {
        _videoController!.play();
      }
    });
  }

  void _enterFullScreen() {
    if (_videoController == null || !_videoController!.value.isInitialized) return;
    
    // Allow landscape explicitly for full screen
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
      DeviceOrientation.portraitUp,
    ]);

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          body: SafeArea(
            child: Stack(
              children: [
                Center(
                  child: AspectRatio(
                    aspectRatio: _videoController!.value.aspectRatio,
                    child: VideoPlayer(_videoController!),
                  ),
                ),
                _buildFullScreenOverlay(),
              ],
            ),
          ),
        ),
        fullscreenDialog: true,
      ),
    ).then((_) {
      // Lock back to portrait when exiting full screen
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
      ]);
    });
  }

  Widget _buildFullScreenOverlay() {
    return Column(
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
              Expanded(
                child: Text(
                  widget.song.title,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // Minimize / Exit Full Screen Button
              IconButton(
                icon: const Icon(Icons.fullscreen_exit, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
              IconButton(
                icon: const Icon(Icons.more_vert, color: Colors.white),
                onPressed: () => _showOptionsMenu(),
              ),
            ],
          ),
        ),
        const Spacer(),
        // Timeline & Controls
        Container(
          color: Colors.black45,
          padding: const EdgeInsets.only(bottom: 24, top: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
               _buildProgressBar(isFullScreen: true),
               Row(
                 mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                 children: [
                   IconButton(
                     onPressed: _toggleLike,
                     icon: Icon(
                       _likeStatus == true ? Icons.thumb_up : Icons.thumb_up_outlined,
                       color: _likeStatus == true ? kPrimaryColor : Colors.white,
                     ),
                   ),
                   IconButton(
                     icon: const Icon(Icons.skip_previous, color: Colors.white, size: 36),
                     onPressed: () {
                         // Full screen prev not implemented yet (needs context of playlist)
                     },
                   ),
                   IconButton(
                    icon: Icon(
                      _videoController!.value.isPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill, 
                      color: Colors.white, 
                      size: 64
                    ),
                    onPressed: () {
                      _videoController!.value.isPlaying ? _videoController!.pause() : _videoController!.play();
                      setState(() {});
                    },
                   ),
                   IconButton(
                     icon: const Icon(Icons.skip_next, color: Colors.white, size: 36),
                     onPressed: () {
                         // Full screen next not implemented yet
                     },
                   ),
                   IconButton(
                     onPressed: () {
                       if (_likeStatus == false) {
                         _toggleLike(); // Toggle off dislike (neutral)
                       } else {
                         ApiService.dislikeSong(widget.song.id);
                         setState(() => _likeStatus = false);
                       }
                     },
                     icon: Icon(
                       _likeStatus == false ? Icons.thumb_down : Icons.thumb_down_outlined,
                       color: _likeStatus == false ? Colors.red : Colors.white,
                     ),
                   ),
                 ],
               ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _toggleLike() async {
    try {
      if (_likeStatus == true) {
        await ApiService.dislikeSong(widget.song.id);
        setState(() => _likeStatus = false);
      } else {
        await ApiService.likeSong(widget.song.id);
        setState(() => _likeStatus = true);
      }
    } catch (e) {
      print("Error toggling like: $e");
    }
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60);
    final seconds = d.inSeconds.remainder(60);
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: Column(
                children: [
                  Expanded(
                    flex: 4,
                    child: _buildContentArea(),
                  ),
                  _buildSongInfo(),
                  _buildActionButtons(),
                  _buildProgressBar(),
                  _buildControls(),
                  _buildBottomBar(), // UP NEXT button opens queue sheet
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white, size: 28),
            onPressed: () => Navigator.pop(context),
          ),
          const Spacer(),
          // Song / Video Toggle
          if (widget.song.hasVideo)
            Container(
              decoration: BoxDecoration(
                color: Colors.white12,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildToggleButton("Song", 0),
                  _buildToggleButton("Video", 1),
                ],
              ),
            ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            onPressed: () => _showOptionsMenu(),
          ),
        ],
      ),
    );
  }

  Widget _buildToggleButton(String label, int modeValue) {
    final isActive = _mode == modeValue;
    return GestureDetector(
      onTap: () => _onModeChanged(modeValue),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isActive ? Colors.black : Colors.white70,
            fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  Widget _buildContentArea() {
    if (_mode == 1) {
      // Video Mode
      if (_isVideoLoading) {
        return const Center(child: CircularProgressIndicator());
      }
      // Error state with retry
      if (_videoError != null) {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 48),
              const SizedBox(height: 16),
              Text(_videoError!, style: const TextStyle(color: Colors.white70)),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _retryVideo,
                icon: const Icon(Icons.refresh),
                label: const Text("Retry"),
                style: ElevatedButton.styleFrom(backgroundColor: kPrimaryColor),
              ),
            ],
          ),
        );
      }
      if (_chewieController != null && _videoController != null && _videoController!.value.isInitialized) {
        // Fix: Use Center + AspectRatio to prevent stretching
        // Chewie handles the aspect ratio internally if we let it
        return Stack(
          alignment: Alignment.center,
          children: [
            Center(
              child: AspectRatio(
                aspectRatio: _videoController!.value.aspectRatio,
                child: Chewie(controller: _chewieController!),
              ),
            ),
            if (_videoController!.value.isBuffering)
              const CircularProgressIndicator(color: Colors.white),
          ],
        );
      }
      return const Center(child: Text("Video not available", style: TextStyle(color: Colors.white54)));
    } else {
      // Song Mode - Show Album Art
      return Padding(
        padding: const EdgeInsets.all(32),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: kPrimaryColor.withOpacity(0.3),
                blurRadius: 30,
                spreadRadius: 5,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: widget.song.coverArt != null || widget.song.thumbnail != null
                ? Image.network(
                    widget.song.thumbnail ?? widget.song.coverArt!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _buildDefaultAlbumArt(),
                  )
                : _buildDefaultAlbumArt(),
          ),
        ),
      );
    }
  }

  Widget _buildDefaultAlbumArt() {
    return Container(
      color: Colors.white10,
      child: const Center(
        child: Icon(Icons.music_note, size: 80, color: Colors.white24),
      ),
    );
  }

  Widget _buildSongInfo() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Column(
        children: [
          Text(
            widget.song.title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            widget.song.artist,
            style: const TextStyle(color: Colors.white70, fontSize: 16),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            onPressed: _toggleLike,
            icon: Icon(
              _likeStatus == true ? Icons.thumb_up : Icons.thumb_up_outlined,
              color: _likeStatus == true ? kPrimaryColor : Colors.white,
            ),
          ),
          const SizedBox(width: 32),
          IconButton(
            onPressed: _toggleLike, // using same handler for dislike for now as toggle
            icon: Icon(
              _likeStatus == false ? Icons.thumb_down : Icons.thumb_down_outlined,
              color: _likeStatus == false ? Colors.red : Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressBar({bool isFullScreen = false}) {
    return Consumer<MusicProvider>(
      builder: (context, music, child) {
        final position = _mode == 1 && _videoController != null
            ? _videoController!.value.position
            : music.position;
        final duration = _mode == 1 && _videoController != null
            ? _videoController!.value.duration
            : music.duration;

        return Padding(
          padding: EdgeInsets.symmetric(horizontal: isFullScreen ? 16 : 24),
          child: Column(
            children: [
              Stack(
                alignment: Alignment.centerLeft,
                children: [
                  // Buffered Indicator - Aligned with Slider track (24px padding)
                  if (_mode == 1 && _videoController != null && duration.inMilliseconds > 0)
                     Padding(
                       padding: const EdgeInsets.symmetric(horizontal: 24), // Match Slider track padding
                       child: LayoutBuilder(
                         builder: (context, constraints) {
                           // Find the max buffered point
                           int maxBuffered = 0;
                           for (var range in _videoController!.value.buffered) {
                             if (range.end.inMilliseconds > maxBuffered) {
                               maxBuffered = range.end.inMilliseconds;
                             }
                           }
                           final double percent = (maxBuffered / duration.inMilliseconds).clamp(0.0, 1.0);
                           return Align(
                             alignment: Alignment.centerLeft,
                             child: Container(
                               width: constraints.maxWidth * percent,
                               height: 4,
                               decoration: BoxDecoration(
                                 color: Colors.white38, 
                                 borderRadius: BorderRadius.circular(2),
                               ),
                             ),
                           );
                         },
                       ),
                     ),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 4,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                      overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                      activeTrackColor: Colors.white,
                      inactiveTrackColor: Colors.transparent, // Transparent so we see buffer behind? No, we want active on top.
                      thumbColor: Colors.white,
                      overlayColor: Colors.white24,
                    ),
                    child: Slider(
                      value: position.inSeconds.toDouble().clamp(0, duration.inSeconds.toDouble()),
                      max: duration.inSeconds.toDouble().clamp(1, double.infinity),
                      onChanged: (value) {
                        final newPosition = Duration(seconds: value.toInt());
                        if (_mode == 1 && _videoController != null) {
                          _videoController!.seekTo(newPosition);
                        } else {
                          music.seek(newPosition);
                        }
                      },
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(_formatDuration(position), style: const TextStyle(color: Colors.white54, fontSize: 12)),
                    if (!isFullScreen && _mode == 1) // Show expand button in mini-player only (video mode)
                       IconButton(
                         padding: EdgeInsets.zero,
                         constraints: const BoxConstraints(),
                         icon: const Icon(Icons.fullscreen, color: Colors.white, size: 24),
                         onPressed: _enterFullScreen,
                       ),
                    Text(_formatDuration(duration), style: const TextStyle(color: Colors.white54, fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildControls() {
    return Consumer<MusicProvider>(
      builder: (context, music, child) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                icon: const Icon(Icons.shuffle, color: Colors.white54),
                onPressed: () {}, // Not implemented
              ),
              IconButton(
                icon: const Icon(Icons.skip_previous, color: Colors.white, size: 36),
                onPressed: music.previous,
              ),
              Container(
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                ),
                child: IconButton(
                  icon: Icon(
                    (_mode == 1 && _videoController != null)
                        ? (_videoController!.value.isPlaying || _videoController!.value.isBuffering 
                            ? Icons.pause 
                            : Icons.play_arrow)
                        : (music.isPlaying ? Icons.pause : Icons.play_arrow),
                    color: Colors.black,
                    size: 32,
                  ),
                  onPressed: () {
                    if (_mode == 1 && _videoController != null) {
                      _videoController!.value.isPlaying ? _videoController!.pause() : _videoController!.play();
                      setState(() {});
                    } else {
                      music.isPlaying ? music.pause() : music.resume();
                    }
                  },
                ),
              ),
              IconButton(
                icon: const Icon(Icons.skip_next, color: Colors.white, size: 36),
                onPressed: music.next,
              ),
              IconButton(
                icon: const Icon(Icons.repeat, color: Colors.white54),
                onPressed: () {}, // Not implemented
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBottomBar() {
    return GestureDetector(
      onTap: _showQueueSheet,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: const BoxDecoration(
          color: Colors.white10,
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "UP NEXT",
                  style: TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.bold),
                ),
                Text(
                  "Tap to see queue",
                  style: TextStyle(color: Colors.white, fontSize: 14),
                ),
              ],
            ),
             Icon(Icons.keyboard_arrow_up, color: Colors.white54),
          ],
        ),
      ),
    );
  }

  void _showQueueSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.9,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          builder: (_, controller) {
            return Container(
              decoration: BoxDecoration(
                color: kBackgroundColor,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                 children: [
                   Padding(
                     padding: const EdgeInsets.all(16),
                     child: Container(
                       width: 40,
                       height: 4,
                       decoration: BoxDecoration(
                         color: Colors.white24,
                         borderRadius: BorderRadius.circular(2),
                       ),
                     ),
                   ),
                   const Padding(
                     padding: EdgeInsets.only(bottom: 16),
                     child: Text(
                       "Up Next",
                       style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                     ),
                   ),
                   Expanded(
                     child: Consumer<MusicProvider>(
                       builder: (context, music, _) {
                         if (music.playlist.isEmpty) {
                            return const Center(child: Text("Queue is empty", style: TextStyle(color: Colors.white54)));
                         }
                         return ListView.builder(
                           controller: controller,
                           itemCount: music.playlist.length,
                           itemBuilder: (context, index) {
                             final song = music.playlist[index];
                             final isPlaying = song.id == widget.song.id;
                             return ListTile(
                               leading: ClipRRect(
                                 borderRadius: BorderRadius.circular(4),
                                 child: Image.network(
                                   song.thumbnail ?? song.coverArt ?? "", 
                                   width: 50, 
                                   height: 50, 
                                   fit: BoxFit.cover,
                                   errorBuilder: (_,__,___) => Container(color: Colors.grey, width: 50, height: 50),
                                 ),
                               ),
                               title: Text(
                                 song.title,
                                 style: TextStyle(
                                   color: isPlaying ? kPrimaryColor : Colors.white,
                                   fontWeight: isPlaying ? FontWeight.bold : FontWeight.normal
                                 ),
                                 maxLines: 1,
                                 overflow: TextOverflow.ellipsis,
                               ),
                               subtitle: Text(song.artist, style: const TextStyle(color: Colors.white54)),
                               onTap: () {
                                 Navigator.pop(context);
                                 music.playSong(song, music.playlist);
                                 Navigator.pushReplacement(
                                   context,
                                   MaterialPageRoute(builder: (_) => UnifiedPlayerScreen(song: song)),
                                 );
                               },
                             );
                           },
                         );
                       },
                     ),
                   ),
                 ],
              ),
            );
          },
        );
      },
    );
  }

  void _showOptionsMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1a1a2e),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      widget.song.thumbnail ?? widget.song.coverArt ?? "",
                      width: 50, height: 50, fit: BoxFit.cover,
                      errorBuilder: (_,__,___) => Container(color: Colors.grey, width: 50, height: 50),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.song.title,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          widget.song.artist,
                          style: const TextStyle(color: Colors.white54, fontSize: 14),
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(color: Colors.white10),
            ListTile(
              leading: const Icon(Icons.playlist_add, color: Colors.white),
              title: const Text("Add to Playlist", style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(ctx);
                final playlists = Provider.of<LibraryProvider>(context, listen: false).playlists;
                _showAddToPlaylistSheet(widget.song, playlists);
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit, color: Colors.blue),
              title: const Text("Rename Song", style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(ctx);
                _showRenameSongDialog(widget.song);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text("Delete Song", style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(ctx);
                _showDeleteConfirmation(widget.song);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showAddToPlaylistSheet(Song song, List<Playlist> playlists) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1a1a2e),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Add \"${song.title}\" to playlist",
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 16),
            if (playlists.isEmpty)
              const Padding(
                padding: EdgeInsets.all(20),
                child: Text("No playlists yet. Create one first!", style: TextStyle(color: Colors.white54)),
              )
            else
              Container(
                constraints: const BoxConstraints(maxHeight: 300),
                child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: playlists.length,
                    itemBuilder: (context, index) {
                         final pl = playlists[index];
                         return ListTile(
                            leading: SizedBox(
                              width: 48,
                              height: 48,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: kPrimaryColor.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(Icons.playlist_play, color: kPrimaryColor),
                              ),
                            ),
                            title: Text(pl.name, style: const TextStyle(color: Colors.white)),
                            subtitle: Text("${pl.songCount} songs", style: const TextStyle(color: Colors.white54, fontSize: 12)),
                            onTap: () async {
                              try {
                                await ApiService.addSongToPlaylist(pl.id, song.id);
                                if (mounted) {
                                  Navigator.pop(ctx);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text("Added to ${pl.name}"), backgroundColor: kPrimaryColor),
                                  );
                                  Provider.of<LibraryProvider>(context, listen: false).refreshData();
                                }
                              } catch (e) {
                                print("Error adding to playlist: $e");
                              }
                            },
                          );
                    }
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showRenameSongDialog(Song song) {
    final titleController = TextEditingController(text: song.title);
    final artistController = TextEditingController(text: song.artist);
    
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1a1a2e),
        title: const Text("Rename Song", style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: "Title",
                labelStyle: TextStyle(color: Colors.white54),
                enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: artistController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: "Artist",
                labelStyle: TextStyle(color: Colors.white54),
                enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () async {
              try {
                await ApiService.updateSong(
                  song.id,
                  title: titleController.text.trim(),
                  artist: artistController.text.trim(),
                );
                if (mounted) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Song updated successfully!"), backgroundColor: kPrimaryColor),
                  );
                  Provider.of<LibraryProvider>(context, listen: false).refreshData();
                  // TODO: Update local song object state if needed
                }
              } catch (e) {
                print("Error renaming song: $e");
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
                  );
                }
              }
            },
            child: const Text("Save", style: TextStyle(color: kPrimaryColor)),
          ),
        ],
      ),
    );
  }

  void _showDeleteConfirmation(Song song) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1a1a2e),
        title: const Text("Delete Song", style: TextStyle(color: Colors.white)),
        content: Text("Are you sure you want to delete \"${song.title}\"? This cannot be undone.", 
          style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () async {
              try {
                await ApiService.deleteSong(song.id);
                if (mounted) {
                   Navigator.pop(ctx); // Close dialog
                   Navigator.pop(context); // Close player screen
                   ScaffoldMessenger.of(context).showSnackBar(
                     const SnackBar(content: Text("Song deleted"), backgroundColor: Colors.red),
                   );
                   Provider.of<LibraryProvider>(context, listen: false).refreshData();
                }
              } catch (e) {
                print("Error deleting song: $e");
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
                  );
                }
              }
            },
            child: const Text("Delete", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
