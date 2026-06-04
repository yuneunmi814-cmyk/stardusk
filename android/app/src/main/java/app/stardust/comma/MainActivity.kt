package app.stardust.comma

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.Map
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import app.stardust.comma.data.Session
import app.stardust.comma.ui.ExploreScreen
import app.stardust.comma.ui.LoginScreen
import app.stardust.comma.ui.SavedScreen
import app.stardust.comma.ui.theme.CommaTheme

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent { CommaTheme { Root() } }
    }
}

@Composable
private fun Root() {
    var authed by remember { mutableStateOf(Session.accessToken != null) }
    if (!authed) {
        LoginScreen(onEnter = { authed = true })
    } else {
        MainTabs()
    }
}

@Composable
private fun MainTabs() {
    var tab by remember { mutableIntStateOf(0) }
    Scaffold(
        bottomBar = {
            NavigationBar {
                NavigationBarItem(
                    selected = tab == 0,
                    onClick = { tab = 0 },
                    icon = { Icon(Icons.Filled.Map, contentDescription = null) },
                    label = { Text("탐색") },
                )
                NavigationBarItem(
                    selected = tab == 1,
                    onClick = { tab = 1 },
                    icon = { Icon(Icons.Filled.Favorite, contentDescription = null) },
                    label = { Text("저장") },
                )
            }
        }
    ) { inner ->
        when (tab) {
            0 -> ExploreScreen(Modifier.padding(inner))
            else -> SavedScreen(Modifier.padding(inner))
        }
    }
}
