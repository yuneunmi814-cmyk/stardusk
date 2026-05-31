import SwiftUI

/// 1단계: 촬영 — "지금 이곳의 하늘을 '찰칵', 그게 전부예요."
/// 검색창도 카테고리도 없다. 셔터 하나로 짧은 하늘 영상을 담는다.
struct SkyCaptureView: View {
    @ObservedObject var camera: CameraService

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch camera.state {
            case .ready, .recording:
                CameraPreviewView(session: camera.session)
                    .ignoresSafeArea()
                shutterLayer
            case .denied:
                fallback(icon: "camera.metering.none",
                         title: "카메라 권한이 필요해요",
                         body: "하늘을 담으려면 설정에서 카메라 접근을 허용해 주세요.",
                         showSettings: true)
            case .unavailable:
                fallback(icon: "camera.fill",
                         title: "여기선 카메라를 쓸 수 없어요",
                         body: "시뮬레이터에는 카메라가 없어요. 실제 기기에서 하늘을 담아보세요.",
                         showSettings: false)
            case .idle, .configuring:
                ProgressView().tint(.white)
            }
        }
        .onAppear { camera.prepare() }
        .onDisappear { camera.stop() }
    }

    // MARK: 셔터 + 안내

    private var shutterLayer: some View {
        VStack {
            Text("— 검색창도, 카테고리도 없습니다 —")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.6))
                .padding(.top, 12)

            Spacer()

            Text(camera.state == .recording ? "하늘을 담는 중…" : "지금 이곳의 하늘을 '찰칵'\n그게 전부예요")
                .font(.subheadline.weight(.medium))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
                .shadow(radius: 6)
                .padding(.bottom, 20)

            shutterButton
                .padding(.bottom, 36)
        }
    }

    private var shutterButton: some View {
        Button {
            camera.state == .recording ? camera.stopRecording() : camera.startRecording()
        } label: {
            ZStack {
                Circle().stroke(.white, lineWidth: 4).frame(width: 84, height: 84)
                if camera.state == .recording {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.red)
                        .frame(width: 32, height: 32)
                } else {
                    Circle().fill(.white).frame(width: 70, height: 70)
                }
            }
        }
        .accessibilityLabel(camera.state == .recording ? "녹화 중지" : "하늘 담기")
    }

    @ViewBuilder
    private func fallback(icon: String, title: String, body: String, showSettings: Bool) -> some View {
        VStack(spacing: 14) {
            Image(systemName: icon).font(.largeTitle).foregroundStyle(.white.opacity(0.8))
            Text(title).font(.headline).foregroundStyle(.white)
            Text(body)
                .font(.callout)
                .foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.center)
            if showSettings {
                Button("설정 열기") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(32)
    }
}
