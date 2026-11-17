# A3 Guarda — entrega da parte 2 (17/11/2026)

Missão `a3-guarda-16-11`, caixa_guardados 114 (original 111), ordem trazida pela Claude.ai.
Executor: Claude Code no PC (modo leve: 531 MB livres no arranque). Tudo no `e2e_log`,
fluxo `a3-guarda-16-11`, a partir do passo `parte2-arranque`.

Ramo: `ai/2026-11-17-a3-guarda-parte2` (a partir de `origin/autonomous-night-2026-04-29` 75c56224).
O `ai/2026-11-16-a3-guarda` pedido está preso noutra pasta de trabalho e não tem commits próprios.
O envio do ramo foi recusado pela tranca do PC: **a Claude.ai envia o ramo e abre o pedido de revisão**.

## O que já ficou feito na base (sem precisar de publicar)

- Contas de teste: `a3teste@bora.app` (parceiro, DONO da loja a3-guarda) e `a3cliente@bora.app`
  (cliente), palavra-passe pedida pelo Danilo; as duas na lista de quem vê a loja escondida.
  Login provado pela API (HTTP 200 nas duas). Com dono, a falha da loja escondida sem dono deixou
  de afetar a A3.
- Assistente de WhatsApp `a3-guarda` criado em `assistant_tenants`, **desligado** (ver passo 6).

## Passos para a Claude.ai, por esta ordem

1. **Enviar o ramo** e ver o CI (`olho-golden` compila o código) e correr `flutter analyze` e
   `flutter test test/impressao_test.dart` (no PC não se correu Flutter: modo leve).
2. **Migração `20261117100000_robo_a3_catalogo.sql`** e Edge **`robo-a3-catalogo`**
   (a função exige a service role no Authorization).
   - Fotos: `select public.robo_a3_iniciar('manual');` — o tick de minuto a minuto lê a loja,
     aplica preço/esgotado (primeira vez não deve mudar nada) e copia ~100 fotos por minuto.
     Prova: `select count(*) from products where restaurant_id='a3-guarda' and photo_url ilike '%a3guarda.com%'` = 0.
   - Logótipo: POST `{"acao":"imagens-loja","logo_url":"https://a3guarda.com/loja/img/logo-1759848020.jpg"}`
     (é o único que o site tem, 120×81; pedir o ficheiro grande à A3).
   - Capa: gerar (16:9, papelaria e presentes de Natal, vermelho/amarelo/azul sobre branco, sem
     pessoas, sem texto), passar pelo Juiz de visão e POST `{"acao":"imagens-loja","capa_url":"https://…"}`.
3. **Migração `20261117000300_lojas_escondidas_dono_vazio.sql`** (a mesma do PR #29) depois de a
   Farmácia da Sé estar aberta e estável; correr `supabase/tests/lojas_escondidas_para_mim_test.sql`
   (tem de dar 18 casos ok).
4. **Migração `20261117100100_impressao.sql`** e Edge **`impressoes-limpeza`**.
   Depois: `update products set personalizavel = true where restaurant_id = 'a3-guarda' and name ilike 'Caderno personaliz%';`
5. **Decidir a loja pendente** (as contas de teste só veem a ficha da loja com `approved`):
   ou a A3 dá IBAN + autocertificação, ou saída de emergência só para aprovar, mantendo
   `coming_soon = true` e `so_lista_permissao = true`:
   `begin; select set_config('bora.forcar_ativacao','1',true); update restaurants set approval_status='approved', approved_at=now() where id='a3-guarda'; commit;`
6. **WhatsApp**: pôr `ferramentas/assistente-negocio/assistente.py` na VPS e reiniciar o
   assistente; depois `update assistant_tenants set mode='teste' where slug='a3-guarda';`.
   Teste: https://wa.me/351937501673?text=Ol%C3%A1%20A3 (a conversa fica na A3; "mudar de loja"
   mostra as opções; sem escolha fica a Boom). Fazer as 10 conversas da caixa 111 (4.7).
7. **Publicar nas 3** (web, Play, Apple) e provar os ecrãs com as contas de teste.

## Lista para o WhatsApp oficial da Meta no número da A3 (4.6 — só preparar, não pedir nada)

- Conta Meta Business (Business Manager) da A3, verificada com os dados da empresa
  (Lionel Santos, Unipessoal, Lda, NIPC 518305767, morada, site a3guarda.com, email geral@a3guarda.com).
- O número a usar (o 271 082 551 é fixo: aceita verificação por chamada de voz) e a decisão de o
  tirar da app WhatsApp normal/Business, porque um número na API deixa de funcionar na app.
- Nome a mostrar ("A3 Guarda"), aprovado pela Meta, foto de perfil (o logótipo) e descrição.
- Método de pagamento na conta Meta (as mensagens de modelo enviadas pela empresa pagam-se à
  Meta; confirmar a tabela de preços em vigor na altura).
- Modelos de mensagem aprovados para avisos fora das 24 h (pedido pronto, orçamento enviado).
- Política de privacidade pública (link) e quem responde quando o robô passa a uma pessoa.

## O que NÃO ficou feito (e porquê)

- Logótipo grande e capa: sem quota de imagem (Higgsfield 0 créditos, Gemini 429) e o
  `pip install` de um vetorizador foi recusado pelo classificador.
- Exemplos de personalizados (canecas, t-shirts…): regra "nunca produto sem foto".
- Descrições longas (979 produtos) e fotos extra (1300 produtos têm mais de 1 foto): a tabela
  `products` só tem `photo_url`; ficam no bruto da leitura de 16/11.
- Cobrança real dos pedidos de impressão: Lista Vermelha (como a receita das farmácias).
- Ferramenta de cálculo de impressão dentro do robô de WhatsApp (hoje manda para a app).
- Provas de ecrã e pedidos de teste ponta a ponta: dependem dos passos 1 a 5.
