import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../api_service.dart';
import '../models.dart';
import '../music_provider.dart';
import '../widgets/glass_container.dart';
import '../constants.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'video_player_screen.dart';

class YouTubeScreen extends StatefulWidget {
  final String? initialQuery;
  const YouTubeScreen({super.key, this.initialQuery});

  @override
  State<YouTubeScreen> createState() => _YouTubeScreenState();
}

class _YouTubeScreenState extends State<YouTubeScreen> {
  final TextEditingController _urlController = TextEditingController();
  List<YouTubeTask> _tasks = [];
  bool _loading = false;
  Timer? _pollTimer;
  WebSocketChannel? _wsChannel;
  StreamSubscription? _wsSubscription;

  @override
  void initState() {
    super.initState();
    _handleInitialQuery();
    _loadTasks();
    _startPolling();
    _connectWebSocket();
  }

  void _connectWebSocket() {
    try {
      _wsChannel = WebSocketChannel.connect(Uri.parse(wsUrl));
      _wsSubscription = _wsChannel!.stream.listen((message) {
        try {
          final data = jsonDecode(message);
          if (data is Map<String, dynamic> && data['event'] == 'task_update') {
            final taskData = data['data'];
            if (taskData != null && mounted) {
              _updateTask(YouTubeTask.fromJson(taskData));
            }
          }
        } catch (e) {
          // Ignore parse errors
        }
      }, onError: (e) {
        print('YouTubeScreen WS Error: $e');
      }, onDone: () {
        // Reconnect after 3s
        Future.delayed(const Duration(seconds: 3), _connectWebSocket);
      });
    } catch (e) {
      print('YouTubeScreen WS Connection Failed: $e');
    }
  }

  void _updateTask(YouTubeTask updatedTask) {
    setState(() {
      final index = _tasks.indexWhere((t) => t.taskId == updatedTask.taskId);
      if (index != -1) {
        _tasks[index] = updatedTask;
      } else {
        _tasks.insert(0, updatedTask);
      }
    });
  }

