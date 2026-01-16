import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../api_service.dart';
import '../models.dart';
import '../music_provider.dart';
import '../widgets/glass_container.dart';
import '../widgets/song_tile.dart';
import '../constants.dart';
import 'video_player_screen.dart';

class HomeScreen extends StatefulWidget {
  final Function(int, [String?]) onNavigate;

  const HomeScreen({super.key, required this.onNavigate});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Map<String, dynamic>? _data;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final data = await ApiService.getHomepage();
      if (mounted) {
        setState(() {
          _data = data;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
      }
      print("Error loading home: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: kPrimaryColor));
    }
    
    // Parse data safely
    final recentJson = _data?['recently_played'] as List? ?? [];
    final recentSongs = recentJson.map((j) => Song.fromJson(j)).toList();
    
    final aiPlaylistJson = _data?['ai_playlist'] as Map?;
    final aiPlaylistName = aiPlaylistJson?['name'] ?? 'AI Mix';
    final aiSongsJson = aiPlaylistJson?['songs'] as List? ?? [];
    final aiSongs = aiSongsJson.map((j) => Song.fromJson(j)).toList();
    
    final recommendations = List<String>.from(_data?['recommendations'] ?? []);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 60, 16, 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Welcome Back", style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                  Text("Your personal music space", style: TextStyle(color: Colors.white54)),
                ],
              ),
              CircleAvatar(
                backgroundColor: kPrimaryColor.withOpacity(0.2),
                child: const Text("U", style: TextStyle(color: kPrimaryColor)),
              )
            ],
          ),
          
          const SizedBox(height: 32),
          
          // Recently Played
          if (recentSongs.isNotEmpty) ...[
            const Text("Recently Played", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: -0.5)),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: recentSongs.length,
                itemBuilder: (context, index) {
                  final song = recentSongs[index];
                  return GestureDetector(
                    onTap: () {
                      if (song.fileName.toLowerCase().endsWith('.mp4') || song.fileName.toLowerCase().endsWith('.mkv')) {
                         Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => VideoPlayerScreen(song: song),
                          ),
                        );
                      } else {
                        Provider.of<MusicProvider>(context, listen: false).playSong(song, recentSongs);
                      }
                    },
                    child: Container(
                      width: 150,
                      margin: const EdgeInsets.only(right: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.3),
                                    blurRadius: 15,
                                    offset: const Offset(0, 8),
                                  ),
                                ],
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: song.coverArt != null
                                    ? Image.network(song.coverArt!, fit: BoxFit.cover, width: 150, height: 150)
                                    : Container(
                                        color: Colors.white.withOpacity(0.08), 
                                        child: const Icon(Icons.music_note, size: 48, color: Colors.white24),
                                      ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            song.title, 
                            maxLines: 1, 
                            overflow: TextOverflow.ellipsis, 
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, letterSpacing: -0.3),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            song.artist, 
                            maxLines: 1, 
                            overflow: TextOverflow.ellipsis, 
                            style: const TextStyle(color: Colors.white54, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 32),
          ],
          
          // AI Playlist
          if (aiSongs.isNotEmpty) ...[
            Row(
              children: [
                Text(aiPlaylistName, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [kPrimaryColor, kSecondaryColor]),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text("AI", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            const SizedBox(height: 16),
            GlassContainer(
              padding: const EdgeInsets.all(0),
              child: Column(
                children: aiSongs.take(5).map((song) => ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  leading: SizedBox(
                    width: 40,
                    height: 40,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: song.coverArt != null && song.coverArt!.isNotEmpty
                          ? Image.network(
                              song.coverArt!, 
                              width: 40, 
                              height: 40, 
                              fit: BoxFit.cover,
                              errorBuilder: (c, e, s) => Container(color: Colors.white10, child: const Icon(Icons.music_note, size: 20, color: Colors.white38)),
                            )
                          : Container(color: Colors.white10, child: const Icon(Icons.music_note, size: 20, color: Colors.white38)),
                    ),
                  ),
                  title: Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(song.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white54, fontSize: 12)),
                  trailing: Text("${(song.duration/60).floor()}:${(song.duration%60).toInt().toString().padLeft(2,'0')}", 
                               style: const TextStyle(color: Colors.white38, fontSize: 12)),
                  onTap: () {
                    Provider.of<MusicProvider>(context, listen: false).playSong(song, aiSongs);
                  },
                )).toList(),
              ),
            ),
            const SizedBox(height: 32),
          ],
          
          // Recommendations
          if (recommendations.isNotEmpty) ...[
            const Text("Recommended for You", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: recommendations.map((rec) => ActionChip(
                label: Text(rec),
                backgroundColor: Colors.white.withOpacity(0.05),
                labelStyle: const TextStyle(color: Colors.white),
                onPressed: () => widget.onNavigate(2, rec), // Go to YouTube with query
              )).toList(),
            ),
            const SizedBox(height: 32),
          ],
          
          // Quick Actions
          const Text("Quick Actions", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.5,
            children: [
              _buildQuickAction('YouTube', Icons.play_arrow_rounded, Colors.red, () => widget.onNavigate(2)),
              _buildQuickAction('Upload', Icons.upload_file_rounded, Colors.blue, () => widget.onNavigate(3)),
              _buildQuickAction('Library', Icons.library_music_rounded, Colors.purple, () => widget.onNavigate(1)),
              // For Playlists we could add navigation to a playlists screen, but for now just navigate to Library
              _buildQuickAction('Playlists', Icons.queue_music_rounded, Colors.green, () => widget.onNavigate(1)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuickAction(String title, IconData icon, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: GlassContainer(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color),
            ),
            const Spacer(),
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}
