import React from 'react';

const Player = ({
    currentSong,
    playlist = [],
    isPlaying,
    progress,
    duration,
    volume,
    onTogglePlay,
    onNext,
    onPrev,
    onSeek,
    onVolumeChange,
    onSelectSong,
    miniBar = false,
    fullView = false
}) => {

    const formatTime = (seconds) => {
        if (!seconds || isNaN(seconds)) return "0:00";
        const m = Math.floor(seconds / 60);
        const s = Math.floor(seconds % 60);
        return `${m}:${s < 10 ? '0' : ''}${s}`;
    };

    const progressPercent = duration > 0 ? (progress / duration) * 100 : 0;

    // Mini bar mode - just the bottom player controls
    if (miniBar) {
        return (
            <>
                {/* Bottom Player Bar */}
                <div className="h-24 glass border-t border-white/10 flex items-center px-6 gap-6 z-40 relative">
                    {/* Left - Song Info */}
                    <div className="flex items-center gap-4 w-64 flex-shrink-0">
                        {currentSong ? (
                            <>
                                <div className={`w-14 h-14 rounded-lg bg-gradient-to-br from-pink-500/30 to-purple-600/30 flex items-center justify-center ${isPlaying ? 'animate-spin-slow' : ''}`}>
                                    {currentSong.cover_art ? (
                                        <img src={currentSong.cover_art} alt="" className="w-full h-full object-cover rounded-lg" />
                                    ) : (
                                        <svg className="w-7 h-7 text-white/60" fill="currentColor" viewBox="0 0 24 24">
                                            <path d="M12 3v10.55c-.59-.34-1.27-.55-2-.55-2.21 0-4 1.79-4 4s1.79 4 4 4 4-1.79 4-4V7h4V3h-6z" />
                                        </svg>
                                    )}
                                </div>
                                <div className="flex-1 min-w-0">
                                    <p className="font-semibold truncate text-sm">{currentSong.title}</p>
                                    <p className="text-xs text-white/50 truncate">{currentSong.artist}</p>
                                </div>
                            </>
                        ) : (
                            <div className="text-white/30 text-sm">No song selected</div>
                        )}
                    </div>

                    {/* Center - Progress Bar */}
                    <div className="flex-1 flex items-center gap-3">
                        <span className="text-xs text-white/40 w-10 text-right">{formatTime(progress)}</span>
                        <div className="flex-1 relative h-1 bg-white/10 rounded-full overflow-hidden">
                            <div
                                className="absolute left-0 top-0 h-full bg-gradient-to-r from-pink-500 to-pink-400 rounded-full transition-all"
                                style={{ width: `${progressPercent}%` }}
                            />
                            <input
                                type="range"
                                min="0"
                                max={duration || 100}
                                value={progress}
                                onChange={(e) => onSeek(parseFloat(e.target.value))}
                                className="absolute inset-0 w-full opacity-0 cursor-pointer"
                                disabled={!currentSong}
                            />
                        </div>
                        <span className="text-xs text-white/40 w-10">{formatTime(duration)}</span>
                    </div>

                    {/* Right - Controls & Volume */}
                    <div className="flex items-center gap-4 flex-shrink-0">
                        <button onClick={onPrev} className="control-btn control-btn-secondary w-10 h-10" disabled={!currentSong}>
                            <svg className="w-4 h-4" fill="currentColor" viewBox="0 0 24 24">
                                <path d="M6 6h2v12H6V6zm3.5 6 8.5 6V6l-8.5 6z" />
                            </svg>
                        </button>
                        <button
                            onClick={onTogglePlay}
                            className="control-btn control-btn-primary w-12 h-12"
                            disabled={!currentSong}
                        >
                            {isPlaying ? (
                                <svg className="w-5 h-5" fill="currentColor" viewBox="0 0 24 24">
                                    <path d="M6 19h4V5H6v14zm8-14v14h4V5h-4z" />
                                </svg>
                            ) : (
                                <svg className="w-5 h-5 ml-0.5" fill="currentColor" viewBox="0 0 24 24">
                                    <path d="M8 5v14l11-7z" />
                                </svg>
                            )}
                        </button>
                        <button onClick={onNext} className="control-btn control-btn-secondary w-10 h-10" disabled={!currentSong}>
                            <svg className="w-4 h-4" fill="currentColor" viewBox="0 0 24 24">
                                <path d="M6 18l8.5-6L6 6v12zm2 0h2V6h-2v12z" transform="scale(-1, 1) translate(-24, 0)" />
                            </svg>
                        </button>

                        {/* Volume */}
                        <div className="flex items-center gap-2 ml-4">
                            <button
                                className="text-white/40 hover:text-white transition"
                                onClick={() => onVolumeChange(volume > 0 ? 0 : 0.8)}
                            >
                                {volume === 0 ? (
                                    <svg className="w-5 h-5" fill="currentColor" viewBox="0 0 24 24">
                                        <path d="M16.5 12c0-1.77-1.02-3.29-2.5-4.03v2.21l2.45 2.45c.03-.2.05-.41.05-.63zm2.5 0c0 .94-.2 1.82-.54 2.64l1.51 1.51C20.63 14.91 21 13.5 21 12c0-4.28-2.99-7.86-7-8.77v2.06c2.89.86 5 3.54 5 6.71zM4.27 3L3 4.27 7.73 9H3v6h4l5 5v-6.73l4.25 4.25c-.67.52-1.42.93-2.25 1.18v2.06c1.38-.31 2.63-.95 3.69-1.81L19.73 21 21 19.73l-9-9L4.27 3zM12 4L9.91 6.09 12 8.18V4z" />
                                    </svg>
                                ) : (
                                    <svg className="w-5 h-5" fill="currentColor" viewBox="0 0 24 24">
                                        <path d="M3 9v6h4l5 5V4L7 9H3zm13.5 3c0-1.77-1.02-3.29-2.5-4.03v8.05c1.48-.73 2.5-2.25 2.5-4.02zM14 3.23v2.06c2.89.86 5 3.54 5 6.71s-2.11 5.85-5 6.71v2.06c4.01-.91 7-4.49 7-8.77s-2.99-7.86-7-8.77z" />
                                    </svg>
                                )}
                            </button>
                            <input
                                type="range"
                                min="0"
                                max="1"
                                step="0.01"
                                value={volume}
                                onChange={(e) => onVolumeChange(parseFloat(e.target.value))}
                                className="w-20"
                            />
                        </div>
                    </div>
                </div>
            </>
        );
    }

    // Full view mode - the complete Now Playing page
    return (
        <>
            {/* Main Content Area with Visualizer */}
            <div className="flex-1 flex">
                {/* Main Now Playing Area - Content Centered */}
                <div className="flex-1 flex flex-col items-center justify-center pb-8 relative overflow-hidden">

                    {/* VIDEO CONTAINER - The actual video element is in App.jsx but we need space for it */}
                    {/* If song has video, it will overlay here. If audio only, we show art */}

                    {/* Background blur from album art - Always show as fallback/background */}
                    <div
                        className="absolute inset-0 bg-cover bg-center opacity-30 blur-3xl scale-150"
                        style={{
                            backgroundImage: currentSong?.cover_art
                                ? `url(${currentSong.cover_art})`
                                : 'linear-gradient(135deg, #ec4899 0%, #9333ea 50%, #1a1a2e 100%)'
                        }}
                    />

                    {/* Album Art - Only show if NO video or implicitly handled by App.jsx video overlay z-index */}
                    {/* We will let App.jsx handle the Video on top. This Art stays here. */}
                    <div className={`relative z-10 mb-6 ${isPlaying && !currentSong?.has_video ? 'animate-spin-slow' : ''}`}>
                        {/* Only show vinyl art if NOT video mode? Or let video cover it? 
                             Let's keep it simple: Art is always here. Video covers if present. */}
                        <div className="w-44 h-44 rounded-full bg-gradient-to-br from-pink-500/30 to-purple-600/30 flex items-center justify-center shadow-2xl shadow-pink-500/20 border-4 border-white/10">
                            {currentSong?.cover_art ? (
                                <img
                                    src={currentSong.cover_art}
                                    alt="Album Art"
                                    className="w-full h-full rounded-full object-cover"
                                />
                            ) : (
                                <div className="w-full h-full rounded-full bg-gradient-to-br from-slate-800 to-slate-900 flex items-center justify-center">
                                    <svg className={`w-16 h-16 text-pink-500/60 ${!currentSong ? 'animate-pulse' : ''}`} fill="currentColor" viewBox="0 0 24 24">
                                        <path d="M12 3v10.55c-.59-.34-1.27-.55-2-.55-2.21 0-4 1.79-4 4s1.79 4 4 4 4-1.79 4-4V7h4V3h-6z" />
                                    </svg>
                                </div>
                            )}
                        </div>
                        {/* Vinyl record inner ring */}
                        <div className="absolute inset-0 rounded-full border-4 border-white/5 pointer-events-none" />
                        <div className="absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 w-10 h-10 rounded-full bg-slate-900/80 border-2 border-white/10 pointer-events-none" />
                    </div>

                    {/* Visualizer - Audio Only */}
                    {isPlaying && currentSong && !currentSong.has_video && (
                        <div className="flex items-end justify-center gap-1 h-12 mb-4 z-10">
                            {[...Array(25)].map((_, i) => (
                                <div
                                    key={i}
                                    className="w-1 bg-gradient-to-t from-pink-500 to-purple-400 rounded-full visualizer-bar"
                                    style={{
                                        animationDelay: `${Math.random() * 0.5}s`,
                                        animationDuration: `${0.3 + Math.random() * 0.3}s`
                                    }}
                                />
                            ))}
                        </div>
                    )}

                    {/* Song Info */}
                    {currentSong ? (
                        <div className="text-center z-10 animate-fade-in relative">
                            {/* Gradient background for text readability over video */}
                            <div className="absolute inset-0 bg-black/40 blur-xl -z-10 rounded-full transform scale-150" />
                            <h1 className="text-2xl font-bold mb-1 bg-gradient-to-r from-white to-white/80 bg-clip-text text-transparent drop-shadow-md">{currentSong.title || "Unknown Title"}</h1>
                            <p className="text-base text-white/80 drop-shadow-md">{currentSong.artist || "Unknown Artist"}</p>
                        </div>
                    ) : (
                        <div className="text-center z-10">
                            <h1 className="text-xl font-semibold text-white/50 mb-1">No song playing</h1>
                            <p className="text-white/30 text-sm">Click a song from the queue to start →</p>
                        </div>
                    )}
                </div>

                {/* Right Sidebar - Playlist */}
                <div className="w-80 glass-dark border-l border-white/5 flex flex-col z-20 bg-black/20 backdrop-blur-md">
                    <div className="p-4 border-b border-white/5">
                        <h2 className="text-sm font-semibold text-white/60 uppercase tracking-wider">Up Next</h2>
                    </div>
                    <div className="flex-1 overflow-y-auto">
                        {playlist.slice(0, 10).map((song, index) => (
                            <div
                                key={song.id}
                                className={`song-item flex items-center gap-3 p-3 cursor-pointer border-b border-white/5
                  ${currentSong?.id === song.id ? 'bg-pink-500/10' : ''}`}
                                onClick={() => onSelectSong(song)}
                            >
                                <div className="w-12 h-12 rounded-lg bg-gradient-to-br from-pink-500/20 to-purple-600/20 flex items-center justify-center flex-shrink-0">
                                    {currentSong?.id === song.id && isPlaying ? (
                                        <div className="flex items-end gap-0.5 h-4">
                                            {[...Array(3)].map((_, i) => (
                                                <div key={i} className="w-1 bg-pink-500 rounded-full visualizer-bar" style={{ animationDelay: `${i * 0.1}s` }} />
                                            ))}
                                        </div>
                                    ) : (
                                        <span className="text-white/40 text-sm">{index + 1}</span>
                                    )}
                                </div>
                                <div className="flex-1 min-w-0">
                                    <p className="font-medium truncate text-sm">{song.title || "Unknown"}</p>
                                    <p className="text-xs text-white/40 truncate">{song.artist || "Unknown"}</p>
                                </div>
                                <span className="text-xs text-white/40">
                                    {song.duration ? formatTime(song.duration) : "—"}
                                </span>
                            </div>
                        ))}
                        {playlist.length === 0 && (
                            <div className="p-8 text-center text-white/30">
                                <p>No songs in queue</p>
                            </div>
                        )}
                    </div>
                </div>
            </div>
        </>
    );
};

export default Player;


