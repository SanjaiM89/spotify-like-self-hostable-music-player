import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:chewie/chewie.dart';
import 'package:video_player/video_player.dart';
import '../providers/video_provider.dart';
import '../music_provider.dart';
import '../constants.dart';
import '../screens/unified_player_screen.dart';

class VideoOverlay extends StatelessWidget {
  const VideoOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<VideoProvider>(
      builder: (context, provider, child) {
        if (provider.currentVideo == null) return const SizedBox.shrink();

        final size = MediaQuery.of(context).size;
        final isMinimized = provider.isMinimized;

        // Dimensions for mini player
        final double miniHeight = 80;
        // final double miniWidth = size.width; 
        
        final double height = isMinimized ? miniHeight : size.height;
        // final double width = size.width;
        
        return AnimatedPositioned(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          top: isMinimized ? size.height - 140 : 0, 
          left: 0,
          right: 0,
          height: height,
          child: Material(
            elevation: isMinimized ? 8 : 0,
            color: Colors.black,
            child: isMinimized 
               ? _buildMiniPlayer(context, provider)
               : _buildFullScreenPlayer(context, provider),
          ),
        );
      },
    );
  }

  Widget _buildFullScreenPlayer(BuildContext context, VideoProvider provider) {
    // Mimic the old VideoPlayerScreen layout
    final song = provider.currentVideo!;
    
    return SafeArea(
      child: Column(
        children: [
          // Drag handle to minimize (optional, but good UX)
          GestureDetector(
             onVerticalDragEnd: (details) {
               if (details.primaryVelocity! > 300) {
                 provider.minimize();
               }
             },
             child: Container(
               height: 24,
               width: double.infinity,
               color: Colors.black,
               child: Center(
                 child: Container(
                   width: 40, 
                   height: 4, 
                   decoration: BoxDecoration(
                     color: Colors.white24,
                     borderRadius: BorderRadius.circular(2),
                   ),
                 ),
               ),
             ),
          ),
          
          // Video Player Area
          AspectRatio(
             aspectRatio: 16 / 9,
             child: Stack(
               children: [
                 if (provider.chewieController != null && provider.videoPlayerController!.value.isInitialized)
                   Chewie(controller: provider.chewieController!)
                 else
                   const Center(child: CircularProgressIndicator()),
                   
                   // Back Button Overlay (to minimize)
                  Positioned(
                    top: 10,
                    left: 10,
                    child: CircleAvatar(
                      backgroundColor: Colors.black45,
                      child: IconButton(
                        icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white),
                        onPressed: () => provider.minimize(),
                      ),
                    ),
                  ),
               ],
             ),
          ),
          
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                   const SizedBox(height: 16),
                   // Title & Info
                   Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          song.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          song.artist,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  
                  // Recommendations
                  if (provider.recommendations.isNotEmpty) ...[
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        "Up Next",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: provider.recommendations.length,
                      itemBuilder: (context, index) {
                        final rec = provider.recommendations[index];
                        final thumbUrl = rec.thumbnail ?? rec.coverArt;
                        
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                          leading: Container(
                            width: 80,
                            height: 50,
                            decoration: BoxDecoration(
                              color: Colors.white12,
                              borderRadius: BorderRadius.circular(4),
                              image: thumbUrl != null ? DecorationImage(
                                image: NetworkImage(thumbUrl),
                                fit: BoxFit.cover,
                              ) : null,
                            ),
                            child: thumbUrl == null 
                              ? const Icon(Icons.play_arrow, color: Colors.white54)
                              : null,
                          ),
                          title: Text(
                            rec.title,
                            style: const TextStyle(color: Colors.white, fontSize: 14),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            rec.artist,
                            style: const TextStyle(color: Colors.white54, fontSize: 12),
                          ),
                          trailing: rec.isVideo 
                            ? const Icon(Icons.videocam, color: Colors.white54, size: 16)
                            : const Icon(Icons.music_note, color: Colors.white54, size: 16),
                          onTap: () => provider.playVideo(rec),
                        );
                      },
                    ),
                    // Add extra padding at bottom to ensure last item is visible above status bar/nav bar
                    const SizedBox(height: 80),
                  ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniPlayer(BuildContext context, VideoProvider provider) {
    final song = provider.currentVideo!;
    
    void openUnifiedPlayer() {
      // Get current position before closing
      Duration? position;
      if (provider.videoPlayerController != null && 
          provider.videoPlayerController!.value.isInitialized) {
        position = provider.videoPlayerController!.value.position;
      }
      
      // Close video provider
      provider.close();
      
      // Navigate to UnifiedPlayerScreen in video mode
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => UnifiedPlayerScreen(
            song: song, 
            startWithVideo: true,
            // Note: We can't easily pass position to UnifiedPlayerScreen
            // without modifying its constructor. For now, it starts from beginning.
          ),
          fullscreenDialog: true,
        ),
      );
    }
    
    return GestureDetector(
      onTap: openUnifiedPlayer,
      onVerticalDragEnd: (details) {
         if (details.primaryVelocity! < -300) {
           openUnifiedPlayer();
         }
      },
      child: Container(
        color: const Color(0xFF1E1E1E),
        padding: const EdgeInsets.all(4.0),
        child: Row(
          children: [
            // Mini Video View
            SizedBox(
              width: 120,
              height: 72,
              child: provider.videoPlayerController != null && provider.videoPlayerController!.value.isInitialized
                  ? AspectRatio(
                      aspectRatio: provider.videoPlayerController!.value.aspectRatio,
                      child: VideoPlayer(provider.videoPlayerController!),
                    )
                  : const Center(child: CircularProgressIndicator(strokeWidth: 2)),
            ),
            const SizedBox(width: 8),
            // Title
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    song.title,
                    style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    song.artist,
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            // Controls
            IconButton(
              icon: Icon(
                provider.videoPlayerController != null && provider.videoPlayerController!.value.isPlaying 
                  ? Icons.pause 
                  : Icons.play_arrow,
                color: Colors.white,
              ),
              onPressed: () {
                if (provider.videoPlayerController!.value.isPlaying) {
                  provider.videoPlayerController!.pause();
                } else {
                  provider.videoPlayerController!.play();
                }
                // Force rebuild to update icon
                provider.refresh(); 
              },
            ),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: () {
                final musicProvider = Provider.of<MusicProvider>(context, listen: false);
                provider.closeAndSwitchToAudio(musicProvider);
              },
            ),
          ],
        ),
      ),
    );
  }
}
