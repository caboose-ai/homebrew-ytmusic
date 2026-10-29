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

    static let slackStatusKey = "slackStatusEnabled"

    private var track = Track()
    private var artworkCache: [String: MPMediaItemArtwork] = [:]

    // Slack status goes through the slk CLI, so every slk call runs on this serial queue,
    // which keeps set and clear in order. cachedSlk is only read and written on that queue.
    private let slkQueue = DispatchQueue(label: "io.caboose-ai.ytmusic.slk")
    private var cachedSlk: String??
    // Set only when this app has put a status up, so quitting never clears one the user set.
    private var slackStatusIsOurs = false

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

    // The handler is registered for every page the wrapper loads, so only accept
    // state from the YouTube Music main frame.
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame,
              message.frameInfo.securityOrigin.host == "music.youtube.com",
              let body = message.body as? [String: Any] else { return }
        let previous = track
        track = Track(body: body)
        if let artwork = track.artwork, artworkCache[artwork] == nil {
            loadArtwork(from: artwork)
        }
        publishNowPlaying()
        updateSlackStatus(from: previous)
    }

    // MARK: - Slack status (opt-in)

    func setSlackStatusEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: Self.slackStatusKey)
        if !enabled {
            clearSlackStatus()
        }
    }

    // Called on quit, so a status this app set does not outlive it.
    func shutdown() {
        clearSlackStatus(wait: true)
    }

    private func updateSlackStatus(from previous: Track) {
        guard UserDefaults.standard.bool(forKey: Self.slackStatusKey) else { return }
        guard track.playing, !track.title.isEmpty else {
            if previous.playing {
                clearSlackStatus()
            }
            return
        }
        let changed = track.title != previous.title || track.artist != previous.artist || !previous.playing
        guard changed else { return }

        var arguments = ["status", slackText(), ":musical_note:"]
        // slk takes a duration such as 5m, so the status expires with the track.
        // Unknown duration leaves the status up until pause or quit.
        if track.duration > track.position {
            let minutes = max(1, Int(ceil((track.duration - track.position) / 60)))
            arguments.append("\(minutes)m")
        }
        slackStatusIsOurs = true
        runSlk(arguments)
    }

    private func clearSlackStatus(wait: Bool = false) {
        guard slackStatusIsOurs else { return }
        slackStatusIsOurs = false
        runSlk(["status", "clear"], wait: wait)
    }

    private func slackText() -> String {
        let text = track.artist.isEmpty ? track.title : "\(track.title) - \(track.artist)"
        // Slack caps status text at 100 characters.
        return String(text.prefix(100))
    }

    private func runSlk(_ arguments: [String], wait: Bool = false) {
        let work: () -> Void = { [weak self] in
            guard let self, let slk = self.slkLocation() else { return }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: slk)
            process.arguments = arguments
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            do {
                if wait {
                    // Bounded, so a hung slk cannot stop the app from quitting.
                    let done = DispatchSemaphore(value: 0)
                    process.terminationHandler = { _ in done.signal() }
                    try process.run()
                    if done.wait(timeout: .now() + 3) == .timedOut {
                        process.terminate()
                    }
                } else {
                    try process.run()
                }
            } catch {
                // slk missing or broken: the feature quietly does nothing.
            }
        }
        if wait {
            slkQueue.sync(execute: work)
        } else {
            slkQueue.async(execute: work)
        }
    }

    // Must only be called on slkQueue.
    private func slkLocation() -> String? {
        if let cachedSlk {
            return cachedSlk
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var candidates = [
            "/opt/homebrew/bin/slk", "/usr/local/bin/slk", home + "/.local/bin/slk", home + "/.gem/bin/slk",
        ]
        // Homebrew's Ruby keeps gem binaries under a versioned folder, e.g. gems/4.0.0/bin.
        let gemRoot = "/opt/homebrew/lib/ruby/gems"
        let gemVersions = (try? FileManager.default.contentsOfDirectory(atPath: gemRoot)) ?? []
        candidates += gemVersions.map { "\(gemRoot)/\($0)/bin/slk" }
        var found = candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
        if found == nil {
            // A Dock-launched app has a minimal PATH, so ask a login shell as a last resort.
            let shell = Process()
            let output = Pipe()
            shell.executableURL = URL(fileURLWithPath: "/bin/zsh")
            shell.arguments = ["-lc", "command -v slk"]
            shell.standardOutput = output
            shell.standardError = FileHandle.nullDevice
            if (try? shell.run()) != nil {
                let data = output.fileHandleForReading.readDataToEndOfFile()
                shell.waitUntilExit()
                // command -v can also print a function or alias; only take an absolute executable.
                let path = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                found = path.hasPrefix("/") && FileManager.default.isExecutableFile(atPath: path) ? path : nil
            }
        }
        cachedSlk = .some(found)
        return found
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
        // The URL comes from page-controlled metadata, so never fetch file: or other schemes.
        guard let url = URL(string: urlString), url.scheme?.lowercased() == "https" else { return }
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
      if (location.host !== 'music.youtube.com' || window.__ytmBridge) return;
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
