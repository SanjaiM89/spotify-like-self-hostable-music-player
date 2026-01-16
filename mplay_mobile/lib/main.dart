import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'constants.dart';
import 'music_provider.dart';
import 'screens/home_screen.dart';
import 'screens/library_screen.dart';
import 'screens/youtube_screen.dart';
import 'screens/upload_screen.dart';
import 'websocket_service.dart';
import 'widgets/mini_player.dart';

Future<void> main() async {
  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.ryanheise.bg_demo.channel.audio',
    androidNotificationChannelName: 'Audio playback',
    androidNotificationOngoing: true,
  );
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => MusicProvider()),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'mPlay Mobile',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: kBackgroundColor,
        primaryColor: kPrimaryColor,
        textTheme: () {
          final base = GoogleFonts.outfitTextTheme(Theme.of(context).textTheme);
          // Include common Tamil fonts as fallback
          const fallback = ['Noto Sans Tamil', 'Latha', 'Vijaya', '.SF NS', 'Roboto'];
          
          TextStyle withFallback(TextStyle? style) => (style ?? const TextStyle()).copyWith(fontFamilyFallback: fallback);
          
          return base.copyWith(
            displayLarge: withFallback(base.displayLarge),
            displayMedium: withFallback(base.displayMedium),
            displaySmall: withFallback(base.displaySmall),
            headlineLarge: withFallback(base.headlineLarge),
            headlineMedium: withFallback(base.headlineMedium),
            headlineSmall: withFallback(base.headlineSmall),
            titleLarge: withFallback(base.titleLarge),
            titleMedium: withFallback(base.titleMedium),
            titleSmall: withFallback(base.titleSmall),
            bodyLarge: withFallback(base.bodyLarge),
            bodyMedium: withFallback(base.bodyMedium),
            bodySmall: withFallback(base.bodySmall),
            labelLarge: withFallback(base.labelLarge),
            labelMedium: withFallback(base.labelMedium),
            labelSmall: withFallback(base.labelSmall),
          ).apply(
            bodyColor: Colors.white,
            displayColor: Colors.white,
          );
        }(),
        colorScheme: ColorScheme.fromSeed(
          seedColor: kPrimaryColor,
          brightness: Brightness.dark,
          secondary: kSecondaryColor,
        ),
      ),
      home: const MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;
  String? _youtubeQuery;
  late WebSocketService _wsService;
  
  // Pages key to force refresh on WS update
  Key _libraryKey = UniqueKey();
  Key _homeKey = UniqueKey();

  final List<Widget> _pages = [];

  @override
  void initState() {
    super.initState();
    _wsService = WebSocketService();
    _wsService.connect();
    
    // Listen for library updates
    _wsService.onLibraryUpdate = (data) {
      print("WS Library Update Received: Refreshing views");
      setState(() {
        _libraryKey = UniqueKey();
        _homeKey = UniqueKey();
      });
    };
    
    // Task updates are handled by YouTubeScreen directly via a stream
    _wsService.onMessage = (msg) {
      // Backwards compatibility - string events
      if (msg == 'library_updated' || msg == 'song_added') {
        print("WS Update Received: Refreshing views");
        setState(() {
          _libraryKey = UniqueKey();
          _homeKey = UniqueKey();
        });
      }
    };
  }
  
  WebSocketService get wsService => _wsService;

  void _handleNavigation(int index, [String? query]) {
    setState(() {
      _selectedIndex = index;
      if (query != null) {
        _youtubeQuery = query;
      }
    });
  }

  @override
  void dispose() {
    _wsService.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Rebuild pages when keys change
    final pages = [
      HomeScreen(key: _homeKey, onNavigate: _handleNavigation),
      LibraryScreen(key: _libraryKey),
      YouTubeScreen(initialQuery: _youtubeQuery),
      const UploadScreen(),
    ];

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              kBackgroundColor,
              Color(0xFF020617), // Darker shade
            ],
          ),
        ),
        child: Stack(
          children: [
            IndexedStack(
              index: _selectedIndex,
              children: pages,
            ),
          // We can put the miniplayer here, aligned to bottom
          Positioned(
            left: 0, 
            right: 0, 
            bottom: 0, 
            child: Consumer<MusicProvider>(
              builder: (context, music, child) {
                if (music.currentSong == null) return const SizedBox.shrink();
                return MiniPlayer();
              },
            ),
          ),
          ],
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) => setState(() => _selectedIndex = index),
        type: BottomNavigationBarType.fixed,
        backgroundColor: Colors.black.withOpacity(0.5),
        selectedItemColor: kPrimaryColor,
        unselectedItemColor: Colors.white38,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home_rounded), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.library_music_rounded), label: 'Library'),
          BottomNavigationBarItem(icon: Icon(Icons.play_circle_fill_rounded), label: 'YouTube'),
          BottomNavigationBarItem(icon: Icon(Icons.upload_file_rounded), label: 'Upload'),
        ],
      ),
    );
  }
}
