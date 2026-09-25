# -*- coding: utf-8 -*-
"""
TESTE PONTA-A-PONTA da Lavagem Auto — contra PRODUCAO.
Passa por RLS e JWT reais (nao usa service_role para as accoes de negocio),
exactamente como a app faria. Cada passo imprime a prova.
"""
import json, os, sys, urllib.request, urllib.error, time, datetime

URL = "https://ojykpzwqrtusfeakzrna.supabase.co"
B = r"C:\Users\danil\Desktop\projetosflutter\bora_app"

def envval(path, key):
    for line in open(path, encoding="utf-8", errors="replace"):
        line = line.strip()
        if line.startswith(key + "="):
            return line.split("=", 1)[1].strip().strip('"').strip("'")
    return None

ANON = envval(os.path.join(B, ".dart_defines"), "SUPABASE_ANON_KEY")
SRK  = envval(os.path.join(B, "backend", ".env"), "SUPABASE_SERVICE_ROLE_KEY")
assert ANON and SRK, "faltam chaves"

WASHER_EMAIL = "lava.leva@bora.app"
CLIENT_EMAIL = "teste.lavagem@bora.app"
PASSWORD     = os.environ.get("CARWASH_TEST_PASSWORD", "")
assert PASSWORD, "define CARWASH_TEST_PASSWORD antes de correr (ver relatorio da missao)"

def call(method, path, body=None, token=None, apikey=None, raw=False):
    data = None if body is None else json.dumps(body).encode()
    req = urllib.request.Request(URL + path, data=data, method=method)
    req.add_header("apikey", apikey or ANON)
    req.add_header("Authorization", "Bearer " + (token or apikey or ANON))
    req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=45) as r:
            t = r.read().decode()
            return r.status, (t if raw else (json.loads(t) if t else None))
    except urllib.error.HTTPError as e:
        t = e.read().decode()
        try: return e.code, json.loads(t)
        except Exception: return e.code, t

def rpc(fn, params, token):
    return call("POST", "/rest/v1/rpc/" + fn, params, token=token)

def admin_create_user(email):
    st, r = call("POST", "/auth/v1/admin/users", {
        "email": email, "password": PASSWORD, "email_confirm": True
    }, apikey=SRK)
    if st in (200, 201):
        return r["id"], "criado"
    # ja existe -> procurar
    st2, r2 = call("GET", "/auth/v1/admin/users?per_page=200", apikey=SRK)
    users = (r2 or {}).get("users", []) if isinstance(r2, dict) else []
    for u in users:
        if u.get("email") == email:
            call("PUT", "/auth/v1/admin/users/" + u["id"], {"password": PASSWORD}, apikey=SRK)
            return u["id"], "ja existia (password reposta)"
    raise SystemExit("nao consegui criar/achar %s -> %s %s" % (email, st, r))

def login(email):
    st, r = call("POST", "/auth/v1/token?grant_type=password",
                 {"email": email, "password": PASSWORD})
    if st != 200:
        raise SystemExit("login falhou %s: %s %s" % (email, st, r))
    return r["access_token"]

def sql_admin(select_path):
    """leitura directa com service_role, so para PROVAR o estado no servidor"""
    return call("GET", "/rest/v1/" + select_path, apikey=SRK)

OK, FAIL = [], []
def check(nome, cond, detalhe=""):
    (OK if cond else FAIL).append(nome)
    print(("  [OK]   " if cond else "  [FALHA]") + " " + nome + ("  " + str(detalhe) if detalhe else ""))

print("=" * 72)
print("TESTE E2E — LAVAGEM AUTO — producao —", datetime.datetime.now().strftime("%Y-%m-%d %H:%M"))
print("=" * 72)

# ── 1. contas ──────────────────────────────────────────────────────────────
print("\n1) CONTAS")
washer_uid, s1 = admin_create_user(WASHER_EMAIL)
client_uid, s2 = admin_create_user(CLIENT_EMAIL)
print("   lavador %s -> %s (%s)" % (WASHER_EMAIL, washer_uid, s1))
print("   cliente %s -> %s (%s)" % (CLIENT_EMAIL, client_uid, s2))

# perfil do lavador "Lava & Leva" (service_role: e cadastro, nao e accao de negocio)
st, r = sql_admin("washers?user_id=eq." + washer_uid + "&select=id")
if st == 200 and r:
    washer_id = r[0]["id"]
    call("PATCH", "/rest/v1/washers?id=eq." + washer_id, {
        "approval_status": "approved", "is_active": True, "is_banned": False
    }, apikey=SRK)
    print("   perfil Lava & Leva ja existia -> %s (reaprovado)" % washer_id)
