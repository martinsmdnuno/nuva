package pt.nunomartins.nuva.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsFocusedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.unit.dp
import pt.nunomartins.nuva.AppModel
import pt.nunomartins.nuva.R

/** Server, user and password, typed with the TV keyboard. The password is sent once and never kept. */
@Composable
fun SignInScreen(model: AppModel) {
    var server by rememberSaveable { mutableStateOf(model.savedServer) }
    var user by rememberSaveable { mutableStateOf(model.savedUser) }
    var password by remember { mutableStateOf("") }
    val first = remember { FocusRequester() }
    val submit = { if (server.isNotBlank() && user.isNotBlank() && !model.loading) model.signIn(server, user, password) }

    Box(Modifier.fillMaxSize().background(Tokens.surface0), contentAlignment = Alignment.Center) {
        Column(Modifier.width(560.dp), verticalArrangement = Arrangement.spacedBy(18.dp)) {
            Text(stringResource(R.string.sign_in_title), Type.title.copy(color = Tokens.ink, fontSize = Type.title.fontSize * 1.3f))
            Text(stringResource(R.string.sign_in_note), Type.body.copy(color = Tokens.inkMuted), maxLines = 2)
            Spacer(Modifier.height(6.dp))
            Field(stringResource(R.string.server), server, { server = it }, Modifier.focusRequester(first), KeyboardType.Uri)
            Field(stringResource(R.string.user), user, { user = it })
            Field(stringResource(R.string.password), password, { password = it }, secret = true, onDone = submit)
            model.error?.let { Text(it, Type.body.copy(color = Tokens.danger), maxLines = 2) }
            Spacer(Modifier.height(6.dp))
            Key(Tone.Play, 220.dp, submit, text = stringResource(if (model.loading) R.string.signing_in else R.string.sign_in))
        }
    }
    LaunchedEffect(Unit) { first.requestFocus() }
}

/** A field on the display: dark, recessed, display-ink text; the focus ring when selected. */
@Composable
private fun Field(
    label: String,
    value: String,
    onChange: (String) -> Unit,
    modifier: Modifier = Modifier,
    keyboard: KeyboardType = KeyboardType.Text,
    secret: Boolean = false,
    onDone: (() -> Unit)? = null,
) {
    val interaction = remember { MutableInteractionSource() }
    val focused by interaction.collectIsFocusedAsState()
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text(label, Type.label.copy(color = Tokens.ink))
        BasicTextField(
            value = value,
            onValueChange = onChange,
            modifier = modifier
                .fillMaxWidth()
                .border(2.dp, if (focused) Tokens.focus else Color.Transparent, KeyShape)
                .background(Tokens.display, KeyShape)
                .padding(horizontal = 16.dp, vertical = 12.dp),
            textStyle = Type.body.copy(color = Tokens.displayInk),
            singleLine = true,
            cursorBrush = SolidColor(Tokens.displayInk),
            interactionSource = interaction,
            visualTransformation = if (secret) PasswordVisualTransformation() else VisualTransformation.None,
            keyboardOptions = KeyboardOptions(
                keyboardType = if (secret) KeyboardType.Password else keyboard,
                imeAction = if (onDone != null) ImeAction.Done else ImeAction.Next,
                autoCorrectEnabled = false,
            ),
            keyboardActions = KeyboardActions(onDone = { onDone?.invoke() }),
        )
    }
}
