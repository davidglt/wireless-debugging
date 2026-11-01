/*
 * Copyright (C) 2026 David González López-Tercero
 * Author: David González López-Tercero
 * SPDX-License-Identifier: GPL-3.0-or-later
 * See LICENSE in the repository root for licensing details.
 */
package local.termux.wirelessdebugging;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;

/**
 * Android-independent request handling for the authenticated control channel.
 * The token is validated before any backend call or state disclosure, and the
 * response never contains the token.
 */
final class ControlProtocol {
    static final int RESULT_OK = 1;
    static final int RESULT_ERROR = 2;

    interface Backend {
        boolean hasPermission();

        int readSetting();

        boolean writeSetting(boolean enabled);

        String versionName();

        long versionCode();
    }

    static final class Response {
        final int code;
        final String data;

        Response(int code, String data) {
            this.code = code;
            this.data = data;
        }
    }

    private ControlProtocol() {
    }

    static boolean validNonce(String nonce) {
        return nonce != null && nonce.matches("[0-9a-f]{32}");
    }

    static Response handle(String expectedToken, String suppliedToken,
            String operation, String nonce, Backend backend) {
        String echo = validNonce(nonce) ? nonce : "none";

        if (expectedToken == null || suppliedToken == null
                || !MessageDigest.isEqual(
                        expectedToken.getBytes(StandardCharsets.UTF_8),
                        suppliedToken.getBytes(StandardCharsets.UTF_8))) {
            return error(echo, "unauthorized");
        }
        if (!validNonce(nonce)) {
            return error(echo, "invalid_nonce");
        }

        try {
            if ("version".equals(operation)) {
                return new Response(RESULT_OK, "wd2 nonce=" + echo
                        + " status=ok op=version" + version(backend));
            }

            boolean permission = backend.hasPermission();

            if ("status".equals(operation)) {
                return ok(echo, operation, backend.readSetting(), permission,
                        version(backend));
            }
            if ("on".equals(operation) || "off".equals(operation)) {
                if (!permission) {
                    return error(echo, "permission_denied", operation,
                            backend.readSetting(), false);
                }
                boolean saved = backend.writeSetting("on".equals(operation));
                int observed = backend.readSetting();
                if (!saved) {
                    return error(echo, "write_failed", operation, observed,
                            true);
                }
                return ok(echo, operation, observed, true, version(backend));
            }
            return error(echo, "invalid_operation");
        } catch (RuntimeException failure) {
            return error(echo, "internal_error");
        }
    }

    static String cleanVersion(String name) {
        if (name == null || name.isEmpty()) {
            return "unknown";
        }
        String cleaned = name.replaceAll("[^A-Za-z0-9._+-]", "_");
        return cleaned.length() > 40 ? cleaned.substring(0, 40) : cleaned;
    }

    /** Version fields read from package metadata, never hardcoded. */
    private static String version(Backend backend) {
        return " version=" + cleanVersion(backend.versionName())
                + " version_code=" + backend.versionCode();
    }

    private static String setting(int value) {
        return value == 1 ? "1" : value == 0 ? "0" : "unknown";
    }

    private static Response ok(String nonce, String operation, int observed,
            boolean permission, String version) {
        return new Response(RESULT_OK, "wd2 nonce=" + nonce
                + " status=ok op=" + operation
                + " setting=" + setting(observed)
                + " permission=" + (permission ? "granted" : "denied")
                + version);
    }

    private static Response error(String nonce, String reason) {
        return new Response(RESULT_ERROR, "wd2 nonce=" + nonce
                + " status=error error=" + reason);
    }

    private static Response error(String nonce, String reason,
            String operation, int observed, boolean permission) {
        return new Response(RESULT_ERROR, "wd2 nonce=" + nonce
                + " status=error error=" + reason
                + " op=" + operation
                + " setting=" + setting(observed)
                + " permission=" + (permission ? "granted" : "denied"));
    }
}
