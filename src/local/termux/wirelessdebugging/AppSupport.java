/*
 * Copyright (C) 2026 David González López-Tercero
 * Author: David González López-Tercero
 * SPDX-License-Identifier: GPL-3.0-or-later
 * See LICENSE in the repository root for licensing details.
 */
package local.termux.wirelessdebugging;

import android.content.ClipData;
import android.content.ClipDescription;
import android.content.ClipboardManager;
import android.content.Context;
import android.content.SharedPreferences;
import android.content.pm.PackageInfo;
import android.content.pm.PackageManager;
import android.os.PersistableBundle;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.TextView;
import android.widget.Toast;

import java.security.SecureRandom;

/** Shared helpers for the interface screens. Never logs the token. */
final class AppSupport {
    static final String PROJECT_URL =
            "https://github.com/davidglt/wireless-debugging";
    static final String GRANT_COMMAND =
            "adb shell pm grant local.termux.wirelessdebugging "
            + "android.permission.WRITE_SECURE_SETTINGS";

    private AppSupport() {
    }

    static SharedPreferences preferences(Context context) {
        return context.getSharedPreferences(
                MainActivity.PREFS, Context.MODE_PRIVATE);
    }

    /** Returns the existing token; creates one only if none exists. */
    static String getOrCreateToken(Context context) {
        SharedPreferences prefs = preferences(context);
        String token = prefs.getString(MainActivity.TOKEN_KEY, null);

        if (token == null) {
            token = createToken();

            if (!prefs.edit().putString(MainActivity.TOKEN_KEY, token)
                    .commit()) {
                throw new IllegalStateException("Could not save control token.");
            }
        }

        return token;
    }

    private static String createToken() {
        byte[] bytes = new byte[32];
        new SecureRandom().nextBytes(bytes);

        StringBuilder result = new StringBuilder(64);
        for (byte value : bytes) {
            result.append(Character.forDigit((value >>> 4) & 15, 16));
            result.append(Character.forDigit(value & 15, 16));
        }
        return result.toString();
    }

    /** Version read from the installed package metadata. */
    static String installedVersion(Context context) {
        try {
            PackageInfo info = context.getPackageManager().getPackageInfo(
                    context.getPackageName(), 0);
            return info.versionName + " (code " + info.getLongVersionCode()
                    + ")";
        } catch (PackageManager.NameNotFoundException | RuntimeException e) {
            return "unavailable";
        }
    }

    static void copy(Context context, String label, String text,
            boolean sensitive) {
        ClipboardManager clipboard = (ClipboardManager)
                context.getSystemService(Context.CLIPBOARD_SERVICE);

        if (clipboard == null) {
            toast(context, "Clipboard is unavailable.");
            return;
        }

        ClipData clip = ClipData.newPlainText(label, text);
        if (sensitive) {
            PersistableBundle extras = new PersistableBundle();
            extras.putBoolean("android.content.extra.IS_SENSITIVE", true);
            clip.getDescription().setExtras(extras);
        }
        clipboard.setPrimaryClip(clip);
        toast(context, label + " copied.");
    }

    static void toast(Context context, String message) {
        Toast.makeText(context, message, Toast.LENGTH_LONG).show();
    }

    static int dp(Context context, int value) {
        return Math.round(value * context.getResources()
                .getDisplayMetrics().density);
    }

    static Button addButton(Context context, LinearLayout layout,
            String label, Runnable action) {
        Button button = new Button(context);
        button.setText(label);
        button.setOnClickListener(view -> action.run());
        layout.addView(button);
        return button;
    }

    static TextView addText(Context context, LinearLayout layout,
            String text, boolean selectable) {
        TextView view = new TextView(context);
        view.setText(text);
        view.setTextIsSelectable(selectable);
        layout.addView(view);
        return view;
    }
}
