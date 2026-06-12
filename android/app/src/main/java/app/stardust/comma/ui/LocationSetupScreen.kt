package app.stardust.comma.ui

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import android.location.Geocoder
import androidx.compose.foundation.background
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Place
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import app.stardust.comma.ui.theme.*
import com.google.android.gms.maps.CameraUpdateFactory
import com.google.android.gms.maps.model.CameraPosition
import com.google.android.gms.maps.model.LatLng
import com.google.maps.android.compose.GoogleMap
import com.google.maps.android.compose.MapProperties
import com.google.maps.android.compose.rememberCameraPositionState
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.util.Locale

/** 검색 결과 한 건 — iOS AddressSearchModel.Result 동등. */
data class PlaceResult(val title: String, val subtitle: String?, val latLng: LatLng)

/** 좌표 → "강릉시 교동" 식 동네명 (iOS reverseGeocode와 동일 조합 규칙). */
suspend fun reversePlaceName(ctx: Context, p: LatLng): String = withContext(Dispatchers.IO) {
    runCatching {
        @Suppress("DEPRECATION")
        val a = Geocoder(ctx, Locale.KOREAN).getFromLocation(p.latitude, p.longitude, 1)?.firstOrNull()
        listOfNotNull(a?.locality ?: a?.adminArea, a?.subLocality ?: a?.thoroughfare)
            .take(2).joinToString(" ").ifBlank { "선택한 위치" }
    }.getOrDefault("선택한 위치")
}

/** 도로명/건물명 검색 — 한국 바운딩 박스 한정, 최대 6건 (iOS MKLocalSearch 동등). */
private suspend fun searchPlaces(ctx: Context, query: String): List<PlaceResult> =
    withContext(Dispatchers.IO) {
        runCatching {
            @Suppress("DEPRECATION")
            Geocoder(ctx, Locale.KOREAN)
                .getFromLocationName(query, 6, 32.5, 124.0, 39.0, 132.5)
                ?.map { a ->
                    val line = a.getAddressLine(0)
                    PlaceResult(
                        title = a.featureName?.takeIf { it.isNotBlank() } ?: line ?: query,
                        subtitle = line,
                        latLng = LatLng(a.latitude, a.longitude),
                    )
                } ?: emptyList()
        }.getOrDefault(emptyList())
    }

/** 위치 설정 — 배달앱식 직관 위치 지정(iOS LocationSetupView 동등).
 *  ① 진입 시 현재 탐색 중심에서 시작 ② 도로명/건물명 검색 ③ 지도 중앙 핀 이동 → "해당 위치로 시작하기". */
