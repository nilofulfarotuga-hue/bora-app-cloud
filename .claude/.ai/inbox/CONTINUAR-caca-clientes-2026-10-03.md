# CONTINUAR — caca-clientes-2026-10-03 (estado às 11h15 de 03/10, sábado)

Relatório: `.claude/.ai/reports/FABLE-2026-10-03-caca-clientes.md`.

## À espera de um clique
Página do Google aberta no Chrome do perfil Bora (Continuar → Permitir). Dois scripts à escuta no PC, em
`.claude/.ai/provas/caca-clientes-2026-10-03/pc/`:
- `autorizar_gmail.py` (até às 16h54) → grava `GMAIL_BORA_*` em `/opt/data/.env` da VPS;
- `depois_do_permitir.py` → teste, resposta, leitura de volta; se 2 mensagens, `carteiro_ligar` + Telegram.

## Como saber se já aconteceu
```sql
select passo, estado, left(detalhe, 200) from e2e_log where fluxo = 'caca-clientes' and passo = 'c5-ligar';
select value from platform_settings where key = 'caca_clientes_enabled';
```
Sem linha `c5-ligar`: não aconteceu. Relançar (PC ligado, perfil Bora):
`python autorizar_gmail.py 21600` e `python depois_do_permitir.py`, e avisar o Danilo pelo Telegram.

## Depois de ligado
1. Segunda 05/10, 09h40: primeira onda (Herdade do Mondego, Quinta do Rio Noémi, Hotel Santos, Mira Serra,
   Pensão Aliança). Conferir `prospect_propostas.estado = 'enviada'` (5 linhas) e `/var/log/carteiro-caca.log`.
2. **Antes de 10/10:** preencher o branding da app OAuth "Bora Carteiro" (página inicial + política de
   privacidade) e carregar em "Publicar app"; depois repetir o Permitir. Em modo de teste o token caduca em 7 dias.
3. Varredura de Covilhã e Seia: `python varrer_osm.py --so "Covilhã,Seia"` (o Overpass público falhou a 03/10),
   depois `python cacar_contactos.py`, `python pecas.py`, deploy do bora-site, e `carteiro_caca.py redigir` na VPS.
4. Texto de convite para serviços (cabeleireiros): o molde de parceiro fala de entregas. Christinnne está em pausa.
5. Captura do ecrã admin (precisa de sessão de admin na web app).
6. Canal para os 121 sem email: Instagram/Facebook (9 têm rede social) ou visita.
