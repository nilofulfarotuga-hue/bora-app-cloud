# Mapa da app (B6.1)

## O que é
Um script que lê o código Flutter do Bora e escreve a lista dos botões, menus, separadores e títulos
que cada ecrã mostra, por app (cliente, estafeta, parceiro, admin). Serve para um robô fiscal saber
se um botão de que o suporte fala existe mesmo, e em que ecrã.

## Como correr
```
node ferramentas/hermes-diretor/gerar_mapa_app.mjs <raiz-do-repo> --json saida/mapa_app.json --sql saida/mapa_app.sql
node ferramentas/hermes-diretor/teste_mapa_app.mjs
```
Só precisa do Node (sem instalar nada). Não corre Flutter e não precisa de rede. O gerador não aplica
o SQL: quem aplica decide. O `delete` do fim do ficheiro SQL vem comentado.

## Como decide a app de cada ficheiro
1. Pasta: `screens/admin` e `widgets/admin` (ou nome `admin_...`) = admin; `screens/client`, `farmacia`,
   `impressao`, `market` = cliente; `screens/partner` = parceiro; `screens/driver`, `cleaner`, `washer`,
   `handyman` = estafeta.
2. Prefixo do nome em `lib/screens`: `client_`, `driver_`, `partner_`, `restaurant_`...
3. Ecrãs soltos em `lib/screens` sem prefixo (carrinho, pedidos, perfil, login): app do cliente.
4. Widgets e o resto: a app dos ecrãs que os importam (os ecrãs do admin só contam se ninguém mais importar).
   Um widget partilhado aparece em todas as apps que o usam.
5. Se nada disto der, o ficheiro é ignorado e fica contado no resumo.

## Limites (o que o script NÃO apanha)
- Textos montados em runtime: variáveis, funções, listas geradas com `map(...)`, textos que vêm da base de dados.
- Linhas de resumo e etiquetas que não são botão nem menu (por exemplo "Desconto (tokens)" no checkout):
  não entram, porque não são ação nem navegação.
- Botões condicionais: o script não sabe `if (role == cliente)`. Um ecrã partilhado (perfil, login) fica na app do cliente.
- Botões e diálogos criados dentro de `lib/services/` e ficheiros sem classe de widget são ignorados (vêm no resumo).
- Rota: só as de `routes: {...}` e as do menu do admin (`menu:<id>`). Ecrãs abertos por `Navigator.push` ficam sem rota.
- Os parênteses/chavetas são lidos por contagem, sem interpretar o Dart todo: um ficheiro com Dart muito invulgar pode perder um botão.
- Textos em inglês não entram: o português é a própria chave de tradução (`'Texto'.tr`).
- Os botões próprios do projeto são descobertos pelo nome da classe (Button/Botao/Chip/Tile/Separador) e por ter um campo
  `label`, `texto` ou `titulo`; botões com outro nome ou outro campo ficam de fora.
