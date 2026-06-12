package app.stardust.comma.ui

import android.Manifest
import android.annotation.SuppressLint
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas as AndroidCanvas
import android.graphics.Paint
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
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
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.compose.ui.geometry.Offset
import androidx.core.content.ContextCompat
import app.stardust.comma.data.Session
import app.stardust.comma.data.TourSpot
import app.stardust.comma.data.WalkRoute
import kotlinx.coroutines.launch
import app.stardust.comma.ui.theme.MeadowAccent
import app.stardust.comma.ui.theme.MeadowDeep
import com.google.android.gms.location.LocationServices
import com.google.android.gms.maps.CameraUpdateFactory
import com.google.android.gms.maps.MapsInitializer
import com.google.android.gms.maps.model.BitmapDescriptor
import com.google.android.gms.maps.model.BitmapDescriptorFactory
import com.google.android.gms.maps.model.CameraPosition
import com.google.android.gms.maps.model.LatLng
import com.google.android.gms.maps.model.LatLngBounds
import com.google.maps.android.compose.GoogleMap
import com.google.maps.android.compose.MapProperties
import com.google.maps.android.compose.Marker
import com.google.maps.android.compose.MarkerState
import com.google.maps.android.compose.Polyline
import com.google.maps.android.compose.rememberCameraPositionState

private val GANGNEUNG = LatLng(37.7519, 128.8761)
private fun inKorea(p: LatLng) = p.latitude in 33.0..39.5 && p.longitude in 124.0..132.0

/** iOS StarDot과 동일한 초원 점 마커: 은은한 헤일로 + 흰 점 + meadowDeep 링. */
private fun meadowDotIcon(density: Float): BitmapDescriptor {
    val deep = android.graphics.Color.parseColor("#5A9E5E")
    val size = (20f * density).toInt().coerceAtLeast(28)   // px
    val bmp = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
    val canvas = AndroidCanvas(bmp)
    val c = size / 2f
    val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    // 1) 헤일로
    paint.style = Paint.Style.FILL
    paint.color = deep
    paint.alpha = 80
    canvas.drawCircle(c, c, size * 0.46f, paint)
    // 2) 흰 점
    paint.alpha = 255
    paint.color = android.graphics.Color.WHITE
    canvas.drawCircle(c, c, size * 0.30f, paint)
    // 3) meadowDeep 링
    paint.style = Paint.Style.STROKE
    paint.strokeWidth = density * 1.5f
    paint.color = deep
    canvas.drawCircle(c, c, size * 0.30f, paint)
    return BitmapDescriptorFactory.fromBitmap(bmp)
}

