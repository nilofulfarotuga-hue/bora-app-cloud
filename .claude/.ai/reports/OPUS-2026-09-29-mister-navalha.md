# Mister Navalha — site e loja na app (29/09/2026)

Motor: Opus · Porta: Claude Code no PC do Danilo · run_id `mister-navalha-2026-09-29`
Provas literais: `.claude/.ai/provas/mister-navalha-2026-09-29/PROVAS.md` (+ capturas em `telemovel/`).
Diário: `e2e_log` fluxo `mister-navalha-2026-09-29` (14 linhas, ids 2591 a 2608, do plano ao fim).

## Acessos

- Supabase por MCP: funcionou (leitura, escrita e provas).
- Cloudflare: os dois tokens do `bora-site/.env` estão activos (Pages e DNS). Nunca foram impressos.
- Storage: chave de serviço do `backend/.env`, lida por script e nunca impressa.
- Chrome, perfil Bora (`d9e862e0…`): a extensão liga, mas **não consegue ler nenhuma página** (ver Bloco 3).
- Computer use no Chrome: **recusado** no diálogo de acesso.
- Córtex: respondeu (busca e registo).

## O que NÃO ficou feito

1. **Os preços do Instagram não foram lidos.** O destaque "Valores" não abriu de maneira nenhuma
   (causa real no Bloco 3). Como a ordem mandava, **os preços ficaram como estavam**: Degradê 13 €,
   Corte de cabelo 12 €, Barba 8 €, Cabelo + barba 18 €, Corte criança 10 €, Sobrancelha 3 €,
   Freestyle 3 €. O site e a app dizem exactamente o mesmo — não há desencontro entre os dois.
2. **Não vi o ecrã da loja dentro da app.** A app web pede login para entrar como cliente e eu não
   escrevo senhas. Provei pelo que a app recebe da base (é o que o ecrã desenha).
3. **Não acrescentei a linha no `DOMINIOS.md` do bora-site** — esse repositório está noutro ramo, de
   outra sessão, e não lhe toquei. A linha a pôr: `misternavalha.boraguarda.com` → projecto `misternavalha`.
4. **O site só está num git local** (como o da Goola e o da Leonidas), sem cópia no GitHub.

## Bloco 1 — Site no ar: https://misternavalha.boraguarda.com

- Pasta fixa: `C:\BoraLocal\projetosflutter\sites\misternavalha\`, guardada em git no mesmo dia
  (commits `3e5c0aa` e `e5e5d9e`). Publica-se com `bash deploy-cloudflare.sh` (só a lista branca).
- Projecto Cloudflare Pages `misternavalha` criado; 19 ficheiros publicados.
- Domínio ligado pelas duas metades: domínio próprio no projecto **e** registo DNS na zona
  boraguarda.com. Certificado emitido e activo.
- Prova pelo endereço público: página 200 e **igual byte a byte** ao ficheiro; os três vídeos
  (`fundo.mp4`, `fundo-telemovel.mp4`, `workshop.mp4`) dão 200 com `video/mp4` e aceitam pedidos
  por partes (o iPhone precisa disso); uma página que não existe dá 404 com a página própria.
- Links todos a funcionar: App Store id6809954739 (a loja portuguesa **já está aberta**, versão
  1.0.4), Google Play, app.boraguarda.com, boraguarda.com, mapa, e os dois Instagrams confirmados
  pelo nome da conta (@barbearia_mister_navalha__ e @ernando__silva).
- Telemóvel com "reduzir movimento" **ligado e desligado**: iPhone 15 no motor do Safari, iPhone 15
  e Pixel 7 no Chrome — **6 em 6 com o vídeo de fundo a correr** (o tempo do vídeo avançou 2,5 s
  entre duas medições), sem deslize para o lado.
  Nota honesta: o emulador liga a preferência do site, não imita a regra de reprodução automática
  do iPhone real. Se um iPhone recusar arrancar o vídeo sozinho, o site arranca-o ao primeiro toque.

## Bloco 2 — Fotos e logo na loja da app

- 11 imagens no Storage, pasta da loja (`553a0d77…/`, galeria em `gallery/`): todas dão 200 pelo
  endereço público e são iguais byte a byte às originais. A **origem de cada foto** ficou gravada
  na base, nos metadados de cada ficheiro.
- Logo em PNG 1024×1024 feito a partir do emblema do site ("Ernando's Mister Navalha, desde 2019"),
  cobre sobre preto, com as fontes certas confirmadas antes da captura.
- Base actualizada e lida de volta: logo, capa, galeria com os 6 cortes e o certificado **por esta
  ordem**, e a foto do Ernando. Os 10 endereços que a base aponta dão todos 200.
- O que a app recebe sem sessão já traz tudo isto, e a Mister Navalha aparece na lista de
  barbearias (com o selo "Em breve", como a Ouro e Prata).
- A loja continua em `coming_soon = true`. Não mexi noutros parceiros nem mandei nada ao Ernando.

## Bloco 3 — Preços (bloqueado)

Tentei sete caminhos, todos com o erro real no `e2e_log`:

1. Extensão do Chrome, perfil Bora: a página do Instagram carrega, mas a extensão não consegue
   ler nada (tempo esgotado em captura, texto e JavaScript).
2. Separador novo e 3. aba activada à força (acessibilidade do Windows), janela à frente,
   maximizada e por cima de tudo: igual — até no example.com e no nosso próprio site.
4. Extensão do perfil pessoal: igual.
5. Computer use no Chrome: acesso recusado.
6. Navegador embutido, sem conta: o Instagram pede login para ver destaques.
7. Um visualizador público de destaques: era página de anúncios e planos pagos — saí sem clicar.

**Causa provável:** na janela "Em Dia" do Chrome há duas barras "Claude iniciou a depuração deste
navegador" — uma depuração de outra sessão ficou pendurada, e a extensão deixou de conseguir entrar
em qualquer página, nos dois perfis. Não carreguei em "Cancelar" para não cortar o trabalho dessa
sessão. Deixei as janelas do Chrome como estavam.

## Encontrei pelo caminho (reporto, não corrigi)

1. **O site convida a marcar, mas a loja na app diz "Em breve".** Botões "Marcar" e "Marcar agora",
   e o texto "a Mister Navalha está lá: escolhes a hora". Quem seguir o site hoje chega a uma loja
   que ainda não aceita marcações.
2. **Regra dos dois botões (PADRAO 1.11):** o site tem dois botões grandes (App Store e Google Play)
   e o "marcar pelo site" vai em letra pequena. Com a App Store portuguesa aberta o risco é menor,
   mas foge à regra escrita.
3. **A extensão do Chrome está presa** e vai travar qualquer sessão que precise do navegador.

## PARA O DANILO

- **Preços:** duas saídas, escolhe uma. (a) Fechar e voltar a abrir o Chrome — a extensão destrava e
  a próxima sessão lê o destaque "Valores" sozinha; ou (b) mandar-me os preços por voz (ou uma
  captura do destaque) e eu acerto o site e a app no mesmo dia.
- **Decisão:** o site fica a dizer "marca pelo Bora" enquanto a loja está "Em breve", ou mudo os
  botões para "Em breve" até fechares com o Ernando?
