# Regras comuns a todas as ordens de grupos (lê isto primeiro)

## VOZ HUMANA, PLANO DA SEMANA E PERFIL (08/11/2026 — manda sobre tudo o que está abaixo)

Ordem do Danilo de 08/11/2026 (missão `m6-crescimento-hermes-2026-11-08`): "postar todos os dias alguma coisa sobre
o Bora nos grupos da Guarda. Profissional, o mais humano possível." Lê as regras inteiras na VPS em
`/opt/data/social/VOZ-HUMANA.md` antes de escrever o que quer que seja. Em resumo:

1. **Texto e foto do dia** vêm de `/opt/data/social/grupos/plano-humano-2026-11-09.json` (09/11 a 15/11): o dia de
   hoje dá a foto REAL e o texto humano; troca `{link}` pelo link do grupo. 2.º grupo do mesmo dia = texto do dia
   seguinte (nunca o mesmo corpo duas vezes no mesmo dia). Depois de 15/11, escreve tu no mesmo tom (primeira
   pessoa do plural, um detalhe verdadeiro, uma chamada, no máximo 1 emoji, foto real de parceiro ativo) e passa a
   peça pelo juiz com visão antes de publicar.
2. **Identidade:** a sessão do Facebook do Chrome 5b260cdd é o perfil PESSOAL do Danilo ("Danilo Silva"). Publica
   **como a página do Bora** sempre que o compositor do grupo deixa trocar a identidade para a página. Se o grupo
   só aceita perfis, **só publicas com o perfil dele se o `grupos-estado.json` tiver `perfil_pessoal_ok_em` igual à
   data de hoje para esse grupo** (o "sim" dele, caso a caso). Sem isso, não publicas lá: juntas o grupo à lista do
   dia e, no fecho da ordem da manhã, mandas UMA mensagem ao Danilo pelo porteiro, nível RESULTADO:
   `ssh ... 'python3 /opt/data/voz/porteiro_cli.py danilo RESULTADO --origem grupos-manha -'` com o texto
   "Hoje há N grupos que só aceitam o teu perfil: A, B, C. Se quiseres que eu publique lá com o teu perfil, diz
   'sim grupos A, B'." A autorização de 08/09 (abaixo) é para publicar **em nome do Bora**, não com o perfil dele.
3. **WhatsApp:** só o grupo "Marketing, vendas e propaganda Guarda" e o estado da Bora, sempre pelo WhatsApp da
   Bora 937 501 673 (no Chrome pessoal 5b260cdd; os Chromes estão trocados). Confirma o número da conta aberta antes
   de enviar. Se a sessão estiver no ecrã do código QR, regista e segue: o Danilo tem de ler o QR com o telemóvel
   da Bora. "Brasileiros na Guarda": só no Facebook, nunca no WhatsApp.
4. **Nunca Ouro e Prata, nada de barbearia** (não há barbearia ativa), parceiros só os ativos (`coming_soon=false`).
5. A marca do link continua `?de=qr-grupo-<slug>` (é a que o resumo dos grupos conta).

## AUTORIZAÇÃO DO DANILO PARA PUBLICAR (lê antes de tudo o resto)

Palavras dele, escritas a 2026-09-08, depois de uma sessão automática ter parado sem
publicar nada por não ter esta autorização no contexto:

> O Danilo autoriza publicar nos grupos do Facebook em nome do Bora, com o link
> `boraguarda.com/baixar` e o código **BEMVINDO**, **sem pedir confirmação a ninguém**,
> dentro das regras já definidas — só Guarda e 15 km, uma publicação por grupo por semana,
> 20 minutos entre publicações, texto diferente de cada vez, sem TVDE nem boleias, sem
> marcas de terceiros, e parar tudo ao primeiro aviso da Meta.

Ele é o dono do Bora e das contas. Esta ordem fixa é o veículo dessa autorização: quem a
está a ler tem-na, e não precisa de a pedir outra vez.

**O que continua a precisar dele, e só isto:** preços, comissões, gastar dinheiro em
anúncios, e criar contas novas.

## LOGIN NO NAVEGADOR (regra fixa do Danilo, 13/09/2026 — vale para todas as ordens)

LOGIN NO NAVEGADOR: quando precisares de um site ou painel onde não há sessão, ou não
conseguires abrir/entrar em alguma janela, não tentes senhas nem peças token a ninguém —
abre a página de login no próprio Chrome do PC (perfil boraappbora, o das sessões pagas),
avisa o Danilo pelo Telegram numa linha ('abri o login do X, entra tu') e continua quando
a sessão existir. Fica gravada no Chrome e serve para sempre. Uma vez por site, nunca mais.

