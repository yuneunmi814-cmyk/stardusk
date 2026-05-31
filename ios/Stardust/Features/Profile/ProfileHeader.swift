import SwiftUI

// 아바타 본체(StarGlowAvatar)와 하늘빛 팔레트(SkyMood)는 SkyMood/StarGlowAvatar 에서 정의한다.
struct ProfileHeader: View {
    @StateObject private var profile = UserProfileStore.shared

    var body: some View {
        VStack(spacing: 10) {
            StarGlowAvatar(colorHex: profile.avatarColorHex,
                           emotion: profile.latestEmotion)
            if let emotion = profile.latestEmotion {
                Text(emotion)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(SkyMood.resolve(emotion: emotion,
                                                      hex: profile.avatarColorHex).accent)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(.easeInOut(duration: 0.8), value: profile.avatarColorHex)
    }
}
