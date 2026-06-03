import SwiftUI
import CoreLocation
import AVFoundation

/// 풀스크린 추천 카드 — 왼쪽 스와이프=패스 / 오른쪽 스와이프=라이크 (버튼으로도 가능).
/// 카드에서 길찾기(외부 지도 핸드오프)·도슨트(상세설명 음성)를 바로 쓸 수 있다.
/// 탭바를 가리지 않도록 시트가 아닌 탐색 탭 위 오버레이로 띄운다.
@available(iOS 17.0, *)
struct SpotCurationView: View {
    let spots: [TourSpot]
    @ObservedObject var vm: ExploreViewModel
    var onClose: () -> Void
    var onLike: (TourSpot) -> Void

    @StateObject private var docent = DocentSpeaker()
    @State private var index = 0
    @State private var drag: CGSize = .zero
    @State private var handoff: [ExternalMapOption] = []
    @State private var showHandoff = false
    @State private var docentLoadingId: String?

    private let threshold: CGFloat = 110

    var body: some View {
        ZStack {
            SkyGradientBackground(mood: .night).ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 0)
                if index < spots.count {
                    cardArea(spots[index])
                } else {
                    finishedState
                }
                Spacer(minLength: 0)
                if index < spots.count { actionButtons(spots[index]) }
            }
            .padding(.top, 8).padding(.bottom, 16)
        }
        .confirmationDialog("길안내 앱 선택", isPresented: $showHandoff, titleVisibility: .visible) {
            ForEach(handoff) { opt in Button(opt.label) { opt.action() } }
            Button("취소", role: .cancel) {}
        }
        .onDisappear { docent.stop() }
    }

    // MARK: 상단 바
    private var topBar: some View {
        HStack {
            Button { docent.stop(); onClose() } label: {
                Image(systemName: "xmark").font(.headline).foregroundStyle(.white)
                    .frame(width: 40, height: 40).background(.white.opacity(0.14), in: Circle())
            }
            Spacer()
            Text("내 주변, 어디로 갈까요?").font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.9))
            Spacer()
            Color.clear.frame(width: 40, height: 40)
        }
        .padding(.horizontal, 18)
    }

    // MARK: 카드
    private func cardArea(_ spot: TourSpot) -> some View {
        let angle = Double(drag.width / 18)
        return card(spot)
            .offset(x: drag.width, y: drag.height * 0.15)
            .rotationEffect(.degrees(angle))
            .overlay(alignment: .topLeading) { decisionStamp(.pass).opacity(stampOpacity(forLike: false)) }
            .overlay(alignment: .topTrailing) { decisionStamp(.like).opacity(stampOpacity(forLike: true)) }
            .gesture(
                DragGesture()
                    .onChanged { drag = $0.translation }
                    .onEnded { value in
                        if value.translation.width < -threshold { pass(spot) }
                        else if value.translation.width > threshold { like(spot) }
                        else { withAnimation(.spring) { drag = .zero } }
                    }
            )
            .padding(.horizontal, 18)
            .id(spot.id)
            .transition(.opacity)
    }

    private func card(_ spot: TourSpot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Color.clear 가 레이아웃 크기(가로=카드폭, 세로=320)를 고정하고,
            // 이미지는 overlay 로만 채워 scaledToFill 이 카드 폭을 밀어내지 못하게 한다.
            SpotImage(url: spot.imageURL) {
                LinearGradient(colors: [Color(hex: "#3A4A86"), Color(hex: "#16224D")],
                               startPoint: .top, endPoint: .bottom)
            }
                .frame(maxWidth: .infinity)
                .frame(height: 320)
                .clipped()
                .overlay(alignment: .topLeading) {
                    if let badge = spot.tasteBadge {
                        Label(badge.text, systemImage: badge.symbol)
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(.ultraThinMaterial, in: Capsule())
                            .padding(14)
                    }
                }

            VStack(alignment: .leading, spacing: 10) {
                Text(spot.spotName).font(.title2.weight(.bold)).lineLimit(2)
                if let addr = spot.address ?? spot.region {
                    Label(addr, systemImage: "mappin").font(.subheadline)
                        .foregroundStyle(.secondary).lineLimit(1)
                }
                if let d = spot.distanceText {
                    Label(d, systemImage: "figure.walk").font(.subheadline).foregroundStyle(.secondary)
                }
                HStack(spacing: 10) {
                    cardChip("길찾기", "location.north.line.fill") { startNavigation(spot) }
                    cardChip(docent.speakingId == spot.id ? "정지" : "안내 듣기",
                             docentLoadingId == spot.id ? "hourglass" :
                                (docent.speakingId == spot.id ? "stop.fill" : "speaker.wave.2.fill")) {
                        toggleDocent(spot)
                    }
                }
                .padding(.top, 2)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
        .clipShape(RoundedRectangle(cornerRadius: 24))   // 이미지 모서리가 카드 둥근모서리 밖으로 안 나가게
        .shadow(color: .black.opacity(0.3), radius: 18, y: 8)
    }

    private func cardChip(_ label: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(label, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14).frame(height: 42)
                .frame(maxWidth: .infinity)
                .background(Color(hex: "#5794E4").opacity(0.16), in: RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(Color(hex: "#5794E4"))
        }
    }

    // MARK: 하단 패스/라이크 버튼
    private func actionButtons(_ spot: TourSpot) -> some View {
        HStack(spacing: 40) {
            bigButton("xmark", Color(.systemGray)) { pass(spot) }
            bigButton("heart.fill", Color(hex: "#5794E4")) { like(spot) }
        }
        .padding(.top, 14)
    }

    private func bigButton(_ icon: String, _ color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.title.weight(.semibold)).foregroundStyle(.white)
                .frame(width: 66, height: 66)
                .background(color, in: Circle())
                .shadow(color: color.opacity(0.5), radius: 10, y: 4)
        }
    }

    // MARK: 다 본 상태
    private var finishedState: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal.fill").font(.system(size: 54))
                .foregroundStyle(Color(hex: "#5794E4"))
            Text("주변 별을 모두 둘러봤어요").font(.headline).foregroundStyle(.white)
            Button { index = 0; drag = .zero } label: {
                Label("처음부터 다시", systemImage: "arrow.clockwise")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 18).frame(height: 44)
                    .background(.white.opacity(0.14), in: Capsule())
            }
            Button("닫기") { onClose() }.foregroundStyle(.white.opacity(0.7)).padding(.top, 4)
        }
    }

    // MARK: 결정 스탬프
    private enum Decision { case like, pass }
    private func decisionStamp(_ d: Decision) -> some View {
        Text(d == .like ? "LIKE" : "PASS")
            .font(.system(size: 30, weight: .heavy))
            .foregroundStyle(d == .like ? Color(hex: "#5794E4") : Color(.systemGray))
            .padding(.horizontal, 12).padding(.vertical, 6)
            .overlay(RoundedRectangle(cornerRadius: 10)
                .stroke(d == .like ? Color(hex: "#5794E4") : Color(.systemGray), lineWidth: 4))
            .rotationEffect(.degrees(d == .like ? -16 : 16))
            .padding(28)
    }
    private func stampOpacity(forLike: Bool) -> Double {
        let x = drag.width
        if forLike { return x > 0 ? Double(min(x / threshold, 1)) : 0 }
        else { return x < 0 ? Double(min(-x / threshold, 1)) : 0 }
    }

    // MARK: 액션
    private func like(_ spot: TourSpot) {
        Task { await vm.recordSwipe("like", spot: spot) }
        onLike(spot)
        advance(off: 520)
    }
    private func pass(_ spot: TourSpot) {
        Task { await vm.recordSwipe("pass", spot: spot) }
        advance(off: -520)
    }
    private func advance(off: CGFloat) {
        docent.stop()
        withAnimation(.easeIn(duration: 0.22)) { drag.width = off }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            index += 1
            drag = .zero
        }
    }

    private func startNavigation(_ spot: TourSpot) {
        let dest = CLLocationCoordinate2D(latitude: spot.latitude, longitude: spot.longitude)
        handoff = ExternalMap.options(to: dest, name: spot.spotName)
        showHandoff = true
    }

    private func toggleDocent(_ spot: TourSpot) {
        if docent.speakingId == spot.id { docent.stop(); return }
        docentLoadingId = spot.id
        Task {
            let text: String
            if let detail = try? await StardustAPI.shared.fetchSpotDetail(tourId: spot.tourId),
               let ov = detail.overview, !ov.isEmpty {
                text = ov
            } else {
                text = "\(spot.spotName). \(spot.address ?? spot.region ?? "")에 위치한 관광지입니다."
            }
            docentLoadingId = nil
            docent.speak(id: spot.id, text: text)
        }
    }
}

/// 도슨트 음성(기기 TTS, 한국어). 같은 카드를 다시 누르면 정지.
@MainActor
final class DocentSpeaker: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published private(set) var speakingId: String?
    private let synth = AVSpeechSynthesizer()

    override init() {
        super.init()
        synth.delegate = self
    }

    func speak(id: String, text: String) {
        synth.stopSpeaking(at: .immediate)
        try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        let u = AVSpeechUtterance(string: text)
        u.voice = AVSpeechSynthesisVoice(language: "ko-KR")
        u.rate = 0.5
        speakingId = id
        synth.speak(u)
    }

    func stop() {
        synth.stopSpeaking(at: .immediate)
        speakingId = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer,
                                       didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.speakingId = nil }
    }
}
