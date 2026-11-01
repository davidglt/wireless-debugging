/*
 * Copyright (C) 2026 David González López-Tercero
 * Author: David González López-Tercero
 * SPDX-License-Identifier: GPL-3.0-or-later
 * See LICENSE and NOTICE in the repository root for licensing details.
 */
package local.termux.wirelessdebugging;

import android.Manifest;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.provider.Settings;

/**
 * Token-authenticated control endpoint. The caller must send an ordered
 * broadcast (am broadcast); the result is returned through the broadcast
 * result code and data, so no file or world-readable channel is used. Each
 * broadcast has its own result, which keeps concurrent requests separate; the
 * caller-supplied nonce is echoed for correlation.
 */
public final class ControlReceiver extends BroadcastReceiver {
    static final String ACTION = "local.termux.wirelessdebugging.CONTROL";

    @Override
    public void onReceive(Context context, Intent intent) {
        if (intent == null || !ACTION.equals(intent.getAction())
                || !isOrderedBroadcast()) {
            return;
        }

        final Context app = context.getApplicationContext() != null
                ? context.getApplicationContext() : context;
        String expected = app.getSharedPreferences(
                MainActivity.PREFS, Context.MODE_PRIVATE)
                .getString(MainActivity.TOKEN_KEY, null);

        ControlProtocol.Response response = ControlProtocol.handle(
                expected,
                intent.getStringExtra("token"),
                intent.getStringExtra("operation"),
                intent.getStringExtra("nonce"),
                new ControlProtocol.Backend() {
                    @Override
                    public boolean hasPermission() {
                        return app.checkSelfPermission(
                                Manifest.permission.WRITE_SECURE_SETTINGS)
                                == PackageManager.PERMISSION_GRANTED;
                    }

                    @Override
                    public int readSetting() {
                        return Settings.Global.getInt(
                                app.getContentResolver(),
                                MainActivity.SETTING, -1);
                    }

                    @Override
                    public String versionName() {
                        try {
                            return app.getPackageManager().getPackageInfo(
                                    app.getPackageName(), 0).versionName;
                        } catch (PackageManager.NameNotFoundException
                                | RuntimeException failure) {
                            return null;
                        }
                    }

                    @Override
                    public long versionCode() {
                        try {
                            return app.getPackageManager().getPackageInfo(
                                    app.getPackageName(), 0)
                                    .getLongVersionCode();
                        } catch (PackageManager.NameNotFoundException
                                | RuntimeException failure) {
                            return -1;
                        }
                    }

                    @Override
                    public boolean writeSetting(boolean enabled) {
                        return Settings.Global.putInt(
                                app.getContentResolver(),
                                MainActivity.SETTING, enabled ? 1 : 0);
                    }
                });

        setResultCode(response.code);
        setResultData(response.data);
    }
}
