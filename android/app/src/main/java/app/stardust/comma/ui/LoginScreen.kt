package app.stardust.comma.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.platform.LocalContext
import app.stardust.comma.BuildConfig
import app.stardust.comma.data.Session
import app.stardust.comma.data.googleIdToken
import app.stardust.comma.ui.theme.MeadowAccent
import app.stardust.comma.ui.theme.MeadowDeep
import app.stardust.comma.ui.theme.meadowBackgroundBrush
import kotlinx.coroutines.launch

@Composable
fun LoginScreen(onEnter: () -> Unit) {
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    var working by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }

    Box(
        Modifier.fillMaxSize().background(meadowBackgroundBrush()),
        contentAlignment = Alignment.Center
    ) {
        Column(
            Modifier.fillMaxSize().padding(28.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Spacer(Modifier.weight(1f))
            Text("쉼표", color = Color.White, fontSize = 40.sp, fontWeight = FontWeight.Medium, letterSpacing = 8.sp)
            Spacer(Modifier.height(10.dp))
            Text(
                "잠시 멈추어,\n숨을 고르다",
                color = Color.White.copy(alpha = 0.9f),
                textAlign = TextAlign.Center,
                lineHeight = 22.sp,
            )
            Spacer(Modifier.weight(1f))

            Button(
                onClick = {
                    if (working) return@Button
                    working = true; error = null
                    scope.launch {
                        try { Session.guestLogin(); onEnter() }
                        catch (e: Exception) { error = "진입에 실패했어요. 잠시 후 다시 시도해 주세요." }
                        finally { working = false }
                    }
                },
                modifier = Modifier.fillMaxWidth().height(52.dp),
                shape = RoundedCornerShape(14.dp),
                colors = ButtonDefaults.buttonColors(containerColor = MeadowAccent, contentColor = Color.White),
            ) { Text(if (working) "들어가는 중…" else "둘러보기 (게스트)", fontWeight = FontWeight.Medium) }

            Spacer(Modifier.height(10.dp))
            OutlinedButton(
                onClick = {
                    if (working) return@OutlinedButton
                    working = true; error = null
                    scope.launch {
                        try {
                            val idToken = googleIdToken(ctx, BuildConfig.GOOGLE_WEB_CLIENT_ID)
                            Session.loginGoogle(idToken); onEnter()
                        } catch (e: Exception) {
                            error = if (BuildConfig.GOOGLE_WEB_CLIENT_ID.isBlank())
                                "Google 로그인은 설정 후 사용할 수 있어요(웹 클라이언트 ID 필요)."
                            else "Google 로그인에 실패했어요."
                        } finally { working = false }
                    }
                },
                modifier = Modifier.fillMaxWidth().height(52.dp),
                shape = RoundedCornerShape(14.dp),
                colors = ButtonDefaults.outlinedButtonColors(contentColor = Color.White),
            ) { Text("Google로 계속하기", fontWeight = FontWeight.Medium) }

            error?.let {
                Spacer(Modifier.height(12.dp))
                Text(it, color = Color.White, textAlign = TextAlign.Center)
            }
            // TODO: Google 로그인(Credential Manager) — 게스트로 먼저 동작 확인 후 추가
            Spacer(Modifier.height(24.dp))
        }
    }
}
