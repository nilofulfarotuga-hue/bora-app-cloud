# CONTINUAR — missão 03/10 à noite (o que ficou por fazer)

Relatório: `.claude/.ai/reports/OPUS-2026-10-03-noite-6-blocos.md`. Código no ar a partir de `b2521671`.

## 1. Gmail do caça-clientes — ANTES DE 10/10 (precisa da extensão do Chrome ligada)
1. Chrome do perfil Bora (deviceId `d9e862e0-a5ea-486f-b054-f333ef51b46a`) → Google Cloud, projeto
   "Default Gemini Project" → Google Auth Platform → **Branding**: página inicial `https://boraguarda.com/`,
   política `https://boraguarda.com/privacidade` (ambas 200 a 03/10), email de suporte boraappbora@gmail.com.
2. **Audience → "Publicar app"** (passa a "Em produção"; app não verificada serve até 100 contas).
3. Só DEPOIS, para o refresh token já não caducar:
   `python .claude/.ai/provas/caca-clientes-2026-10-03/pc/autorizar_gmail.py 21600` e
   `python .claude/.ai/provas/caca-clientes-2026-10-03/pc/depois_do_permitir.py`. Avisa o Danilo pelo
   Telegram numa linha: "carrega Permitir".
4. Prova: linha `e2e_log` com fluxo `caca-clientes` e passo `c5-ligar`; email de teste em boraappbora@gmail.com,
   assinado "Bora App — Guarda".

## 2. Prova no emulador da troca de modo (Bloco 4.3)
Conta de teste com limpeza + cliente (pedir ao Danilo a autorização para uma conta de teste, ou usar
uma demo que já tenha esses papéis): limpeza → "Mudar de modo" → Cliente → Perfil → "Mudar de modo" →
Limpeza; fechar a app e reabrir; não pode ficar trancada.

## 3. Medição de frames dos mapas (Bloco 5d)
Precisa de uma corrida/entrega de teste com IDs sintéticos blindados (ver memória "teste em produção
oferece a gente real"). `flutter run --profile` + DevTools, GPX de 2 rotas na Guarda (uma certa e uma
com desvio), antes/depois. Ainda por fazer: `loadCurrent` do `TvdeDriverStore` notificar só quando algo mudou.

## 4. Mesmo defeito do Favor (Bloco 3c)
`send_package_form_screen.dart` e `carry_groceries_form_screen.dart` não esperam pelo resultado do
pagamento; aplicar o mesmo que no `errand_form_screen.dart` (trava + `popUntil` + "Os meus pedidos").
