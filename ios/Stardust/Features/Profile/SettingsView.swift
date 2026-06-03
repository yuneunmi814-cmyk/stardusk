import SwiftUI

/// 앱 설정 — 계정·알림·위치·약관·정보. 홈(탐색) 우상단 톱니에서 진입.
struct SettingsView: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    @AppStorage("marketingOptIn") private var marketingOptIn = false

    @State private var showLogoutConfirm = false
    @State private var showDeleteConfirm = false
    @State private var working = false
    @State private var errorText: String?

    private let privacyURL = URL(string: "https://yuneunmi814-cmyk.github.io/stardusk/privacy.html")!
    private let supportEmail = "yuneunmi814@gmail.com"
    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(v) (\(b))"
    }

    var body: some View {
        NavigationStack {
            Form {
                // 계정
                Section("계정") {
                    HStack {
                        Label("닉네임", systemImage: "person.fill")
                        Spacer()
                        Text(session.nickname ?? "여행자").foregroundStyle(.secondary)
                    }
                    Button { showLogoutConfirm = true } label: {
                        Label("로그아웃", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                    Button(role: .destructive) { showDeleteConfirm = true } label: {
                        Label("회원 탈퇴", systemImage: "trash")
                    }
                }
                .listRowBackground(Meadow.surface(scheme))

                // 알림·위치
                Section("권한") {
                    Button { openSystemSettings() } label: {
                        Label("알림 설정", systemImage: "bell.badge")
                    }
                    Button { openSystemSettings() } label: {
                        Label("위치 권한", systemImage: "location")
                    }
                    Toggle(isOn: $marketingOptIn) {
                        Label("마케팅·개인화 푸시 동의", systemImage: "sparkles")
                    }
                    .tint(Color.meadowDeep)
                }
                .listRowBackground(Meadow.surface(scheme))

                // 약관·정책
                Section("약관 및 정책") {
                    Link(destination: privacyURL) {
                        Label("개인정보 처리방침", systemImage: "hand.raised")
                    }
                    Link(destination: privacyURL) {
                        Label("이용약관", systemImage: "doc.text")
                    }
                }
                .listRowBackground(Meadow.surface(scheme))

                // 정보
                Section("정보") {
                    HStack {
                        Label("앱 버전", systemImage: "info.circle")
                        Spacer()
                        Text(appVersion).foregroundStyle(.secondary)
                    }
                    Link(destination: URL(string: "mailto:\(supportEmail)")!) {
                        Label("문의하기", systemImage: "envelope")
                    }
                }
                .listRowBackground(Meadow.surface(scheme))

                if let errorText {
                    Section { Text(errorText).font(.footnote).foregroundStyle(.red) }
                        .listRowBackground(Meadow.surface(scheme))
                }
            }
            .scrollContentBackground(.hidden)
            .background(MeadowBackground())
            .tint(Color.meadowDeep)   // 탭바 tint 상속 차단(버튼/링크 보이게) + 초원 악센트
            .foregroundStyle(Meadow.textPrimary(scheme))
            .navigationTitle("설정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("닫기") { dismiss() }
                }
            }
            .overlay { if working { ProgressView().padding(16).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)) } }
            .confirmationDialog("로그아웃 할까요?", isPresented: $showLogoutConfirm, titleVisibility: .visible) {
                Button("로그아웃", role: .destructive) { session.logout() }
                Button("취소", role: .cancel) {}
            }
            .confirmationDialog("정말 탈퇴할까요?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("탈퇴하기", role: .destructive) { performDelete() }
                Button("취소", role: .cancel) {}
            } message: {
                Text("계정과 별·여정·취향 기록이 모두 삭제되며 복구할 수 없어요.")
            }
        }
    }

    private func performDelete() {
        working = true
        Task {
            defer { working = false }
            do {
                try await session.deleteAccount()       // 성공 시 로그아웃 → 로그인 화면
            } catch let e as StardustError {
                if case .unauthorized = e {
                    // 세션 만료 → 로그아웃해 로그인 화면으로(재로그인 후 재시도)
                    errorText = "세션이 만료됐어요. 다시 로그인 후 시도해 주세요."
                    session.logout()
                } else {
                    errorText = e.errorDescription ?? "탈퇴에 실패했어요."
                }
            } catch {
                errorText = "탈퇴에 실패했어요. 잠시 후 다시 시도해 주세요."
            }
        }
    }

    private func openSystemSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}
