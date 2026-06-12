package app.stardust.comma.data

import com.squareup.moshi.Json
import com.squareup.moshi.JsonClass
import retrofit2.http.Body
import retrofit2.http.DELETE
import retrofit2.http.GET
import retrofit2.http.POST
import retrofit2.http.Path
import retrofit2.http.Query

// ── 응답 봉투 {status, data} ─────────────────────────────
@JsonClass(generateAdapter = true)
data class Envelope<T>(val status: String?, val data: T)

@JsonClass(generateAdapter = true)
data class AuthData(
    @Json(name = "user_id") val userId: String,
    val nickname: String,
    @Json(name = "access_token") val accessToken: String,
    @Json(name = "expires_in") val expiresIn: Int,
)

@JsonClass(generateAdapter = true)
data class TourSpot(
    @Json(name = "tour_id") val tourId: String,
    @Json(name = "spot_name") val spotName: String,
    val region: String?,
    val address: String?,
    @Json(name = "image_url") val imageUrl: String?,
    val latitude: Double,
    val longitude: Double,
    @Json(name = "distance_meters") val distanceMeters: Int?,
    val label: String?,
    @Json(name = "popularity_score") val popularityScore: Double?,
) {
    /** KTO 이미지는 http 로 내려오므로 https 로 승격(안드로이드 cleartext 차단 회피). */
    val secureImageUrl: String?
        get() = imageUrl?.let { if (it.startsWith("http://")) "https://" + it.removePrefix("http://") else it }

    val distanceText: String?
        get() = distanceMeters?.let { if (it >= 1000) String.format("%.1fkm", it / 1000.0) else "${it}m" }
}

@JsonClass(generateAdapter = true)
data class LoginBody(
    val provider: String,
    @Json(name = "identity_token") val identityToken: String,
    val nickname: String? = null,
)

@JsonClass(generateAdapter = true)
data class SwipeBody(@Json(name = "tour_id") val tourId: String, val action: String)

@JsonClass(generateAdapter = true)
data class SwipeData(
    @Json(name = "taste_score") val tasteScore: Double,
    val learned: Boolean,
)

@JsonClass(generateAdapter = true)
data class SpotDetail(
    @Json(name = "content_id") val contentId: String,
    val overview: String?,
)

// ── 도보안내(길찾기) ─────────────────────────────────────
@JsonClass(generateAdapter = true)
data class WalkPoint(val lat: Double, val lng: Double)

@JsonClass(generateAdapter = true)
data class WalkStep(
    val lat: Double,
    val lng: Double,
    @Json(name = "distance_m") val distanceM: Int,
    val turn: String,            // left | right | straight
    val instruction: String,     // 한국어 안내문
)

@JsonClass(generateAdapter = true)
data class WalkRoute(
    val source: String,          // tmap(실경로) | straight(직선 폴백)
    @Json(name = "total_m") val totalM: Int,
    @Json(name = "eta_min") val etaMin: Int,
    val path: List<WalkPoint>,
    val steps: List<WalkStep>,
) {
    val totalText: String
        get() = if (totalM >= 1000) String.format("%.1fkm", totalM / 1000.0) else "${totalM}m"
}

interface CommaApi {
    @POST("auth/guest")
    suspend fun guest(): Envelope<AuthData>

    @POST("auth/login")
    suspend fun login(@Body body: LoginBody): Envelope<AuthData>

    @GET("tour/spots")
    suspend fun nearby(
        @Query("latitude") lat: Double,
        @Query("longitude") lng: Double,
        @Query("radius") radius: Int = 15000,
        @Query("limit") limit: Int = 100,
    ): Envelope<List<TourSpot>>

    @GET("tour/deck")
    suspend fun deck(
        @Query("latitude") lat: Double,
        @Query("longitude") lng: Double,
        @Query("radius") radius: Int = 15000,
        @Query("limit") limit: Int = 20,
    ): Envelope<List<TourSpot>>

    @GET("tour/saved")
    suspend fun saved(): Envelope<List<TourSpot>>

    @DELETE("tour/saved/{id}")
    suspend fun unsave(@Path("id") id: String): Envelope<List<TourSpot>>

    @POST("tour/swipe")
    suspend fun swipe(@Body body: SwipeBody): Envelope<SwipeData>

    @GET("tour/{id}/detail")
    suspend fun detail(@Path("id") id: String): Envelope<SpotDetail>

    @GET("tour/walk-route")
    suspend fun walkRoute(
        @Query("from_lat") fromLat: Double,
        @Query("from_lng") fromLng: Double,
        @Query("to_lat") toLat: Double,
        @Query("to_lng") toLng: Double,
    ): Envelope<WalkRoute>

    @DELETE("auth/me")
    suspend fun deleteAccount(): retrofit2.Response<Unit>
}
