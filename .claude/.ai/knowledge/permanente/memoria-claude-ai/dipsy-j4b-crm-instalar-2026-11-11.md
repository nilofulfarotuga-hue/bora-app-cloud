---
id: memoria-claude-ai-dipsy-j4b-crm-instalar-2026-11-11
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-11-11
zona: verde
confianca: alta
estado: atual
---

# Missão do Dipsy dipsy-j4b-crm-instalar-2026-11-11

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `dipsy-j4b-crm-instalar-2026-11-11`, origem `claude-code`, atualizada em 2026-11-11T08:55:35.03228+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: dipsy j4b crm instalar 2026 11 11 · memoria claude.ai · claude_ai_memoria

MISSAO DIPSY: dipsy-j4b-crm-instalar-2026-11-11

# CRM de WhatsApp grátis — instalar o WAHA na VPS (continuação da J4)

Quem manda: o Danilo, 10/11/2026 16:43: "CRM do WhatsApp, faz, mas manda o Dipsy fazer." Antes: 09/11/2026 20:43 "tem que ser gratuito". A J4 de 10/11 só pesquisou (Chatwoot + Evolution API) e nada instalou. Escrito pelo Claude Code a 11/11/2026 (missão fechar-tudo-2026-11-11, bloco 7), depois de medir a VPS.

## Porquê WAHA e não Chatwoot + Evolution (VPS medida a 11/11/2026 às 08:48)
A VPS tem 3915 MB de RAM com 1929 MB disponíveis, a troca (swap) já com 933 de 2047 MB em uso, 1 CPU, e o disco com 4,2 GB livres de 48 GB (92 % cheio). O Hermes sozinho usa ~1 GB. Chatwoot (Rails + Sidekiq + Redis) mais a Evolution API pedem 2 a 3 GB de RAM e ~3 GB de imagens: não cabem deixando 1 GB livre para o Hermes, nem no disco. O WAHA (devlikeapro/waha, Apache 2.0) com o motor GOWS ou NOWEB (sem navegador) gasta 100 a 300 MB. Desde a versão 2026.6.1 tudo o que era do WAHA Plus (sessões ilimitadas, multimédia, armazenamento PostgreSQL, segurança) é grátis no Core: https://waha.devlike.pro/docs/how-to/waha-plus/ (lido a 11/11/2026). Nota: o DeskcommCRM EXISTE (github.com/melgarafael/DeskcommCRM — a J4 disse que não) e usa precisamente WAHA NOWEB + Supabase, mas recomenda 4 GB de RAM: fica para depois, quando houver RAM.

## Carta de autonomia
- Podes: entrar na VPS do Hermes (ssh -i ~/.ssh/id_ed25519_vps root@srv1786862.hstgr.cloud); criar UM contentor novo chamado crm-waha (e um volume crm-waha-sessions, se for preciso) com limite de memória de 400 MB e reinício automático; ligar o WAHA à base do projeto Supabase GRÁTIS bora-crm-pmes (ref xmwqltqocytijzfqkfrh, organização "Bora PMEs"); ler a tarefa 1710 (tabela despacho do Supabase do Bora, só LER) e o livro; escrever no e2e_log.
- Precisa do "sim" do Danilo no Telegram. PEDE TODOS OS "SIM" DE UMA VEZ, numa só mensagem, no início, numerada: (1) criar o registo de DNS de um subdomínio novo (ex.: crm.boraguarda.com para o IP da VPS; a 11/11 não há registo curinga em boraguarda.com) e (2) a regra nova no Traefik que o põe na internet com HTTPS. Sem "sim", faz tudo o resto e deixa isto por fazer, registado. Se a tua guarda barrar o ssh, pede o "sim" (a guarda pergunta) e espera; sem ele, regista e para.
- Nunca: gastar dinheiro (nada de planos pagos, nem "teste grátis com cartão", nem doações; nunca a frase que liga o motor pago); mandar mensagens de WhatsApp a ninguém nem ligar um número (PARAR NO ECRÃ DO QR: o número é do cliente); tocar no Supabase do Bora (ojykpzwqrtusfeakzrna) além de ler o despacho e escrever no e2e_log; mexer, parar, reiniciar ou apagar contentores, imagens ou volumes que já existem (hermes-agent-fvnc-hermes-agent-1, traefik-traefik-1, omniroute, cortex-mcp, conselho-mcp, buzz-*, bora-*, searxng, a imagem hermes-backup e as outras); docker system prune ou image prune; apagar dados; pôr senhas no Telegram, no livro, no e2e_log ou no relatório (os motores grátis podem guardar o que lhes chega: as senhas geram-se NA VPS e ficam só num ficheiro de root).

