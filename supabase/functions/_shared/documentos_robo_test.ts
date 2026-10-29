// deno test --allow-env supabase/functions/_shared/documentos_robo_test.ts
// Peças puras do robô "fiscal de documentos". Sem rede, sem chaves, sem dados reais:
// os nomes e NIFs aqui são inventados.
import {
  decidir,
  detetarMime,
  type EntradaDecisao,
  lerResposta,
  type Leitura,
  nifBate,
  nomeBate,
  paraBase64,
  promptDoDocumento,
  sha256Hex,
} from './documentos_robo.ts';

function afirmar(cond: boolean, msg: string) {
  if (!cond) throw new Error(msg);
}

const leitura = (o: Partial<Leitura>): Leitura => ({
  tipo_detectado: 'comprovativo_atividade_AT',
  legivel: true,
  nome_lido: 'Maria Teste Silva',
  nif_lido: '123456789',
  validade: null,
  cara_nitida: null,
  confianca: 0.97,
  ...o,
});

const entrada = (o: Partial<EntradaDecisao>): EntradaDecisao => ({
  esperado: 'comprovativo_atividade_AT',
  leitura: leitura({}),
  nomeConta: 'Maria Teste Silva',
  nifConta: '123456789',
  confiancaMin: 0.85,
  hoje: '2026-10-29',
  ...o,
});

Deno.test('comprovativo certo, nome e NIF batem -> ok', () => {
  const v = decidir(entrada({}));
  afirmar(v.decisao === 'ok', `esperava ok, deu ${v.decisao}`);
  afirmar(v.nome_bate === true && v.nif_bate === true, 'nome e NIF deviam bater');
});

Deno.test('cartão de cidadão no lugar do comprovativo -> errado, com a frase certa', () => {
  const v = decidir(entrada({ leitura: leitura({ tipo_detectado: 'cartao_cidadao' }) }));
  afirmar(v.decisao === 'errado', `esperava errado, deu ${v.decisao}`);
  afirmar(
    v.motivo_pt === 'Enviaste o cartão de cidadão no lugar do comprovativo de atividade das Finanças. Envia o comprovativo de atividade das Finanças.',
    `motivo inesperado: ${v.motivo_pt}`,
  );
});

Deno.test('folha de empresa (outro) no lugar do comprovativo -> errado', () => {
  const v = decidir(entrada({ leitura: leitura({ tipo_detectado: 'outro', nome_lido: null, nif_lido: null }) }));
  afirmar(v.decisao === 'errado', 'folha qualquer devia ser errado');
  afirmar(v.motivo_pt.startsWith('O ficheiro que enviaste não é o comprovativo'), v.motivo_pt);
});

Deno.test('errado com pouca confiança vira dúvida (fica para o Danilo)', () => {
  const v = decidir(entrada({ leitura: leitura({ tipo_detectado: 'outro', confianca: 0.6 }) }));
  afirmar(v.decisao === 'duvida', `esperava duvida, deu ${v.decisao}`);
});

Deno.test('ilegível com confiança alta -> errado; com pouca -> dúvida', () => {
  afirmar(decidir(entrada({ leitura: leitura({ legivel: false }) })).decisao === 'errado', 'ilegivel alto');
  afirmar(decidir(entrada({ leitura: leitura({ legivel: false, confianca: 0.4 }) })).decisao === 'duvida', 'ilegivel baixo');
});

Deno.test('NIF que não bate -> dúvida, nunca errado sozinho', () => {
  const v = decidir(entrada({ leitura: leitura({ nif_lido: '987654321' }) }));
  afirmar(v.decisao === 'duvida', `esperava duvida, deu ${v.decisao}`);
  afirmar(v.nif_bate === false, 'nif_bate devia ser false');
});

Deno.test('nome diferente -> dúvida', () => {
  const v = decidir(entrada({ leitura: leitura({ nome_lido: 'Joaquim Outro Nome' }) }));
  afirmar(v.decisao === 'duvida' && v.nome_bate === false, 'nome diferente devia dar duvida');
});

