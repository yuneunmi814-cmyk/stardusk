package app.stardust.comma.data

import com.squareup.moshi.Moshi
import com.squareup.moshi.kotlin.reflect.KotlinJsonAdapterFactory
import okhttp3.Interceptor
import okhttp3.OkHttpClient
import retrofit2.Retrofit
import retrofit2.converter.moshi.MoshiConverterFactory

/**
 * 세션 + 네트워킹 싱글톤. iOS 와 동일한 백엔드를 호출한다.
 * - 게스트 토큰 자동 발급, 401 시 게스트 재발급 후 1회 재시도.
 */
object Session {
    private const val BASE = "https://stardust-api-ts8t.onrender.com/api/v1/"

    @Volatile var accessToken: String? = null
        private set
    @Volatile var nickname: String? = null
        private set

    private val authInterceptor = Interceptor { chain ->
        val req = chain.request().newBuilder().apply {
            accessToken?.let { header("Authorization", "Bearer $it") }
        }.build()
        chain.proceed(req)
    }

    private val client = OkHttpClient.Builder()
        .addInterceptor(authInterceptor)
        .build()

    private val moshi = Moshi.Builder().add(KotlinJsonAdapterFactory()).build()

    val api: CommaApi = Retrofit.Builder()
        .baseUrl(BASE)
        .client(client)
        .addConverterFactory(MoshiConverterFactory.create(moshi))
        .build()
        .create(CommaApi::class.java)

    suspend fun ensureGuest() {
        if (accessToken == null) guestLogin()
    }

    suspend fun guestLogin() {
        val auth = api.guest().data
        accessToken = auth.accessToken
        nickname = auth.nickname
    }

    fun logout() { accessToken = null; nickname = null }
}
