# Caça-clientes — relatório de 03/10/2026 (run_id `caca-clientes-2026-10-03`), com a continuação

Motor: Fable 5.1. Sessão aberta na pasta do BoraStudio e movida para `bora_app`.
Este ficheiro substitui a versão da manhã; a continuação (decisões 1 a 7 do Danilo) está na segunda metade.

## Acessos

- Painel: menu do admin → **Caça-clientes**. Publicado: `app_latest_version_code` = **640** (era 639).
- Interruptor: `platform_settings.caca_clientes_enabled` — **desligado** até o email de teste passar.
- Carteiro (VPS): `/opt/data/rotinas/carteiro_caca.py`, md5 igual ao do repo.
- Cron (VPS): 4 linhas `# caca-clientes-*`; cópia do crontab anterior em `/root/crontab.bak-caca-clientes-20261003`.
- Google Cloud (conta Bora, projeto "Default Gemini Project"): app OAuth **Bora Carteiro**, cliente "Desktop".
  O ficheiro do cliente está em `C:\BoraLocal\_segredos\avenca\gmail_bora_oauth_client.json` (fora do repo).
- Scripts do PC: `.claude/.ai/provas/caca-clientes-2026-10-03/pc/` (`cacar_contactos.py`, `varrer_osm.py`, `pecas.py`, `autorizar_gmail.py`).

## O que NÃO ficou feito (e porquê)

1. **Email de teste, ligar o carteiro e primeira onda: à espera do clique do Danilo.** A página do Google está
   aberta à frente desde as 10h54 ("A Google não validou esta app" → Continuar → Permitir). O script
   `autorizar_gmail.py` fica 6 horas à escuta (até às 16h54) e grava o token na VPS sozinho. Logo a seguir, o
   `depois_do_permitir.py` manda o email de teste, responde-lhe, lê a conversa de volta e, só se vierem 2
   mensagens, liga o interruptor e os bots `vendedor` (RPC `carteiro_ligar`, migração `20261003101512`) e avisa
   pelo Telegram. Se o teste falhar, não liga nada. Estado em `pc/depois_do_permitir.log` e no `e2e_log`
   (passo `c5-ligar`). Se o PC for desligado antes do clique, os dois scripts morrem e é preciso relançá-los.
2. **A primeira onda não pode ser hoje: 03/10 é sábado.** O carteiro só envia em dias úteis, das 09h30 às 11h30.
   Sai na segunda-feira, 05/10, às 09h40 — se o Permitir e o teste estiverem feitos.
3. **Token do Gmail com prazo de 7 dias.** A app OAuth ficou em modo de teste (o Google só deixa publicar depois
   de preencher a página de branding: página inicial e política de privacidade). Em modo de teste o token caduca
   ao fim de 7 dias. Falta preencher o branding e carregar em "Publicar app".
4. **Meta de 60% com email verificado: falhada. 15 em 136 ativos (11%).** A lista cresceu com cafés e restaurantes
   sem site, e o email desses não está em lado nenhum público.
5. **Varredura: só Guarda e Gouveia.** Covilhã e Seia não responderam (o servidor público do OpenStreetMap deu
   tempo esgotado seis vezes). Imobiliárias, advogados, ginásios e oficinas: zero encontrados nos dois concelhos
   que responderam.
6. **Pontuação sem as avaliações do Google** (os 15 pontos de ">50 avaliações" pedem a Places paga).
7. **Captura do ecrã admin: não feita.** A web app pede login e eu não escrevo palavras-passe.
8. **Peça "a tua loja no Bora" é uma página, não uma loja em rascunho na base** (`restaurants` com
   `is_active=false` não foi criada).
9. **Córtex:** o conector pede autorização outra vez nesta sessão; o digest ficou só em `claude_ai_memoria`.

## Continuação — bloco a bloco, com a prova

- **1. Chave na VPS.** `grep -c "^PROSPECTS_KEY="` → `1`; `carteiro desligado`, `resumo: SEM NOVIDADE`.
- **2. Gmail.** Gmail API: "Status: Ativado". Ecrã de consentimento criado; utilizador de teste
  boraappbora@gmail.com ("1 usuário (1 de teste)"). Cliente Desktop criado. Página aberta:
  `PAGINA ABERTA no Chrome (perfil Bora)`. Telegram enviado às 10h55 (lido de volta no registo do servidor).
- **3. Peças.** Maquetes premium registadas (prospects 402 e 403) — os dois links respondem 200 com noindex.
  13 páginas simples novas em `boraguarda.com/avenca/<token>/` (10 "o que a Bora preparou", 3 "na Bora"),
  publicadas (`Deployment complete`), 200 com noindex.
- **4. Arrumar.** 5 cadeias descartadas (Springfield, Telepizza, INATEL, Decenio, Lanidor). As 10 propostas
  antigas ficaram sem preço e assinadas "Bora App — Guarda" (`com_preco=0`, `assinadas=10`). Concelho preenchido
  nas 112 linhas (`sem_concelho=0`).
  Nota: o "Sou o Danilo" estava nos ficheiros `PARA_ENVIAR.md` do repo `propostas`, não nestas 10; esses
  ficheiros ficaram como estavam e os emails dessas duas quintas foram escritos de novo.
- **5. Ligar.** Cron instalado com guarda de fuso (o cron da VPS corre em UTC): enviar 09h40, leitor de hora a
  hora, resumo 09h50, redator 08h00, tudo hora de Lisboa. Interruptor e bots: por ligar (ponto 1).
- **6. Varredura OSM.** +48 em Gouveia, +17 na Guarda, +2 manuais → **193 na base, 136 ativos**.
  Caçador: `FIM cacador: 136 alvos, 15 com email verificado, 9 so com rede social`. Pontuação recalculada pela
  regra da ordem (sem a parcela das avaliações).
- **Redator.** O motor grátis escreveu 10 emails e reprovei os 10 a olho (elogios inventados, "Mira Serra precisa
  de ajuda", clínica convidada para a app). Passou a **molde fixo**, que só afirma o que o caçador mediu e
  confirma outra vez, da VPS, antes de escrever "o site não abre". **14 emails prontos.**
  Primeira onda, por ordem: Herdade do Mondego, Quinta do Rio Noémi, Hotel Santos, Mira Serra, Pensão Aliança.
- **7. Provas.** `flutter analyze` do projeto inteiro: 261 avisos antigos, **0 erros**, nada no ecrã novo (corrido
  com 655 MB livres, abaixo do portão de 800; sem mais nada pesado a correr). Build: 640.

## Decisões que tomei sozinho

- Restaurantes e cafés **fora da Guarda** (ou a mais de 10 km) vão como `site`, não como `parceiro-bora`: a app
  só entrega na Guarda.
- O cabeleireiro Christinnne ficou **em pausa**: o convite de parceiro fala de entregas e não serve para marcações.
- As páginas antigas de 24/09 mantêm a secção "149 € por mês": é preço já decidido, não mexi. Os emails não levam preço.
- O motor grátis fica só para sugerir a resposta quando um negócio responde (o Danilo lê antes de dizer "manda").

## PARA O DANILO

1. **Carrega em Continuar e depois em Permitir** na página do Google que está aberta no Chrome (conta da Bora).
2. Depois do teste passar, a primeira onda sai **segunda-feira às 09h40**. Queres ler os 5 emails antes?
   Estão no painel, em Caça-clientes → "prontos para enviar".
