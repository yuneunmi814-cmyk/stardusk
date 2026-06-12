package app.stardust.comma.ui

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Map
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import app.stardust.comma.data.TourSpot
import app.stardust.comma.ui.theme.MeadowDeep

/** 길안내 앱 한 가지 선택지 — iOS ExternalMapOption 동등. */
data class MapAppOption(val label: String, val uri: Uri)

/** 설치된 지도앱만 선택지로 반환(iOS ExternalMap.openWalking과 동일 우선순위·스킴).
 *  매니페스트 <queries> 에 스킴이 선언돼 있어야 설치 감지가 동작한다(Android 11+). */
fun walkNavOptions(ctx: Context, spot: TourSpot): List<MapAppOption> {
    val enc = Uri.encode(spot.spotName)
    val candidates = listOf(
        // 네이버지도: 도보 경로
        MapAppOption(
            "네이버지도",
            Uri.parse("nmap://route/walk?dlat=${spot.latitude}&dlng=${spot.longitude}&dname=$enc&appname=app.stardust.comma"),
        ),
        // 카카오맵: 도보 경로(FOOT)
        MapAppOption("카카오맵", Uri.parse("kakaomap://route?ep=${spot.latitude},${spot.longitude}&by=FOOT")),
        // 티맵: 목적지 안내
        MapAppOption("티맵", Uri.parse("tmap://route?goalname=$enc&goalx=${spot.longitude}&goaly=${spot.latitude}")),
    )
    val installed = candidates.filter { opt ->
        ctx.packageManager.resolveActivity(Intent(Intent.ACTION_VIEW, opt.uri), 0) != null
    }
    // 폴백: 기본 지도앱(geo: — 항상 마지막 선택지)
    val geo = MapAppOption(
        "다른 지도앱",
        Uri.parse("geo:${spot.latitude},${spot.longitude}?q=${spot.latitude},${spot.longitude}(${enc})"),
    )
    return installed + geo
}

/** 즉시 실행 폴백 — 선택 UI를 못 띄우는 곳에서 첫 선택지로 바로 연다. */
fun openExternalWalkNav(ctx: Context, spot: TourSpot) {
    val first = walkNavOptions(ctx, spot).first()
    runCatching { ctx.startActivity(Intent(Intent.ACTION_VIEW, first.uri)) }
}

/** "길안내 앱 선택" 바텀시트 — iOS confirmationDialog 동등. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MapAppChooserSheet(spot: TourSpot, onDismiss: () -> Unit) {
    val ctx = LocalContext.current
    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(Modifier.padding(start = 20.dp, end = 20.dp, bottom = 28.dp)) {
            Text(
                "길안내 앱 선택",
                fontWeight = FontWeight.Medium,
                style = MaterialTheme.typography.titleMedium,
            )
            Spacer(Modifier.height(6.dp))
            walkNavOptions(ctx, spot).forEach { opt ->
                Surface(
                    onClick = {
                        runCatching { ctx.startActivity(Intent(Intent.ACTION_VIEW, opt.uri)) }
                        onDismiss()
                    },
                    color = Color.Transparent,
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Row(
                        Modifier.padding(vertical = 14.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Icon(Icons.Filled.Map, contentDescription = null, tint = MeadowDeep)
                        Spacer(Modifier.width(12.dp))
                        Text(opt.label, style = MaterialTheme.typography.bodyLarge)
                    }
                }
            }
        }
    }
}