else:
    st, r = call("POST", "/rest/v1/washers", {
        "user_id": washer_uid, "name": "Lava & Leva", "phone": "937501673",
        "email": WASHER_EMAIL, "base_lat": 40.5373, "base_lng": -7.2676,
        "base_address": "Guarda", "service_radius_km": 8,
        "approval_status": "approved", "is_active": True,
    }, apikey=SRK)
    st2, r2 = sql_admin("washers?user_id=eq." + washer_uid + "&select=id")
    washer_id = r2[0]["id"]
    print("   perfil Lava & Leva criado -> %s" % washer_id)

tok_w = login(WASHER_EMAIL)
tok_c = login(CLIENT_EMAIL)
check("os dois conseguem entrar (JWT emitido)", bool(tok_w and tok_c))

# ── 2. preco vem do servidor ───────────────────────────────────────────────
print("\n2) PRECO (fonte unica no servidor)")
st, q = rpc("carwash_quote", {"p_service_type": "full"}, tok_c)
print("   carwash_quote('full') ->", json.dumps(q))
check("lavagem completa = 20,00 EUR", q.get("total_cents") == 2000, q.get("total_cents"))
check("comissao Bora = 15% = 3,00 EUR", q.get("bora_fee_cents") == 300, q.get("bora_fee_cents"))
check("lavador recebe 17,00 EUR", q.get("washer_earnings_cents") == 1700, q.get("washer_earnings_cents"))

st, qi = rpc("carwash_quote", {"p_service_type": "interior"}, tok_c)
check("'so interior' esta DESLIGADO (recusa)", st != 200 or (isinstance(qi, dict) and qi.get("code")), str(qi)[:60])

# ── 3. portao antes do Stripe ──────────────────────────────────────────────
print("\n3) PORTAO ANTES DO STRIPE (licao 31/07)")
st, r = rpc("create_carwash_booking", {
    "p_service_type": "full", "p_plate": "XX-00-XX", "p_client_phone": "937501673",
    "p_when_mode": "now", "p_scheduled_at": None,
    "p_address_street": "Rua Teste", "p_address_city": "Guarda", "p_address_postal": "",
    "p_lat": 40.5373, "p_lng": -7.2676, "p_payment_method": "card",
}, tok_c)
check("cartao recusado ANTES de tocar no Stripe", st != 200 and "card_mbway_not_enabled" in str(r), str(r)[:70])

# fora da zona
st, r = rpc("create_carwash_booking", {
    "p_service_type": "full", "p_plate": "XX-00-XX", "p_client_phone": "937501673",
    "p_when_mode": "now", "p_scheduled_at": None,
    "p_address_street": "Lisboa", "p_address_city": "Lisboa", "p_address_postal": "",
    "p_lat": 38.7223, "p_lng": -9.1393, "p_payment_method": "cash",
}, tok_c)
check("morada fora do raio de 8 km e recusada", st != 200 and "out_of_service_area" in str(r), str(r)[:70])

# ── 4. pedido real EM DINHEIRO ─────────────────────────────────────────────
print("\n4) PEDIDO REAL (dinheiro)")
st, b = rpc("create_carwash_booking", {
    "p_service_type": "full", "p_plate": "AA-11-BB", "p_client_phone": "937501673",
    "p_when_mode": "now", "p_scheduled_at": None,
    "p_address_street": "Rua Alves Roçadas 12", "p_address_city": "Guarda",
    "p_address_postal": "6300-664", "p_lat": 40.5373, "p_lng": -7.2676,
    "p_payment_method": "cash", "p_car_make_model": "Renault Clio",
    "p_car_color": "Cinzento", "p_pickup_notes": "Garagem do predio, chave com o porteiro",
}, tok_c)
if st != 200:
    print("   ERRO ao criar:", st, b); sys.exit(1)
bid = b["id"]
print("   pedido criado ->", bid)
check("estado inicial = scheduled", b["status"] == "scheduled", b["status"])
check("total gravado = 2000 centimos", b["total_cents"] == 2000, b["total_cents"])
check("oferta foi para o Lava & Leva", b["offer_washer_id"] == washer_id, b["offer_washer_id"])
check("oferta tem prazo (10 min)", bool(b["offer_expires_at"]), b["offer_expires_at"])

# ── 5. o lavador VE a oferta (RLS pela chave user_id) ──────────────────────
print("\n5) O LAVADOR VE A OFERTA (licao Valdemir: chave = user_id)")
st, vis = call("GET", "/rest/v1/carwash_bookings?offer_washer_id=eq." + washer_id +
               "&status=eq.scheduled&select=id,plate", token=tok_w)
check("lavador ve o pedido na sua lista", any(x["id"] == bid for x in (vis or [])), vis)

