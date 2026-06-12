package app.stardust.comma.ui

import android.speech.tts.TextToSpeech
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ChevronLeft
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Map
import androidx.compose.material.icons.filled.Straight
import androidx.compose.material.icons.filled.TurnLeft
import androidx.compose.material.icons.filled.TurnRight
import androidx.compose.material.icons.filled.VolumeUp
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import app.stardust.comma.data.TourSpot
import app.stardust.comma.data.WalkRoute
import app.stardust.comma.ui.theme.*
import java.util.Locale

/** 지도 하단 도보안내 카드 — 총거리/도보시간 + 회전지점 안내문 넘겨보기 + TTS + 외부앱 안전망. */
@Composable
fun WalkGuidanceCard(
    spot: TourSpot,
    route: WalkRoute,
    modifier: Modifier = Modifier,
    onClose: () -> Unit,
) {
    var stepIndex by remember(route) { mutableIntStateOf(0) }
    var showAppChooser by remember { mutableStateOf(false) }
    val ctx = LocalContext.current

    val dark = isSystemInDarkTheme()
    val surface = if (dark) MeadowSurfaceDark else MeadowSurface
    val textPrimary = if (dark) MeadowSurface else MeadowTextPrimary
    val textSecondary = if (dark) Color(0xFFA8BEAB) else MeadowTextSecondary

    // 한국어 TTS — 카드가 사라지면 정리
    val tts = remember { mutableStateOf<TextToSpeech?>(null) }
    DisposableEffect(Unit) {
        val engine = TextToSpeech(ctx) { status ->
            if (status == TextToSpeech.SUCCESS) tts.value?.language = Locale.KOREAN
        }
        tts.value = engine
        onDispose { engine.stop(); engine.shutdown() }
    }

    val step = route.steps.getOrNull(stepIndex)
    val summary = "${spot.spotName}까지 ${route.totalText}, 도보 ${route.etaMin}분"

    Surface(
        modifier = modifier.fillMaxWidth(),
        shape = RoundedCornerShape(20.dp),
        color = surface,
        shadowElevation = 10.dp,
    ) {
        Column(Modifier.padding(start = 16.dp, end = 8.dp, top = 12.dp, bottom = 14.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    Text(
                        spot.spotName,
                        color = textPrimary,
                        fontWeight = FontWeight.Medium,
                        style = MaterialTheme.typography.titleMedium,
                        maxLines = 1,
                    )
                    val mode = if (route.source == "straight") " · 직선 기준" else ""
                    Text(
                        "${route.totalText} · 도보 ${route.etaMin}분$mode",
                        color = textSecondary,
                        style = MaterialTheme.typography.bodySmall,
                    )
                }
                IconButton(onClick = { tts.value?.stop(); onClose() }) {
                    Icon(Icons.Filled.Close, contentDescription = "안내 종료", tint = textSecondary)
                }
            }

            if (step != null) {
                Spacer(Modifier.height(6.dp))
                Row(verticalAlignment = Alignment.CenterVertically) {
                    val turnIcon = when (step.turn) {
                        "left" -> Icons.Filled.TurnLeft
                        "right" -> Icons.Filled.TurnRight
                        else -> Icons.Filled.Straight
                    }
                    Icon(turnIcon, contentDescription = step.turn, tint = MeadowDeep, modifier = Modifier.size(28.dp))
                    Spacer(Modifier.width(10.dp))
                    Text(
                        step.instruction.ifBlank { "목적지 방향으로 이동하세요" },
                        color = textPrimary,
                        style = MaterialTheme.typography.bodyMedium,
                        maxLines = 2,
                        modifier = Modifier.weight(1f),
                    )
                    if (route.steps.size > 1) {
                        IconButton(
                            onClick = { if (stepIndex > 0) stepIndex -= 1 },
                            enabled = stepIndex > 0,
                        ) { Icon(Icons.Filled.ChevronLeft, contentDescription = "이전 안내", tint = textSecondary) }
                        Text(
                            "${stepIndex + 1}/${route.steps.size}",
                            color = textSecondary,
                            style = MaterialTheme.typography.labelMedium,
                        )
                        IconButton(
                            onClick = { if (stepIndex < route.steps.size - 1) stepIndex += 1 },
                            enabled = stepIndex < route.steps.size - 1,
                        ) { Icon(Icons.Filled.ChevronRight, contentDescription = "다음 안내", tint = textSecondary) }
                    }
                }
            }

            Spacer(Modifier.height(10.dp))
            Row(Modifier.padding(end = 8.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                GuideChip("안내 듣기", Icons.Filled.VolumeUp, Modifier.weight(1f)) {
                    val text = summary + ". " + (step?.instruction?.ifBlank { null } ?: "목적지 방향으로 이동하세요")
                    tts.value?.speak(text, TextToSpeech.QUEUE_FLUSH, null, "walk_${spot.tourId}")
                }
                GuideChip("외부 지도앱", Icons.Filled.Map, Modifier.weight(1f)) {
                    showAppChooser = true
                }
            }
        }
    }

    // iOS와 동일한 "길안내 앱 선택" — 설치된 지도앱(네이버/카카오/티맵) + 폴백
    if (showAppChooser) {
        MapAppChooserSheet(spot = spot, onDismiss = { showAppChooser = false })
    }
}

@Composable
private fun GuideChip(
    label: String,
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    modifier: Modifier = Modifier,
    onClick: () -> Unit,
) {
    Surface(
        modifier = modifier.height(42.dp),
        shape = RoundedCornerShape(10.dp),
        color = MeadowDeep.copy(alpha = 0.14f),
        onClick = onClick,
    ) {
        Row(Modifier.fillMaxSize(), horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically) {
            Icon(icon, contentDescription = null, tint = MeadowDeep)
            Spacer(Modifier.width(6.dp))
            Text(label, color = MeadowDeep, fontWeight = FontWeight.Medium)
        }
    }
}
