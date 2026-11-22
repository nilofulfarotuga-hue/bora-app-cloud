#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
stripe_ler.py — o Hermes LE a Stripe, e so le: saldo, pagamentos e reembolsos
(missao hermes-diretor-2026-11-20, B4.4).

A chave e restrita e so de leitura (Balance, Balance Transaction Sources, Charges and Refunds, Payment
Intents). Vive num ficheiro que so o Hermes le (pasta cofre, modo 600) e nunca se mostra. Mexer em dinheiro
continua a ser so pelas funcoes do Bora, com o autorizo do Danilo: esta chave nao consegue cobrar, devolver
nem mudar nada.

  stripe_ler.py saldo
  stripe_ler.py pagamentos [N]       os ultimos N pagamentos (10 por omissao, 50 no maximo)
  stripe_ler.py reembolsos [N]       os ultimos N reembolsos
  stripe_ler.py pagamento <pi_...>   um pagamento pelo id

Nao mostra e-mails, nomes nem cartoes: so id, valor, estado, data e o numero do pedido do Bora, se vier.
"""
import json
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

COFRE = "/opt/data/cofre/stripe-leitura.chave"
API = "https://api.stripe.com/v1/"


def pedir(caminho, **params):
    try:
        segredo = open(COFRE, encoding="utf-8").read().strip()
    except Exception:
        print("NAO CONSEGUI LER: a chave de leitura da Stripe nao esta no cofre")
        sys.exit(2)
    url = API + caminho + ("?" + urllib.parse.urlencode(params) if params else "")
    req = urllib.request.Request(url, headers={"Authorization": "Bearer " + segredo})
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return json.loads(r.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        try:
            erro = json.loads(e.read().decode("utf-8")).get("error", {})
        except Exception:
            erro = {}
        print("A STRIPE RECUSOU (HTTP %d): %s" % (e.code, (erro.get("message") or erro.get("type") or "sem detalhe")[:200]))
        sys.exit(1)
    except Exception as e:  # noqa: BLE001
        print("NAO CONSEGUI LER a Stripe: %s" % str(e)[:120])
        sys.exit(1)


def euros(valor, moeda):
    return "%.2f %s" % ((valor or 0) / 100.0, (moeda or "").upper())


def quando(ts):
    return time.strftime("%d/%m %H:%M UTC", time.gmtime(ts or 0))


def n_pedido(arg, omissao=10):
    try:
        return max(1, min(50, int(arg)))
    except Exception:
        return omissao


def main():
    a = sys.argv[1:]
    if not a:
        print(__doc__)
        return 2
    if a[0] == "saldo":
        s = pedir("balance")
        for nome, chave in (("disponivel", "available"), ("a caminho", "pending")):
            for x in s.get(chave, []):
                print("%s: %s" % (nome, euros(x.get("amount"), x.get("currency"))))
        return 0
    if a[0] == "pagamentos":
        d = pedir("payment_intents", limit=n_pedido(a[1] if len(a) > 1 else None))
        for p in d.get("data", []):
            m = p.get("metadata") or {}
            print("%s | %s | %s | %s | pedido: %s" % (quando(p.get("created")), euros(p.get("amount"), p.get("currency")),
                                                    p.get("status"), p.get("id"), m.get("order_id") or m.get("orderId") or "-"))
        print("(%d pagamentos)" % len(d.get("data", [])))
        return 0
    if a[0] == "reembolsos":
        d = pedir("refunds", limit=n_pedido(a[1] if len(a) > 1 else None))
        for r in d.get("data", []):
            print("%s | %s | %s | %s | do pagamento %s | motivo: %s" % (
                quando(r.get("created")), euros(r.get("amount"), r.get("currency")), r.get("status"), r.get("id"),
                r.get("payment_intent") or "-", r.get("reason") or "-"))
        print("(%d reembolsos)" % len(d.get("data", [])))
        return 0
    if a[0] == "pagamento" and len(a) > 1 and a[1].startswith("pi_"):
        p = pedir("payment_intents/" + urllib.parse.quote(a[1], safe="_"))
        m = p.get("metadata") or {}
        print("%s | %s | %s | recebido: %s | pedido: %s" % (
            quando(p.get("created")), euros(p.get("amount"), p.get("currency")), p.get("status"),
            euros(p.get("amount_received"), p.get("currency")), m.get("order_id") or m.get("orderId") or "-"))
        return 0
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main())
