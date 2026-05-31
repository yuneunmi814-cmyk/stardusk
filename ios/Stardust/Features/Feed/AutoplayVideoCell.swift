import SwiftUI

struct AutoplayVideoCell<Item: PlayableSky>: View where Item.ID == String {
    let video: Item
    @EnvironmentObject private var stage: FeedStageCoordinator
    @StateObject private var vm: VideoCellViewModel

    init(video: Item) {
        self.video = video
        _vm = StateObject(wrappedValue: VideoCellViewModel(url: video.videoURL))
    }

    var body: some View {
        GeometryReader { geo in
            let frame = geo.frame(in: .global)
            let screenMidY = UIScreen.main.bounds.midY
            let distance = abs(frame.midY - screenMidY)
            let isOnScreen = frame.maxY > 0 && frame.minY < UIScreen.main.bounds.height

            ZStack {
                // 썸네일을 먼저 깔아 두면 로딩 중에도 색감이 유지된다(스켈레톤 대체)
                AsyncImage(url: video.thumbnailURL) { img in
                    img.resizable().scaledToFill()
                } placeholder: {
                    Color(hex: video.skyColorHex).opacity(0.4)
                }

                if let player = vm.activePlayer {
                    PlayerLayerView(player: player)
                        .transition(.opacity)
                }

                // 감정 라벨 오버레이 (서버 자동 생성값)
                VStack { Spacer()
                    HStack {
                        if let emotion = video.emotionLabel {
                            Text(emotion)
                                .font(.caption.bold())
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(.ultraThinMaterial, in: Capsule())
                        }
                        Spacer()
                    }.padding(12)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 18))
            // 가시성/거리 보고 → 코디네이터가 무대 중앙 셀 선정
            .onChange(of: frame.midY) { _, _ in
                stage.report(id: video.id, distanceToCenter: isOnScreen ? distance : nil)
            }
            .onAppear {
                stage.report(id: video.id, distanceToCenter: isOnScreen ? distance : nil)
            }
            // 화면 완전 이탈 → 즉시 해제(누수 차단)
            .onDisappear {
                stage.report(id: video.id, distanceToCenter: nil)
                vm.teardown()
            }
            // 내가 '무대 주인공'이 되면 재생, 아니면 일시정지
            .onChange(of: stage.activeID) { _, active in
                if active == video.id { vm.activate() } else { vm.pause() }
            }
        }
        .aspectRatio(9/16, contentMode: .fit)   // 세로 하늘 영상 기준
    }
}
