import SwiftUI
import CoreLocation

@MainActor
final class ExploreViewModel: ObservableObject {
    // 지도 탭: 기준 위치 주변 명소(마커)
    @Published private(set) var mapSpots: [TourSpot] = []
    @Published var selectedSpot: TourSpot?

    // 개인화 큐레이션 덱(§3.6 deck_rank) + 취향 스코어(0 숨은 명소 ~ 1 핫플)
    @Published private(set) var deckSpots: [TourSpot] = []
    @Published private(set) var tasteScore: Double = 0.5

    // 리스트 탭: 통합 검색 결과 + 필터
    @Published private(set) var listItems: [TourSpot] = []
    @Published private(set) var listTotal = 0
    @Published var keyword = ""
    @Published var selectedProvince: String?
    @Published var selectedCity: String?

    // 지역 필터 목록
    @Published private(set) var regions: [RegionGroup] = []

    @Published private(set) var isLoading = false
    @Published var errorText: String?

    private let api = StardustAPI.shared

    var cities: [String] {
        regions.first { $0.province == selectedProvince }?.cities ?? []
    }

    // MARK: 지도 탭

    func loadMap(center: CLLocationCoordinate2D) async {
        isLoading = true; defer { isLoading = false }
        do {
            mapSpots = try await api.fetchNearbySpots(
                lat: center.latitude, lng: center.longitude, radius: 15000, limit: 100)
            errorText = nil
        } catch let e as StardustError {
            errorText = e.errorDescription
        } catch {
            errorText = "주변 명소를 불러오지 못했어요."
        }
    }

    // MARK: 개인화 덱 · 취향 학습(§3.6)

    /// '내 주변 별 탐색' 큐레이션 덱을 취향 반영 순(deck_rank)으로 불러온다.
    func loadDeck(center: CLLocationCoordinate2D) async {
        do {
            deckSpots = try await api.fetchDeck(
                lat: center.latitude, lng: center.longitude, radius: 15000, limit: 20)
            errorText = nil
        } catch let e as StardustError {
            errorText = e.errorDescription
        } catch {
            errorText = "추천 카드를 불러오지 못했어요."
        }
    }

    /// 카드 스와이프(Like/Pass)를 취향 학습에 반영. Refresh 는 호출하지 않는다(판단 보류).
    /// 학습 실패는 탐색 흐름을 막지 않도록 조용히 무시한다.
    func recordSwipe(_ action: String, spot: TourSpot) async {
        guard let result = try? await api.postSwipe(tourId: spot.tourId, action: action) else { return }
        if result.learned { tasteScore = result.tasteScore }
    }

    // MARK: 리스트 탭

    func loadRegions() async {
        guard regions.isEmpty else { return }
        regions = (try? await api.fetchRegions()) ?? []
    }

    func runSearch(center: CLLocationCoordinate2D?) async {
        isLoading = true; defer { isLoading = false }
        do {
            let data = try await api.searchSpots(
                keyword: keyword.isEmpty ? nil : keyword,
                province: selectedProvince,
                city: selectedCity,
                lat: center?.latitude, lng: center?.longitude,
                limit: 50, offset: 0)
            listItems = data.items
            listTotal = data.total
            errorText = nil
        } catch let e as StardustError {
            errorText = e.errorDescription
        } catch {
            errorText = "검색에 실패했어요."
        }
    }

    func selectProvince(_ p: String?) {
        selectedProvince = p
        selectedCity = nil
    }
}
