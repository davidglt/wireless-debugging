/*
 * Copyright (C) 2026 David González López-Tercero
 * Author: David González López-Tercero
 * SPDX-License-Identifier: GPL-3.0-or-later
 * See LICENSE and NOTICE in the repository root for licensing details.
 */
package local.termux.wirelessdebugging;

import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.CountDownLatch;

public final class ControlProtocolTest {
    private static final String TOKEN = "a".repeat(64);
    private static final String NONCE = "0123456789abcdef0123456789abcdef";

    static final class Fake implements ControlProtocol.Backend {
        volatile int setting;
        final boolean permission;
        int calls;

        Fake(int setting, boolean permission) {
            this.setting = setting;
            this.permission = permission;
        }

        public synchronized boolean hasPermission() {
            calls++;
            return permission;
        }

        public synchronized int readSetting() {
            calls++;
            return setting;
        }

        public synchronized boolean writeSetting(boolean enabled) {
            calls++;
            setting = enabled ? 1 : 0;
            return true;
        }
    }

    private static void check(boolean condition, String message) {
        if (!condition) {
            throw new AssertionError(message);
        }
    }

    private static ControlProtocol.Response run(
            Fake backend, String token, String op, String nonce) {
        return ControlProtocol.handle(TOKEN, token, op, nonce, backend);
    }

    public static void main(String[] args) throws Exception {
        Fake fake = new Fake(0, true);
        ControlProtocol.Response r = run(fake, TOKEN, "status", NONCE);
        check(r.code == ControlProtocol.RESULT_OK && r.data.contains("setting=0")
                && r.data.contains("nonce=" + NONCE), "status: " + r.data);

        r = run(fake, TOKEN, "on", NONCE);
        check(r.data.contains("status=ok") && r.data.contains("setting=1")
                && fake.setting == 1, "on: " + r.data);

        r = run(fake, TOKEN, "off", NONCE);
        check(r.data.contains("setting=0") && fake.setting == 0, "off");

        Fake untouched = new Fake(0, true);
        r = run(untouched, "b".repeat(64), "on", NONCE);
        check(r.code == ControlProtocol.RESULT_ERROR
                && r.data.contains("error=unauthorized")
                && !r.data.contains("setting=") && untouched.calls == 0
                && untouched.setting == 0, "invalid token: " + r.data);
        r = run(untouched, null, "status", NONCE);
        check(r.data.contains("unauthorized") && untouched.calls == 0, "null");
        r = ControlProtocol.handle(null, TOKEN, "status", NONCE, untouched);
        check(r.data.contains("unauthorized") && untouched.calls == 0, "unset");
        check(!r.data.contains(TOKEN), "token leaked");

        Fake denied = new Fake(0, false);
        r = run(denied, TOKEN, "on", NONCE);
        check(r.code == ControlProtocol.RESULT_ERROR
                && r.data.contains("error=permission_denied")
                && r.data.contains("permission=denied")
                && denied.setting == 0, "permission: " + r.data);
        r = run(denied, TOKEN, "status", NONCE);
        check(r.data.contains("status=ok") && r.data.contains("permission=denied"),
                "status without permission");

        r = run(fake, TOKEN, "reboot", NONCE);
        check(r.data.contains("invalid_operation"), "operation");
        r = run(fake, TOKEN, "status", "bad nonce");
        check(r.data.contains("invalid_nonce"), "nonce");

        // Concurrent requests keep their own correlation identifiers.
        final int threads = 32;
        final CountDownLatch start = new CountDownLatch(1);
        final List<String> failures = new ArrayList<>();
        final Fake shared = new Fake(0, true);
        List<Thread> pool = new ArrayList<>();
        for (int i = 0; i < threads; i++) {
            final String nonce = String.format("%032x", i + 1);
            final String op = i % 2 == 0 ? "on" : "status";
            Thread t = new Thread(() -> {
                try {
                    start.await();
                    ControlProtocol.Response x = run(shared, TOKEN, op, nonce);
                    if (!x.data.contains("nonce=" + nonce)
                            || !x.data.contains("status=ok")) {
                        synchronized (failures) {
                            failures.add(x.data);
                        }
                    }
                } catch (InterruptedException e) {
                    synchronized (failures) {
                        failures.add("interrupted");
                    }
                }
            });
            pool.add(t);
            t.start();
        }
        start.countDown();
        for (Thread t : pool) {
            t.join();
        }
        check(failures.isEmpty(), "concurrency: " + failures);

        System.out.println("ControlProtocolTest: all checks passed");
    }
}
