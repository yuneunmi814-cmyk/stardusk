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
    @State private var breathe = false   // orb 호흡 애니메이션

    var body: some View {
        ZStack {
            SkyGradientBackground(mood: .dawn)   // HTML 로그인과 동일한 새벽 하늘
                .ignoresSafeArea()

            VStack(spacing: 28) {
                Spacer()

                VStack(spacing: 14) {
                    // HTML .orb — 천천히 호흡하는 빛무리(해)
                    Circle()
                        .fill(RadialGradient(
                            colors: [.white,
                                     Color(hex: "#CDB4F0"),
                                     Color(hex: "#A6C8F0"),
                                     Color(hex: "#F6C5D8"),
                                     Color(hex: "#FBD9BF")],
                            center: UnitPoint(x: 0.36, y: 0.30),
                            startRadius: 2, endRadius: 60))
                        .frame(width: 96, height: 96)
                        .shadow(color: Color(hex: "#F6C5D8").opacity(0.55), radius: 26)
                        .scaleEffect(breathe ? 1.06 : 1.0)
                        .animation(.easeInOut(duration: 3.2).repeatForever(autoreverses: true),
                                   value: breathe)

                    Text("STARDUST")
                        .font(.largeTitle.bold())
                        .foregroundStyle(.white)
                        .tracking(4)
                    Text("당신이 머문 자리마다\n별이 뜹니다")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                }

                Spacer()

                VStack(spacing: 9) {
                    // ① Apple — 공식 버튼(HTML btn-apple: 검정)
                    SignInWithAppleButton(.continue) { request in
                        request.requestedScopes = [.fullName, .email]
                    } onCompletion: { result in
                        handleApple(result)
                    }
                    .signInWithAppleButtonStyle(.black)
                    .frame(height: 50)
                    .clipShape(RoundedRectangle(cornerRadius: 15))

                    // ② 브랜드 색 소셜 버튼 (HTML btn-google/kakao/naver)
                    brandButton("Google로 계속하기", icon: "g.circle.fill",
                                bg: .white, fg: Color(hex: "#1F1F1F"), bordered: true) {
                        handleGoogle()
                    }
                    brandButton("카카오로 계속하기", icon: "message.fill",
                                bg: Color(hex: "#FEE500"), fg: Color(hex: "#191600")) {
                        handleKakao()
                    }
                    brandButton("네이버로 계속하기", icon: "n.square.fill",
                                bg: Color(hex: "#03C75A"), fg: .white) {
                        handleNaver()
                    }

                    // ③ 게스트 — HTML btn-ghost
                    Button {
                        errorText = "게스트 둘러보기는 곧 제공돼요. 로그인 후 별을 띄워보세요."
                    } label: {
                        Text("둘러보기 (게스트)")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(maxWidth: .infinity).frame(height: 48)
                            .foregroundStyle(.white)
                            .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 15))
                            .overlay(RoundedRectangle(cornerRadius: 15)
                                .stroke(.white.opacity(0.25), lineWidth: 1))
                    }

                    Text("토큰은 Keychain에 안전하게 보관됩니다")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.white.opacity(0.5))
                        .padding(.top, 6)
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
        .onAppear { breathe = true }
    }

    /// HTML btn-google/kakao/naver — 브랜드 색 소셜 버튼.
    @ViewBuilder
    private func brandButton(_ title: String, icon: String,
                             bg: Color, fg: Color, bordered: Bool = false,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: icon)
                Text(title).font(.system(size: 14, weight: .semibold))
            }
            .frame(maxWidth: .infinity).frame(height: 50)
            .foregroundStyle(fg)
            .background(bg, in: RoundedRectangle(cornerRadius: 15))
            .overlay {
                if bordered {
                    RoundedRectangle(cornerRadius: 15).stroke(.black.opacity(0.12), lineWidth: 1)
                }
            }
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

    /// 네이버 로그인 — SDK 로 access_token 을 받아 백엔드(provider="naver")로 검증.
    private func handleNaver() {
        isWorking = true
        NaverLoginManager.shared.login { result in
            switch result {
            case .failure:
                isWorking = false
                errorText = "네이버 로그인에 실패했어요."
            case .success(let accessToken):
                Task {
                    defer { isWorking = false }
                    do {
                        try await session.login(provider: "naver",
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
