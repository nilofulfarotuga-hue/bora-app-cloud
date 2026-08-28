# -*- coding: utf-8 -*-
"""Modelos de email do Supabase Auth, em PT-PT e com a marca Bora.

Porque existe este ficheiro: os modelos vivem no painel do Supabase, fora do
git. Se ficarem só lá, ninguém sabe o que lá está nem consegue repor. Aqui
ficam versionados, e este script volta a aplicá-los quando for preciso.

Correr:  python .claude/.ai/scripts/modelos-email-supabase.py
Requer:  .supabase-token.env com SUPABASE_ACCESS_TOKEN
"""
import io, json, os, urllib.request

REF = "ojykpzwqrtusfeakzrna"
LOGO = "https://boraguarda.com/assets/img/bora_logo.png"
VERDE = "#16A34A"
LARANJA = "#F97316"

MOLDURA = """<!doctype html>
<html lang="pt-PT">
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"></head>
<body style="margin:0;padding:0;background:#F5F5F4;">
<table role="presentation" width="100%%" cellpadding="0" cellspacing="0" style="background:#F5F5F4;padding:32px 16px;">
<tr><td align="center">
  <table role="presentation" width="100%%" cellpadding="0" cellspacing="0" style="max-width:520px;background:#ffffff;border-radius:16px;overflow:hidden;box-shadow:0 2px 12px rgba(0,0,0,.06);font-family:Inter,-apple-system,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;">
    <tr><td style="padding:28px 32px 8px;text-align:center;">
      <img src="%(logo)s" alt="Bora" width="132" style="display:block;margin:0 auto;max-width:132px;height:auto;">
    </td></tr>
    <tr><td style="padding:8px 32px 4px;">
      <h1 style="margin:0;font-size:22px;line-height:1.25;color:#1C1917;font-weight:700;">%(titulo)s</h1>
    </td></tr>
    <tr><td style="padding:12px 32px 0;">
      %(corpo)s
    </td></tr>
    <tr><td style="padding:24px 32px 8px;" align="center">
      <a href="{{ .ConfirmationURL }}" style="display:inline-block;background:%(verde)s;color:#ffffff;text-decoration:none;font-weight:700;font-size:16px;padding:14px 28px;border-radius:999px;">%(botao)s</a>
    </td></tr>
    <tr><td style="padding:8px 32px 0;">
      <p style="margin:0;font-size:13px;line-height:1.6;color:#78716C;">
        Se o botão não funcionar, copie este endereço para o navegador:<br>
        <span style="word-break:break-all;color:%(verde)s;">{{ .ConfirmationURL }}</span>
      </p>
    </td></tr>
    <tr><td style="padding:20px 32px 0;">
      <p style="margin:0;font-size:13px;line-height:1.6;color:#78716C;">%(rodape)s</p>
    </td></tr>
    <tr><td style="padding:24px 32px 28px;border-top:1px solid #E7E5E4;margin-top:16px;">
      <p style="margin:16px 0 0;font-size:12px;line-height:1.6;color:#A8A29E;">
        Bora — entregas, viagens e reservas na Guarda.<br>
        <a href="https://boraguarda.com" style="color:%(laranja)s;text-decoration:none;">boraguarda.com</a>
      </p>
    </td></tr>
  </table>
</td></tr>
</table>
</body></html>
"""

P = 'style="margin:0 0 12px;font-size:15px;line-height:1.65;color:#44403C;"'

