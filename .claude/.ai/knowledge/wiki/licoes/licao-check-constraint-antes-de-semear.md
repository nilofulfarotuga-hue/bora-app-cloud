---
id: licao-check-constraint-antes-de-semear
tipo: licao
origem: [_reservas_pro_autosetup / restaurant_tables.zona · mega-fix 2026-07-18 rodada 2 Parte 7]
ultima_confirmacao: 2026-07-18
zona: verde
confianca: verificado
---

# Lição — antes de semear dados, lê as CHECK constraints da tabela (valores enumerados)

**Problema.** A função de auto-setup de reservas inseria mesas com `zona = 'Sala'` e a migration
passou (o CREATE FUNCTION é válido), mas a PRIMEIRA execução rebentou:
`new row for relation "restaurant_tables" violates check constraint "restaurant_tables_zona_check"`.
A coluna `zona` só aceita `interior/esplanada/balcao/privé/terraço/bar/outdoor`.

**Causa real.** Assumi um valor "razoável" ('Sala') sem verificar que a coluna tinha uma CHECK
constraint com um domínio fechado. O erro só aparece em RUNTIME (no INSERT), não na criação da
função — por isso um teste ao vivo é obrigatório, não opcional.

**Regra generalizável.**
- Antes de INSERT de dados-semente em colunas que "cheiram a enum" (zona, shape, status, tipo,
  reason), consulta as constraints:
  ```sql
  SELECT conname, pg_get_constraintdef(oid)
  FROM pg_constraint WHERE conrelid='public.<tabela>'::regclass AND contype='c';
  ```
- Usa SEMPRE um valor do domínio permitido; não inventes rótulos "bonitos".
- **Corre a função uma vez de verdade** (não só CREATE) e verifica as contagens — a validade da
  DDL não prova a validade dos DADOS que ela insere.

Uma migration que cria uma função "passa" mesmo com dados inválidos lá dentro; só o INSERT real os
testa. Ver [[licao-rpc-composite-null-row]] (outro caso onde o comportamento só se vê ao correr).
