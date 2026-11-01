/*
 * Copyright (C) 2026 David González López-Tercero
 * Author: David González López-Tercero
 * SPDX-License-Identifier: GPL-3.0-or-later
 * See LICENSE and NOTICE in the repository root for licensing details.
 */
package local.termux.wirelessdebugging;

import android.app.Activity;
import android.content.ActivityNotFoundException;
import android.content.Intent;
import android.net.Uri;
import android.os.Bundle;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

/** About screen: attribution, installed version and project link. */
public final class AboutActivity extends Activity {
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
                + "\nAuthor: David González López-Tercero"
                + "\nCopyright (C) 2026 David González López-Tercero"
                + "\nLicense: GNU GPL v3 or later\n\n"
                + AppSupport.PROJECT_URL + "\n", true);

        AppSupport.addButton(this, layout, "Open project page", () -> {
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
}
