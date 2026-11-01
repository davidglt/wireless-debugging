/*
 * Copyright (C) 2026 David González López-Tercero
 * Author: David González López-Tercero
 * SPDX-License-Identifier: GPL-3.0-or-later
 * See LICENSE and NOTICE in the repository root for licensing details.
 */
package local.termux.wirelessdebugging;

import android.app.Activity;
import android.os.Bundle;
import android.view.WindowManager;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

/**
 * Setup screen: permission command, Termux instructions and the control
 * token. The token is hidden until the user asks, the window is FLAG_SECURE,
 * and opening this screen never replaces an existing token.
 */
public final class SetupActivity extends Activity {
    private static final String MASK = "\u2022\u2022\u2022\u2022\u2022\u2022"
            + "\u2022\u2022 (hidden)";

    private TextView tokenView;
    private Button toggleButton;
    private boolean tokenVisible;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        getWindow().addFlags(WindowManager.LayoutParams.FLAG_SECURE);

        int padding = AppSupport.dp(this, 20);
        LinearLayout layout = new LinearLayout(this);
        layout.setOrientation(LinearLayout.VERTICAL);
        layout.setPadding(padding, padding, padding, padding);

        TextView title = AppSupport.addText(this, layout, "Setup", false);
        title.setTextSize(24);

        AppSupport.addText(this, layout,
                "\n1. Grant the required permission once, from a computer or "
                + "an authorized ADB connection:\n", false);
        AppSupport.addText(this, layout, AppSupport.GRANT_COMMAND, true);
        AppSupport.addButton(this, layout, "Copy command", () ->
                AppSupport.copy(this, "Command", AppSupport.GRANT_COMMAND,
                        false));

        AppSupport.addText(this, layout,
                "\n2. Configure the Termux command:\n"
                + "Install scripts/wireless-debugging from the project into "
                + "$HOME/bin together with scripts/adb-local-check, then save the control token below to "
                + "~/.config/wireless-debugging/token (mode 600) using the "
                + "README instructions. Termux also needs the Display over "
                + "other apps special access.\n\n"
                + "3. Control token:\n", false);

        tokenView = AppSupport.addText(this, layout, MASK, false);
        toggleButton = AppSupport.addButton(
                this, layout, "Show token", this::toggleToken);
        AppSupport.addButton(this, layout, "Copy token", this::copyToken);

        AppSupport.addText(this, layout,
                "\nKeep the token private. It authorizes external control of "
                + "this app. Do not publish it or commit it to Git.\n\n"
                + "Enabling the setting does not guarantee that ADB is "
                + "reachable, and it does not bypass Android network "
                + "approval. The setting status does not verify ADB "
                + "connectivity.\n", false);

        AppSupport.addButton(this, layout, "Close", this::finish);

        ScrollView scroll = new ScrollView(this);
        scroll.addView(layout);
        setContentView(scroll);
    }

    @Override
    protected void onStop() {
        super.onStop();
        hideToken();
    }

    private void toggleToken() {
        if (tokenVisible) {
            hideToken();
            return;
        }

        try {
            tokenView.setText(AppSupport.getOrCreateToken(this));
            tokenView.setTextIsSelectable(true);
            tokenVisible = true;
            toggleButton.setText("Hide token");
        } catch (RuntimeException error) {
            AppSupport.toast(this, "Error: " + error.getMessage());
        }
    }

    private void hideToken() {
        tokenVisible = false;
        if (tokenView != null) {
            tokenView.setTextIsSelectable(false);
            tokenView.setText(MASK);
            toggleButton.setText("Show token");
        }
    }

    private void copyToken() {
        try {
            AppSupport.copy(this, "Control token",
                    AppSupport.getOrCreateToken(this), true);
        } catch (RuntimeException error) {
            AppSupport.toast(this, "Error: " + error.getMessage());
        }
    }
}
