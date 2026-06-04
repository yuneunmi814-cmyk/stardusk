package app.stardust.comma.ui

import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import app.stardust.comma.data.Session
import app.stardust.comma.ui.theme.MeadowDeep
import app.stardust.comma.ui.theme.meadowBackgroundBrush
import kotlinx.coroutines.launch

private const val PRIVACY_URL = "https://yuneunmi814-cmyk.github.io/stardusk/privacy.html"

@Composable
fun SettingsScreen(modifier: Modifier = Modifier, onSignedOut: () -> Unit) {
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    var showDelete by remember { mutableStateOf(false) }
    var working by remember { mutableStateOf(false) }

    Box(modifier.fillMaxSize().background(meadowBackgroundBrush())) {
        Column(Modifier.fillMaxSize().padding(20.dp)) {
            Text("설정", fontWeight = FontWeight.Bold, style = MaterialTheme.typography.headlineMedium)
            Spacer(Modifier.height(16.dp))

            Card(shape = RoundedCornerShape(16.dp)) {
                Column {
                    Row(Modifier.fillMaxWidth().padding(16.dp)) {
                        Text("닉네임", fontWeight = FontWeight.Medium)
                        Spacer(Modifier.weight(1f))
                        Text(Session.nickname ?: "둘러보는 여행자", color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f))
                    }
                    Divider()
                    Text("로그아웃", color = MeadowDeep, fontWeight = FontWeight.Medium,
                        modifier = Modifier.fillMaxWidth().clickable { Session.logout(); onSignedOut() }.padding(16.dp))
                    Divider()
                    Text("회원 탈퇴", color = Color(0xFFD9534F), fontWeight = FontWeight.Medium,
                        modifier = Modifier.fillMaxWidth().clickable { showDelete = true }.padding(16.dp))
                }
            }

            Spacer(Modifier.height(16.dp))
            Card(shape = RoundedCornerShape(16.dp)) {
                Column {
                    Text("개인정보 처리방침", color = MeadowDeep,
                        modifier = Modifier.fillMaxWidth().clickable {
                            ctx.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(PRIVACY_URL)))
                        }.padding(16.dp))
                    Divider()
                    Row(Modifier.fillMaxWidth().padding(16.dp)) {
                        Text("앱 버전"); Spacer(Modifier.weight(1f))
                        Text("1.0", color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f))
                    }
                }
            }
        }
        if (working) CircularProgressIndicator(Modifier.align(Alignment.Center))
    }

    if (showDelete) {
        AlertDialog(
            onDismissRequest = { showDelete = false },
            title = { Text("정말 탈퇴할까요?") },
            text = { Text("계정과 저장·취향 기록이 모두 삭제되며 복구할 수 없어요.") },
            confirmButton = {
                TextButton(onClick = {
                    showDelete = false; working = true
                    scope.launch {
                        runCatching { Session.deleteAccount() }
                        working = false; onSignedOut()
                    }
                }) { Text("탈퇴하기", color = Color(0xFFD9534F)) }
            },
            dismissButton = { TextButton(onClick = { showDelete = false }) { Text("취소") } },
        )
    }
}
