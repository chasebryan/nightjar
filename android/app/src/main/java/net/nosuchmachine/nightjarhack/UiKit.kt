package net.nosuchmachine.nightjarhack

import android.content.Context
import android.content.SharedPreferences
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.KeyboardArrowRight
import androidx.compose.material3.ColorScheme
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.MutableState
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/// The iOS palette, named once — the mirror's foundation.
/// iOS dark: near-black #080808 base, grouped panels #1C1C1E,
/// secondary label gray, system blue accent, system red error.
/// No purple: the stock Material scheme was the loudest tell
/// that this was a different app wearing the same name.
object IosColors {
    val Base = Color(0xFF080808)
    val Panel = Color(0xFF1C1C1E)
    val PanelRaised = Color(0xFF242426)
    val Label = Color(0xFFFFFFFF)
    val SecondaryLabel = Color(0xFF98989F)
    val TertiaryLabel = Color(0xFF636366)
    val Accent = Color(0xFF0A84FF)
    val Error = Color(0xFFFF453A)
    val Separator = Color(0x1FFFFFFF)
    val TabBar = Color(0xE6121212)
    val ToastNeutral = Color(0xF2292929)
    val ToastError = Color(0xEBFF453A)
}

/// The color scheme every screen wears — darkColorScheme with
/// the iOS palette poured in, container family included, so
/// Cards, bars and fields stop tinting themselves purple.
fun nightjarColorScheme(): ColorScheme = darkColorScheme(
    primary = IosColors.Accent,
    onPrimary = IosColors.Label,
    background = IosColors.Base,
    onBackground = IosColors.Label,
    surface = IosColors.Panel,
    onSurface = IosColors.Label,
    surfaceVariant = IosColors.PanelRaised,
    onSurfaceVariant = IosColors.SecondaryLabel,
    surfaceContainerLowest = Color(0xFF141416),
    surfaceContainerLow = IosColors.Panel,
    surfaceContainer = IosColors.Panel,
    surfaceContainerHigh = IosColors.PanelRaised,
    surfaceContainerHighest = Color(0xFF2C2C2E),
    outline = Color(0xFF38383A),
    outlineVariant = Color(0xFF2C2C2E),
    error = IosColors.Error,
    onError = IosColors.Label
)

/// The inset-grouped panel: flat #1C1C1E, 10dp radius, no
/// elevation — the surface every iOS screen is built from,
/// and the Card replacement for the screen passes.
@Composable
fun IosPanel(
    modifier: Modifier = Modifier,
    content: @Composable ColumnScope.() -> Unit
) {
    Column(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 6.dp)
            .clip(RoundedCornerShape(10.dp))
            .background(IosColors.Panel)
            .padding(horizontal = 16.dp, vertical = 8.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
        content = content
    )
}

/// The Card replacement inside the tab lists (which already
/// carry the 16dp inset): a flat translucent panel, 10dp
/// radius, no elevation, no margin of its own. Children keep
/// their own 12dp content padding, exactly as the Cards did.
@Composable
fun IosPanelCard(
    modifier: Modifier = Modifier,
    content: @Composable ColumnScope.() -> Unit
) {
    Column(
        modifier = modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(10.dp))
            .background(Color(0xD91C1C1E)),
        content = content
    )
}

/// The tab's title in iOS large-title manners: bold, quiet,
/// sitting directly on the backdrop — not a Material headline
/// floating in a list.
@Composable
fun TabTitle(text: String) {
    Text(
        text,
        fontSize = 28.sp,
        fontWeight = androidx.compose.ui.text.font.FontWeight.Bold,
        color = IosColors.Label,
        modifier = Modifier.padding(top = 4.dp, bottom = 2.dp)
    )
}

/// A grouped-list section header: small, gray, uppercase,
/// letterspaced — the iOS section voice.
@Composable
fun IosSectionHeader(title: String) {
    Text(
        title.uppercase(),
        fontSize = 13.sp,
        letterSpacing = 0.6.sp,
        color = IosColors.SecondaryLabel,
        modifier = Modifier.padding(start = 16.dp, top = 18.dp, bottom = 2.dp)
    )
}

