import AppKit
import MediaPlayer
import WebKit

/// Connects the YouTube Music page to macOS: JS commands go down into the page,
/// track state comes up from the page and feeds MPNowPlayingInfoCenter, and
/// media keys / Control Center come back in as MPRemoteCommandCenter events.
final class PlayerBridge: NSObject, WKScriptMessageHandler {
    static let messageHandlerName = "ytmusic"

    enum Control: String {
        case play, pause, toggle, next, prev
    }

    struct Track {
        var title = ""
        var artist = ""
        var album = ""
        var artwork: String?
        var duration = 0.0
        var position = 0.0
        var playing = false

        init() {}

        init(body: [String: Any]) {
            title = body["title"] as? String ?? ""
            artist = body["artist"] as? String ?? ""
            album = body["album"] as? String ?? ""
            artwork = (body["artwork"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            duration = body["duration"] as? Double ?? 0
            position = body["position"] as? Double ?? 0
            playing = body["playing"] as? Bool ?? false
        }
    }

    weak var webView: WKWebView?

    private var track = Track()
    private var artworkCache: [String: MPMediaItemArtwork] = [:]

    override init() {
        super.init()
        registerRemoteCommands()
    }

    func send(_ control: Control) {
        webView?.evaluateJavaScript("window.ytm && window.ytm.\(control.rawValue)()")
    }

    private func seek(to seconds: Double) {
        guard seconds.isFinite else { return }
        webView?.evaluateJavaScript(String(format: "window.ytm && window.ytm.seek(%.3f)", seconds))
    }

    // MARK: - WKScriptMessageHandler

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any] else { return }
        track = Track(body: body)
        if let artwork = track.artwork, artworkCache[artwork] == nil {
            loadArtwork(from: artwork)
        }
        publishNowPlaying()
    }

    // MARK: - Now Playing

    private func publishNowPlaying() {
        let center = MPNowPlayingInfoCenter.default()
        guard !track.title.isEmpty else {
            center.nowPlayingInfo = nil
            center.playbackState = .stopped
            return
        }

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: track.artist,
            MPMediaItemPropertyAlbumTitle: track.album,
            MPMediaItemPropertyPlaybackDuration: track.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: track.position,
            MPNowPlayingInfoPropertyPlaybackRate: track.playing ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
        ]
        if let artwork = track.artwork.flatMap({ artworkCache[$0] }) {
            info[MPMediaItemPropertyArtwork] = artwork
        }
        center.nowPlayingInfo = info
        center.playbackState = track.playing ? .playing : .paused
    }

    private func loadArtwork(from urlString: String) {
        guard let url = URL(string: urlString) else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data, let image = NSImage(data: data) else { return }
            let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            DispatchQueue.main.async {
                guard let self else { return }
                if self.artworkCache.count > 100 {
                    self.artworkCache.removeAll()
                }
                self.artworkCache[urlString] = artwork
                if self.track.artwork == urlString {
                    self.publishNowPlaying()
                }
            }
        }.resume()
    }

    // MARK: - Remote commands (media keys, Control Center, Touch Bar)

    private func registerRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.isEnabled = true
        center.playCommand.addTarget { [weak self] _ in
            self?.send(.play)
            return .success
        }

        center.pauseCommand.isEnabled = true
        center.pauseCommand.addTarget { [weak self] _ in
            self?.send(.pause)
            return .success
        }

        center.togglePlayPauseCommand.isEnabled = true
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.send(.toggle)
            return .success
        }

        center.nextTrackCommand.isEnabled = true
        center.nextTrackCommand.addTarget { [weak self] _ in
            self?.send(.next)
            return .success
        }

        center.previousTrackCommand.isEnabled = true
        center.previousTrackCommand.addTarget { [weak self] _ in
            self?.send(.prev)
            return .success
        }

        center.changePlaybackPositionCommand.isEnabled = true
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            self?.seek(to: event.positionTime)
            return .success
        }
    }

    // MARK: - Injected page script

    static let userScript = #"""
    (() => {
      if (window.__ytmBridge) return;
      window.__ytmBridge = true;

      const video = () => document.querySelector('video');
      const press = (selector) => {
        const button = document.querySelector(`ytmusic-player-bar ${selector}`);
        if (button) button.click();
      };
      const finite = (n) => (Number.isFinite(n) ? n : 0);

      const largestArtwork = (artwork) => {
        if (!artwork || !artwork.length) return '';
        const size = (entry) => Math.max(0, ...(entry.sizes || '').split(' ').map((s) => parseInt(s, 10) || 0));
        return artwork.reduce((best, entry) => (size(entry) > size(best) ? entry : best)).src || '';
      };

      const snapshot = () => {
        const v = video();
        const meta = (navigator.mediaSession && navigator.mediaSession.metadata) || {};
        return {
          title: meta.title || '',
          artist: meta.artist || '',
          album: meta.album || '',
          artwork: largestArtwork(meta.artwork),
          duration: v ? finite(v.duration) : 0,
          position: v ? finite(v.currentTime) : 0,
          playing: !!v && !v.paused && !v.ended,
        };
      };

      let lastKey = '';
      const keyOf = (s) => [s.title, s.artist, s.album, s.artwork, s.playing].join('\u0001');
      const send = (state) => {
        lastKey = keyOf(state);
        window.webkit.messageHandlers.ytmusic.postMessage(state);
      };
      // Track and playing-state changes are caught by polling; media events cover the rest.
      const checkTrack = () => {
        const state = snapshot();
        if (keyOf(state) !== lastKey) send(state);
      };

      window.ytm = {
        play() { const v = video(); if (v) v.play().catch(() => {}); },
        pause() { const v = video(); if (v) v.pause(); },
        toggle() {
          const v = video();
          if (!v) return;
          if (v.paused) v.play().catch(() => {});
          else v.pause();
        },
        next() { press('.next-button'); },
        prev() { press('.previous-button'); },
        seek(t) { const v = video(); if (v && Number.isFinite(t)) v.currentTime = t; },
      };

      ['play', 'pause', 'seeked', 'durationchange'].forEach((type) => {
        document.addEventListener(type, () => send(snapshot()), true);
      });
      setInterval(checkTrack, 1000);
      checkTrack();
    })();
    """#
}
