import AVFoundation
import Observation

/// A queue entry. The same track can appear more than once.
struct QueueItem: Identifiable, Hashable, Sendable {
    let id = UUID()
    let entry: Entry
}

enum RepeatMode: String, Sendable {
    case off, all, one

    var next: RepeatMode {
        switch self {
        case .off: .all
        case .all: .one
        case .one: .off
        }
    }
}

/// AVPlayerItem that knows which queue entry it belongs to.
private final class QueuePlayerItem: AVPlayerItem {
    let queueID: QueueItem.ID
    let url: URL
    /// Reports a failure to load (undecodable file, server refused the stream).
    var statusObservation: NSKeyValueObservation?
    /// The audio stream's own rate, read when the item is made; nil if the asset wouldn't say.
    var sampleRate: Double?

    init(url: URL, queueID: QueueItem.ID) {
        self.queueID = queueID
        self.url = url
        super.init(asset: AVURLAsset(url: url), automaticallyLoadedAssetKeys: ["duration"])
    }
}

/// Playback on top of AVQueuePlayer. The AVQueuePlayer always holds at most two
/// tracks: the current one and the next (preloaded, so there's no silence between tracks).
@MainActor
@Observable
final class PlayerController {
    typealias Resolver = @Sendable (Entry) async throws -> URL

    private(set) var queue: [QueueItem] = []
    private(set) var currentID: QueueItem.ID?
    private(set) var isPlaying = false
    private(set) var currentTime: Double = 0
    private(set) var duration: Double = 0
    private(set) var formatLabel = ""
    /// Sample rate of the current track's audio stream (any source), nil until it is known.
    private(set) var trackSampleRate: Double?
    /// "Couldn't play <title>", shown on the display until a track plays.
    private(set) var errorMessage: String?
    /// The system's reason, for the tooltip.
    private(set) var errorDetail: String?
    /// A track is being resolved or opened (a slow server).
    private(set) var isLoading = false

    var volume: Float = 1 {
        didSet { player.volume = volume.clamped }
    }

    var repeatMode: RepeatMode = .off {
        didSet { refreshUpcoming() }
    }

    var shuffle = false {
        didSet {
            guard shuffle != oldValue else { return }
            rebuildOrder()
            refreshUpcoming()
        }
    }

    var current: QueueItem? { queue.first { $0.id == currentID } }

    /// Called after a seek (for Now Playing).
    @ObservationIgnored var onSeek: (() -> Void)?

    /// Called when a track starts, picked or reached on its own (for the use counts).
    @ObservationIgnored var onTrackStarted: ((Entry) -> Void)?

    /// Called with a track's sample rate as it becomes the current one, before it starts when it
    /// was picked by hand (so the output can be set to it).
    @ObservationIgnored var onTrackRate: ((Double) -> Void)?

    /// Called once when a track fails, before trying it again: a server source can sign in afresh.
    @ObservationIgnored var onStreamFailure: (@Sendable (Entry) async -> Void)?

    /// Equalizer applied to every track.
    let equalizer: Equalizer

    /// The underlying AVPlayer, for the AirPlay picker.
    var avPlayer: AVPlayer { player }

    @ObservationIgnored private let player = AVQueuePlayer()
    @ObservationIgnored private let resolve: Resolver
    /// Playback order (queue ids). Same as the queue without shuffle.
    @ObservationIgnored private var order: [QueueItem.ID] = []
    @ObservationIgnored private var currentAVItem: QueuePlayerItem?
    /// Whether the loading track should start playing (pause while loading).
    @ObservationIgnored private var autoplay = true
    /// Tracks that failed twice: skipped until played by hand or the queue is replaced.
    @ObservationIgnored private var failedIDs: Set<QueueItem.ID> = []
    /// Tracks that failed once and are being tried again.
    @ObservationIgnored private var retriedIDs: Set<QueueItem.ID> = []
    @ObservationIgnored private var playToken = 0
    @ObservationIgnored private var upcomingToken = 0
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []
    @ObservationIgnored private var timeObserver: Any?