@SuppressLint("MissingPermission")
@Composable
fun LocationSetupScreen(
    initial: LatLng,
    onConfirm: (LatLng, String) -> Unit,
    onClose: () -> Unit,
) {
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    val dark = isSystemInDarkTheme()
    val surface = if (dark) MeadowSurfaceDark else MeadowSurface
    val textPrimary = if (dark) MeadowSurface else MeadowTextPrimary
    val textSecondary = if (dark) Color(0xFFA8BEAB) else MeadowTextSecondary

    val cam = rememberCameraPositionState { position = CameraPosition.fromLatLngZoom(initial, 14f) }
    var placeName by remember { mutableStateOf("현재 위치") }
    var query by remember { mutableStateOf("") }
    var results by remember { mutableStateOf<List<PlaceResult>>(emptyList()) }

    // 지도 멈출 때마다 중앙 좌표 역지오코딩 → 동네명 갱신
    LaunchedEffect(cam) {
        snapshotFlow { cam.isMoving }.collect { moving ->
            if (!moving) placeName = reversePlaceName(ctx, cam.position.target)
        }
    }

    fun runSearch() {
        val q = query.trim()
        if (q.isEmpty()) { results = emptyList(); return }
        scope.launch { results = searchPlaces(ctx, q) }
    }

    Box(Modifier.fillMaxSize().background(surface)) {
        GoogleMap(
            modifier = Modifier.fillMaxSize(),
            cameraPositionState = cam,
            properties = MapProperties(
                isMyLocationEnabled = ContextCompat.checkSelfPermission(
                    ctx, Manifest.permission.ACCESS_FINE_LOCATION
                ) == PackageManager.PERMISSION_GRANTED
            ),
        )

        // 중앙 고정 핀 (지도 위 정중앙)
        Icon(
            Icons.Filled.Place,
            contentDescription = "선택 위치",
            tint = MeadowDeep,
            modifier = Modifier.align(Alignment.Center).size(44.dp).offset(y = (-22).dp),
        )

        // 상단: 닫기 + 검색바 + 결과
        Column(Modifier.fillMaxWidth().padding(horizontal = 14.dp).padding(top = 14.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Surface(shape = RoundedCornerShape(12.dp), color = surface, shadowElevation = 4.dp) {
                    IconButton(onClick = onClose) {
                        Icon(Icons.Filled.Close, contentDescription = "닫기", tint = textSecondary)
                    }
                }
                Spacer(Modifier.width(8.dp))
                Surface(
                    shape = RoundedCornerShape(12.dp),
                    color = surface,
                    shadowElevation = 4.dp,
                    modifier = Modifier.weight(1f),
                ) {
                    Row(Modifier.padding(horizontal = 12.dp), verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Filled.Search, contentDescription = null, tint = textSecondary)
                        TextField(
                            value = query,
                            onValueChange = { query = it },
                            placeholder = { Text("도로명·건물명으로 검색", color = textSecondary) },
                            singleLine = true,
                            colors = TextFieldDefaults.colors(
                                focusedContainerColor = Color.Transparent,
                                unfocusedContainerColor = Color.Transparent,
                                focusedIndicatorColor = Color.Transparent,
                                unfocusedIndicatorColor = Color.Transparent,
                            ),
                            modifier = Modifier.weight(1f),
                            keyboardActions = androidx.compose.foundation.text.KeyboardActions(onSearch = { runSearch() }),
                            keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(
                                imeAction = androidx.compose.ui.text.input.ImeAction.Search
                            ),
                        )
                        if (query.isNotEmpty()) {
                            IconButton(onClick = { query = ""; results = emptyList() }) {
                                Icon(Icons.Filled.Close, contentDescription = "지우기", tint = textSecondary)
                            }
                        }
                    }
                }
            }

            if (results.isNotEmpty()) {
                Spacer(Modifier.height(6.dp))
                Surface(shape = RoundedCornerShape(12.dp), color = surface, shadowElevation = 4.dp) {
                    Column {
                        results.forEach { r ->
                            Surface(
                                onClick = {
                                    scope.launch {
                                        cam.animate(CameraUpdateFactory.newLatLngZoom(r.latLng, 15f))
                                    }
                                    placeName = r.title
                                    query = ""; results = emptyList()
                                },
                                color = Color.Transparent,
                                modifier = Modifier.fillMaxWidth(),
                            ) {
                                Column(Modifier.padding(horizontal = 12.dp, vertical = 10.dp)) {
                                    Text(r.title, color = textPrimary, fontWeight = FontWeight.Medium, maxLines = 1)
                                    r.subtitle?.let {
                                        Text(it, color = textSecondary, style = MaterialTheme.typography.bodySmall, maxLines = 1)
                                    }
                                }
                            }
                            HorizontalDivider(color = textSecondary.copy(alpha = 0.15f))
                        }
                    }
                }
            }
        }

        // 하단 확정 카드
        Surface(
            shape = RoundedCornerShape(20.dp),
            color = surface,
            shadowElevation = 10.dp,
            modifier = Modifier.align(Alignment.BottomCenter).fillMaxWidth()
                .padding(horizontal = 14.dp, vertical = 16.dp),
        ) {
            Column(Modifier.padding(16.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Filled.Place, contentDescription = null, tint = MeadowDeep)
                    Spacer(Modifier.width(8.dp))
                    Text(placeName, color = textPrimary, fontWeight = FontWeight.Medium, maxLines = 1)
                }
                Spacer(Modifier.height(12.dp))
                Button(
                    onClick = { onConfirm(cam.position.target, placeName) },
                    modifier = Modifier.fillMaxWidth().height(50.dp),
                    shape = RoundedCornerShape(14.dp),
                    colors = ButtonDefaults.buttonColors(containerColor = MeadowAccent, contentColor = Color.White),
                ) {
                    Text("해당 위치로 시작하기", fontWeight = FontWeight.Medium)
                }
            }
        }
    }
}