/// The hairline between rows inside a panel.
@Composable
fun Hairline() {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .height(0.5.dp)
            .background(IosColors.Separator)
    )
}

/// SharedPreferences-backed state — the Android stand-in for
/// the iOS app's @AppStorage fields.
class Prefs(context: Context) {
    private val shared: SharedPreferences =
        context.getSharedPreferences("nightjarhack.prefs", Context.MODE_PRIVATE)

    fun string(key: String, default: String): String =
        shared.getString(key, default) ?: default

    fun int(key: String, default: Int): Int = shared.getInt(key, default)
    fun bool(key: String, default: Boolean): Boolean =
        shared.getBoolean(key, default)

    fun put(key: String, value: String) {
        shared.edit().putString(key, value).apply()
    }

    fun put(key: String, value: Int) {
        shared.edit().putInt(key, value).apply()
    }

    fun put(key: String, value: Boolean) {
        shared.edit().putBoolean(key, value).apply()
    }
}

@Composable
fun rememberPrefs(): Prefs {
    val context = LocalContext.current
    return remember { Prefs(context.applicationContext) }
}

@Composable
fun prefString(prefs: Prefs, key: String, default: String): MutableState<String> {
    val state = remember { mutableStateOf(prefs.string(key, default)) }
    return object : MutableState<String> by state {
        override var value: String
            get() = state.value
            set(newValue) {
                state.value = newValue
                prefs.put(key, newValue)
            }
    }
}

@Composable
fun prefInt(prefs: Prefs, key: String, default: Int): MutableState<Int> {
    val state = remember { mutableStateOf(prefs.int(key, default)) }
    return object : MutableState<Int> by state {
        override var value: Int
            get() = state.value
            set(newValue) {
                state.value = newValue
                prefs.put(key, newValue)
            }
    }
}

@Composable
fun prefBool(prefs: Prefs, key: String, default: Boolean): MutableState<Boolean> {
    val state = remember { mutableStateOf(prefs.bool(key, default)) }
    return object : MutableState<Boolean> by state {
        override var value: Boolean
            get() = state.value
            set(newValue) {
                state.value = newValue
                prefs.put(key, newValue)
            }
    }
}

/// A section that folds open and shut from its header — the
/// Android CollapsibleSection, same manners as the iOS one.
@Composable
fun CollapsibleSection(
    title: String,
    openState: MutableState<Boolean>,
    content: @Composable () -> Unit
) {
    Column(modifier = Modifier.fillMaxWidth()) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .clickable { openState.value = !openState.value }
                .padding(vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            Text(title, style = MaterialTheme.typography.titleMedium)
            Icon(
                imageVector = if (openState.value) Icons.Filled.KeyboardArrowDown
                else Icons.Filled.KeyboardArrowRight,
                contentDescription = if (openState.value) "Collapse" else "Expand"
            )
        }
        AnimatedVisibility(visible = openState.value) {
            Column(
                modifier = Modifier.fillMaxWidth(),
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                content()
            }
        }
    }
}

@Composable
fun MonoText(text: String, modifier: Modifier = Modifier) {
    Text(
        text, modifier = modifier,
        style = MaterialTheme.typography.bodySmall.copy(fontFamily = FontFamily.Monospace)
    )
}

/// Labeled value line — the detail-page workhorse.
@Composable
fun FactRow(label: String, value: String) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 2.dp),
        horizontalArrangement = Arrangement.SpaceBetween
    ) {
        Text(label, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(value, style = MaterialTheme.typography.bodyMedium)
    }
}

/// Format an epoch-seconds age the way the iOS rows do.
fun ageText(ageSeconds: Int): String {
    return when {
        ageSeconds < 60 -> "${ageSeconds}s ago"
        ageSeconds < 3600 -> "${ageSeconds / 60}m ago"
        else -> "${ageSeconds / 3600}h ${ageSeconds / 60 % 60}m ago"
    }
}