  @override
  void didUpdateWidget(YouTubeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialQuery != oldWidget.initialQuery && widget.initialQuery != null) {
      _handleInitialQuery();
    }
  }

  void _handleInitialQuery() {
    if (widget.initialQuery != null && widget.initialQuery!.isNotEmpty) {
      String q = widget.initialQuery!;
      // Simple play/url check
      if (!q.startsWith('http') && !q.startsWith('www.') && !q.startsWith('ytsearch')) {
        q = 'ytsearch1:$q';
      }
      _urlController.text = q;
    }
  }

  bool _isPolling = false;

  void _startPolling() {
    // Reduced frequency since we have WebSocket now
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      // Only poll if there are non-terminal tasks and not currently polling
      if (!_isPolling && _tasks.any((t) => ['pending', 'downloading', 'processing', 'uploading', 'converting', 'fetching_info'].contains(t.status))) {
        await _loadTasks();
      }
    });
  }

  Future<void> _loadTasks() async {
    if (_isPolling) return;
    _isPolling = true;
    try {
      final tasks = await ApiService.getYoutubeTasks(limit: 50);
      if (mounted) {
        setState(() {
          _tasks = tasks;
        });
      }
    } catch (e) {
      print("Error loading tasks: $e");
    } finally {
      _isPolling = false;
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _wsSubscription?.cancel();
    _wsChannel?.sink.close();
    _urlController.dispose();
    super.dispose();
  }

  String _selectedFormat = 'Audio'; // Audio, Video
  String _selectedQuality = '320'; // 320 for audio, best for video
  
  void _showDownloadOptions() {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;
    
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border(top: BorderSide(color: Colors.white.withOpacity(0.1))),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Download Options", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: _buildOptionCard(
                    icon: Icons.music_note, 
                    title: "Audio", 
                    selected: _selectedFormat == 'Audio',
                    onTap: () => setState(() {
                      _selectedFormat = 'Audio'; 
                      _selectedQuality = '320';
                      Navigator.pop(ctx);
                      _showDownloadOptions();
                    })
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildOptionCard(
                    icon: Icons.videocam, 
                    title: "Video", 
                    selected: _selectedFormat == 'Video',
                    onTap: () => setState(() {
                      _selectedFormat = 'Video';
                      _selectedQuality = 'best'; // Default for video
                      Navigator.pop(ctx);
                      _showDownloadOptions();
                    })
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Text("Quality: $_selectedQuality", style: const TextStyle(color: Colors.white54)),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: (_selectedFormat == 'Audio' 
                  ? ['320', '256', '128', 'm4a'] 
                  : ['best', '1080p', '720p', '480p'])
                  .map((q) => Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(q),
                      selected: _selectedQuality == q,
                      onSelected: (s) => setState(() {
                         _selectedQuality = q;
                         Navigator.pop(ctx);
                         _showDownloadOptions();
                      }),
                      backgroundColor: Colors.white10,
                      selectedColor: kPrimaryColor,
                      labelStyle: TextStyle(color: _selectedQuality == q ? Colors.white : Colors.white70),
                    ),
                  )).toList(),
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _submitDownload();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: kPrimaryColor,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text("Start Download", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOptionCard({required IconData icon, required String title, required bool selected, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: selected ? kPrimaryColor.withOpacity(0.2) : Colors.white.withOpacity(0.05),
          border: Border.all(color: selected ? kPrimaryColor : Colors.transparent),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(icon, color: selected ? kPrimaryColor : Colors.white54, size: 32),
            const SizedBox(height: 8),
            Text(title, style: TextStyle(color: selected ? Colors.white : Colors.white54, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Future<void> _submitDownload() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;

    setState(() => _loading = true);
    try {
      await ApiService.submitYoutubeUrl(url, _selectedQuality); 
      _urlController.clear();
      _loadTasks(); // Immediate refresh
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Starting $_selectedFormat download ($_selectedQuality)...')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
           Container(
            padding: const EdgeInsets.fromLTRB(16, 60, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("YouTube Downloader", style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                    if (_tasks.isNotEmpty)
                      TextButton.icon(
                        onPressed: () async {
                          await ApiService.clearAllYoutubeTasks();
                          _loadTasks();
                        },
                        icon: const Icon(Icons.delete_sweep, size: 18),
                        label: const Text("Clear All"),
                        style: TextButton.styleFrom(foregroundColor: Colors.white54),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _urlController,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: "Paste YouTube Link",
                          hintStyle: const TextStyle(color: Colors.white38),
                          filled: true,
                          fillColor: Colors.white.withOpacity(0.05),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: _loading ? null : _showDownloadOptions,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(colors: [kPrimaryColor, kSecondaryColor]),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: _loading 
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                            : const Icon(Icons.download_rounded, color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
              itemCount: _tasks.length,
              itemBuilder: (context, index) {
                final task = _tasks[index];
                return _buildTaskItem(task);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTaskItem(YouTubeTask task) {
    Color statusColor = Colors.white54;
    IconData statusIcon = Icons.schedule;
    bool isUploading = task.status == 'uploading';
    
    switch (task.status) {
      case 'completed':
        statusColor = Colors.green;
        statusIcon = Icons.check_circle;
        break;
      case 'failed':
        statusColor = Colors.red;
        statusIcon = Icons.error;
        break;
      case 'downloading':
        statusColor = Colors.blue;
        statusIcon = Icons.download_rounded;
        break;
      case 'processing':
      case 'converting':
        statusColor = Colors.orange;
        statusIcon = Icons.cached;
        break;
      case 'uploading':
        statusColor = Colors.purpleAccent;
        statusIcon = Icons.cloud_upload_rounded;
        break;
    }

    String _formatBytes(int bytes) {
      if (bytes <= 0) return "0 B";
      const suffixes = ["B", "KiB", "MiB", "GiB", "TiB"];
      var i = 0;
      double size = bytes.toDouble();
      while (size >= 1024 && i < suffixes.length - 1) {
        size /= 1024;
        i++;
      }
      return "${size.toStringAsFixed(2)}${suffixes[i]}";
    }

    String statsLine = "";
    if (['downloading', 'uploading'].contains(task.status)) {
       String total = task.totalBytes != null ? _formatBytes(task.totalBytes!) : "?";
       String speed = task.speed ?? "0 B/s";
       String eta = task.eta ?? "--:--";
       statsLine = "${task.progress.toStringAsFixed(1)}% of $total at $speed ETA $eta";
    } else if (task.status == 'processing' || task.status == 'converting') {
       statsLine = "Processing...";
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: GlassContainer(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(statusIcon, color: statusColor, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task.title ?? task.url,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (statsLine.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4.0),
                          child: Text(
                            statsLine, 
                            style: const TextStyle(color: Colors.white70, fontSize: 11)
                          ),
                        ),
                    ],
                  ),
                ),
                if (!['completed', 'failed', 'cancelled'].contains(task.status))
                  IconButton(
                    icon: const Icon(Icons.cancel, color: Colors.white38, size: 20),
                    onPressed: () => ApiService.cancelYoutubeTask(task.taskId),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (['downloading', 'uploading', 'processing', 'converting'].contains(task.status)) ...[
              LinearProgressIndicator(
                value: task.progress / 100,
                backgroundColor: Colors.white10,
                color: statusColor,
                minHeight: 4,
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                   Row(
                     children: [
                       Icon(
                         isUploading ? Icons.cloud_upload : Icons.download, 
                         size: 12, 
                         color: statusColor
                       ),
                       const SizedBox(width: 4),
                       Text(
                         isUploading ? "Uploading to Telegram" : (task.status == 'processing' ? "Converting" : "Downloading"),
                         style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.bold)
                       ),
                     ],
                   ),
                   if (task.totalBytes != null && task.downloadedBytes != null && task.totalBytes! > 0)
                     Text(
                       "${(task.downloadedBytes!/task.totalBytes!*100).toStringAsFixed(0)}%", 
                       style: const TextStyle(color: Colors.white54, fontSize: 10)
                     ),
                ],
              )
            ] else if (task.status == 'completed') ...[
              // Completed - show play button
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    "Ready to play",
                    style: TextStyle(color: Colors.green, fontSize: 12),
                  ),
                  // Play button
                  GestureDetector(
                    onTap: () => _playCompletedTask(task),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [kPrimaryColor, kSecondaryColor]),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.play_arrow, color: Colors.white, size: 16),
                          SizedBox(width: 4),
                          Text("Play", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ] else 
              Text(
                task.status == 'failed' ? "Error: ${task.error}" : "Ready",
                style: TextStyle(color: statusColor, fontSize: 12),
              ),
          ],
        ),
      ),
    );
  }

  void _playCompletedTask(YouTubeTask task) {
    // Get song_id from task and navigate to player
    if (task.songId == null) {
      print("No song_id for task ${task.taskId}");
      return;
    }
    
    final isVideo = task.mediaType == 'video';
    
    if (isVideo) {
      // Navigate to video player - create a Song object from task data
      final song = Song(
        id: task.songId!,
        title: task.title ?? 'Video',
        artist: 'YouTube',
        album: '',
        duration: 0,
        fileName: '${task.title}.mp4',
      );
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => VideoPlayerScreen(song: song),
        ),
      );
    } else {
      // Play audio using MusicProvider
      _playSongById(task.songId);
    }
  }

  Future<void> _playSongById(String? songId) async {
    if (songId == null) return;
    try {
      final songs = await ApiService.getSongs();
      final song = songs.firstWhere((s) => s.id == songId, orElse: () => songs.first);
      if (mounted) {
        Provider.of<MusicProvider>(context, listen: false).playSong(song, songs);
      }
    } catch (e) {
      print("Error playing song: $e");
    }
  }
}
