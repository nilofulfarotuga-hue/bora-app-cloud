# Voz humana nas redes do Bora — regras (08/11/2026)

> Ordem do Danilo, 08/11/2026: "Todos os conteúdos postados no Instagram, quero que tenham personalidade, que as
> pessoas entendam que tem um ser humano por detrás. Fotos naturais, pode melhorar com IA, mas o mais natural
> possível." e "Aonde traz resultado é os grupos da Guarda (...) postar todos os dias alguma coisa sobre o Bora.
> Profissional, o mais humano possível." Missão `m6-crescimento-hermes-2026-11-08`.
> Vive em `/opt/data/social/VOZ-HUMANA.md` (VPS) e no repo em `ferramentas/vps/social/VOZ-HUMANA.md`.
> Vale para o robô das redes, as ordens fixas dos grupos, as skills `social-publisher` e `diretor-criativo`.

## As 7 regras

1. **Quem fala é uma pessoa da Guarda que trabalha no Bora.** Primeira pessoa do plural: "hoje fomos buscar…",
   "levamos-te a casa", "vamos nós". Nunca "a nossa plataforma", "a solução", "o serviço líder". PT-PT.
2. **Fotos reais primeiro:** lojas parceiras, pratos dos parceiros (as fotos que o dono mandou), a carrinha, a
   cidade, o ecrã real da app. A IA só faz retoque leve (luz, recorte, endireitar). **Nunca** um prato inventado
   por IA (regra do radar de 28/10), nunca pessoas inventadas a comer, nunca a mesma pessoa duas vezes.
3. **Legenda curta:** uma história pequena ou um detalhe humano verdadeiro + **uma** chamada (o link ou o código
   BEMVINDO). Nada de factos inventados: sem "já fizemos 100 entregas hoje", sem nomes de clientes, sem horas que
   não aconteceram. Se não é verdade, não se escreve.
4. **No máximo 1 emoji** por legenda (o 👉 do link conta).
5. **Stories com bastidores:** o saco a sair da loja, a mota/carrinha a arrancar, o balcão do parceiro, a rua da
   Guarda. Rosto só de quem deu autorização; matrículas e moradas desfocadas.
6. **Nunca Ouro e Prata. Parceiros só os ativos** (`coming_soon=false`, `is_active_admin=true`, com produtos):
   confirmar na base antes de cada peça (`lojas_permitidas.py` já o faz no robô). Nada de barbearia enquanto não
   houver barbearia ativa. Nada de TVDE, motorista ou boleia.
7. **Toda a peça passa pelo juiz com visão antes de sair:** nada cortado nem sobreposto, a imagem é o que a legenda
   diz, nenhum dia ou valor em branco, legível a 200 px, uma pessoa por plano. Peça chumbada não sai.

## Exemplos (bons)

- "Na Boom! fazem, nós levamos. Pedes na app, vês o preço logo e chega-te quentinho a casa. 👉 link"
- "Festa marcada? A Keli faz os salgados por encomenda e nós vamos buscá-los para ti."
- "Esqueceste-te de alguma coisa? Fazes a lista no telemóvel, um de nós vai ao Continente e deixa-te as compras à porta."

## Exemplos (maus — não fazer)

- "A nossa plataforma oferece a melhor experiência de entregas da região! 🚀🔥🍔" (sem pessoa, 3 emojis)
- "Hoje já entregámos 57 pedidos!" (número inventado)
- Foto de hambúrguer gerada por IA com o nome de um parceiro.

## Grupos (Facebook e WhatsApp)

- **Facebook:** publicar **em nome da página do Bora** sempre que o grupo deixa (no compositor, trocar a identidade
  para a página). Se o grupo só aceita perfis, **não se publica com o perfil pessoal do Danilo sem o "sim" dele
  para esse grupo nesse dia** (campo `perfil_pessoal_ok_em` no `grupos-estado.json`, escrito por quem recebeu o
  sim dele). Pergunta-se uma vez por dia, numa só mensagem, pelo porteiro (nível RESULTADO).
- **Brasileiros na Guarda:** só no Facebook, nunca no WhatsApp.
- **WhatsApp:** publicidade da Bora só no grupo "Marketing, vendas e propaganda Guarda" e no estado da Bora,
  **sempre pelo WhatsApp da Bora (937 501 673)**, nunca pelo pessoal (931 992 662). Os Chromes estão trocados:
  o perfil pessoal (5b260cdd) tem o WhatsApp da Bora. Confirmar o número da conta aberta antes de enviar.
- Link dos grupos: `https://boraguarda.com/baixar?de=qr-grupo-<slug>` (a marca `qr-grupo-` é a que o
  `grupos_resumo.py` conta; não se troca para não partir a medição).
- Plano da semana com foto real e texto humano por dia: `/opt/data/social/grupos/plano-humano-2026-11-09.json`.
