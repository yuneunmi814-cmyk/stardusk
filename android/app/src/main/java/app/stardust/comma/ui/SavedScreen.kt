package app.stardust.comma.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.NearMe
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import app.stardust.comma.data.Session
import app.stardust.comma.data.TourSpot
import app.stardust.comma.ui.theme.Meadow
import app.stardust.comma.ui.theme.MeadowDeep
import app.stardust.comma.ui.theme.meadowBackgroundBrush
import coil.compose.AsyncImage
import kotlinx.coroutines.launch

@Composable
fun SavedScreen(modifier: Modifier = Modifier) {
    val scope = rememberCoroutineScope()
    var spots by remember { mutableStateOf<List<TourSpot>>(emptyList()) }
    var loading by remember { mutableStateOf(true) }
    var navSpot by remember { mutableStateOf<TourSpot?>(null) }   // 길안내 앱 선택 대상

    suspend fun load() {
        loading = true
        spots = try { Session.api.saved().data } catch (e: Exception) { emptyList() } finally { loading = false }
    }
    LaunchedEffect(Unit) { load() }

    Box(modifier.fillMaxSize().background(meadowBackgroundBrush())) {
        Column(Modifier.fillMaxSize().padding(20.dp)) {
            Text("저장한 곳", fontWeight = FontWeight.Bold, style = MaterialTheme.typography.headlineMedium)
            Spacer(Modifier.height(12.dp))

            if (!loading && spots.isEmpty()) {
                Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    Text("저장한 곳이 없어요\n탐색에서 마음에 든 자연을 라이크(♥)하면 모여요")
                }
            } else {
                LazyColumn(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    items(spots, key = { it.tourId }) { s ->
                        SavedRow(
                            s,
                            onNavigate = { navSpot = s },
                            onUnsave = {
                                scope.launch {
                                    spots = try { Session.api.unsave(s.tourId).data } catch (e: Exception) { spots }
                                }
                            },
                        )
                    }
                }
            }
        }
    }

    // iOS SavedView와 동일한 "길안내 앱 선택"
    navSpot?.let { MapAppChooserSheet(spot = it, onDismiss = { navSpot = null }) }
}

@Composable
private fun SavedRow(s: TourSpot, onNavigate: () -> Unit, onUnsave: () -> Unit) {
    Surface(shape = RoundedCornerShape(20.dp), tonalElevation = 1.dp) {
        Row(Modifier.fillMaxWidth().padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
            AsyncImage(
                model = s.secureImageUrl,
                contentDescription = null,
                modifier = Modifier.size(70.dp).clip(RoundedCornerShape(10.dp)).background(Meadow),
            )
            Spacer(Modifier.width(12.dp))
            Column(Modifier.weight(1f)) {
                Text(s.spotName, fontWeight = FontWeight.Medium, maxLines = 1)
                (s.address ?: s.region)?.let {
                    Text(it, style = MaterialTheme.typography.bodySmall, maxLines = 1)
                }
            }
            IconButton(onClick = onNavigate) {
                Icon(Icons.Filled.NearMe, contentDescription = "길찾기", tint = MeadowDeep)
            }
            IconButton(onClick = onUnsave) {
                Icon(Icons.Filled.Favorite, contentDescription = "저장 해제", tint = MeadowDeep)
            }
        }
    }
}
