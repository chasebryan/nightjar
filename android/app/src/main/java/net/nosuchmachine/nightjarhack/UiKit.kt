package net.nosuchmachine.nightjarhack

import android.content.Context
import android.content.SharedPreferences
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.KeyboardArrowRight
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.MutableState
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp

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
