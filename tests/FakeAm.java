/*
 * Copyright (C) 2026 David González López-Tercero
 * Author: David González López-Tercero
 * SPDX-License-Identifier: GPL-3.0-or-later
 * See LICENSE and NOTICE in the repository root for licensing details.
 */
package local.termux.wirelessdebugging;

/**
 * Test double for "am broadcast": runs the real ControlProtocol against a
 * file-backed setting and prints output in the format of am. Test only.
 * Environment: FAKE_AM_TOKEN, FAKE_AM_STATE (file), FAKE_AM_PERMISSION=1|0,
 * FAKE_AM_DELAY (seconds), FAKE_AM_MODE=garbage|wrongnonce.
 */
import java.nio.file.Files;
import java.nio.file.Paths;
import java.nio.file.StandardOpenOption;

public final class FakeAm {
    public static void main(String[] args) throws Exception {
        String op = null;
        String nonce = null;
        String token = null;
        for (int i = 0; i + 1 < args.length; i++) {
            if (args[i].equals("--es")) {
                String key = args[i + 1];
                String value = args[i + 2];
                if (key.equals("operation")) op = value;
                if (key.equals("nonce")) nonce = value;
                if (key.equals("token")) token = value;
            }
        }
        String mode = System.getenv("FAKE_AM_MODE");
        if ("garbage".equals(mode)) {
            System.out.println("Broadcast completed: result=0");
            return;
        }
        String delay = System.getenv("FAKE_AM_DELAY");
        if (delay != null) {
            Thread.sleep(Long.parseLong(delay) * 1000);
        }
        final java.nio.file.Path state = Paths.get(System.getenv("FAKE_AM_STATE"));
        final boolean permission = !"0".equals(System.getenv("FAKE_AM_PERMISSION"));
        ControlProtocol.Backend backend = new ControlProtocol.Backend() {
            public boolean hasPermission() {
                return permission;
            }

            public int readSetting() {
                try {
                    return Integer.parseInt(
                            new String(Files.readAllBytes(state)).trim());
                } catch (Exception e) {
                    return -1;
                }
            }

            public boolean writeSetting(boolean enabled) {
                try {
                    Files.write(state, (enabled ? "1" : "0").getBytes(),
                            StandardOpenOption.CREATE,
                            StandardOpenOption.TRUNCATE_EXISTING);
                    return true;
                } catch (Exception e) {
                    return false;
                }
            }
        };
        String used = "wrongnonce".equals(mode) ? "f".repeat(32) : nonce;
        ControlProtocol.Response r = ControlProtocol.handle(
                System.getenv("FAKE_AM_TOKEN"), token, op, used, backend);
        System.out.println("Broadcasting: Intent { act=... }");
        System.out.println("Broadcast completed: result=" + r.code
                + ", data=\"" + r.data + "\"");
    }
}
