import React, { useState, useEffect, useRef } from 'react';
import { getSongs, recordPlay, getStreamUrl } from './api';
import Player from './Player';
import Upload from './Upload';
import YouTube from './YouTube';
import Home from './Home';

function App() {
  // Media State
  const videoRef = useRef(null);
  const [currentSong, setCurrentSong] = useState(null);
  const [songs, setSongs] = useState([]);
  const [isPlaying, setIsPlaying] = useState(false);
  const [progress, setProgress] = useState(0);
  const [duration, setDuration] = useState(0);
  const [volume, setVolume] = useState(0.8);

  // UI State
  const [view, setView] = useState('home');
  const [loading, setLoading] = useState(true);
  const [currentIndex, setCurrentIndex] = useState(0);
  const [youtubeQuery, setYoutubeQuery] = useState('');

  useEffect(() => {
    loadSongs();

    // WebSocket for real-time updates
    const ws = new WebSocket('ws://localhost:8000/ws');

    ws.onopen = () => {
      console.log('Connected to notification server');
    };

    ws.onmessage = (event) => {
      if (event.data === 'library_updated') {
        console.log('Library update received, refreshing...');
        loadSongs();
      }
    };

    ws.onerror = (error) => {
      console.error('WebSocket error:', error);
    };

    return () => {
      ws.close();
    };
  }, []);

  // --- Media Controls ---

  useEffect(() => {
    if (currentSong && videoRef.current) {
      // Auto-play when song changes
      videoRef.current.play()
        .then(() => setIsPlaying(true))
        .catch(e => console.error("Play error:", e));
    }
  }, [currentSong]);

  useEffect(() => {
    if (videoRef.current) {
      videoRef.current.volume = volume;
    }
  }, [volume]);

  const togglePlay = () => {
    if (videoRef.current) {
      if (isPlaying) {
        videoRef.current.pause();
      } else {
        videoRef.current.play();
      }
      setIsPlaying(!isPlaying);
    }
  };

  const handleTimeUpdate = () => {
    if (videoRef.current) {
      setProgress(videoRef.current.currentTime);
      setDuration(videoRef.current.duration || 0);
    }
  };

  const handleSeek = (time) => {
    if (videoRef.current) {
      videoRef.current.currentTime = time;
      setProgress(time);
    }
  };

  const handleNext = () => {
    if (songs.length === 0) return;
    const nextIdx = (currentIndex + 1) % songs.length;
    setCurrentIndex(nextIdx);
    setCurrentSong(songs[nextIdx]);
  };

  const handlePrev = () => {
    if (songs.length === 0) return;
    const prevIdx = currentIndex === 0 ? songs.length - 1 : currentIndex - 1;
    setCurrentIndex(prevIdx);
    setCurrentSong(songs[prevIdx]);
  };

  const handlePlaySong = async (song) => {
    if (currentSong?.id === song.id) {
      togglePlay();
      return;
    }
    setCurrentSong(song);
    const idx = songs.findIndex(s => s.id === song.id);
    if (idx >= 0) setCurrentIndex(idx);

    // Record play for history
    try {
      await recordPlay(song.id);
    } catch (err) {
      console.error('Failed to record play:', err);
    }
  };

  // --- Data Loading ---

  const loadSongs = async () => {
    try {
      const data = await getSongs();
      setSongs(data);
    } catch (error) {
      console.error("Error loading songs:", error);
    } finally {
      setLoading(false);
    }
  };

  const handleUploadComplete = () => {
    loadSongs();
    setView('nowplaying');
  };

  const handleNavigate = (viewId, query = '') => {
    setView(viewId);
    if (query) setYoutubeQuery(query);
  };

  const navItems = [
    { id: 'home', label: 'Home', icon: '🏠' },
    { id: 'nowplaying', label: 'Now Playing' },
    { id: 'playlist', label: 'Library' },
    { id: 'youtube', label: 'YouTube', icon: '🎬' },
    { id: 'upload', label: 'Upload' },
  ];

  // Determine Media URL
  // If song has video, request video stream. Otherwise audio.
  const mediaUrl = currentSong
    ? getStreamUrl(currentSong.id, currentSong.has_video ? 'video' : 'audio')
    : undefined;

  return (
    <div className="h-screen flex flex-col overflow-hidden bg-slate-900 text-white">
      {/* Top Navigation */}
      <nav className="glass-dark border-b border-white/5 px-8 py-4 flex items-center justify-between z-50">
        <div className="flex items-center gap-8">
          <span className="text-2xl font-bold bg-gradient-to-r from-pink-500 to-pink-400 bg-clip-text text-transparent">
            mPlay
          </span>
          <div className="flex items-center gap-6">
            {navItems.map(item => (
              <button
                key={item.id}
                onClick={() => handleNavigate(item.id)}
                className={`text-sm font-medium transition-all relative py-2
                  ${view === item.id
                    ? 'text-white'
                    : 'text-white/50 hover:text-white/80'
                  }`}
              >
                {item.label}
                {view === item.id && (
                  <span className="absolute bottom-0 left-0 right-0 h-0.5 bg-pink-500 rounded-full" />
                )}
              </button>
            ))}
          </div>
        </div>

        <div className="flex items-center gap-6">
          <div className="flex items-center gap-2 px-4 py-2 rounded-full bg-white/5 hover:bg-white/10 transition cursor-pointer">
            <svg className="w-4 h-4 text-white/50" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z" />
            </svg>
            <span className="text-sm text-white/50">Search</span>
          </div>
          <div className="w-10 h-10 rounded-full bg-gradient-to-br from-pink-500 to-purple-600 flex items-center justify-center">
            <span className="text-sm font-medium">U</span>
          </div>
        </div>
      </nav>

      {/* Main Content Area - Stacked for persistence */}
      <div className="flex-1 flex flex-col overflow-hidden relative group">

        {/* Persistent Video Element */}
        {/* Situated in background, visible only when logic dictates */}
        <div className={`absolute inset-0 z-0 bg-black flex items-center justify-center transition-opacity duration-500
            ${view === 'nowplaying' && currentSong?.has_video ? 'opacity-100' : 'opacity-0 pointer-events-none'}`}>
          <video
            ref={videoRef}
            src={mediaUrl}
            className="w-full h-full object-contain"
            onTimeUpdate={handleTimeUpdate}
            onEnded={handleNext}
            onLoadedMetadata={() => setDuration(videoRef.current?.duration || 0)}
            playsInline
          />
        </div>

        {/* Content Layers */}
        <div className="relative z-10 flex-1 overflow-hidden flex flex-col">
          {view === 'home' && <Home onPlaySong={handlePlaySong} onNavigate={handleNavigate} />}
          {view === 'youtube' && <YouTube onDownloadComplete={handleUploadComplete} initialQuery={youtubeQuery} />}
          {view === 'upload' && <Upload onUploadComplete={handleUploadComplete} />}

          {view === 'playlist' && (
            <div className="h-full flex-1 overflow-y-auto p-8">
              <div className="max-w-4xl mx-auto">
                <h1 className="text-3xl font-bold mb-8 animate-fade-in">Your Library</h1>
                {loading ? (
                  <div className="flex items-center justify-center py-20">
                    <div className="w-12 h-12 rounded-full border-4 border-pink-500/30 border-t-pink-500 animate-spin" />
                  </div>
                ) : songs.length === 0 ? (
                  <div className="text-center py-20 animate-fade-in">
                    <div className="w-24 h-24 mx-auto mb-6 rounded-full bg-white/5 flex items-center justify-center">
                      <svg className="w-12 h-12 text-white/20" fill="currentColor" viewBox="0 0 24 24">
                        <path d="M12 3v10.55c-.59-.34-1.27-.55-2-.55-2.21 0-4 1.79-4 4s1.79 4 4 4 4-1.79 4-4V7h4V3h-6z" />
                      </svg>
                    </div>
                    <p className="text-xl text-white/40 mb-4">No songs yet</p>
                    <button onClick={() => handleNavigate('upload')} className="btn-primary">
                      Upload Music
                    </button>
                  </div>
                ) : (
                  <div className="space-y-2">
                    {songs.map((song, index) => (
                      <div
                        key={song.id}
                        className={`song-item flex items-center gap-4 p-4 rounded-xl cursor-pointer animate-fade-in
                            ${currentSong?.id === song.id ? 'bg-pink-500/10 border border-pink-500/20' : 'hover:bg-white/5'}`}
                        style={{ animationDelay: `${index * 0.05}s` }}
                        onClick={() => handlePlaySong(song)}
                      >
                        <div className="w-14 h-14 rounded-lg bg-gradient-to-br from-pink-500/20 to-purple-600/20 flex items-center justify-center flex-shrink-0">
                          {currentSong?.id === song.id ? (
                            <div className="flex items-end gap-0.5 h-5">
                              {[...Array(3)].map((_, i) => (
                                <div key={i} className="w-1 bg-pink-500 rounded-full visualizer-bar" style={{ animationDelay: `${i * 0.1}s` }} />
                              ))}
                            </div>
                          ) : (
                            <span className="text-white/40">{index + 1}</span>
                          )}
                        </div>
                        <div className="flex-1 min-w-0">
                          <p className="font-semibold truncate">{song.title || "Unknown"}</p>
                          <p className="text-sm text-white/50 truncate">{song.artist || "Unknown Artist"}</p>
                        </div>
                        <span className="text-sm text-white/40">{song.album || ""}</span>
                        <span className="text-sm text-white/40 w-16 text-right">
                          {song.duration ? `${Math.floor(song.duration / 60)}:${(song.duration % 60).toString().padStart(2, '0')}` : "—"}
                        </span>
                      </div>
                    ))}
                  </div>
                )}
              </div>
            </div>
          )}

          {/* Now Playing - using shared state */}
          {view === 'nowplaying' && (
            <Player
              currentSong={currentSong}
              playlist={songs}
              isPlaying={isPlaying}
              progress={progress}
              duration={duration}
              volume={volume}
              onTogglePlay={togglePlay}
              onSeek={handleSeek}
              onVolumeChange={setVolume}
              onNext={handleNext}
              onPrev={handlePrev}
              onSelectSong={handlePlaySong}
              fullView={true}
            />
          )}
        </div>
      </div>

      {/* Persistent Player Bar - Always visible at bottom */}
      <Player
        currentSong={currentSong}
        playlist={songs}
        isPlaying={isPlaying}
        progress={progress}
        duration={duration}
        volume={volume}
        onTogglePlay={togglePlay}
        onSeek={handleSeek}
        onVolumeChange={setVolume}
        onNext={handleNext}
        onPrev={handlePrev}
        onSelectSong={handlePlaySong}
        miniBar={true}
      />
    </div>
  );
}

export default App;
