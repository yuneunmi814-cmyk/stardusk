import SwiftUI
import MapKit
import CoreLocation

struct SafeZoneSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var homeCoord: CLLocationCoordinate2D?

    var body: some View {
        VStack(spacing: 20) {
            Text("머무는 곳을 한 번만 알려주세요")
                .font(.title2.bold())
            Text("집·회사 근처에서 남긴 별은 자동으로 위치를 흐리게 가려드려요.\n다신 묻지 않을게요.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            // (지도에서 한 지점 선택 → homeCoord 에 바인딩하는 MapReader 등으로 구현)
            MapPinPicker(coordinate: $homeCoord)
                .frame(height: 320)
                .clipShape(RoundedRectangle(cornerRadius: 20))

            Button("이 위치를 내 안전지대로 저장") {
                guard let c = homeCoord else { return }
                SafeZoneManager.shared.saveZones([.init(name: "집", lat: c.latitude, lng: c.longitude)])
                SafeZoneManager.shared.markSetupComplete()
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .disabled(homeCoord == nil)

            Button("나중에 할게요") { SafeZoneManager.shared.markSetupComplete(); dismiss() }
                .font(.footnote)
        }
        .padding()
    }
}
