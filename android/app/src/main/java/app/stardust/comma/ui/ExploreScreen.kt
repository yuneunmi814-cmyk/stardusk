package app.stardust.comma.ui

import android.Manifest
import android.annotation.SuppressLint
import android.content.pm.PackageManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
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
import app.stardust.comma.data.Session
import app.stardust.comma.data.TourSpot
import app.stardust.comma.ui.theme.MeadowAccent
import com.google.android.gms.location.LocationServices
import com.google.android.gms.maps.model.CameraPosition
import com.google.android.gms.maps.model.LatLng
import com.google.maps.android.compose.GoogleMap
import com.google.maps.android.compose.MapProperties
import com.google.maps.android.compose.Marker
import com.google.maps.android.compose.MarkerState
import com.google.maps.android.compose.rememberCameraPositionState

private val GANGNEUNG = LatLng(37.7519, 128.8761)
private fun inKorea(p: LatLng) = p.latitude in 33.0..39.5 && p.longitude in 124.0..132.0

@SuppressLint("MissingPermission")
@Composable
fun ExploreScreen(modifier: Modifier = Modifier) {
    val ctx = LocalContext.current
    var center by remember { mutableStateOf(GANGNEUNG) }
    var spots by remember { mutableStateOf<List<TourSpot>>(emptyList()) }
    var loading by remember { mutableStateOf(false) }
    var reload by remember { mutableIntStateOf(0) }   // 버튼으로 강제 재검색 트리거
    val cam = rememberCameraPositionState { position = CameraPosition.fromLatLngZoom(GANGNEUNG, 11f) }

    val fused = remember { LocationServices.getFusedLocationProviderClient(ctx) }

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
                )
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

        // CTA — 다시 가까운 자연 불러오기(추후 큐레이션 카드로 확장)
        Button(
            onClick = { applyLocation(); reload++ },   // 내 위치 재취득 + 강제 재검색
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
