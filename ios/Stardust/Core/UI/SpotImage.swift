import SwiftUI

/// 명소 원격 사진 표시 컴포넌트.
/// KTO(한국관광공사) 대표사진은 **항상 우하단에 워터마크 로고**가 박혀 있다.
/// 이를 지우기 위해 이미지를 좌상단(.topLeading) 기준으로 살짝 확대해
/// 오른쪽·아래만 크롭한다 → 워터마크가 프레임 밖으로 밀려나 보이지 않는다.
/// (좌상단 피사체 구도는 보존)
struct SpotImage<Placeholder: View>: View {
    let url: URL?
    var zoom: CGFloat = 1.22            // 우·하단 약 18% 크롭(워터마크 제거)
    @ViewBuilder var placeholder: () -> Placeholder

    var body: some View {
        Color.clear
            .overlay {
                AsyncImage(url: url) { img in
                    img.resizable()
                        .scaledToFill()
                        .scaleEffect(zoom, anchor: .topLeading)
                } placeholder: {
                    placeholder()
                }
            }
            .clipped()
    }
}
