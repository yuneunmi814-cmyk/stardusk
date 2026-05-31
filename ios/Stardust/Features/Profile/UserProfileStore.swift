import SwiftUI

@MainActor
final class UserProfileStore: ObservableObject {
    static let shared = UserProfileStore()
    @Published var avatarColorHex: String = "#5794E4"
    @Published var latestEmotion: String? = nil

    func applyLatestStar(colorHex: String, emotion: String?) {
        withAnimation(.easeInOut(duration: 0.8)) {   // 색이 부드럽게 번지듯 전환
            avatarColorHex = colorHex
            latestEmotion = emotion
        }
        UserDefaults.standard.set(colorHex, forKey: "stardust.avatarColor")
    }
}
