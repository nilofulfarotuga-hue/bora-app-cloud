// Prova pelo endereço público que a web já serve o código novo (ronda 04/10, fecho 05/10).
// Olha para o CORPO, não para o código de resposta (o Pages devolve 200 para tudo), e
// compara o endereço limpo com o de quebra-cache: se diferirem, é cache e diz-se.
// Tem de dar "antigo: true / novo: false" antes do deploy e o contrário depois.
//   node prova_web_publicada.mjs
const sitios = ['https://app.boraguarda.com', 'https://bora-app-web.pages.dev'];
const novo = [
  'carrinho_guardar', 'carrinho_convertido', 'driver_heartbeat_segredo_obter',
  'rascunho_pagamento_excluido', 'O estafeta deixa o pedido à tua porta',
  'Chamar estafeta por aqui ainda não está disponível',
];
const antigo = ['quando estiver pronto. (BR §14.9)'];

// O dart2js escreve os acentos como \xNN (ou \uNNNN): procura-se das duas maneiras.
const comoNoBundle = (frase) => frase.replace(/[^\x00-\x7f]/g, (c) => {
  const n = c.charCodeAt(0);
  return n < 256 ? '\\x' + n.toString(16).padStart(2, '0') : '\\u' + n.toString(16).padStart(4, '0');
});
const tem = (t, frase) => t.includes(frase) || t.includes(comoNoBundle(frase));

async function ler(url) {
  const r = await fetch(url, { headers: { 'Cache-Control': 'no-cache' } });
  const t = await r.text();
  return { http: r.status, texto: t, bytes: Buffer.byteLength(t) };
}

for (const s of sitios) {
  try {
    const limpo = await ler(`${s}/main.dart.js`);
    const quebrado = await ler(`${s}/main.dart.js?prova=${Date.now()}`);
    const ehJs = limpo.texto.includes('dart') && limpo.bytes > 1_000_000;
    console.log(`== ${s}/main.dart.js  http ${limpo.http}  ${limpo.bytes} bytes  é o bundle da app: ${ehJs}`);
    console.log(`   limpo e quebra-cache iguais: ${limpo.texto === quebrado.texto}`);
    for (const m of novo) console.log(`   novo   "${m}": ${tem(limpo.texto, m)}`);
    for (const m of antigo) console.log(`   antigo "${m}": ${tem(limpo.texto, m)}`);
  } catch (e) {
    console.log(`== ${s}: falhou a ler — ${String(e).slice(0, 120)}`);
  }
}
