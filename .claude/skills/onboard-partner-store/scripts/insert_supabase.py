"""Orquestrador do onboarding de LOJA. DRY-RUN default; --commit aplica.

Mesmo fluxo que onboard-partner-restaurant, mas register-partner com category='store'
e produtos com coluna 'unidade' (un/kg/lt). Reutiliza _partner_jwt do restaurant.

Uso: python insert_supabase.py --dir ".claude/.ai/onboard/worten-guarda" [--commit]
"""
from __future__ import annotations

import argparse
import csv
import importlib.util
import subprocess
import sys
from pathlib import Path

import yaml  # type: ignore

from _shared import Ctx, log, read_pipeline_json, write_pipeline_json
import validate_info

SCRIPTS = Path(__file__).resolve().parent
_REST = SCRIPTS.parents[1] / "onboard-partner-restaurant" / "scripts"
_spec = importlib.util.spec_from_file_location("rest_insert", _REST / "insert_supabase.py")
_ri = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_ri)  # type: ignore  # reutiliza _partner_jwt


def _run_step(script: str, onboard_dir: Path) -> None:
    res = subprocess.run([sys.executable, str(SCRIPTS / script), "--dir", str(onboard_dir)])
    if res.returncode != 0:
        log(f"Passo falhou: {script}", "ERROR")
        sys.exit(res.returncode)


def _build_register_body(r: dict) -> dict:
    return {
        "restaurantName": r["name"], "address": r["address"], "email": r["email"],
        "phone": str(r.get("phone", "")), "cuisineType": "", "category": "store",
        "lat": r.get("lat"), "lng": r.get("lng"),
        "nif": str(r["nif"]) if r.get("nif") else None,
        "iban": str(r["iban"]).upper().replace(" ", "") if r.get("iban") else None,
        "ownerDocUrl": r.get("owner_doc_url") or None,
    }


def _dry_run_report(onboard_dir: Path, r: dict, state: dict) -> None:
    cats, descs = state.get("categories", {}), state.get("descriptions", {})
    lines = [f"# Preview onboarding LOJA — {r['name']}", "",
             f"- categoria: store (is_partner=true) · morada: {r['address']}",
             f"- lat/lng: {r.get('lat')},{r.get('lng')} · NIF {r.get('nif','-')} · IBAN {r.get('iban','-')}",
             f"- payload register-partner: `{_build_register_body(r)}`", "", "## Produtos"]
    for name in cats:
        lines.append(f"- **{name}** [{cats[name]}] — {descs.get(name,'')}")
    lines += ["", "_Dry-run: nada escrito em Supabase. Reveja e use --commit._"]
    (onboard_dir / "_preview" / "relatorio.md").write_text("\n".join(lines), encoding="utf-8")
    log(f"Relatório dry-run: {onboard_dir/'_preview'/'relatorio.md'}")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", required=True)
    ap.add_argument("--commit", action="store_true")
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

    for step in ("geocode.py", "process_images.py", "generate_descriptions.py", "categorize_products.py"):
        _run_step(step, onboard_dir)

    data = yaml.safe_load((onboard_dir / "info.yaml").read_text(encoding="utf-8")) or {}
    r = data.get("restaurant", data.get("store", data))
    state = read_pipeline_json(onboard_dir)

    if not args.commit:
        _dry_run_report(onboard_dir, r, state)
        log("DRY-RUN concluído. Use --commit para aplicar.")
        return 0

    if not (ctx.supabase_url and ctx.service_role_key and ctx.anon_key):
        log("Faltam SUPABASE_URL / SERVICE_ROLE_KEY / ANON_KEY no ambiente.", "ERROR")
        return 1

    restaurant_id = None
    try:
        jwt = _ri._partner_jwt(ctx, r["email"])
        resp = ctx.invoke_register_partner(_build_register_body(r), jwt)
        restaurant_id = resp["restaurant_id"]
        log(f"register-partner OK → {restaurant_id} (store, pending)")

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
                    "description": descs.get(name, ""), "price": price,
                    "category": cats.get(name, "outros"),
                    "unit": (row.get("unidade") or "un").strip() or "un",
                    "is_available": True, "source": "onboard-partner-store",
                })
        if rows:
            pr = ctx.rest("POST", "products", jwt, rows)
            if pr.status_code >= 300:
                raise RuntimeError(f"INSERT produtos falhou: {pr.status_code} {pr.text[:200]}")
            log(f"{len(rows)} produto(s) inseridos.")

        state["committed"] = {"restaurant_id": restaurant_id, "products": len(rows)}
        write_pipeline_json(onboard_dir, state)
        log(f"✅ Onboarding LOJA COMPLETO. restaurant_id={restaurant_id} (pending).")
        return 0
    except Exception as e:  # noqa: BLE001
        log(f"Erro no commit: {e} — rollback…", "ERROR")
        if restaurant_id:
            try:
                svc = ctx.service_role_key
                ctx.rest("DELETE", f"products?restaurant_id=eq.{restaurant_id}", svc)
                ctx.rest("DELETE", f"restaurants?id=eq.{restaurant_id}", svc)
                log(f"Rollback OK ({restaurant_id} removido).")
            except Exception as re:  # noqa: BLE001
                log(f"⚠️ Rollback falhou: {re}. Remover manualmente {restaurant_id}.", "ERROR")
        return 1


if __name__ == "__main__":
    sys.exit(main())
