import AVFoundation
import Observation

/// Uma entrada da fila. A mesma faixa pode aparecer mais de uma vez.
struct QueueItem: Identifiable, Hashable, Sendable {
    let id = UUID()
    let entry: Entry
}

enum RepeatMode: Sendable {
    case off, all, one

    var next: RepeatMode {
        switch self {
        case .off: .all
        case .all: .one
        case .one: .off
        }
    }
}

/// AVPlayerItem que sabe a que entrada da fila pertence.
private final class QueuePlayerItem: AVPlayerItem {
    let queueID: QueueItem.ID
    let url: URL

    init(url: URL, queueID: QueueItem.ID) {
        self.queueID = queueID
        self.url = url
        super.init(asset: AVURLAsset(url: url), automaticallyLoadedAssetKeys: ["duration"])
    }
}

/// Reprodução sobre AVQueuePlayer. O AVQueuePlayer tem sempre no máximo duas
/// faixas: a atual e a seguinte (pré-carregada, para não haver silêncio entre faixas).
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
    private(set) var errorMessage: String?

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

    /// Chamado depois de um seek (para o Now Playing).
    @ObservationIgnored var onSeek: (() -> Void)?

    /// Equalizador aplicado a cada faixa.
    let equalizer: Equalizer

    /// O AVPlayer por baixo, para o seletor AirPlay.
    var avPlayer: AVPlayer { player }

    @ObservationIgnored private let player = AVQueuePlayer()
    @ObservationIgnored private let resolve: Resolver
    /// Ordem de reprodução (ids da fila). Igual à fila sem aleatório.
    @ObservationIgnored private var order: [QueueItem.ID] = []
    @ObservationIgnored private var currentAVItem: QueuePlayerItem?
    /// Se a faixa em carregamento deve começar a tocar (pausa durante o carregamento).
    @ObservationIgnored private var autoplay = true
    @ObservationIgnored private var isLoading = false
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
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated { self?.tick(time) }
        }
    }

    // MARK: Fila

    /// Substitui a fila (tocar pasta) e começa em `startAt`.
    func setQueue(_ entries: [Entry], startAt: Int = 0) {
        queue = entries.map { QueueItem(entry: $0) }
        guard queue.indices.contains(startAt) else {
            stopAll()
            return
        }
        currentID = queue[startAt].id
        rebuildOrder()
        play(queue[startAt].id)
    }

    /// Junta ao fim da fila.
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
            // A faixa atual saiu: segue para a próxima que fica.
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

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        queue.move(fromOffsets: source, toOffset: destination)
        if !shuffle { order = queue.map(\.id) }
        refreshUpcoming()
    }

    func clear() {
        queue = []
        order = []
        stopAll()
    }

    // MARK: Transporte

    func play(_ id: QueueItem.ID) {
        guard let item = queue.first(where: { $0.id == id }) else { return }
        playToken += 1
        let token = playToken
        upcomingToken += 1
        currentID = id
        currentAVItem = nil
        currentTime = 0
        duration = 0
        formatLabel = item.entry.format
        errorMessage = nil
        autoplay = true
        isLoading = true
        player.removeAllItems()
        Task {
            let avItem = await makeItem(item)
            guard token == playToken else { return }
            isLoading = false
            guard let avItem else { return }
            currentAVItem = avItem
            player.insert(avItem, after: nil)
            if autoplay { player.play() }
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
            play(currentID)
        } else if let first = order.first {
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

    /// Volta ao início da faixa se já passaram 3 s; senão vai para a anterior.
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
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        onSeek?()
    }

    func skip(by seconds: Double) { seek(to: currentTime + seconds) }

    func changeVolume(by delta: Float) { volume = (volume + delta).clamped }

    // MARK: Interno

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
    }

    private func rebuildOrder() {
        let ids = queue.map(\.id)
        guard shuffle else {
            order = ids
            return
        }
        // Aleatório: a atual fica primeiro, o resto baralhado.
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

    /// O que toca depois da atual, sem intervenção.
    private var upcomingID: QueueItem.ID? {
        guard let currentID else { return nil }
        if repeatMode == .one { return currentID }
        return step(from: currentID, by: 1, wrap: repeatMode == .all)
    }

    /// Garante que o AVQueuePlayer tem a faixa seguinte certa depois da atual.
    private func refreshUpcoming() {
        upcomingToken += 1
        let token = upcomingToken
        guard let currentAVItem, player.currentItem === currentAVItem else { return }
        for item in player.items().dropFirst() { player.remove(item) }
        guard let id = upcomingID, let item = queue.first(where: { $0.id == id }) else { return }
        Task {
            guard let avItem = await makeItem(item), token == upcomingToken,
                  player.currentItem === currentAVItem else { return }
            player.insert(avItem, after: currentAVItem)
        }
    }

    private func makeItem(_ item: QueueItem) async -> QueuePlayerItem? {
        do {
            let url = try await resolve(item.entry)
            let avItem = QueuePlayerItem(url: url, queueID: item.id)
            await equalizer.attach(to: avItem)
            return avItem
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
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
        // O AVQueuePlayer avançou sozinho para a faixa pré-carregada.
        currentAVItem = item
        currentID = item.queueID
        currentTime = 0
        duration = 0
        formatLabel = queue.first { $0.id == item.queueID }?.entry.format ?? ""
        loadFormat(item)
        refreshUpcoming()
    }

    private func statusChanged() {
        if player.currentItem == nil, currentAVItem != nil {
            // Fim da fila: fica na última faixa, pronta a tocar de novo.
            player.pause()
            currentAVItem = nil
            currentTime = 0
        }
        isPlaying = player.timeControlStatus != .paused && player.currentItem != nil
    }

    private func tick(_ time: CMTime) {
        guard player.currentItem != nil else { return }
        currentTime = time.seconds.isFinite ? time.seconds : 0
        if let d = player.currentItem?.duration.seconds, d.isFinite, d > 0 {
            duration = d
        }
    }
}

#if DEBUG
extension PlayerController {
    /// Estado fixo para capturas e previews, sem tocar nada.
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
