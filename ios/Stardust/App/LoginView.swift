import SwiftUI
import AuthenticationServices
import GoogleSignIn
import KakaoSDKAuth
import KakaoSDKUser

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

                    // ② 소셜 로그인 — Google 은 실제 연동, 카카오/네이버는 자리표시자
                    socialButton(title: "Google 로 계속하기", system: "g.circle.fill") {
                        handleGoogle()
                    }
                    socialButton(title: "카카오로 계속하기", system: "message.fill") {
                        handleKakao()
                    }
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
    private func socialButton(title: String, system: String,
                              action: (() -> Void)? = nil) -> some View {
        Button {
            if let action {
                action()
            } else {
                errorText = "\(title.replacingOccurrences(of: "로 계속하기", with: "")) 연동은 준비 중이에요."
            }
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

    /// Google 로그인 — SDK 로 ID 토큰을 받아 백엔드(provider="google")로 검증 요청.
    private func handleGoogle() {
        guard let presenter = Self.topViewController() else {
            errorText = "로그인 화면을 열 수 없어요."
            return
        }
        isWorking = true
        GIDSignIn.sharedInstance.signIn(withPresenting: presenter) { result, error in
            if let error = error as NSError? {
                isWorking = false
                // -5 = 사용자가 취소 → 조용히 무시
                if error.code != -5 { errorText = "Google 로그인에 실패했어요." }
                return
            }
            guard let idToken = result?.user.idToken?.tokenString else {
                isWorking = false
                errorText = "Google 로그인 정보를 읽지 못했어요."
                return
            }
            let name = result?.user.profile?.name
            Task {
                defer { isWorking = false }
                do {
                    try await session.login(provider: "google",
                                            identityToken: idToken,
                                            nickname: name)
                    errorText = nil
                } catch let e as StardustError {
                    errorText = e.errorDescription
                } catch {
                    errorText = "로그인에 실패했어요. 잠시 후 다시 시도해 주세요."
                }
            }
        }
    }

    /// 카카오 로그인 — 카카오톡 앱이 있으면 앱으로, 없으면 카카오계정으로.
    /// access_token 을 받아 백엔드(provider="kakao")로 검증 요청한다.
    private func handleKakao() {
        isWorking = true
        let completion: (OAuthToken?, Error?) -> Void = { token, error in
            if error != nil {
                isWorking = false
                errorText = "카카오 로그인에 실패했어요."
                return
            }
            guard let accessToken = token?.accessToken else {
                isWorking = false
                errorText = "카카오 로그인 정보를 읽지 못했어요."
                return
            }
            Task {
                defer { isWorking = false }
                do {
                    try await session.login(provider: "kakao",
                                            identityToken: accessToken,
                                            nickname: nil)
                    errorText = nil
                } catch let e as StardustError {
                    errorText = e.errorDescription
                } catch {
                    errorText = "로그인에 실패했어요. 잠시 후 다시 시도해 주세요."
                }
            }
        }
        if UserApi.isKakaoTalkLoginAvailable() {
            UserApi.shared.loginWithKakaoTalk(completion: completion)
        } else {
            UserApi.shared.loginWithKakaoAccount(completion: completion)
        }
    }

    /// 현재 화면 최상단 뷰 컨트롤러(Google SDK 모달 프리젠터용).
    private static func topViewController() -> UIViewController? {
        let keyWindow = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
        var top = keyWindow?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}
