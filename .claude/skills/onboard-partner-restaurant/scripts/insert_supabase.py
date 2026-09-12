"""Orquestrador do onboarding. DRY-RUN por defeito; --commit aplica em Supabase.

Pipeline:
  1. require_knowledge() — lê bora-knowledge (falha cedo se ausente)
  2. validate_info.validate()  3. geocode  4. process_images
  5. generate_descriptions     6. categorize_products
  7. (dry-run) escreve _preview/relatorio.md e PÁRA se sem --commit
  8. --commit: autentica como parceiro → register-partner → upload assets → INSERT produtos
  9. rollback se qualquer passo do commit falhar

Uso:
    python insert_supabase.py --dir ".claude/.ai/onboard/belmonte-grill" [--commit]
"""
from __future__ import annotations

import argparse
import csv
import subprocess
import sys
from pathlib import Path

import yaml  # type: ignore

from _shared import Ctx, log, read_pipeline_json, write_pipeline_json
import validate_info

SCRIPTS = Path(__file__).resolve().parent


def _run_step(script: str, onboard_dir: Path) -> None:
    res = subprocess.run([sys.executable, str(SCRIPTS / script), "--dir", str(onboard_dir)])
    if res.returncode != 0:
        log(f"Passo falhou: {script}", "ERROR")
        sys.exit(res.returncode)


def _build_register_body(r: dict) -> dict:
    return {
        "restaurantName": r["name"],
        "address": r["address"],
        "email": r["email"],
        "phone": str(r.get("phone", "")),
        "cuisineType": r.get("cuisine_type", ""),
        "category": "restaurant",
        "lat": r.get("lat"), "lng": r.get("lng"),
        "nif": str(r["nif"]) if r.get("nif") else None,
        "iban": str(r["iban"]).upper().replace(" ", "") if r.get("iban") else None,
        "ownerDocUrl": r.get("owner_doc_url") or None,
    }


def _partner_jwt(ctx: Ctx, email: str) -> str:
    """Cria/obtém o auth user do parceiro (service role) e devolve um access token.

    Estratégia: admin cria utilizador (idempotente) com role bora_role=partner e
    password temporária; depois sign-in (password grant) → access_token.
    """
    import requests
    pw = "Bora!" + email.split("@")[0][:8] + "2026"  # determinística p/ retomar
    # admin create (ignora erro se já existir)
    requests.post(f"{ctx.supabase_url}/auth/v1/admin/users", timeout=30,
                  headers={"Authorization": f"Bearer {ctx.service_role_key}",
                           "apikey": ctx.service_role_key, "Content-Type": "application/json"},
                  json={"email": email, "password": pw, "email_confirm": True,
                        "user_metadata": {"bora_role": "partner"}})
    tok = requests.post(f"{ctx.supabase_url}/auth/v1/token?grant_type=password", timeout=30,
                        headers={"apikey": ctx.anon_key, "Content-Type": "application/json"},
                        json={"email": email, "password": pw})
    tok.raise_for_status()
    return tok.json()["access_token"]


