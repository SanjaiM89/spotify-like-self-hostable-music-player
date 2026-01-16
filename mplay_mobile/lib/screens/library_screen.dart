import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../api_service.dart';
import '../models.dart';
import '../music_provider.dart';
import '../widgets/song_tile.dart';
import '../constants.dart';
import 'video_player_screen.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> with SingleTickerProviderStateMixin {
  List<Song> _songs = [];
  List<Song> _filteredSongs = [];
  List<dynamic> _playlists = [];
  bool _loading = true;
  final TextEditingController _searchController = TextEditingController();
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      final songs = await ApiService.getSongs();
      final playlists = await ApiService.getPlaylists();
      if (mounted) {
        setState(() {
          _songs = songs;
          _filteredSongs = songs;
          _playlists = playlists;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
      print("Error loading library: $e");
    }
  }

  void _filterSongs(String query) {
    if (query.isEmpty) {
      setState(() => _filteredSongs = _songs);
    } else {
      setState(() {
        _filteredSongs = _songs.where((s) => 
          s.title.toLowerCase().contains(query.toLowerCase()) || 
          s.artist.toLowerCase().contains(query.toLowerCase())
        ).toList();
      });
    }
  }

  void _showCreatePlaylistDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1a1a2e),
        title: const Text("New Playlist"),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: "Playlist name",
            hintStyle: TextStyle(color: Colors.white38),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () async {
              if (controller.text.trim().isNotEmpty) {
                await ApiService.createPlaylist(controller.text.trim());
                Navigator.pop(ctx);
                _loadData();
              }
            },
            child: const Text("Create"),
          ),
        ],
      ),
    );
  }

  void _showSongOptionsMenu(Song song) {
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
          children: [
            // Song info header
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: song.coverArt != null
                      ? Image.network(song.coverArt!, width: 50, height: 50, fit: BoxFit.cover)
                      : Container(width: 50, height: 50, color: Colors.white10),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(song.title, style: const TextStyle(fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
                      Text(song.artist, style: const TextStyle(color: Colors.white54, fontSize: 13)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const Divider(color: Colors.white12),
            ListTile(
              leading: const Icon(Icons.playlist_add, color: kPrimaryColor),
              title: const Text("Add to Playlist"),
              onTap: () {
                Navigator.pop(ctx);
                _showAddToPlaylistSheet(song);
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit, color: Colors.blue),
              title: const Text("Rename Song"),
              onTap: () {
                Navigator.pop(ctx);
                _showRenameSongDialog(song);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text("Delete Song"),
              onTap: () {
                Navigator.pop(ctx);
                _showDeleteConfirmation(song);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showAddToPlaylistSheet(Song song) {
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
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            if (_playlists.isEmpty)
              const Padding(
                padding: EdgeInsets.all(20),
                child: Text("No playlists yet. Create one first!", style: TextStyle(color: Colors.white54)),
              )
            else
              ...(_playlists.map((pl) => ListTile(
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
                title: Text(pl['name'] ?? 'Untitled'),
                subtitle: Text("${(pl['songs'] as List?)?.length ?? 0} songs", style: const TextStyle(color: Colors.white54, fontSize: 12)),
                onTap: () async {
                  await ApiService.addSongToPlaylist(pl['id'], song.id);
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text("Added to ${pl['name']}"), backgroundColor: kPrimaryColor),
                  );
                },
              ))),
            const SizedBox(height: 16),
            Center(
              child: TextButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  _showCreatePlaylistDialog();
                },
                icon: const Icon(Icons.add),
                label: const Text("Create New Playlist"),
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
        title: const Text("Rename Song"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(labelText: "Title", labelStyle: TextStyle(color: Colors.white54)),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: artistController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(labelText: "Artist", labelStyle: TextStyle(color: Colors.white54)),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
          TextButton(
            onPressed: () async {
              await ApiService.updateSong(
                song.id,
                title: titleController.text.trim(),
                artist: artistController.text.trim(),
              );
              Navigator.pop(ctx);
              _loadData(); // Refresh list
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Song updated"), backgroundColor: Colors.green),
              );
            },
            child: const Text("Save"),
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
        title: const Text("Delete Song?"),
        content: Text("Are you sure you want to delete \"${song.title}\"?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
          TextButton(
            onPressed: () async {
              await ApiService.deleteSong(song.id);
              Navigator.pop(ctx);
              _loadData(); // Refresh list
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Song deleted"), backgroundColor: Colors.red),
              );
            },
            child: const Text("Delete", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final music = Provider.of<MusicProvider>(context);

    return Scaffold(
      body: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.fromLTRB(16, 60, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      "Library", 
                      style: TextStyle(
                        fontSize: 32, 
                        fontWeight: FontWeight.bold,
                        letterSpacing: -0.5,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add_rounded),
                      onPressed: _showCreatePlaylistDialog,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Tabs
                TabBar(
                  controller: _tabController,
                  labelColor: kPrimaryColor,
                  unselectedLabelColor: Colors.white54,
                  indicatorColor: kPrimaryColor,
                  tabs: const [
                    Tab(text: "Songs"),
                    Tab(text: "Playlists"),
                  ],
                ),
              ],
            ),
          ),
          
          // Content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // Songs Tab
                _buildSongsTab(music),
                // Playlists Tab
                _buildPlaylistsTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSongsTab(MusicProvider music) {
    return Column(
      children: [
        // Search
        Padding(
          padding: const EdgeInsets.all(16),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(14),
            ),
            child: TextField(
              controller: _searchController,
              onChanged: _filterSongs,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                hintText: "Search songs, artists...",
                hintStyle: TextStyle(color: Colors.white38),
                prefixIcon: Icon(Icons.search, color: Colors.white38),
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
            ),
          ),
        ),
        // List
        Expanded(
          child: _loading 
            ? const Center(child: CircularProgressIndicator(color: kPrimaryColor))
            : _filteredSongs.isEmpty 
              ? const Center(child: Text("No songs found", style: TextStyle(color: Colors.white38)))
              : ListView.builder(
                  itemCount: _filteredSongs.length,
                  padding: const EdgeInsets.only(bottom: 100, left: 16, right: 16), 
                  itemBuilder: (context, index) {
                    final song = _filteredSongs[index];
                    return GestureDetector(
                      onLongPress: () => _showSongOptionsMenu(song),
                      child: SongTile(
                        song: song,
                        isPlaying: music.currentSong?.id == song.id,
                        onTap: () {
                          if (song.fileName.toLowerCase().endsWith('.mp4') || song.fileName.toLowerCase().endsWith('.mkv')) {
                             Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => VideoPlayerScreen(song: song),
                              ),
                            );
                          } else {
                            music.playSong(song, _filteredSongs);
                          }
                        },
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildPlaylistsTab() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: kPrimaryColor));
    }
    
    if (_playlists.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.queue_music_rounded, size: 64, color: Colors.white24),
            const SizedBox(height: 16),
            const Text("No playlists yet", style: TextStyle(color: Colors.white54)),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _showCreatePlaylistDialog,
              icon: const Icon(Icons.add),
              label: const Text("Create Playlist"),
            ),
          ],
        ),
      );
    }
    
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _playlists.length,
      itemBuilder: (context, index) {
        final pl = _playlists[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(14),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: SizedBox(
              width: 56,
              height: 56,
              child: Container(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [kPrimaryColor, kSecondaryColor]),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.playlist_play_rounded, color: Colors.white, size: 28),
              ),
            ),
            title: Text(pl['name'] ?? 'Untitled', style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text("${(pl['songs'] as List?)?.length ?? 0} songs", style: const TextStyle(color: Colors.white54, fontSize: 13)),
            trailing: PopupMenuButton(
              icon: const Icon(Icons.more_vert, color: Colors.white54),
              color: const Color(0xFF1a1a2e),
              itemBuilder: (ctx) => [
                const PopupMenuItem(value: 'delete', child: Text("Delete")),
              ],
              onSelected: (val) async {
                if (val == 'delete') {
                  await ApiService.deletePlaylist(pl['id']);
                  _loadData();
                }
              },
            ),
          ),
        );
      },
    );
  }
}