Deno.test('documento de identificação: passaporte serve, carta é dúvida, fora de prazo é errado', () => {
  const base = { esperado: 'documento_identificacao' as const };
  afirmar(decidir(entrada({ ...base, leitura: leitura({ tipo_detectado: 'passaporte' }) })).decisao === 'ok', 'passaporte');
  afirmar(decidir(entrada({ ...base, leitura: leitura({ tipo_detectado: 'carta_conducao' }) })).decisao === 'duvida', 'carta');
  const v = decidir(entrada({ ...base, leitura: leitura({ tipo_detectado: 'cartao_cidadao', validade: '2024-01-31' }) }));
  afirmar(v.decisao === 'errado', 'caducado');
});

Deno.test('selfie: rosto nítido ok; sem rosto errado; nada de nome/NIF para comparar', () => {
  const ok = decidir(entrada({
    esperado: 'selfie',
    leitura: leitura({ tipo_detectado: 'selfie', nome_lido: null, nif_lido: null, cara_nitida: true }),
  }));
  afirmar(ok.decisao === 'ok' && ok.nome_bate === null && ok.nif_bate === null, 'selfie ok');
  const mau = decidir(entrada({
    esperado: 'selfie',
    leitura: leitura({ tipo_detectado: 'selfie', nome_lido: null, nif_lido: null, cara_nitida: false }),
  }));
  afirmar(mau.decisao === 'errado', 'selfie sem rosto');
});

Deno.test('nome e NIF: compara sem acentos nem partículas; null quando falta um lado', () => {
  afirmar(nomeBate('José da Silva Pereira', 'JOSE SILVA PEREIRA') === true, 'acentos e partículas');
  afirmar(nomeBate('Ana', 'Ana') === true, 'nome simples');
  afirmar(nomeBate('Ana Costa', null) === null, 'falta lido');
  afirmar(nomeBate('Ana Costa', 'Rui Pinto') === false, 'diferente');
  afirmar(nifBate('123 456 789', '123456789') === true, 'nif com espaços');
  afirmar(nifBate('123456789', '12345') === null, 'nif incompleto não compara');
});

Deno.test('formato pelos primeiros bytes', () => {
  const pdf = new TextEncoder().encode('%PDF-1.7 corpo qualquer');
  const jpg = Uint8Array.from([0xff, 0xd8, 0xff, 0xe0, 0, 0, 0, 0, 0, 0, 0, 0, 0]);
  const png = Uint8Array.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0, 0, 0, 0]);
  const txt = new TextEncoder().encode('isto não é um documento');
  afirmar(detetarMime(pdf) === 'application/pdf', 'pdf');
  afirmar(detetarMime(jpg) === 'image/jpeg', 'jpg');
  afirmar(detetarMime(png) === 'image/png', 'png');
  afirmar(detetarMime(txt) === null, 'texto');
});

Deno.test('resposta do modelo: JSON estrito ou nada', () => {
  const boa = { candidates: [{ content: { parts: [{ text: JSON.stringify({ tipo_detectado: 'passaporte', legivel: true, confianca: 1.4 }) }] } }] };
  const l = lerResposta(boa);
  afirmar(l !== null && l.tipo_detectado === 'passaporte' && l.confianca === 1, 'confiança limitada a 1');
  afirmar(lerResposta({ candidates: [{ content: { parts: [{ text: 'não é json' }] } }] }) === null, 'lixo');
  afirmar(lerResposta({ candidates: [{ content: { parts: [{ text: '{"tipo_detectado":"inventado","legivel":true}' }] } }] }) === null, 'tipo inventado');
});

Deno.test('base64 e hash', async () => {
  afirmar(paraBase64(new TextEncoder().encode('bora')) === 'Ym9yYQ==', 'base64');
  afirmar((await sha256Hex(new TextEncoder().encode('abc'))).startsWith('ba7816bf'), 'sha256');
});

Deno.test('o pedido ao modelo proíbe biometria e injeção', () => {
  const p = promptDoDocumento('selfie');
  afirmar(p.includes('NÃO compares rostos'), 'sem biometria');
  afirmar(p.includes('ignora-o por completo'), 'sem injeção');
});
