/*
 * Copyright (C) 2026 David González López-Tercero
 * Author: David González López-Tercero
 * SPDX-License-Identifier: GPL-3.0-or-later
 * See LICENSE in the repository root for licensing details.
 */
package local.termux.wirelessdebugging;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.ActivityNotFoundException;
import android.content.Intent;
import android.net.Uri;
import android.os.Bundle;
import android.text.SpannableString;
import android.text.Spanned;
import android.text.method.LinkMovementMethod;
import android.text.style.ClickableSpan;
import android.view.View;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;

/** About screen: attribution, installed version, license and repository. */
public final class AboutActivity extends Activity {
    /** Asset packaged by build.sh from the repository LICENSE file. */
    static final String LICENSE_ASSET = "LICENSE.txt";
    private static final String LICENSE_PREFIX = "License: ";
    private static final String LICENSE_LINK = "GNU GPL v3 or later";

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        int padding = AppSupport.dp(this, 20);
        LinearLayout layout = new LinearLayout(this);
        layout.setOrientation(LinearLayout.VERTICAL);
        layout.setPadding(padding, padding, padding, padding);

        TextView title = AppSupport.addText(
                this, layout, "Wireless Debugging", false);
        title.setTextSize(24);

        AppSupport.addText(this, layout,
                "\nVersion: " + AppSupport.installedVersion(this)
                + "\nCopyright \u00a9 2026 David Gonz\u00e1lez "
                + "L\u00f3pez-Tercero", true);

        SpannableString license =
                new SpannableString(LICENSE_PREFIX + LICENSE_LINK);
        license.setSpan(new ClickableSpan() {
            @Override
            public void onClick(View widget) {
                showLicense();
            }
        }, LICENSE_PREFIX.length(), license.length(),
                Spanned.SPAN_EXCLUSIVE_EXCLUSIVE);
        TextView licenseView = AppSupport.addText(this, layout, "", false);
        licenseView.setText(license);
        licenseView.setMovementMethod(LinkMovementMethod.getInstance());
        licenseView.setPadding(0, 0, 0, padding);

        AppSupport.addButton(this, layout, "Repository", () -> {
            try {
                startActivity(new Intent(Intent.ACTION_VIEW,
                        Uri.parse(AppSupport.PROJECT_URL)));
            } catch (ActivityNotFoundException error) {
                AppSupport.toast(this, "No application can open the link.");
            }
        });
        AppSupport.addButton(this, layout, "Close", this::finish);

        ScrollView scroll = new ScrollView(this);
        scroll.addView(layout);
        setContentView(scroll);
    }

    /** Shows the bundled GPL text; no network access is needed. */
    private void showLicense() {
        String text;
        try (InputStream in = getAssets().open(LICENSE_ASSET)) {
            ByteArrayOutputStream out = new ByteArrayOutputStream();
            byte[] buffer = new byte[8192];
            int count;
            while ((count = in.read(buffer)) != -1) {
                out.write(buffer, 0, count);
            }
            text = new String(out.toByteArray(), StandardCharsets.UTF_8);
        } catch (IOException error) {
            AppSupport.toast(this, "The license text is unavailable.");
            return;
        }

        int padding = AppSupport.dp(this, 16);
        TextView body = new TextView(this);
        body.setText(text);
        body.setTextIsSelectable(true);
        body.setPadding(padding, padding, padding, padding);
        ScrollView scroll = new ScrollView(this);
        scroll.addView(body);

        new AlertDialog.Builder(this)
                .setTitle("GNU General Public License v3")
                .setView(scroll)
                .setPositiveButton("Close", null)
                .show();
    }
}
