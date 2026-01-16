import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models.dart';
import '../music_provider.dart';
import '../widgets/song_tile.dart';
import '../widgets/glass_container.dart';
import '../constants.dart';
import '../api_service.dart';

class PlaylistDetailScreen extends StatefulWidget {
  final Playlist playlist;

  const PlaylistDetailScreen({Key? key, required this.playlist}) : super(key: key);

  @override
  State<PlaylistDetailScreen> createState() => _PlaylistDetailScreenState();
}

class _PlaylistDetailScreenState extends State<PlaylistDetailScreen> {
  bool _isLoading = true;
  List<Song> _songs = [];
  bool _isPlaying = false;
  bool _isSaved = false;

  @override
  void initState() {
    super.initState();
    _loadSongs();
  }

  Future<void> _loadSongs() async {
    // If playlist already has songs, use them
    if (widget.playlist.songs != null && widget.playlist.songs!.isNotEmpty) {
      setState(() {
        _songs = widget.playlist.songs!;
        _isLoading = false;
      });
      return;
    }

    // Otherwise fetch full details
    try {
      final fullPlaylist = await ApiService.getAppPlaylist(widget.playlist.id);
      if (mounted && fullPlaylist != null && fullPlaylist.songs != null) {
        setState(() {
          _songs = fullPlaylist.songs!;
          _isLoading = false;
        });
      }
    } catch (e) {
      print("Error loading playlist songs: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _playAll() {
    if (_songs.isEmpty) return;
    
    final musicProvider = Provider.of<MusicProvider>(context, listen: false);
    musicProvider.setPlaylist(_songs);
    musicProvider.playSong(_songs[0], _songs);
    setState(() => _isPlaying = true);
  }

  Future<void> _addToMyLibrary() async {
    if (_isSaved) return;

    setState(() => _isLoading = true);
    try {
      final success = await ApiService.importAppPlaylist(widget.playlist.id);
      if (success) {
        setState(() => _isSaved = true);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Saved to your Playlists!"),
              backgroundColor: kPrimaryColor,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      print("Error importing playlist: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Failed to save playlist"), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackgroundColor,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Stack(
        children: [
          // Background Image
          if (widget.playlist.coverImage != null)
            Positioned.fill(
              child: Opacity(
                opacity: 0.3,
                child: Image.network(
                  widget.playlist.coverImage!,
                  fit: BoxFit.cover,
                  errorBuilder: (c, o, s) => Container(color: kBackgroundColor),
                ),
              ),
            ),
            
          // Gradient Overlay
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    kBackgroundColor.withOpacity(0.5),
                    kBackgroundColor,
                  ],
                  stops: const [0.0, 0.6],
                ),
              ),
            ),
          ),

          // Content
          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 20),
                
                // Playlist Header
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Cover Image
                      Container(
                        width: 140,
                        height: 140,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.4),
                              blurRadius: 20,
                              offset: const Offset(0, 10),
                            ),
                          ],
                          image: widget.playlist.coverImage != null
                              ? DecorationImage(
                                  image: NetworkImage(widget.playlist.coverImage!),
                                  fit: BoxFit.cover,
                                )
                              : null,
                          color: Colors.grey[900],
                        ),
                        child: widget.playlist.coverImage == null
                            ? const Icon(Icons.music_note, color: Colors.white24, size: 60)
                            : null,
                      ),
                      
                      const SizedBox(width: 24),
                      
                      // Info
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 10),
                            Text(
                              "PLAYLIST",
                              style: TextStyle(
                                color: kPrimaryColor.withOpacity(0.8),
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 2,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              widget.playlist.name,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                height: 1.2,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 8),
                            if (widget.playlist.description != null)
                              Text(
                                widget.playlist.description!,
                                style: const TextStyle(
                                  color: Colors.white54,
                                  fontSize: 13,
                                  height: 1.4,
                                ),
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                              ),
                            const SizedBox(height: 16),
                            Text(
                              "${widget.playlist.songCount} Songs",
                              style: const TextStyle(
                                color: Colors.white38,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 32),
                
                // Action Buttons
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    children: [
                      // Play All Button
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _playAll,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: kPrimaryColor,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30),
                            ),
                            elevation: 8,
                            shadowColor: kPrimaryColor.withOpacity(0.4),
                          ),
                          child: const Text(
                            "PLAY ALL",
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1,
                            ),
                          ),
                        ),
                      ),
                      
                      const SizedBox(width: 16),
                      
                      // Add to Library Button
                      GlassContainer(
                        borderRadius: 30,
                        padding: EdgeInsets.zero,
                        color: _isSaved ? kPrimaryColor : Colors.white.withOpacity(0.1),
                        child: IconButton(
                          onPressed: _addToMyLibrary,
                          icon: Icon(
                            _isSaved ? Icons.playlist_add_check : Icons.playlist_add, 
                            color: Colors.white,
                          ),
                          tooltip: _isSaved ? "Saved to Library" : "Save as Playlist",
                        ),
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 24),
                
                // Songs List
                Expanded(
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator(color: kPrimaryColor))
                      : ListView.builder(
                          padding: const EdgeInsets.only(bottom: 100), // Space for mini player
                          itemCount: _songs.length,
                          itemBuilder: (context, index) {
                            final song = _songs[index];
                            return SongTile(
                              song: song,
                              onTap: () {
                                final musicProvider = Provider.of<MusicProvider>(context, listen: false);
                                musicProvider.setPlaylist(_songs); // Set context
                                musicProvider.playSong(song, _songs);
                              },
                              trailing: IconButton(
                                icon: const Icon(Icons.more_vert, color: Colors.white54),
                                onPressed: () {
                                  // Show options
                                },
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
