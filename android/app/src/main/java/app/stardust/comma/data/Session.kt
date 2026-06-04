package app.stardust.comma.data

import com.squareup.moshi.Moshi
import com.squareup.moshi.kotlin.reflect.KotlinJsonAdapterFactory
import okhttp3.Authenticator
import okhttp3.Interceptor
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response
import okhttp3.Route
import org.json.JSONObject
import retrofit2.Retrofit
import retrofit2.converter.moshi.MoshiConverterFactory

/**
 * 세션 + 네트워킹 싱글톤. iOS 와 동일한 백엔드 호출.
 * - 게스트 토큰 자동 발급
 * - 401(만료) 시 게스트 토큰을 재발급해 원요청을 1회 자동 재시도(OkHttp Authenticator)
 */
object Session {
    private const val BASE = "https://stardust-api-ts8t.onrender.com/api/v1/"

    @Volatile var accessToken: String? = null; private set
    @Volatile var nickname: String? = null; private set

    private fun setToken(token: String?, name: String? = nickname) { accessToken = token; nickname = name }

    private val authInterceptor = Interceptor { chain ->
        val b = chain.request().newBuilder()
        accessToken?.let { b.header("Authorization", "Bearer $it") }
        chain.proceed(b.build())
    }

    // 401 → 게스트 재발급 후 재시도(동일 요청이 또 401이면 포기)
    private val reauthLock = Any()
    private val authenticator = Authenticator { _: Route?, response: Response ->
        if (responseCount(response) >= 2) return@Authenticator null
        synchronized(reauthLock) {
            val fresh = blockingGuestToken() ?: return@Authenticator null
            accessToken = fresh.first; nickname = fresh.second
            response.request.newBuilder()
                .header("Authorization", "Bearer ${fresh.first}")
                .build()
        }
    }

    private fun responseCount(resp: Response): Int {
        var r: Response? = resp; var c = 1
        while (r?.priorResponse != null) { c++; r = r.priorResponse }
        return c
    }

    /** Authenticator 안에서 쓰는 동기 게스트 발급(별도의 bare 클라이언트, 재귀 방지). */
    private fun blockingGuestToken(): Pair<String, String?>? = runCatching {
        val bare = OkHttpClient()
        val req = Request.Builder()
            .url(BASE + "auth/guest")
            .post("".toRequestBody("application/json".toMediaType()))
            .build()
        bare.newCall(req).execute().use { res ->
            if (!res.isSuccessful) return null
            val data = JSONObject(res.body?.string() ?: return null).getJSONObject("data")
            data.getString("access_token") to data.optString("nickname", null)
        }
    }.getOrNull()

    private val client = OkHttpClient.Builder()
        .addInterceptor(authInterceptor)
        .authenticator(authenticator)
        .build()

    private val moshi = Moshi.Builder().add(KotlinJsonAdapterFactory()).build()

    val api: CommaApi = Retrofit.Builder()
        .baseUrl(BASE).client(client)
        .addConverterFactory(MoshiConverterFactory.create(moshi))
        .build().create(CommaApi::class.java)

    suspend fun ensureGuest() { if (accessToken == null) guestLogin() }

    suspend fun guestLogin() {
        val auth = api.guest().data
        setToken(auth.accessToken, auth.nickname)
    }

    suspend fun deleteAccount() {
        runCatching { api.deleteAccount() }   // 성공/실패 무관하게 로컬 세션은 비운다
        logout()
    }

    fun logout() { accessToken = null; nickname = null }
}