MODELOS = {
    "recovery": dict(
        assunto="Definir uma palavra-passe nova — Bora",
        titulo="Esqueceu-se da palavra-passe?",
        corpo=(
            '<p %s>Recebemos um pedido para definir uma palavra-passe nova na '
            'sua conta Bora. Carregue no botão abaixo para escolher uma.</p>' % P),
        botao="Definir palavra-passe nova",
        rodape="A ligação é válida durante uma hora e só pode ser usada uma vez. "
               "Se não foi você que pediu, ignore este email — a sua palavra-passe "
               "actual continua a funcionar e nada muda.",
    ),
    "confirmation": dict(
        assunto="Confirme o seu email — Bora",
        titulo="Bem-vindo à Bora",
        corpo=(
            '<p %s>Falta um passo para a sua conta ficar pronta: confirmar que '
            'este email é mesmo seu.</p>' % P),
        botao="Confirmar o meu email",
        rodape="Se não foi você que criou esta conta, ignore este email e nada acontece.",
    ),
    "email_change": dict(
        assunto="Confirme o email novo — Bora",
        titulo="Mudança de email",
        corpo=(
            '<p %s>Pediu para passar a usar este endereço na sua conta Bora. '
            'Confirme para a mudança ficar activa.</p>' % P),
        botao="Confirmar o email novo",
        rodape="Enquanto não confirmar, a conta continua a usar o email anterior. "
               "Se não foi você que pediu, ignore este email.",
    ),
    "magic_link": dict(
        assunto="Entrar na Bora",
        titulo="A sua ligação de entrada",
        corpo='<p %s>Carregue no botão para entrar na sua conta Bora.</p>' % P,
        botao="Entrar na Bora",
        rodape="A ligação é válida durante uma hora e só pode ser usada uma vez.",
    ),
    "invite": dict(
        assunto="Foi convidado para a Bora",
        titulo="Tem um convite",
        corpo='<p %s>Foi convidado para a Bora. Carregue para criar a sua conta.</p>' % P,
        botao="Aceitar o convite",
        rodape="Se não estava à espera deste convite, ignore este email.",
    ),
}


def monta(m):
    return MOLDURA % dict(logo=LOGO, verde=VERDE, laranja=LARANJA,
                          titulo=m["titulo"], corpo=m["corpo"],
                          botao=m["botao"], rodape=m["rodape"])


def main():
    aqui = os.path.dirname(os.path.abspath(__file__))
    raiz = os.path.abspath(os.path.join(aqui, "..", "..", ".."))
    env = os.path.join(raiz, ".supabase-token.env")
    if not os.path.exists(env):
        env = r"C:\Users\danil\Desktop\projetosflutter\bora_app\.supabase-token.env"
    token = ""
    for linha in io.open(env, encoding="utf-8"):
        if linha.startswith("SUPABASE_ACCESS_TOKEN="):
            token = linha.split("=", 1)[1].strip().strip('"')
    if not token:
        raise SystemExit("falta o SUPABASE_ACCESS_TOKEN")

    # Um campo por pedido: mandar os dez de uma vez dá 403, o corpo fica
    # grande demais para a API de gestão. Um a um passa sempre.
    def poe(campo, valor):
        pedido = urllib.request.Request(
            "https://api.supabase.com/v1/projects/%s/config/auth" % REF,
            data=json.dumps({campo: valor}).encode("utf-8"),
            headers={"Authorization": "Bearer " + token,
                     "Content-Type": "application/json",
                     # Sem User-Agent proprio o filtro da API devolve 403 ao
                     # Python-urllib. Com curl passava, com urllib nao — foi
                     # isto, nao o tamanho nem o HTML.
                     "User-Agent": "bora-scripts/1.0"},
            method="PATCH")
        with urllib.request.urlopen(pedido, timeout=60) as r:
            return json.loads(r.read().decode("utf-8"))

    d = {}
    for chave, m in MODELOS.items():
        html = monta(m)
        poe("mailer_subjects_" + chave, m["assunto"])
        d = poe("mailer_templates_%s_content" % chave, html)
        print("  %-14s enviado — %d chars | assunto: %s"
              % (chave, len(html), m["assunto"]))

    print()
    print("  o que ficou GRAVADO no servidor:")
    for chave in MODELOS:
        v = d.get("mailer_templates_%s_content" % chave) or ""
        marca = "com a marca Bora" if "boraguarda.com" in v else ">>> SEM a marca <<<"
        print("   %-14s %5d chars | %-18s | assunto: %s"
              % (chave, len(v), marca, d.get("mailer_subjects_" + chave)))


if __name__ == "__main__":
    main()
