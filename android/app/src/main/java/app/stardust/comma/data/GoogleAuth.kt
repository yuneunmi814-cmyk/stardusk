package app.stardust.comma.data

import android.content.Context
import androidx.credentials.CredentialManager
import androidx.credentials.GetCredentialRequest
import com.google.android.libraries.identity.googleid.GetGoogleIdOption
import com.google.android.libraries.identity.googleid.GoogleIdTokenCredential

/**
 * Credential Manager 로 Google ID 토큰을 받아온다.
 * serverClientId = Google Cloud 의 **웹 클라이언트 ID**(백엔드 GOOGLE_CLIENT_ID 와 동일해야 함).
 * BuildConfig.GOOGLE_WEB_CLIENT_ID(local.properties 의 GOOGLE_WEB_CLIENT_ID)에서 주입.
 */
suspend fun googleIdToken(ctx: Context, webClientId: String): String {
    require(webClientId.isNotBlank()) { "GOOGLE_WEB_CLIENT_ID 미설정" }
    val option = GetGoogleIdOption.Builder()
        .setServerClientId(webClientId)
        .setFilterByAuthorizedAccounts(false)   // 모든 구글 계정 선택 허용
        .build()
    val request = GetCredentialRequest.Builder().addCredentialOption(option).build()
    val result = CredentialManager.create(ctx).getCredential(ctx, request)
    val cred = GoogleIdTokenCredential.createFrom(result.credential.data)
    return cred.idToken
}
