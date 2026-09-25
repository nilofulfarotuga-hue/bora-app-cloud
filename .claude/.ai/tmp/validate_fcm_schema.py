#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Validador mecanico (nearest-equivalent do FCM validate_only) para as 13
Edge Functions de notificacao do Bora App.

Nenhuma chamada de rede e feita. Nao usa credenciais. Nao envia nada.

O que faz: extrai o objecto `message` (ou `payload`) que cada function
constroi e envia para https://fcm.googleapis.com/v1/projects/{id}/messages:send,
e valida os NOMES DOS CAMPOS contra o schema oficial da FCM HTTP v1 API
(Message / AndroidConfig / AndroidNotification / ApnsConfig / Aps / WebpushConfig).

Isto e o mais perto que se chega de "validate_only" sem:
  - extrair o secret FIREBASE_SERVICE_ACCOUNT (credencial de producao)
  - correr Deno/supabase functions serve (nao instalados nesta maquina)
  - fazer uma chamada de rede real a FCM (que exigiria o token OAuth2 acima)

Um payload com nomes de campo invalidos e EXACTAMENTE o tipo de erro que a
FCM devolveria com validate_only:true -> INVALID_ARGUMENT. Nomes todos
validos nao GARANTE que a FCM aceite (haveria de correr o pedido real),
mas elimina a classe de erro mais comum (campo errado/typo) sem qualquer
risco de entrega.
"""
import re
import sys
import os
import json

ROOT = r"C:\BoraLocal\projetosflutter\bora_app\supabase\functions"

FUNCS = [
    "notify-admin-reimbursement",
    "notify-admin-urgent",
    "notify-chat-message",
    "notify-cleaner",
    "notify-client",
    "notify-driver",
    "notify-partner",
    "notify-partner-low-rating",
    "notify-purchase-finalized",
    "notify-service-provider",
    "notify-tvde-client",
    "notify-tvde-driver",
    "notify-washer",
]

# Schema oficial FCM HTTP v1 (https://firebase.google.com/docs/reference/fcm/rest/v1/projects.messages)
MESSAGE_KEYS = {"name", "data", "notification", "android", "webpush", "apns", "fcm_options", "token", "topic", "condition"}
NOTIFICATION_KEYS = {"title", "body", "image"}
ANDROID_KEYS = {"collapse_key", "priority", "ttl", "restricted_package_name", "data", "notification", "fcm_options", "direct_boot_ok"}
ANDROID_NOTIF_KEYS = {
    "title", "body", "icon", "color", "sound", "tag", "click_action",
    "body_loc_key", "body_loc_args", "title_loc_key", "title_loc_args",
    "channel_id", "ticker", "sticky", "event_time", "local_only",
    "notification_priority", "default_sound", "default_vibrate_timings",
    "default_light_settings", "vibrate_timings", "visibility",
    "notification_count", "light_settings", "image", "bypass_proxy_notification",
}
APNS_KEYS = {"headers", "payload", "fcm_options"}
APS_KEYS = {
    "alert", "badge", "sound", "thread-id", "category", "content-available",
    "mutable-content", "target-content-id", "interruption-level",
    "relevance-score", "filter-criteria", "stale-date", "content-state",
    "timestamp", "event", "dismissal-date", "attributes-type", "attributes",
}
WEBPUSH_KEYS = {"headers", "data", "notification", "fcm_options"}
FCM_OPTIONS_KEYS = {"analytics_label", "image", "link"}
TOP_SEND_KEYS = {"message", "validate_only"}

ANDROID_PRIORITY_VALUES = {"NORMAL", "HIGH", "high", "normal"}  # SDK accepts lower-case 'high'/'normal', v1 REST wants NORMAL/HIGH but Deno fetch code commonly uses lower-case and FCM backend normalizes it — flag only, don't fail
NOTIF_PRIORITY_VALUES = {
    "PRIORITY_UNSPECIFIED", "PRIORITY_MIN", "PRIORITY_LOW", "PRIORITY_DEFAULT",
    "PRIORITY_HIGH", "PRIORITY_MAX",
}
VISIBILITY_VALUES = {"VISIBILITY_UNSPECIFIED", "PRIVATE", "PUBLIC", "SECRET"}


def extract_block(src, start_idx):
    """Given index of an opening '{', return the matching-brace substring (inclusive)."""
    depth = 0
    i = start_idx
    in_str = None
    while i < len(src):
        c = src[i]
        if in_str:
            if c == '\\':
                i += 2
                continue
            if c == in_str:
                in_str = None
        else:
            if c in ('"', "'", '`'):
                in_str = c
            elif c == '{':
                depth += 1
            elif c == '}':
                depth -= 1
                if depth == 0:
                    return src[start_idx:i+1]
        i += 1
    return None


def find_object_after(src, marker):
    """Find `marker` then the next '{' after it, return the balanced block."""
    m = re.search(re.escape(marker), src)
    if not m:
        return None
    brace_idx = src.find('{', m.end())
    if brace_idx == -1:
        return None
    return extract_block(src, brace_idx)


def top_level_keys(block):
    """Extract top-level `key:` names from a {...} block (depth 1 only)."""
    if block is None:
        return []
    inner = block[1:-1]
    keys = []
    depth = 0
    i = 0
    in_str = None
    key_buf = ""
    expecting_key = True
    n = len(inner)
    while i < n:
        c = inner[i]
        if in_str:
            key_buf += c if expecting_key else ""
            if c == '\\':
                i += 1
                if i < n:
                    key_buf += inner[i] if expecting_key else ""
            elif c == in_str:
                in_str = None
            i += 1
            continue
        if c in ('"', "'"):
            in_str = c
            i += 1
            continue
        if c == '{' or c == '[':
            depth += 1
            expecting_key = False
            i += 1
            continue
        if c == '}' or c == ']':
            depth -= 1
            i += 1
            continue
        if depth == 0:
            if c == ':':
                k = key_buf.strip().strip('"').strip("'")
                if k:
                    keys.append(k)
                key_buf = ""
                expecting_key = False
                i += 1
                continue
            if c == ',':
                key_buf = ""
                expecting_key = True
                i += 1
                continue
            if expecting_key and (c.isalnum() or c in '_$'):
                key_buf += c
            i += 1
            continue
        i += 1
    return keys


def sub_block(block, key):
    """Find `key:` at top level of block, return its {...} sub-block if object-valued."""
    if block is None:
        return None
    # naive: find "key:" then check next non-space char is '{'
    pattern = re.compile(r'(?<![\w$])' + re.escape(key) + r'\s*:\s*\{')
    m = pattern.search(block)
    if not m:
        return None
    brace_idx = block.rfind('{', 0, m.end())
    return extract_block(block, brace_idx)


def validate_file(fname):
    path = os.path.join(ROOT, fname, "index.ts")
    result = {"function": fname, "path": path, "exists": os.path.isfile(path)}
    if not result["exists"]:
        result["status"] = "FICHEIRO_NAO_ENCONTRADO"
        return result

    with open(path, "r", encoding="utf-8") as f:
        src = f.read()

    result["uses_fcm_v1_url"] = "fcm.googleapis.com/v1/projects/" in src
    result["uses_firebase_admin_sdk"] = ("firebase-admin" in src) or ("npm:firebase-admin" in src)
    result["has_getFirebaseAccessToken"] = "getFirebaseAccessToken" in src or "getAccessToken" in src
    result["has_validate_only_field"] = bool(re.search(r'validate_only\s*:\s*true', src))

    # Find "message:" object nested inside the outer send payload, e.g.
    #   const message = { message: { token:..., notification:{...}, android:{...}, apns:{...} } }
    outer = find_object_after(src, "const message = ") or find_object_after(src, "const message=")
    inner_message = None
    if outer:
        inner_message = sub_block(outer, "message")
    if inner_message is None and outer is not None:
        # some files might build message directly without nested "message:" wrapper name collision
        inner_message = outer

    errors = []
    warnings = []

    if inner_message is None:
        errors.append("Nao foi possivel extrair estaticamente o objecto da mensagem FCM (payload complexo/condicional) — necessita leitura manual.")
        result["message_keys"] = []
    else:
        mkeys = top_level_keys(inner_message)
        result["message_keys"] = mkeys
        unknown = [k for k in mkeys if k not in MESSAGE_KEYS]
        if unknown:
            errors.append(f"Campo(s) desconhecido(s) no nivel Message: {unknown}")

        notif = sub_block(inner_message, "notification")
        if notif:
            nk = top_level_keys(notif)
            bad = [k for k in nk if k not in NOTIFICATION_KEYS]
            if bad:
                errors.append(f"Campo(s) desconhecido(s) em notification{{}}: {bad}")

        android = sub_block(inner_message, "android")
        if android:
            ak = top_level_keys(android)
            bad = [k for k in ak if k not in ANDROID_KEYS]
            if bad:
                errors.append(f"Campo(s) desconhecido(s) em android{{}}: {bad}")
            android_notif = sub_block(android, "notification")
            if android_notif:
                ank = top_level_keys(android_notif)
                bad2 = [k for k in ank if k not in ANDROID_NOTIF_KEYS]
                if bad2:
                    errors.append(f"Campo(s) desconhecido(s) em android.notification{{}}: {bad2}")
                # check enum-ish values when literal present
                npm = re.search(r"notification_priority\s*:\s*['\"]([A-Z_]+)['\"]", android_notif)
                if npm and npm.group(1) not in NOTIF_PRIORITY_VALUES:
                    errors.append(f"android.notification.notification_priority invalido: {npm.group(1)}")
                vis = re.search(r"visibility\s*:\s*['\"]([A-Z_]+)['\"]", android_notif)
                if vis and vis.group(1) not in VISIBILITY_VALUES:
                    errors.append(f"android.notification.visibility invalido: {vis.group(1)}")
            pr = re.search(r"priority\s*:\s*['\"]([a-zA-Z_]+)['\"]", android)
            if pr and pr.group(1) not in ANDROID_PRIORITY_VALUES:
                warnings.append(f"android.priority com valor pouco comum: {pr.group(1)}")

        apns = sub_block(inner_message, "apns")
        if apns:
            apk = top_level_keys(apns)
            bad = [k for k in apk if k not in APNS_KEYS]
            if bad:
                errors.append(f"Campo(s) desconhecido(s) em apns{{}}: {bad}")
            payload = sub_block(apns, "payload")
            if payload:
                aps = sub_block(payload, "aps")
                if aps:
                    apsk = top_level_keys(aps)
                    bad3 = [k for k in apsk if k not in APS_KEYS]
                    if bad3:
                        errors.append(f"Campo(s) desconhecido(s) em apns.payload.aps{{}}: {bad3}")

        webpush = sub_block(inner_message, "webpush")
        if webpush:
            wk = top_level_keys(webpush)
            bad = [k for k in wk if k not in WEBPUSH_KEYS]
            if bad:
                errors.append(f"Campo(s) desconhecido(s) em webpush{{}}: {bad}")

    result["errors"] = errors
    result["warnings"] = warnings
    result["status"] = "OK_ESTRUTURA_VALIDA" if not errors else "ERRO_ESTRUTURA"
    return result


def main():
    results = [validate_file(f) for f in FUNCS]
    print(json.dumps(results, indent=2, ensure_ascii=False))
    ok = sum(1 for r in results if r.get("status") == "OK_ESTRUTURA_VALIDA")
    err = sum(1 for r in results if r.get("status") == "ERRO_ESTRUTURA")
    missing = sum(1 for r in results if r.get("status") == "FICHEIRO_NAO_ENCONTRADO")
    print(f"\n=== RESUMO: {ok} OK / {err} ERRO / {missing} EM FALTA / {len(results)} TOTAL ===", file=sys.stderr)


if __name__ == "__main__":
    main()
