import SwiftUI
import AuthenticationServices

/// 첫 진입 화면 — "당신이 머문 자리마다 별이 뜹니다".
/// Apple 로그인을 1순위로, 소셜/게스트는 보조 진입로로 둔다.
struct LoginView: View {
    @EnvironmentObject private var session: SessionStore
    @State private var errorText: String?
    @State private var isWorking = false

    var body: some View {
        ZStack {
            SkyGradientBackground(mood: .night)   // §4.4a — 숨 쉬는 밤하늘 + 별
                .ignoresSafeArea()

            VStack(spacing: 28) {
                Spacer()

                VStack(spacing: 10) {
                    Text("STARDUST")
                        .font(.largeTitle.bold())
                        .foregroundStyle(.white)
                        .tracking(4)
                    Text("당신이 머문 자리마다 별이 뜹니다")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.85))
                }

                Spacer()

                VStack(spacing: 12) {
                    // ① Apple 로그인 (1순위)
                    SignInWithAppleButton(.signIn) { request in
                        request.requestedScopes = [.fullName, .email]
                    } onCompletion: { result in
                        handleApple(result)
                    }
                    .signInWithAppleButtonStyle(.white)
                    .frame(height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                    // ② 소셜 로그인 (서버 OAuth 연동 예정 — 자리표시자)
                    socialButton(title: "Google 로 계속하기", system: "g.circle.fill")
                    socialButton(title: "카카오로 계속하기", system: "message.fill")
                    socialButton(title: "네이버로 계속하기", system: "n.square.fill")

                    // ③ 게스트 — 둘러보기
                    Button {
                        // 게스트는 토큰 없이 피드만 둘러보기(현재는 비활성 안내)
                        errorText = "게스트 둘러보기는 곧 제공돼요. 로그인 후 별을 띄워보세요."
                    } label: {
                        Text("로그인 없이 둘러보기")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.white.opacity(0.8))
                            .padding(.top, 4)
                    }
                }
                .padding(.horizontal, 28)
                .disabled(isWorking)

                if let err = errorText {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.9))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                }

                Spacer().frame(height: 24)
            }
            .overlay { if isWorking { ProgressView().tint(.white) } }
        }
    }

    @ViewBuilder
    private func socialButton(title: String, system: String) -> some View {
        Button {
            errorText = "\(title.replacingOccurrences(of: "로 계속하기", with: "")) 연동은 준비 중이에요."
        } label: {
            HStack {
                Image(systemName: system)
                Text(title).font(.callout.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .foregroundStyle(.white)
            .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.25), lineWidth: 1))
        }
    }

    private func handleApple(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let auth):
            guard
                let cred = auth.credential as? ASAuthorizationAppleIDCredential,
                let tokenData = cred.identityToken,
                let token = String(data: tokenData, encoding: .utf8)
            else {
                errorText = "Apple 로그인 정보를 읽지 못했어요."
                return
            }
            let name = [cred.fullName?.familyName, cred.fullName?.givenName]
                .compactMap { $0 }.joined()
            isWorking = true
            Task {
                defer { isWorking = false }
                do {
                    try await session.login(provider: "apple",
                                            identityToken: token,
                                            nickname: name.isEmpty ? nil : name)
                    errorText = nil
                } catch let e as StardustError {
                    errorText = e.errorDescription
                } catch {
                    errorText = "로그인에 실패했어요. 잠시 후 다시 시도해 주세요."
                }
            }
        case .failure:
            // 사용자가 취소한 경우 등 — 조용히 무시
            break
        }
    }
}
