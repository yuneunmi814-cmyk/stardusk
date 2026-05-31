import SwiftUI
import MapKit
import CoreLocation

@available(iOS 17.0, *)
struct MapPinPicker: View {
    @Binding var coordinate: CLLocationCoordinate2D?

    // 기본 카메라: 강원 강릉(서비스 주무대) 근방
    @State private var camera: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 37.7519, longitude: 128.8761),
            span: MKCoordinateSpan(latitudeDelta: 0.03, longitudeDelta: 0.03)
        )
    )
    @State private var centerCoordinate = CLLocationCoordinate2D(latitude: 37.7519, longitude: 128.8761)

    var body: some View {
        ZStack {
            MapReader { proxy in
                Map(position: $camera) {
                    if let coordinate {
                        Annotation("내 안전지대", coordinate: coordinate) {
                            Image(systemName: "house.circle.fill")
                                .font(.title)
                                .foregroundStyle(.white, Color(hex: "#7FA8E0"))
                                .shadow(radius: 4)
                        }
                    }
                    UserAnnotation()   // 현재 위치 점
                }
                .mapControls { MapUserLocationButton(); MapCompass() }
                // ① 지도를 탭하면 그 지점을 좌표로 변환해 선택
                .onTapGesture { screenPoint in
                    if let c = proxy.convert(screenPoint, from: .local) {
                        withAnimation(.spring) { coordinate = c }
                    }
                }
                // ② 카메라가 멈출 때마다 중심 좌표를 기억(중앙 핀 방식 지원)
                .onMapCameraChange(frequency: .onEnd) { ctx in
                    centerCoordinate = ctx.region.center
                }
            }

            // 중앙 고정 조준 핀: 탭하지 않아도 '지도 중심'을 지정할 수 있게 한다.
            if coordinate == nil {
                Image(systemName: "scope")
                    .font(.title)
                    .foregroundStyle(Color(hex: "#7FA8E0"))
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .bottom) {
            Button {
                withAnimation(.spring) { coordinate = centerCoordinate }
            } label: {
                Label("이 지도 중심으로 지정", systemImage: "mappin.and.ellipse")
                    .font(.caption.bold())
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(.ultraThinMaterial, in: Capsule())
            }
            .padding(.bottom, 12)
        }
    }
}
