HANDOFF → bibliotecario-cerebro
tipo: licao
escopo: projeto
tema-alvo: permanente/procedural/licoes/licao-erro-a-primeira-nao-e-prova.md
conteudo: ver abaixo

---

# Lição: erro à primeira não é prova (repetição automática)

**Regra:** uma guarda do servidor só prova que a *nossa* chamada se aplicou
**quando aparece numa repetição a seguir a um tecto de tempo**. À primeira
tentativa, essa mesma guarda quer dizer exactamente o que diz.

**O que aconteceu (2026-08-20, missão da reserva agendada).** Ao pôr tecto de
tempo (12 s) nas RPCs que criam coisas, apareceu o problema: se a chamada demora
mas **passa** no servidor, dizer "não ficou marcada" leva a pessoa a repetir — e
a duplicar a reserva. A saída foi: ao expirar, não assumir falha; repetir uma
vez; se a repetição bater na guarda (`reservation_overlap`, `ride_in_progress`,
`slot_taken`, `credit_not_active`, `cleaner_not_available`, `invalid_status`),
essa guarda é a prova de que a primeira se aplicou → tratar como SUCESSO.

**O erro a evitar:** consultar essa lista de guardas na **primeira** tentativa.
Aí, `reservation_overlap` significa choque a sério com outra reserva do cliente,
e tratá-lo como "já ficou marcada" mentia-lhe. Está fixado por teste:
*"erro à primeira NÃO repete"* em `test/falha_de_acao_test.dart`.

**Como fazer, em qualquer repetição automática que venhamos a montar:**
1. tecto de tempo na chamada;
2. ao expirar, **não** declarar falha — repetir **uma** vez;
3. só na repetição é que a guarda conta como prova de que já se aplicou;
4. a frase ao utilizador manda **confirmar**, não afirma cegamente
   ("já ficou marcada — confirma em 'As minhas reservas'"), porque há sempre o
   caso residual de a guarda ser por causa de outra coisa.

**Corolário separado, do mesmo dia:** um varrimento a `RAISE EXCEPTION` tem de
apanhar também as marcas com parâmetro. O regex `RAISE EXCEPTION '([a-z_]+)'`
perde `RAISE EXCEPTION 'credit_not_active: %', v_status` — e foi por isso que
essa guarda pareceu não existir. Usar `'([a-z_]+)[^']*'`.

**Onde vive o código:** `lib/models/falha_de_acao.dart`
(`criarComTectoSeguro`, `provaQueJaFoiCriado`, `JaFicouCriado`).
Commits: `43103a7` (local) → publicado em `aac2b22`, versionCode 539.