# ── 6. aceitar + ETA ───────────────────────────────────────────────────────
print("\n6) ACEITAR + ETA")
st, acc = rpc("washer_accept_booking", {"p_booking_id": bid}, tok_w)
if st != 200: print("   ERRO:", st, acc); sys.exit(1)
check("estado = accepted", acc["status"] == "accepted", acc["status"])
check("lavador atribuido", acc["washer_id"] == washer_id)
check("ETA calculado e multiplo de 5", acc["eta_minutes"] and acc["eta_minutes"] % 5 == 0,
      str(acc["eta_minutes"]) + " min")
check("ETA >= buffer de 10 min", (acc["eta_minutes"] or 0) >= 10, acc["eta_minutes"])
print("   ETA prometido: %s min (chega ~%s)" % (acc["eta_minutes"], acc["eta_at"]))

# ── 7. as 4 fotos sao mesmo obrigatorias ───────────────────────────────────
print("\n7) AS 4 FOTOS SAO OBRIGATORIAS (validado no SERVIDOR)")
rpc("carwash_mark_on_the_way", {"p_booking_id": bid}, tok_w)
st, r = rpc("carwash_mark_picked_up", {"p_booking_id": bid, "p_photos": []}, tok_w)
check("recolha SEM fotos e recusada", st != 200 and "missing_photos" in str(r), str(r)[:80])

st, r = rpc("carwash_mark_picked_up", {"p_booking_id": bid, "p_photos": [
    {"angle": "frente", "url": bid + "/before/frente.jpg"},
    {"angle": "tras",   "url": bid + "/before/tras.jpg"},
]}, tok_w)
check("recolha com SO 2 fotos e recusada", st != 200 and "missing_photos" in str(r), str(r)[:80])

fotos = [{"angle": a, "url": "%s/before/%s.jpg" % (bid, a)}
         for a in ("frente", "tras", "esquerda", "direita")]
st, r = rpc("carwash_mark_picked_up", {"p_booking_id": bid, "p_photos": fotos}, tok_w)
check("recolha com as 4 fotos passa", st == 200 and r.get("status") == "picked_up", str(r)[:60])

# ── 8. resto do ciclo ──────────────────────────────────────────────────────
print("\n8) RESTO DO CICLO")
for fn, esperado in [("carwash_mark_started", "in_progress"),
                     ("carwash_mark_delivering", "delivering"),
                     ("carwash_mark_delivered", "delivered")]:
    st, r = rpc(fn, {"p_booking_id": bid}, tok_w)
    check("%s -> %s" % (fn.replace("carwash_mark_", ""), esperado),
          st == 200 and r.get("status") == esperado, str(r)[:60] if st != 200 else "")

# ── 9. cliente fecha + avalia ──────────────────────────────────────────────
print("\n9) CLIENTE CONFIRMA E AVALIA")
st, r = rpc("carwash_confirm_completion",
            {"p_booking_id": bid, "p_rating": 5, "p_comment": "teste"}, tok_c)
check("estado final = completed", st == 200 and r.get("status") == "completed", str(r)[:60])
check("pagamento em dinheiro fica cash_pending",
      r.get("payment_status") == "cash_pending", r.get("payment_status"))

# ── 10. PROVA FINAL POR SELECT NO SERVIDOR ─────────────────────────────────
print("\n10) PROVA POR SELECT NO SERVIDOR (nao pela palavra do executor)")
st, rows = sql_admin("carwash_bookings?id=eq." + bid +
    "&select=status,total_cents,washer_earnings_cents,bora_fee_cents,eta_minutes,"
    "rating,photos_before,accepted_at,picked_up_at,delivered_at,completed_at,payment_method")
row = rows[0]
print("   " + json.dumps({k: v for k, v in row.items() if k != "photos_before"}, ensure_ascii=False))
check("status no banco = completed", row["status"] == "completed")
check("total = 2000", row["total_cents"] == 2000)
check("lavador = 1700 (85%)", row["washer_earnings_cents"] == 1700)
check("Bora = 300 (15%)", row["bora_fee_cents"] == 300)
check("contas batem (1700+300=2000)",
      row["washer_earnings_cents"] + row["bora_fee_cents"] == row["total_cents"])
check("4 fotos gravadas", len(row["photos_before"]) == 4, len(row["photos_before"]))
check("carimbos do ciclo todos preenchidos",
      all(row[k] for k in ("accepted_at", "picked_up_at", "delivered_at", "completed_at")))
check("avaliacao gravada = 5", row["rating"] == 5, row["rating"])

st, w = sql_admin("washers?id=eq." + washer_id + "&select=washes_done,rating_avg,ratings_count")
print("   lavador:", json.dumps(w[0]))
check("contador de lavagens subiu", w[0]["washes_done"] >= 1, w[0]["washes_done"])

print("\n" + "=" * 72)
print("RESULTADO: %d passaram, %d falharam" % (len(OK), len(FAIL)))
if FAIL:
    print("FALHAS:", ", ".join(FAIL))
print("booking de teste:", bid)
print("washer_id:", washer_id, "| washer_uid:", washer_uid)
print("=" * 72)