def _dry_run_report(onboard_dir: Path, r: dict, state: dict) -> None:
    lines = [f"# Preview onboarding — {r['name']}", "", "## Restaurante",
             f"- categoria: restaurant (is_partner=true)",
             f"- morada: {r['address']}", f"- lat/lng: {r.get('lat')},{r.get('lng')}",
             f"- NIF: {r.get('nif','-')} · IBAN: {r.get('iban','-')}",
             f"- payload register-partner: `{_build_register_body(r)}`", "",
             "## Produtos"]
    cats, descs = state.get("categories", {}), state.get("descriptions", {})
    for name in cats:
        lines.append(f"- **{name}** [{cats[name]}] — {descs.get(name,'')}")
    lines += ["", "## Imagens processadas",
              f"- logo/capa/produtos em `_preview/images/` (3 tamanhos cada)",
              "", "_Dry-run: nada foi escrito em Supabase. Reveja e use --commit._"]
    (onboard_dir / "_preview" / "relatorio.md").write_text("\n".join(lines), encoding="utf-8")
    log(f"Relatório dry-run: {onboard_dir/'_preview'/'relatorio.md'}")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", required=True)
    ap.add_argument("--commit", action="store_true", help="aplica em Supabase (default: dry-run)")
    args = ap.parse_args()
    onboard_dir = Path(args.dir)

    ctx = Ctx.load(commit=args.commit)
    ctx.require_knowledge()

    errors = validate_info.validate(onboard_dir)
    if errors:
        log(f"{len(errors)} erro(s); corrija antes de continuar.", "ERROR")
        for e in errors:
            log(f"  - {e}", "ERROR")
        return 1

    for step in ("geocode.py", "process_images.py",
                 "generate_descriptions.py", "categorize_products.py"):
        _run_step(step, onboard_dir)

    data = yaml.safe_load((onboard_dir / "info.yaml").read_text(encoding="utf-8")) or {}
    r = data.get("restaurant", data)
    state = read_pipeline_json(onboard_dir)

    if not args.commit:
        _dry_run_report(onboard_dir, r, state)
        log("DRY-RUN concluído. Use --commit para aplicar.")
        return 0

    # ---------------- COMMIT (transacional) ----------------
    if not (ctx.supabase_url and ctx.service_role_key and ctx.anon_key):
        log("Faltam SUPABASE_URL / SERVICE_ROLE_KEY / ANON_KEY no ambiente.", "ERROR")
        return 1

    restaurant_id = None
    try:
        jwt = _partner_jwt(ctx, r["email"])
        resp = ctx.invoke_register_partner(_build_register_body(r), jwt)
        restaurant_id = resp["restaurant_id"]
        log(f"register-partner OK → {restaurant_id} (pending)")

        # assets logo (hero=capa)
        imgs = state.get("images", {})
        photo_url = hero_url = None
        for asset, kind, target in (("logo", "logo", "photo_url"), ("capa", "hero", "hero_image_url")):
            src = imgs.get(asset, {}).get("card") or imgs.get(asset, {}).get("hero")
            if src:
                up = ctx.invoke_upload_asset(restaurant_id, kind, Path(src), "image/webp", jwt)
                if target == "photo_url":
                    photo_url = up["public_url"]
                else:
                    hero_url = up["public_url"]
        if photo_url or hero_url:
            patch = {k: v for k, v in (("photo_url", photo_url), ("hero_image_url", hero_url)) if v}
            ctx.rest("PATCH", f"restaurants?id=eq.{restaurant_id}", jwt, patch)
            log("photo_url/hero_image_url atualizados.")

        # produtos
        cats, descs = state.get("categories", {}), state.get("descriptions", {})
        rows = []
        with (onboard_dir / "produtos.csv").open(encoding="utf-8") as f:
            for row in csv.DictReader(f):
                name = (row.get("nome") or "").strip()
                if not name:
                    continue
                price = float(str(row.get("preço", row.get("preco", "0"))).replace(",", "."))
                rows.append({
                    "restaurant_id": restaurant_id, "name": name,
                    "description": descs.get(name, ""),
                    "price": price, "category": cats.get(name, "principal"),
                    "is_available": True, "source": "onboard-partner-restaurant",
                })
        if rows:
            pr = ctx.rest("POST", "products", jwt, rows)
            if pr.status_code >= 300:
                raise RuntimeError(f"INSERT produtos falhou: {pr.status_code} {pr.text[:200]}")
            log(f"{len(rows)} produto(s) inseridos.")

        state["committed"] = {"restaurant_id": restaurant_id, "products": len(rows)}
        write_pipeline_json(onboard_dir, state)
        log(f"✅ Onboarding COMPLETO. restaurant_id={restaurant_id} (approval_status=pending).")
        return 0

    except Exception as e:  # noqa: BLE001
        log(f"Erro no commit: {e} — a fazer rollback…", "ERROR")
        if restaurant_id:
            try:
                svc = ctx.service_role_key
                ctx.rest("DELETE", f"products?restaurant_id=eq.{restaurant_id}", svc)
                ctx.rest("DELETE", f"restaurants?id=eq.{restaurant_id}", svc)
                log(f"Rollback OK (restaurante {restaurant_id} removido).")
            except Exception as re:  # noqa: BLE001
                log(f"⚠️ Rollback falhou: {re}. Remover manualmente {restaurant_id}.", "ERROR")
        log("Para retomar: corrija a causa e re-execute com --commit.", "INFO")
        return 1


if __name__ == "__main__":
    sys.exit(main())
