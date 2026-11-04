// Linha do prémio do check-in no pedido (04/11/2026).
//
// O artigo do prémio entra no carrinho com o nome "Prémio Bora Todo Dia: …"
// e vale 0 € ao cliente. O servidor (finalize_storeshopping_purchase_v2)
// reconhece-o pelo mesmo prefixo do nome e devolve ao estafeta o que ele pagou
// no balcão. Por isso a app usa a mesma regra para destacar a linha e esconder
// os botões que mexem no total do cliente.

const String prefixoPremioCheckin = 'Prémio Bora Todo Dia';

/// O artigo-prémio entra no carrinho com o id `premio-checkin-…`.
const String prefixoIdPremioCheckin = 'premio-checkin-';

bool ehLinhaPremioCheckin(String nome, {String productId = ''}) =>
    productId.startsWith(prefixoIdPremioCheckin) ||
    nome.trimLeft().toLowerCase().startsWith(prefixoPremioCheckin.toLowerCase());
