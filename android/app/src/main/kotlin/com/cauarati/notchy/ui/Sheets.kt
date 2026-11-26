package com.cauarati.notchy.ui

import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.slideInVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.cauarati.notchy.R
import com.cauarati.notchy.core.MotionSpec
import com.cauarati.notchy.core.Radii

/**
 * A panel that rises from the bottom over whatever is on screen, with a dim scrim behind it. It is black in
 * both themes, like the island it comes from. Tapping the scrim or pressing Back closes it; taps on the
 * panel itself never reach the scrim.
 */
@Composable
fun BottomSheetHost(onDismiss: () -> Unit, content: @Composable ColumnScope.() -> Unit) {
    BackHandler(onBack = onDismiss)
    val closeLabel = stringResource(R.string.action_close)
    var shown by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) { shown = true }
    val shape = RoundedCornerShape(topStart = Radii.SHEET.dp, topEnd = Radii.SHEET.dp)
    Box(Modifier.fillMaxSize()) {
        Box(
            Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.55f))
                .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null, onClick = onDismiss)
                .semantics { contentDescription = closeLabel; role = Role.Button },
        )
        AnimatedVisibility(
            visible = shown, modifier = Modifier.align(Alignment.BottomCenter),
            enter = if (reducedMotion()) fadeIn(tween(MotionSpec.REDUCED_MS)) else slideInVertically(spring(dampingRatio = 0.72f, stiffness = 400f)) { it } + fadeIn(),
        ) {
            Column(
                Modifier.fillMaxWidth().clip(shape).background(Color(tokens().sheet)).border(1.dp, Color(tokens().heroLine), shape)
                    .pointerInput(Unit) { detectTapGestures { } }
                    // A large font can make the sheet taller than the screen: it scrolls, so its buttons are always reachable.
                    .verticalScroll(rememberScrollState())
                    .padding(start = 20.dp, end = 20.dp, top = 10.dp, bottom = 20.dp),
                content = {
                    Box(Modifier.align(Alignment.CenterHorizontally).size(width = 36.dp, height = 4.dp).clip(RoundedCornerShape(2.dp)).background(Color(tokens().heroTextDim).copy(alpha = 0.45f)))
                    Box(Modifier.size(14.dp))
                    content()
                },
            )
        }
    }
}
