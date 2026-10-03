---
tema: estado-teste-e2e · escopo: projeto · estado: atual · atualizado: 2026-07-11
id: estado-teste-e2e
tipo: foto
origem: [ordem-20260711181356-c98b · sessão "destravar tudo" 2026-07-11]
ultima_confirmacao: 2026-07-11
zona: verde
confianca: auto
---

# 📍 Ponto de retoma — teste E2E `delivery-mercado-cash`

> Foto do exato ponto onde o teste parou em 2026-07-11, para nunca se perder e poder
> continuar dali em vez de recomeçar do zero.

## Onde chegou (✅ passou)
1. `reset-role-screen` passa.
2. Permissões do Android concedidas.
3. Login cliente — chega a digitar a password no campo `fld_password`.
4. Abre Supermercados → Continente.
5. Rola categorias.
6. Abre a lista de produtos.

## Onde falta (❌ por fazer)
1. Tocar num produto real.
2. Botão **+** de adicionar ao carrinho (canto inferior direito do card do produto).
3. Abrir o carrinho.
4. Finalizar em dinheiro (cash).
5. Confirmar → criar o pedido na tabela `orders`.

## Bug real pendente
Nomes de produtos do Continente com entidades HTML por descodificar
(ex.: `C&atilde;o` → devia mostrar `Cão`). Não é fragilidade de teste — é um bug de
apresentação real no catálogo/scrape do Continente.

## Estado do ambiente
- Danilo já terminou de atualizar o app (build nova) nos 2 telemóveis.
- 2026-07-11 (sessão "destravar tudo"): confirmado `adb devices` com os 2 aparelhos
  `device` (autorizados) — `N75LTG5X5DSKDMV4` e `RZGYB1XQD2P` (este último tinha caído
  para `unauthorized`; resolvido com `adb kill-server` + `adb start-server`).

## Próxima ordem planeada
App-install automático + workflow de nuvem GitHub Actions + recomeçar o teste a partir
do passo 6 (lista de produtos) em diante.

## Não fazer ainda
Não recomeçar o teste completo antes da próxima ordem — esta página é só o marcador do
ponto de retoma.