@SuppressLint("MissingPermission")
@Composable
fun ExploreScreen(modifier: Modifier = Modifier) {
    val ctx = LocalContext.current
    var center by remember { mutableStateOf(GANGNEUNG) }
    var spots by remember { mutableStateOf<List<TourSpot>>(emptyList()) }
    var loading by remember { mutableStateOf(false) }
    var reload by remember { mutableIntStateOf(0) }   // 버튼으로 강제 재검색 트리거
    val scope = rememberCoroutineScope()
    var showCuration by remember { mutableStateOf(false) }
    var deck by remember { mutableStateOf<List<TourSpot>>(emptyList()) }
    // 도보안내 모드 — 길찾기 탭 시 backend /tour/walk-route 경로를 지도에 올린다.
    var walkTarget by remember { mutableStateOf<TourSpot?>(null) }
    var walkRoute by remember { mutableStateOf<WalkRoute?>(null) }
    // 위치 설정(iOS LocationSetupView 동등) + 경로 실패 시 길안내 앱 선택 폴백
    var showLocationSetup by remember { mutableStateOf(false) }
    var placeName by remember { mutableStateOf("현위치") }
    var navFallbackSpot by remember { mutableStateOf<TourSpot?>(null) }
    val cam = rememberCameraPositionState { position = CameraPosition.fromLatLngZoom(GANGNEUNG, 11f) }

    // 중심이 바뀔 때마다 위치 칩의 동네명 갱신
    LaunchedEffect(center) { placeName = reversePlaceName(ctx, center) }

    // 경로 수신 → 출발·도착이 모두 보이게 카메라 맞춤
    LaunchedEffect(walkRoute) {
        val r = walkRoute ?: return@LaunchedEffect
        if (r.path.size < 2) return@LaunchedEffect
        val bounds = LatLngBounds.builder()
            .apply { r.path.forEach { include(LatLng(it.lat, it.lng)) } }
            .build()
        runCatching { cam.animate(CameraUpdateFactory.newLatLngBounds(bounds, 140)) }
    }

    /** 도보안내 시작 — 실패(해외 좌표·네트워크 등)하면 외부 지도앱으로 안전망 핸드오프. */
    fun startWalkGuidance(spot: TourSpot) {
        scope.launch {
            runCatching {
                Session.ensureGuest()
                Session.api.walkRoute(center.latitude, center.longitude, spot.latitude, spot.longitude).data
            }.onSuccess { route ->
                walkTarget = spot
                walkRoute = route
            }.onFailure {
                navFallbackSpot = spot       // 경로 실패(해외 좌표 등) → 길안내 앱 선택으로 안전망
            }
        }
    }

    val fused = remember { LocationServices.getFusedLocationProviderClient(ctx) }
    // BitmapDescriptorFactory는 Maps 초기화 후에만 사용 가능 → 먼저 초기화.
    val dotIcon = remember {
        @Suppress("DEPRECATION")
        MapsInitializer.initialize(ctx)
        meadowDotIcon(ctx.resources.displayMetrics.density)
    }

    fun applyLocation() {
        val granted = ContextCompat.checkSelfPermission(ctx, Manifest.permission.ACCESS_FINE_LOCATION) ==
            PackageManager.PERMISSION_GRANTED
        if (!granted) return
        fused.lastLocation.addOnSuccessListener { loc ->
            if (loc != null) {
                val p = LatLng(loc.latitude, loc.longitude)
                center = if (inKorea(p)) p else GANGNEUNG   // 한국 밖이면 강릉 폴백
            }
        }
    }

    val permLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestMultiplePermissions()
    ) { applyLocation() }

    // 진입: 권한 요청(또는 이미 허용이면 위치 적용)
    LaunchedEffect(Unit) {
        val granted = ContextCompat.checkSelfPermission(ctx, Manifest.permission.ACCESS_FINE_LOCATION) ==
            PackageManager.PERMISSION_GRANTED
        if (granted) applyLocation()
        else permLauncher.launch(arrayOf(
            Manifest.permission.ACCESS_FINE_LOCATION,
            Manifest.permission.ACCESS_COARSE_LOCATION,
        ))
    }

    // center 변경 또는 reload 증가 시: 카메라 이동 + 주변 자연 명소 로드
    LaunchedEffect(center, reload) {
        cam.position = CameraPosition.fromLatLngZoom(center, 11f)
        loading = true
        spots = try {
            Session.ensureGuest()
            Session.api.nearby(center.latitude, center.longitude).data
        } catch (e: Exception) { emptyList() } finally { loading = false }
    }

    Box(modifier.fillMaxSize()) {
        GoogleMap(
            modifier = Modifier.fillMaxSize(),
            cameraPositionState = cam,
            properties = MapProperties(
                isMyLocationEnabled = ContextCompat.checkSelfPermission(
                    ctx, Manifest.permission.ACCESS_FINE_LOCATION
                ) == PackageManager.PERMISSION_GRANTED
            ),
        ) {
            spots.forEach { s ->
                Marker(
                    state = MarkerState(LatLng(s.latitude, s.longitude)),
                    title = s.spotName,
                    snippet = s.address ?: s.region,
                    icon = dotIcon,                  // iOS와 동일한 초원 점 스타일
                    anchor = Offset(0.5f, 0.5f),     // 좌표 정중앙에 점이 오도록
                )
            }
            // 도보안내 — 경로 폴리라인 + 목적지 핀
            walkRoute?.let { r ->
                Polyline(
                    points = r.path.map { LatLng(it.lat, it.lng) },
                    color = MeadowDeep,
                    width = 12f,
                    geodesic = true,
                )
            }
            walkTarget?.let { t ->
                Marker(
                    state = MarkerState(LatLng(t.latitude, t.longitude)),
                    title = t.spotName,
                    icon = BitmapDescriptorFactory.defaultMarker(BitmapDescriptorFactory.HUE_GREEN),
                )
            }
        }

        // 좌상단 위치 칩 — 동네명 + 변경(iOS ExploreView 동등)
        Surface(
            onClick = { showLocationSetup = true },
            shape = RoundedCornerShape(20.dp),
            tonalElevation = 2.dp,
            shadowElevation = 4.dp,
            modifier = Modifier.align(Alignment.TopStart).padding(start = 12.dp, top = 12.dp),
        ) {
            Row(
                Modifier.padding(horizontal = 12.dp, vertical = 8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(Icons.Filled.Place, contentDescription = null, tint = MeadowDeep, modifier = Modifier.size(18.dp))
                Spacer(Modifier.width(6.dp))
                Text(placeName, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Medium, maxLines = 1)
                Spacer(Modifier.width(8.dp))
                Text("변경", style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.Medium, color = MeadowDeep)
            }
        }

        if (loading) {
            CircularProgressIndicator(
                Modifier.align(Alignment.TopCenter).padding(top = 12.dp),
                color = MeadowAccent,
            )
        }

        // 빈 상태
        if (!loading && spots.isEmpty()) {
            Surface(
                Modifier.align(Alignment.Center),
                shape = RoundedCornerShape(16.dp),
                tonalElevation = 2.dp,
            ) { Text("이 지역은 아직 준비 중이에요", Modifier.padding(16.dp)) }
        }

        // 하단 — 도보안내 중엔 안내 카드, 평소엔 큐레이션 CTA
        val target = walkTarget
        val route = walkRoute
        if (target != null && route != null) {
            WalkGuidanceCard(
                spot = target,
                route = route,
                modifier = Modifier.align(Alignment.BottomCenter).padding(horizontal = 14.dp, vertical = 14.dp),
                onClose = { walkTarget = null; walkRoute = null },
            )
        } else {
            Button(
                onClick = {
                    scope.launch {
                        Session.ensureGuest()
                        val d = runCatching { Session.api.deck(center.latitude, center.longitude).data }.getOrDefault(emptyList())
                        deck = d.ifEmpty { spots }
                        if (deck.isNotEmpty()) showCuration = true
                    }
                },
                modifier = Modifier.align(Alignment.BottomCenter).padding(bottom = 20.dp).height(54.dp),
                shape = RoundedCornerShape(27.dp),
                colors = ButtonDefaults.buttonColors(containerColor = MeadowAccent, contentColor = Color.White),
            ) {
                Icon(Icons.Filled.Search, contentDescription = null)
                Spacer(Modifier.width(8.dp))
                Text("지금, 가까운 쉼표로", fontWeight = FontWeight.Medium)
            }
        }
    }

    // 위치 설정 — 풀스크린(지도 중앙 핀 + 검색 + 해당 위치로 시작하기)
    if (showLocationSetup) {
        Dialog(
            onDismissRequest = { showLocationSetup = false },
            properties = DialogProperties(usePlatformDefaultWidth = false),
        ) {
            LocationSetupScreen(
                initial = center,
                onConfirm = { picked, name ->
                    showLocationSetup = false
                    walkTarget = null; walkRoute = null   // 지역 변경 시 진행 중 도보안내 종료
                    placeName = name
                    center = picked
                    reload += 1                           // 동일 좌표 재선택이어도 재검색
                },
                onClose = { showLocationSetup = false },
            )
        }
    }

    // 경로 실패 폴백 — iOS와 동일한 "길안내 앱 선택"
    navFallbackSpot?.let { spot ->
        MapAppChooserSheet(spot = spot, onDismiss = { navFallbackSpot = null })
    }

    // 큐레이션 카드 덱(진짜 풀스크린 오버레이 — 하단 내비게이션 바까지 덮어 라이크/패스 버튼 노출)
    if (showCuration) {
        Dialog(
            onDismissRequest = { showCuration = false },
            properties = DialogProperties(usePlatformDefaultWidth = false),
        ) {
            CurationOverlay(
                spots = deck,
                onClose = { showCuration = false },
                onNavigate = { spot ->
                    showCuration = false           // 오버레이 닫고 지도 위에서 도보안내
                    startWalkGuidance(spot)
                },
            )
        }
    }
}