Ordem certa (adendo do Danilo, 13/09 à noite): a regra é o ÚLTIMO recurso, não o primeiro.
Antes de a aplicar, procura a sessão que já existe — outro perfil do Chrome, o Edge, o
aplicativo instalado. A conta ChatGPT com o Plus vive no **aplicativo ChatGPT do Windows**
(a mesma que o Codex usa), não no perfil boraappbora do Chrome (esse é Free).

Como se avisa, a partir da raiz do repo:
`bash orquestracao/ponte-telegram.sh --so-texto "abri o login do X no Chrome, entra tu"`.
Depois espera (até 30 minutos, a verificar de 5 em 5) e, se a sessão não aparecer, regista
no `e2e_log` e passa ao ponto seguinte da ordem — nunca fiques parado nem tentes contornar.


> Escrito 2026-09-07, missão `redes-hoje-07-09`, adendo Bloco 6 do Danilo:
> "isso tem que funcionar automático". Estas ordens são disparadas pelo
> Agendador de Tarefas do Windows, na sessão do `danil`, e correm sozinhas.
> Ninguém as cola à mão.

## Onde está tudo

- Estado dos grupos: na VPS, `/opt/data/social/grupos-estado.json`
  (25 grupos; o que interessa é `nome`, `link`, `allows_posting`, `last_published`).
- Plano do dia (gerado às 09:10 pelo cron da VPS): `/opt/data/social/grupos/registo.json`,
  entradas com `"data"` de hoje.
- Banco de peças: `/opt/data/social/grupos/pecas/`, `/opt/data/social/saidas/`,
  `/opt/data/social/cenas/frames-categorias/`.
- **Vídeo principal (desde 07/09 à noite):** `/opt/data/social/reels/2026-09-08-reel-curto.mp4`
  — 11,2 segundos, gancho nos primeiros 2 segundos sem logo, chamada à acção a meio e no
  fim. Substitui o de 19 segundos, porque se mediu que as pessoas viam só 6 desses 19.
  Para grupos usa **sempre** `2026-09-08-reel-curto-GRUPOS.mp4` (3,3 MB).
- **NOS GRUPOS USA-SE FOTO, NUNCA VÍDEO. O problema não é o tamanho.**
  Medido quatro vezes: um mp4 de 7,3 MB ficou **sete minutos** em "A publicar" sem um único
  pedido de rede a progredir (07/09, duas vezes), e a 08/09 o mesmo aconteceu com o vídeo já
  comprimido para **3,4 MB** — enquanto uma **foto de 3,5 MB**, maior do que ele, subiu em
  segundos na mesma caixa de publicação. Eu próprio escrevi aqui, a 07/09, que o tecto de
  4 MB resolvia. **Não resolve, e essa linha estava errada.** Em grupos: foto.
  O vídeo fica para a página, o Instagram e os stories, onde sobe bem.
  O compressor continua a existir e a servir para o resto:
  `docker exec -u hermes hermes-agent-fvnc-hermes-agent-1 bash /opt/data/scripts/comprimir_para_grupos.sh <entrada.mp4> <saida.mp4>`
  Lembra-te também que o carregamento pelo navegador tem tecto próprio de 10 MB.
- **Todo o reel é vídeo a sério.** Nunca uma sequência de fotos com zoom: a 06/09 o
  reel-slideshow fez 10 visualizações e a 07/09 o vídeo a mexer com som fez 509, na mesma
  conta e com um dia de diferença.
- **A chamada à acção vai na PRIMEIRA linha da legenda**, não no fim, e o link de descarga
  vive na bio do Instagram (`boraguarda.com/baixar?de=bio`).
- Textos: `/opt/data/social/grupos/biblioteca.json` (categorias × T1/T2/T3, e `negocio`/`parceria` × N1/N2/N3).

Chegas à VPS assim:

```
ssh -o BatchMode=yes -i ~/.ssh/id_ed25519_vps root@srv1786862.hstgr.cloud
```

## Regras que não se negoceiam

