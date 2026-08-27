import Foundation

public actor WatchedItemReminderCoordinator {
  private let policy: WatchedItemReminderPolicy
  private let stateStore: any WatchedItemReminderStateStoring
  private let notificationService: any AgentNotificationServing
  private var state: WatchedItemReminderStateDocument

  public init(
    policy: WatchedItemReminderPolicy,
    stateStore: any WatchedItemReminderStateStoring,
    notificationService: any AgentNotificationServing
  ) throws {
    self.policy = policy
    self.stateStore = stateStore
    self.notificationService = notificationService
    state = try stateStore.load()
  }

  public func evaluate(
    _ folders: [WatchedFolderReminderObservation],
    at now: Date
  ) async throws -> Int {
    var folderStates = Dictionary(uniqueKeysWithValues: state.folders.map { ($0.folderID, $0) })
    let candidates = reminderCandidates(in: folders, states: &folderStates, at: now)
    try persist(folderStates, evaluatedAt: now)
    guard !candidates.isEmpty,
          await notificationService.authorization() == .authorized
    else { return 0 }

    var deliveredCount = 0
    for folderID in candidates {
      do {
        try await notificationService.deliver(.watchedItemsNeedAttention)
      } catch {
        continue
      }
      let previous = folderStates[folderID]
      folderStates[folderID] = WatchedFolderReminderState(
        folderID: folderID,
        deliveredForCurrentCondition: true,
        snoozedUntil: previous?.snoozedUntil
      )
      try persist(folderStates, evaluatedAt: now)
      deliveredCount += 1
    }
    return deliveredCount
  }

  private func reminderCandidates(
    in folders: [WatchedFolderReminderObservation],
    states: inout [UUID: WatchedFolderReminderState],
    at now: Date
  ) -> [UUID] {
    var candidates: [UUID] = []
    for folder in folders.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
      let previous = states[folder.id]
      guard policy.isEligible(folder, at: now) else {
        states[folder.id] = WatchedFolderReminderState(
          folderID: folder.id,
          deliveredForCurrentCondition: false,
          snoozedUntil: previous?.snoozedUntil
        )
        continue
      }
      if previous?.deliveredForCurrentCondition != true,
         previous?.snoozedUntil.map({ $0 > now }) != true {
        candidates.append(folder.id)
      }
    }
    return candidates
  }

  private func persist(
    _ folderStates: [UUID: WatchedFolderReminderState],
    evaluatedAt: Date
  ) throws {
    state = WatchedItemReminderStateDocument(
      folders: folderStates.values.sorted { $0.folderID.uuidString < $1.folderID.uuidString },
      lastEvaluatedAt: evaluatedAt
    )
    try stateStore.save(state)
  }
}