    init(resolve: @escaping Resolver, equalizer: Equalizer? = nil) {
        self.resolve = resolve
        self.equalizer = equalizer ?? Equalizer()
        player.actionAtItemEnd = .advance
        observations.append(player.observe(\.currentItem) { [weak self] _, _ in
            Task { @MainActor in self?.currentItemChanged() }
        })
        observations.append(player.observe(\.timeControlStatus) { [weak self] _, _ in
            Task { @MainActor in self?.statusChanged() }
        })
        NotificationCenter.default.addObserver(
            forName: AVPlayerItem.failedToPlayToEndTimeNotification, object: nil, queue: .main
        ) { [weak self] note in
            // A stream that breaks mid-track (network gone).
            let id = (note.object as? QueuePlayerItem)?.queueID
            let error = note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
            MainActor.assumeIsolated {
                if let id { self?.failed(id, error: error) }
            }
        }
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated { self?.tick(time) }
        }
    }

    // MARK: Queue

    /// Replaces the queue (play folder) and starts at `startAt`.
    func setQueue(_ entries: [Entry], startAt: Int = 0) {
        queue = entries.map { QueueItem(entry: $0) }
        failedIDs = []
        retriedIDs = []
        guard queue.indices.contains(startAt) else {
            stopAll()
            return
        }
        currentID = queue[startAt].id
        rebuildOrder()
        play(queue[startAt].id)
    }

    /// Appends to the end of the queue.
    func append(_ entries: [Entry]) {
        let items = entries.map { QueueItem(entry: $0) }
        queue.append(contentsOf: items)
        if shuffle {
            let start = (order.firstIndex { $0 == currentID } ?? -1) + 1
            for item in items {
                order.insert(item.id, at: Int.random(in: start...order.count))
            }
        } else {
            order = queue.map(\.id)
        }
        refreshUpcoming()
    }

    func remove(atOffsets offsets: IndexSet) {
        let removed = Set(offsets.map { queue[$0].id })
        let wasPlaying = isPlaying
        var replacement: QueueItem.ID?
        if let currentID, removed.contains(currentID) {
            // The current track was removed: move on to the next remaining one.
            replacement = order.drop { $0 != currentID }.first { !removed.contains($0) }
        }
        queue.remove(atOffsets: offsets)
        order.removeAll { removed.contains($0) }
        if let currentID, removed.contains(currentID) {
            if let replacement, wasPlaying {
                play(replacement)
            } else {
                stopAll()
                self.currentID = replacement
            }
        } else {
            refreshUpcoming()
        }
    }

    /// Removes every queue entry that matches (a CD that went away). If the current
    /// track goes too, playback stops instead of moving on.
    func removeAll(where shouldRemove: (Entry) -> Bool) {
        let removed = Set(queue.filter { shouldRemove($0.entry) }.map(\.id))
        guard !removed.isEmpty else { return }
        let stopsCurrent = currentID.map(removed.contains) ?? false
        if stopsCurrent { stopAll() }
        queue.removeAll { removed.contains($0.id) }
        order.removeAll { removed.contains($0) }
        if !stopsCurrent { refreshUpcoming() }
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        queue.move(fromOffsets: source, toOffset: destination)
        if !shuffle { order = queue.map(\.id) }
        refreshUpcoming()
    }

    /// Puts back the last session's queue, stopped on its track at its position: play picks it up there.
    func restore(_ entries: [Entry], current: Int?, position: Double, duration: Double) {
        guard queue.isEmpty, !entries.isEmpty else { return }
        queue = entries.map { QueueItem(entry: $0) }
        currentID = current.flatMap { queue.indices.contains($0) ? queue[$0].id : nil }
        rebuildOrder()
        guard let item = self.current else { return }
        currentTime = max(0, position)
        self.duration = max(0, duration)
        formatLabel = item.entry.format
    }

    func clear() {
        queue = []
        order = []
        failedIDs = []
        retriedIDs = []
        errorMessage = nil
        errorDetail = nil
        stopAll()
    }

    // MARK: Transport

    /// Plays a queue entry. One the user picks is tried again even if it failed before.
    func play(_ id: QueueItem.ID) {
        failedIDs.remove(id)
        start(id)
    }

    /// `position`: where to pick the track up again, when it broke off part way (the network went).
    private func start(_ id: QueueItem.ID, at position: Double = 0) {
        guard let item = queue.first(where: { $0.id == id }) else { return }
        playToken += 1
        let token = playToken
        upcomingToken += 1
        currentID = id
        currentAVItem = nil
        currentTime = position
        duration = 0
        formatLabel = item.entry.format
        trackSampleRate = nil
        autoplay = true
        isLoading = true
        equalizer.spectrum.setDuration(0)
        equalizer.spectrum.startAfresh()
        player.removeAllItems()
        Task {
            let made = await makeItem(item)
            guard token == playToken else { return }
            isLoading = false
            let avItem: QueuePlayerItem
            switch made {
            case .success(let made): avItem = made
            case .failure(let error):
                failed(id, error: error)
                return
            }
            currentAVItem = avItem
            if position > 0 {
                await avItem.seek(to: CMTime(seconds: position, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
                guard token == playToken else { return }
            }
            announceRate(of: avItem)
            player.insert(avItem, after: nil)
            if autoplay { player.play() }
            onTrackStarted?(item.entry)
            loadFormat(avItem)
            refreshUpcoming()
        }
    }

    func togglePlayPause() {
        if isPlaying || (isLoading && autoplay) {
            pause()
        } else if player.currentItem != nil {
            autoplay = true
            player.play()
        } else if let currentID {
            // Nothing loaded (a restored session, the end of the queue): from where the display says.
            failedIDs.remove(currentID)
            start(currentID, at: currentTime)
        } else if let first = order.first(where: { !failedIDs.contains($0) }) ?? order.first {
            play(first)
        }
    }

    func pause() {
        autoplay = false
        player.pause()
    }

    func stop() {
        player.pause()
        seek(to: 0)
    }

    func next() {
        guard let currentID, let id = step(from: currentID, by: 1, wrap: repeatMode != .off) else { return }
        play(id)
    }

    /// Goes back to the start of the track if 3 s have passed; otherwise to the previous one.
    func previous() {
        guard let currentID else { return }
        if currentTime > 3 {
            seek(to: 0)
        } else if let id = step(from: currentID, by: -1, wrap: repeatMode != .off) {
            play(id)
        } else {
            seek(to: 0)
        }
    }

    func seek(to seconds: Double) {
        let target = max(0, duration > 0 ? min(seconds, duration) : seconds)
        currentTime = target
        equalizer.spectrum.startAfresh()
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        onSeek?()
    }

    func skip(by seconds: Double) { seek(to: currentTime + seconds) }

    func changeVolume(by delta: Float) { volume = (volume + delta).clamped }

    // MARK: Internal

    private func stopAll() {
        playToken += 1
        isLoading = false
        upcomingToken += 1
        player.removeAllItems()
        currentAVItem = nil
        currentID = nil
        currentTime = 0
        duration = 0
        formatLabel = ""
        trackSampleRate = nil
    }

    private func rebuildOrder() {
        let ids = queue.map(\.id)
        guard shuffle else {
            order = ids
            return
        }
        // Shuffle: the current track stays first, the rest shuffled.
        let rest = ids.filter { $0 != currentID }.shuffled()
        order = (currentID.map { [$0] } ?? []) + rest
    }

    private func step(from id: QueueItem.ID, by delta: Int, wrap: Bool) -> QueueItem.ID? {
        guard let i = order.firstIndex(of: id), !order.isEmpty else { return nil }
        let j = i + delta
        if order.indices.contains(j) { return order[j] }
        guard wrap else { return nil }
        return order[(j + order.count) % order.count]
    }

    /// What plays after the current track, without intervention. Skips tracks that failed.
    private var upcomingID: QueueItem.ID? {
        guard let currentID else { return nil }
        if repeatMode == .one { return failedIDs.contains(currentID) ? nil : currentID }
        return playable(after: currentID, wrap: repeatMode == .all)
    }

    /// The next track that hasn't failed, in playing order, or nil.
    private func playable(after id: QueueItem.ID, wrap: Bool) -> QueueItem.ID? {
        var candidate = id
        for _ in 0..<order.count {
            guard let next = step(from: candidate, by: 1, wrap: wrap), next != id else { return nil }
            if !failedIDs.contains(next) { return next }
            candidate = next
        }
        return nil
    }

    /// A track failed to resolve, open or keep playing. The first time it is tried again (after
    /// the source had its chance to sign in afresh); the second time it is skipped, with a message
    /// on the display. If nothing in the queue plays, playback stops on the failed track.
    private func failed(_ id: QueueItem.ID, error: Error?) {
        guard let item = queue.first(where: { $0.id == id }), !failedIDs.contains(id) else { return }
        let isCurrent = id == currentID
        if !retriedIDs.contains(id) {
            retriedIDs.insert(id)
            Log.shared.error(.player, "track-retried", error, detail: item.entry.path)
            let token = playToken
            // A track that was already playing picks up where it broke off, not from the start.
            let position = isCurrent ? currentTime : 0
            Task {
                await onStreamFailure?(item.entry)
                if isCurrent {
                    guard token == playToken, currentID == id else { return }
                    start(id, at: position)
                } else {
                    refreshUpcoming()
                }
            }
            return
        }
        failedIDs.insert(id)
        Log.shared.error(.player, "track-skipped", error, detail: item.entry.path)
        guard isCurrent else {
            refreshUpcoming()
            return
        }
        errorMessage = String(localized: "Não foi possível tocar \(item.entry.title)")
        errorDetail = error?.localizedDescription
        if autoplay, let next = playable(after: id, wrap: repeatMode != .off) {
            start(next)
        } else {
            // Nothing else to try: stay on this track, stopped.
            playToken += 1
            upcomingToken += 1
            isLoading = false
            player.removeAllItems()
            currentAVItem = nil
            currentTime = 0
        }
    }

    /// Ensures the AVQueuePlayer has the right next track after the current one.
    private func refreshUpcoming() {
        upcomingToken += 1
        let token = upcomingToken
        guard let currentAVItem, player.currentItem === currentAVItem else { return }
        for item in player.items().dropFirst() { player.remove(item) }
        guard let id = upcomingID, let item = queue.first(where: { $0.id == id }) else { return }
        Task {
            let made = await makeItem(item)
            guard token == upcomingToken, player.currentItem === currentAVItem else { return }
            switch made {
            case .success(let avItem): player.insert(avItem, after: currentAVItem)
            case .failure(let error): failed(id, error: error)
            }
        }
    }

    private func makeItem(_ item: QueueItem) async -> Result<QueuePlayerItem, Error> {
        do {
            let url = try await resolve(item.entry)
            let avItem = QueuePlayerItem(url: url, queueID: item.id)
            let id = item.id
            avItem.statusObservation = avItem.observe(\.status) { [weak self] observed, _ in
                guard observed.status == .failed else { return }
                let error = observed.error
                Task { @MainActor in self?.failed(id, error: error) }
            }
            await equalizer.attach(to: avItem)
            avItem.sampleRate = await Self.sampleRate(of: avItem.asset)
            return .success(avItem)
        } catch {
            return .failure(error)
        }
    }

    private func announceRate(of item: QueuePlayerItem) {
        trackSampleRate = item.sampleRate
        if let rate = item.sampleRate { onTrackRate?(rate) }
    }

    /// The rate of the asset's audio stream, the same way for a file, a server's stream and a CD.
    private static func sampleRate(of asset: AVAsset) async -> Double? {
        guard let track = try? await asset.loadTracks(withMediaType: .audio).first,
              let description = try? await track.load(.formatDescriptions).first,
              let rate = description.audioStreamBasicDescription?.mSampleRate, rate > 0 else { return nil }
        return rate
    }

    private func loadFormat(_ item: QueuePlayerItem) {
        let url = item.url
        Task {
            let label = await Task.detached { AudioFormat.label(for: url) }.value
            if currentAVItem === item { formatLabel = label }
        }
    }

    private func currentItemChanged() {
        guard let item = player.currentItem as? QueuePlayerItem else {
            statusChanged()
            return
        }
        guard item !== currentAVItem else { return }
        // The AVQueuePlayer advanced on its own to the preloaded track. On the same tap the sound
        // ran on without a pause; with a tap of its own (another format) it started afresh.
        if let previous = currentAVItem, let tap = Equalizer.tap(of: previous), tap === Equalizer.tap(of: item) {
            equalizer.spectrum.movedOn(after: previous.duration.seconds)
        } else {
            equalizer.spectrum.startAfresh()
        }
        currentAVItem = item
        currentID = item.queueID
        currentTime = 0
        duration = 0
        let entry = queue.first { $0.id == item.queueID }?.entry
        formatLabel = entry?.format ?? ""
        announceRate(of: item)
        if let entry { onTrackStarted?(entry) }
        loadFormat(item)
        refreshUpcoming()
    }

    private func statusChanged() {
        if player.currentItem == nil, currentAVItem != nil {
            // End of queue: stays on the last track, ready to play again.
            player.pause()
            currentAVItem = nil
            currentTime = 0
        }
        isPlaying = player.timeControlStatus != .paused && player.currentItem != nil
    }

    private func tick(_ time: CMTime) {
        guard player.currentItem != nil else { return }
        currentTime = time.seconds.isFinite ? time.seconds : 0
        // Music is really coming out (a broken file also "waits to play" for a moment): the
        // message about an earlier failure has done its job, and this track counts as good again.
        if currentTime > 0, player.timeControlStatus == .playing, let currentID,
           errorMessage != nil || retriedIDs.contains(currentID) {
            errorMessage = nil
            errorDetail = nil
            retriedIDs.remove(currentID)
        }
        if let d = player.currentItem?.duration.seconds, d.isFinite, d > 0 {
            duration = d
            equalizer.spectrum.setDuration(d)
        }
    }
}

#if DEBUG
extension PlayerController {
    /// Fixed state for screenshots and previews, without playing anything.
    func debugSet(queue entries: [Entry], current: Int, time: Double, duration: Double, format: String) {
        queue = entries.map { QueueItem(entry: $0) }
        order = queue.map(\.id)
        currentID = queue[current].id
        isPlaying = true
        currentTime = time
        self.duration = duration
        formatLabel = format
    }
}
#endif

private extension Float {
    var clamped: Float { Swift.min(1, Swift.max(0, self)) }
}