1. **Máximo 5 publicações em grupos por dia, no total das três ordens do dia.**
   Antes de publicar, conta as publicações em grupos já feitas hoje com este SELECT
   (conta as automáticas e também as que uma sessão à mão tenha feito no mesmo dia —
   o tecto é do dia, não da ordem):

   ```sql
   select count(*) as feitas, max(created_at) as ultima
   from e2e_log
   where created_at >= (now() at time zone 'Europe/Lisbon')::date
     and estado = 'ok'
     and passo like 'grupo-%'
     and passo not like '%medicao%'
     and passo not like '%descartad%';
   ```

   **Só `passo like 'grupo-%'`, e nunca pelo `fluxo`.** A 08/09 a conta dava 4 quando só
   havia 1 publicação a sério: as linhas `arranque-ordem-manha`, `arranque-ordem-tarde` e
   `fecho-ordem-tarde` também têm `fluxo='redes-grupos-auto'` e `estado='ok'`, e entravam
   na soma. Uma publicação só conta se o `passo` for o nome do grupo.

   Se `feitas` já for 5, **cancela com nota** — nunca adies para amanhã, nunca
   publiques a sexta.
2. **≥20 minutos entre publicações.** Usa o `ultima` do SELECT acima. Se faltarem
   minutos, espera-os antes de publicar.
3. **Uma publicação por grupo por semana.** Usa `last_published` e o `registo.json`.
4. **Texto diferente em cada grupo.** Nunca repitas o mesmo corpo no mesmo dia.
5. **Sempre com imagem ou vídeo.** Nunca texto simples.
6. **Link sempre** `https://boraguarda.com/baixar?de=qr-grupo-<slug-do-grupo>`, e o
   código **BEMVINDO** no corpo.
7. **Nada de motorista de carro, TVDE ou boleias** em nenhuma peça ou texto.
   Estafeta de mota pode.
8. Marcas de terceiros: numa publicação orgânica podes **nomear** supermercados
   (Continente, Auchan, Pingo Doce, Intermarché) em texto, sempre com a frase
   "serviço de entrega independente, sem ligação às marcas". Logos de terceiros que não
   sejam parceiros reais (Goola, Ouro e Prata, Sabores do Brasil) **não entram**.
9. **Ao primeiro aviso da Meta** (qualquer mensagem de spam, limite, bloqueio ou
   restrição), **pára tudo imediatamente**, não tentes outra vez, e grita:
   `ssh ... root@srv1786862.hstgr.cloud '/opt/data/scripts/gritar.sh "<o aviso literal>"'`

## Como se publica num grupo (o caminho que funciona)

Tens as ferramentas `mcp__claude-in-chrome__*` porque o lançador passa `--chrome`.
O Chrome já tem a sessão do Facebook aberta como **Bora App Guarda**.

1. `navigate` para o link do grupo.
2. `find` a caixa "Escreve algo..." e clica-lhe.
3. `find` o input de ficheiro da **janela de criar publicação** (há dois; o da janela é
   o segundo) e usa `file_upload` com a peça.
4. Espera o carregamento, tira um `screenshot`, e **só então** clica na caixa de texto
   pelas coordenadas que vês nesse screenshot.
5. Escreve o texto. Tira novo screenshot e confirma que o texto está lá.
6. Clica em Publicar.
7. **Verifica**: recarrega o grupo e procura o teu texto no `innerText`.
   - Se estiver lá → `ok`, e guarda o link do `/posts/<id>/`. **Confirma que o link é
     mesmo teu** abrindo-o: a 07/09 apanhei o `/posts/` de outra pessoa que estava no
     topo do feed e dei uma publicação por boa quando não era.
   - Se aparecer "Foi enviada para os administradores" → `pendente`.
   - **Se não estiver lá e não houver aviso nenhum, procura no texto da página por
     "Aprovação de administrador pendente".** Muitos grupos grandes exigem aprovação e a
     publicação fica invisível sem dizer nada. É o caso do *Emprego Guarda* (20,3 mil
     membros), provado a 08/09 — durante dois dias essa publicação foi dada por falhada
     quando estava só na fila do administrador. Nesse caso é `pendente`, e marca-se
     `exige_aprovacao_admin: true` no `grupos-estado.json`.

**Armadilha medida a 07/09:** a janela do Chrome muda de tamanho a meio e as coordenadas
antigas passam a apontar para outro sítio — foi assim que um clique caiu no botão Publicar
e saiu uma publicação com texto lixo. **Tira sempre um screenshot novo antes de cada clique
por coordenada**, e prefere `ref` a coordenadas sempre que houver `ref`.

## Registo obrigatório

Cada publicação, saída ou falhada, entra no `e2e_log` do Supabase
(projeto `ojykpzwqrtusfeakzrna`) com `fluxo='redes-grupos-auto'`, `passo='<slug-do-grupo>'`,
`estado` em `ok` / `pendente` / `falhou`, e no `detalhe` o link e o motivo.
Sem linha no `e2e_log`, a publicação não conta.