## O que fazer
1. Antes de tudo, mede outra vez na VPS (só leitura): free -m, df -h /, docker stats --no-stream. Se a RAM disponível for menor que 1400 MB ou o disco livre menor que 3 GB, PARA, regista no e2e_log com os números e não instales.
2. Escolhe a imagem mais pequena do WAHA com o motor GOWS (ou NOWEB): vê as etiquetas na página oficial (waha.devlike.pro) ou no Docker Hub. Confirma o tamanho antes do docker pull; depois do pull o disco livre tem de continuar com pelo menos 2,5 GB (senão apaga SÓ a imagem que tu puxaste e regista).
3. Senhas só na VPS: cria /root/crm-waha (chmod 700); gera WAHA_API_KEY, WAHA_DASHBOARD_PASSWORD e WHATSAPP_SWAGGER_PASSWORD com `openssl rand -hex 24` direto para /root/crm-waha/.env (chmod 600), sem as mostrar. Utilizador do painel: admin (WAHA_DASHBOARD_USERNAME).
4. Base: WHATSAPP_SESSIONS_POSTGRESQL_URL com a cadeia de ligação do Postgres do bora-crm-pmes (Session pooler), escrita só no /root/crm-waha/.env. Se não a tiveres guardada num ficheiro de root ou em ~/.dsh/secrets, NÃO mudes a senha da base: usa o armazenamento local (volume crm-waha-sessions em /app/.sessions) e regista porquê. O WAHA cria uma base por sessão: se o Supabase recusar (sem permissão para criar base, ou o pooler não chegar a bases novas), passa também ao volume local e regista.
5. Arranca só para dentro (nada aberto à internet sem o "sim"): `docker run -d --name crm-waha --restart unless-stopped --memory 400m -p 127.0.0.1:3000:3000 --env-file /root/crm-waha/.env -e WHATSAPP_DEFAULT_ENGINE=GOWS <imagem>` (mais o volume, se for o caso).
6. Prova: docker ps (crm-waha Up); `curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:3000/api/sessions` sem chave tem de dar 401 e com a chave do .env (cabeçalho X-Api-Key, lida do ficheiro dentro do mesmo comando) tem de dar 200; docker stats --no-stream (memória do crm-waha); free -m e df -h depois.
7. Ecrã do QR, sem ligar nenhum número: túnel do PC (`ssh -i ~/.ssh/id_ed25519_vps -N -L 3000:127.0.0.1:3000 root@srv1786862.hstgr.cloud`), abre http://localhost:3000/dashboard, entra, cria a sessão "default" e para no ecrã do QR; captura_ecra e guarda a imagem em C:\BoraLocal\QG\crm\. Depois para a sessão (sem a apagar) para não ficar a gerar QR, e fecha o túnel.
8. Só se o Danilo disse "sim" ao DNS e ao Traefik: cópia da configuração do Traefik antes; regra nova só para o crm-waha (Host crm.boraguarda.com, HTTPS com Let's Encrypt, com a autenticação do próprio WAHA ligada); prova com `curl -I https://crm.boraguarda.com/dashboard` (401 ou página de entrar). Nunca abrir o painel do Hermes.
9. Escreve C:\BoraLocal\QG\crm\LEIA-ME-crm-waha.md: o que ficou instalado, como entrar (a senha está em /root/crm-waha/.env, só root), como parar (docker stop crm-waha), RAM e disco antes e depois, e o próximo passo (caixa partilhada, etiquetas, respostas rápidas e robô de resposta com motor grátis: WAHA + tabelas no bora-crm-pmes, ou o DeskcommCRM quando houver RAM).

## Tempo
Esta missão corre até 40 minutos. Antes do fim, escreve em C:\BoraLocal\QG\crm\PROGRESSO-j4b.md o que fizeste e o próximo passo: se não acabares, a fila lança-a uma 2.ª vez e continuas daí (lê esse ficheiro primeiro).

## Critério de pronto
Linha no e2e_log (fluxo dipsy-j4b-crm-instalar-2026-11-11) por passo, com prova: números da VPS antes e depois, docker ps, os códigos 401/200, captura do ecrã do QR. No fim, o endereço e onde está a senha (num ficheiro só de root na VPS, nunca no Telegram nem no livro). O que ficou à espera de "sim" listado no fim, numerado, um por linha.

## Dúvidas
Pergunta ao Claude.ai na página duvidas-dipsy do livro. Não pares: segue com o que não depende da dúvida.

