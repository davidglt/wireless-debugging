/*
 * Copyright (C) 2026 David González López-Tercero
 * Author: David González López-Tercero
 * SPDX-License-Identifier: GPL-3.0-or-later
 * See LICENSE and NOTICE in the repository root for licensing details.
 */
package local.termux.wirelessdebugging;

import android.Manifest;
import android.app.Activity;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.os.Bundle;
import android.provider.Settings;
import android.view.WindowManager;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;

public final class MainActivity extends Activity {
    static final String SETTING = "adb_wifi_enabled";
    static final String PREFS = "private_settings";
    static final String TOKEN_KEY = "control_token";

    private TextView statusView;

    @Override
    public void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        getWindow().addFlags(WindowManager.LayoutParams.FLAG_SECURE);

        try {
            AppSupport.getOrCreateToken(this);
        } catch (RuntimeException error) {
            notifyUser("Error: " + error.getMessage());
        }

        showInterface();
    }

    @Override
    protected void onResume() {
        super.onResume();
        refreshStatus();
    }

    private boolean hasWritePermission() {
        return checkSelfPermission(Manifest.permission.WRITE_SECURE_SETTINGS)
                == PackageManager.PERMISSION_GRANTED;
    }

    private int readState() {
        return Settings.Global.getInt(getContentResolver(), SETTING, -1);
    }

    private void setEnabled(boolean enabled) {
        if (!hasWritePermission()) {
            throw new SecurityException(
                    "WRITE_SECURE_SETTINGS has not been granted.");
        }

        boolean saved = Settings.Global.putInt(
                getContentResolver(), SETTING, enabled ? 1 : 0);

        if (!saved) {
            throw new IllegalStateException("Could not update system setting.");
        }
    }

    private String stateDescription() {
        int state = readState();

        if (state == 1) {
            return "Wireless debugging setting: ON";
        }
        if (state == 0) {
            return "Wireless debugging setting: OFF";
        }
        return "Wireless debugging setting: UNKNOWN";
    }

    private void showInterface() {
        int padding = AppSupport.dp(this, 20);

        LinearLayout layout = new LinearLayout(this);
        layout.setOrientation(LinearLayout.VERTICAL);
        layout.setPadding(padding, padding, padding, padding);

        TextView title = AppSupport.addText(
                this, layout, "Wireless Debugging", false);
        title.setTextSize(24);

        statusView = AppSupport.addText(this, layout, "", false);

        AppSupport.addButton(this, layout, "Turn ON",
                () -> changeFromInterface(true));
        AppSupport.addButton(this, layout, "Turn OFF",
                () -> changeFromInterface(false));
        AppSupport.addButton(this, layout, "Refresh status", this::refreshStatus);
        AppSupport.addButton(this, layout, "Setup", () ->
                startActivity(new Intent(this, SetupActivity.class)));
        AppSupport.addButton(this, layout, "About", () ->
                startActivity(new Intent(this, AboutActivity.class)));

        ScrollView scroll = new ScrollView(this);
        scroll.addView(layout);
        setContentView(scroll);

        refreshStatus();
    }

    private void changeFromInterface(boolean enabled) {
        try {
            setEnabled(enabled);
            int observed = readState();
            if (observed != (enabled ? 1 : 0)) {
                notifyUser("Error: setting change was not observed.");
                refreshStatus();
                return;
            }
            notifyUser("System setting updated.");
        } catch (RuntimeException error) {
            notifyUser("Error: " + error.getMessage());
        }
        refreshStatus();
    }

    private void refreshStatus() {
        if (statusView == null) {
            return;
        }

        try {
            statusView.setText(
                    "\n" + stateDescription()
                    + "\nRequired permission: "
                    + (hasWritePermission() ? "GRANTED" : "NOT GRANTED")
                    + "\nSetting status does not verify ADB connectivity."
                    + "\n");
        } catch (RuntimeException error) {
            statusView.setText("\nStatus unavailable: "
                    + error.getMessage() + "\n");
        }
    }

    private void notifyUser(String message) {
        Toast.makeText(this, message, Toast.LENGTH_LONG).show();
    }
}
