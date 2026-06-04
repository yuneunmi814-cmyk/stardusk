package app.stardust.comma.ui

import android.content.Intent
import android.net.Uri
import android.speech.tts.TextToSpeech
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.NearMe
import androidx.compose.material.icons.filled.VolumeUp
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import app.stardust.comma.data.Session
import app.stardust.comma.data.TourSpot
import app.stardust.comma.ui.theme.*
import coil.compose.AsyncImage
import kotlinx.coroutines.launch
import java.util.Locale
import kotlin.math.roundToInt

/** iOS 큐레이션 카드와 동일한 스와이프 덱(라이크/패스 + 길찾기 + 안내 듣기). */
@Composable
fun CurationOverlay(spots: List<TourSpot>, onClose: () -> Unit) {
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    var index by remember { mutableIntStateOf(0) }
    var dragX by remember { mutableFloatStateOf(0f) }

    // 한국어 TTS
    val tts = remember { mutableStateOf<TextToSpeech?>(null) }
    DisposableEffect(Unit) {
        val engine = TextToSpeech(ctx) { status ->
            if (status == TextToSpeech.SUCCESS) tts.value?.language = Locale.KOREAN
        }
        tts.value = engine
        onDispose { engine.stop(); engine.shutdown() }
    }

    fun advance(liked: Boolean, spot: TourSpot) {
        // 앱 수명 스코프로 보내 오버레이가 닫혀도(예: 마지막 카드 라이크) 저장이 유실되지 않게 한다.
        Session.recordSwipe(spot.tourId, liked)
        tts.value?.stop()
        dragX = 0f
        index += 1
    }

    Box(
        Modifier.fillMaxSize().background(
            Brush.verticalGradient(listOf(MeadowDeep, MeadowNightBg))
        )
    ) {
        Column(Modifier.fillMaxSize().padding(top = 16.dp, bottom = 20.dp)) {
            // 상단 바
            Row(Modifier.fillMaxWidth().padding(horizontal = 18.dp), verticalAlignment = Alignment.CenterVertically) {
                IconButton(onClick = onClose) {
                    Icon(Icons.Filled.Close, contentDescription = "닫기", tint = Color.White)
                }
                Spacer(Modifier.weight(1f))
                Text("지금, 어디로 도망칠까요?", color = Color.White.copy(alpha = 0.9f), fontWeight = FontWeight.Medium)
                Spacer(Modifier.weight(1f))
                Spacer(Modifier.width(48.dp))
            }
            Spacer(Modifier.weight(1f))

            if (index < spots.size) {
                val spot = spots[index]
                CommaCard(
                    spot = spot,
                    offsetX = dragX,
                    modifier = Modifier.padding(horizontal = 18.dp).pointerInput(index) {
                        detectHorizontalDragGestures(
                            onDragEnd = {
                                when {
                                    dragX > 220 -> advance(true, spot)
                                    dragX < -220 -> advance(false, spot)
                                    else -> dragX = 0f
                                }
                            }
                        ) { _, drag -> dragX += drag }
                    },
                    onNavigate = {
                        val uri = Uri.parse("geo:${spot.latitude},${spot.longitude}?q=${Uri.encode(spot.spotName)}")
                        runCatching { ctx.startActivity(Intent(Intent.ACTION_VIEW, uri)) }
                    },
                    onSpeak = {
                        scope.launch {
                            val text = runCatching { Session.api.detail(spot.tourId).data.overview }.getOrNull()
                                ?.takeIf { it.isNotBlank() }
                                ?: "${spot.spotName}. ${spot.address ?: spot.region ?: ""}에 위치한 자연 명소입니다."
                            tts.value?.speak(text, TextToSpeech.QUEUE_FLUSH, null, spot.tourId)
                        }
                    },
                )
                Spacer(Modifier.weight(1f))
                Row(
                    Modifier.fillMaxWidth().padding(top = 14.dp),
                    horizontalArrangement = Arrangement.Center,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    BigCircle(Icons.Filled.Close, Color(0xFF9E9E9E)) { advance(false, spot) }
                    Spacer(Modifier.width(40.dp))
                    BigCircle(Icons.Filled.Favorite, MeadowAccent) { advance(true, spot) }
                }
            } else {
                FinishedState(onRestart = { index = 0 }, onClose = onClose)
                Spacer(Modifier.weight(1f))
            }
        }
    }
}

@Composable
private fun CommaCard(
    spot: TourSpot,
    offsetX: Float,
    modifier: Modifier = Modifier,
    onNavigate: () -> Unit,
    onSpeak: () -> Unit,
) {
    val scheme = androidx.compose.foundation.isSystemInDarkTheme()
    val surface = if (scheme) MeadowSurfaceDark else MeadowSurface
    val textPrimary = if (scheme) MeadowSurface else MeadowTextPrimary
    val textSecondary = if (scheme) Color(0xFFA8BEAB) else MeadowTextSecondary

    Surface(
        modifier = modifier
            .fillMaxWidth()
            .offset { IntOffset(offsetX.roundToInt(), 0) },
        shape = RoundedCornerShape(20.dp),
        color = surface,
        shadowElevation = 10.dp,
    ) {
        Column {
            AsyncImage(
                model = spot.secureImageUrl,
                contentDescription = null,
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxWidth().height(300.dp).background(Meadow),
            )
            Column(Modifier.padding(16.dp)) {
                spot.label?.let {
                    val badge = if (it == "hotplace") "인기 핫플" else "숨은 명소"
                    Text(badge, color = MeadowDeep, fontWeight = FontWeight.Medium, style = MaterialTheme.typography.labelMedium)
                    Spacer(Modifier.height(4.dp))
                }
                Text(spot.spotName, color = textPrimary, fontWeight = FontWeight.Medium, style = MaterialTheme.typography.titleLarge, maxLines = 2)
                (spot.address ?: spot.region)?.let {
                    Spacer(Modifier.height(4.dp))
                    Text(it, color = textSecondary, style = MaterialTheme.typography.bodyMedium, maxLines = 1)
                }
                spot.distanceText?.let {
                    Spacer(Modifier.height(2.dp))
                    Text("도보/차량 $it", color = textSecondary, style = MaterialTheme.typography.bodySmall)
                }
                Spacer(Modifier.height(12.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    CardChip("길찾기", Icons.Filled.NearMe, Modifier.weight(1f), onNavigate)
                    CardChip("안내 듣기", Icons.Filled.VolumeUp, Modifier.weight(1f), onSpeak)
                }
            }
        }
    }
}

@Composable
private fun CardChip(label: String, icon: androidx.compose.ui.graphics.vector.ImageVector, modifier: Modifier, onClick: () -> Unit) {
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

@Composable
private fun BigCircle(icon: androidx.compose.ui.graphics.vector.ImageVector, color: Color, onClick: () -> Unit) {
    Surface(shape = CircleShape, color = color, modifier = Modifier.size(64.dp), onClick = onClick) {
        Box(contentAlignment = Alignment.Center) {
            Icon(icon, contentDescription = null, tint = Color.White, modifier = Modifier.size(30.dp))
        }
    }
}

@Composable
private fun FinishedState(onRestart: () -> Unit, onClose: () -> Unit) {
    Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) {
        Text("근처 쉼표를 모두 둘러봤어요", color = Color.White, fontWeight = FontWeight.Medium, style = MaterialTheme.typography.titleMedium)
        Spacer(Modifier.height(14.dp))
        TextButton(onClick = onRestart) { Text("처음부터 다시", color = Color.White) }
        TextButton(onClick = onClose) { Text("닫기", color = Color.White.copy(alpha = 0.7f)) }
    }
}
