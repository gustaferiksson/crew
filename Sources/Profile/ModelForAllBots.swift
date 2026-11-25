import Observation

@Observable
final class ModelForAllBots {
    typealias Apply = (_ bot: String, _ choice: ModelChoice, _ confirmation: ModelConfirmation) async throws -> ModelChangeOutcome

    enum Phase: Equatable {
        case choosing, running, finished
        case confirming(String)
    }

    struct Failure: Equatable {
        let bot: String
        let message: String
    }

    var choice: ModelChoice?
    private(set) var phase = Phase.choosing
    private(set) var total = 0
    private(set) var changed = 0
    private(set) var failures: [Failure] = []
    private(set) var current = ""
    private(set) var remaining: [Bot] = []
    private(set) var added = 0
    private(set) var isStopping = false
    private(set) var wasStopped = false
    private var snapshot: Set<Bot.ID> = []
    private var isConfirmed = false

    init() {}

    init(choice: ModelChoice, phase: Phase, total: Int, changed: Int, failures: [Failure] = [], current: String = "", remaining: [Bot] = [], added: Int = 0) {
        self.choice = choice
        self.phase = phase
        self.total = total
        self.changed = changed
        self.failures = failures
        self.current = current
        self.remaining = remaining
        self.added = added
    }

    var attempted: Int { changed + failures.count }

    static func targets(in bots: [Bot], for choice: ModelChoice?) -> [Bot] {
        let candidates = bots.filter { bot in
            guard bot.isDefault || bot.meta.hidden != true else { return false }
            guard let choice else { return true }
            return bot.model != choice.model || bot.provider != choice.provider
        }
        return candidates.filter(\.isDefault) + candidates.filter { !$0.isDefault }
    }

    static func hiddenCount(in bots: [Bot]) -> Int {
        bots.count { !$0.isDefault && $0.meta.hidden == true }
    }

    func start(on bots: [Bot], apply: Apply, roster: () -> [Bot]) async {
        let targets = Self.targets(in: bots, for: choice)
        guard !targets.isEmpty else { return }
        snapshot = Set(bots.map(\.id))
        total = targets.count
        changed = 0
        remaining = targets
        isConfirmed = false
        await run(apply: apply, roster: roster)
    }

    func confirm(apply: Apply, roster: () -> [Bot]) async {
        isConfirmed = true
        await run(apply: apply, roster: roster)
    }

    func cancelConfirmation() {
        remaining = []
        phase = .choosing
    }

    func stop() {
        guard phase == .running else { return }
        isStopping = true
    }

    func run(apply: Apply, roster: () -> [Bot]) async {
        guard let choice else { return }
        let queue = remaining
        remaining = []
        failures = []
        isStopping = false
        wasStopped = false
        phase = .running
        for (index, bot) in queue.enumerated() {
            guard !isStopping else {
                remaining += queue[index...]
                wasStopped = true
                break
            }
            current = bot.title
            do {
                switch try await apply(bot.name, choice, isConfirmed ? .confirmed : .ask) {
                case .applied:
                    changed += 1
                case .needsConfirmation(let message) where !isConfirmed && changed == 0 && failures.isEmpty:
                    remaining = Array(queue[index...])
                    phase = .confirming(message)
                    return
                case .needsConfirmation(let message):
                    fail(bot, message)
                }
            } catch GatewayError.rpc(_, let message) {
                fail(bot, message)
            } catch {
                fail(bot, error.localizedDescription)
                remaining += queue[(index + 1)...]
                break
            }
        }
        added = roster().count { !snapshot.contains($0.id) && $0.meta.hidden != true }
        phase = .finished
    }

    private func fail(_ bot: Bot, _ message: String) {
        failures.append(Failure(bot: bot.title, message: message))
        remaining.append(bot)
    }
}
