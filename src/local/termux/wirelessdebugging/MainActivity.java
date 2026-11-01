package local.termux.wirelessdebugging;

import android.Manifest;
import android.app.Activity;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.PackageManager;
import android.os.Bundle;
import android.provider.Settings;
import android.view.WindowManager;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.SecureRandom;

public final class MainActivity extends Activity {
    private static final String CONTROL_ACTION =
            "local.termux.wirelessdebugging.CONTROL";
    private static final String SETTING = "adb_wifi_enabled";
    private static final String PREFS = "private_settings";
    private static final String TOKEN_KEY = "control_token";

    private TextView statusView;
    private TextView tokenView;

    @Override
    public void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        getWindow().addFlags(WindowManager.LayoutParams.FLAG_SECURE);

        if (CONTROL_ACTION.equals(getIntent().getAction())) {
            handleControl(getIntent());
            return;
        }

        showInterface();
    }

    @Override
    protected void onResume() {
        super.onResume();
        refreshStatus();
    }

    private SharedPreferences preferences() {
        return getSharedPreferences(PREFS, MODE_PRIVATE);
    }

    private String getOrCreateToken() {
        String token = preferences().getString(TOKEN_KEY, null);

        if (token == null) {
            token = createToken();

            if (!preferences().edit().putString(TOKEN_KEY, token).commit()) {
                throw new IllegalStateException("Could not save control token.");
            }
        }

        return token;
    }

    private String createToken() {
        byte[] bytes = new byte[32];
        new SecureRandom().nextBytes(bytes);

        StringBuilder result = new StringBuilder(64);
        for (byte value : bytes) {
            result.append(Character.forDigit((value >>> 4) & 15, 16));
            result.append(Character.forDigit(value & 15, 16));
        }
        return result.toString();
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

    private void handleControl(Intent intent) {
        try {
            String expected = preferences().getString(TOKEN_KEY, null);
            String supplied = intent.getStringExtra("token");

            if (expected == null || supplied == null
                    || supplied.length() != expected.length()
                    || !MessageDigest.isEqual(
                            expected.getBytes(StandardCharsets.UTF_8),
                            supplied.getBytes(StandardCharsets.UTF_8))) {
                throw new SecurityException("Invalid control token.");
            }

            String operation = intent.getStringExtra("operation");

            if ("on".equals(operation)) {
                setEnabled(true);
                notifyUser("Wireless debugging enable request saved.");
            } else if ("off".equals(operation)) {
                setEnabled(false);
                notifyUser("Wireless debugging disable request saved.");
            } else if ("status".equals(operation)) {
                notifyUser(stateDescription());
            } else {
                throw new IllegalArgumentException(
                        "Operation must be on, off, or status.");
            }
        } catch (RuntimeException error) {
            notifyUser("Error: " + error.getMessage());
        } finally {
            finish();
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
        int padding = Math.round(
                20 * getResources().getDisplayMetrics().density);

        LinearLayout layout = new LinearLayout(this);
        layout.setOrientation(LinearLayout.VERTICAL);
        layout.setPadding(padding, padding, padding, padding);

        TextView title = new TextView(this);
        title.setText("Wireless Debugging");
        title.setTextSize(24);
        layout.addView(title);

        statusView = new TextView(this);
        layout.addView(statusView);

        addButton(layout, "Turn ON", () -> changeFromInterface(true));
        addButton(layout, "Turn OFF", () -> changeFromInterface(false));
        addButton(layout, "Refresh status", this::refreshStatus);

        TextView instructions = new TextView(this);
        instructions.setText(
                "\nGrant the required permission once using ADB:\n\n"
                + "adb shell pm grant local.termux.wirelessdebugging "
                + "android.permission.WRITE_SECURE_SETTINGS\n\n"
                + "Control token — keep it private:\n");
        instructions.setTextIsSelectable(true);
        layout.addView(instructions);

        tokenView = new TextView(this);
        tokenView.setTextIsSelectable(true);
        layout.addView(tokenView);

        try {
            tokenView.setText(getOrCreateToken());
        } catch (RuntimeException error) {
            tokenView.setText("Error: " + error.getMessage());
        }

        TextView warning = new TextView(this);
        warning.setText(
                "\nThe token authorizes external control of this app.\n"
                + "Do not publish it or commit it to Git.\n\n"
                + "Android may still require network approval.\n"
                + "An ON setting does not guarantee that ADB is reachable.");
        layout.addView(warning);

        ScrollView scroll = new ScrollView(this);
        scroll.addView(layout);
        setContentView(scroll);

        refreshStatus();
    }

    private void addButton(
            LinearLayout layout, String label, Runnable action) {
        Button button = new Button(this);
        button.setText(label);
        button.setOnClickListener(view -> action.run());
        layout.addView(button);
    }

    private void changeFromInterface(boolean enabled) {
        try {
            setEnabled(enabled);
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
