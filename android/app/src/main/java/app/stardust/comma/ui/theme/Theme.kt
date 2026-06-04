package app.stardust.comma.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color

// "광활한 초원" 디자인 토큰 (iOS MeadowTheme 와 동일 팔레트)
val MeadowSky = Color(0xFFCDEAFE)
val MeadowHorizon = Color(0xFFA8D5A2)
val Meadow = Color(0xFF7CB87C)
val MeadowDeep = Color(0xFF5A9E5E)
val MeadowSurface = Color(0xFFFDFBF3)
val MeadowTextPrimary = Color(0xFF2E4A30)
val MeadowTextSecondary = Color(0xFF6B8A6E)
val MeadowAccent = Color(0xFFE8B84B)
val MeadowNightBg = Color(0xFF1E3322)
val MeadowSurfaceDark = Color(0xFF28402D)

private val LightColors = lightColorScheme(
    primary = MeadowDeep,
    onPrimary = Color.White,
    secondary = MeadowAccent,
    background = MeadowSurface,
    onBackground = MeadowTextPrimary,
    surface = MeadowSurface,
    onSurface = MeadowTextPrimary,
)

private val DarkColors = darkColorScheme(
    primary = Meadow,
    onPrimary = Color.White,
    secondary = MeadowAccent,
    background = MeadowNightBg,
    onBackground = MeadowSurface,
    surface = MeadowSurfaceDark,
    onSurface = MeadowSurface,
)

/** 메인 배경 그라데이션(라이트=하늘→풀색, 다크=밤의 초원). */
@Composable
fun meadowBackgroundBrush(): Brush {
    return if (isSystemInDarkTheme())
        Brush.verticalGradient(listOf(MeadowNightBg, Color(0xFF142317)))
    else
        Brush.verticalGradient(listOf(MeadowSky, MeadowHorizon, Meadow, MeadowDeep))
}

@Composable
fun CommaTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = if (isSystemInDarkTheme()) DarkColors else LightColors,
        content = content
    )
}
