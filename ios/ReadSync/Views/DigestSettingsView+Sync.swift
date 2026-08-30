import SwiftUI

extension DigestSettingsView {
  func loadSyncedPreferences() async {
    guard let ownerID = auth.user?.id, let token = await auth.validAccessToken() else { return }
    let row = try? await DigestSync.fetchSubscriber(ownerID: ownerID, accessToken: token)
    applySyncedPreferences(row ?? nil)
  }

  func applySyncedPreferences(_ row: DigestSubscriberRow?) {
    guard let row else { return }
    if !row.email.isEmpty {
      email = row.email
    }
    enabled = row.enabled
    if let last = row.last_sent_at, !last.isEmpty {
      syncedStatus = last
    }
  }
}
