// deno test supabase/functions/_shared/tvde_conformidade_test.ts
import { assertEquals } from "jsr:@std/assert@1";
import {
  FornecedorInvoiceXpress,
  FornecedorStub,
  escolherFornecedor,
  pedidoDoResumo,
  validarPedido,
} from "./tvde_faturacao.ts";
import { AdaptadorAguardaImt, escolherAdaptadorImt, normalizarMatricula } from "./tvde_imt.ts";

const resumo = {
  ride_id: "e9e285cc-a814-496d-ade0-e8b6dfdae53e",
  codigo_viagem: "E9E285CCA814496DADE0E8B6DFDAE53E",
  data: "2026-09-30T10:00:00Z",
  origem: "Guarda Gare",
  destino: "Hospital",
  distancia_km: 3.2,
  duracao_min: 9,
  total_pago_cents: 500,
};

Deno.test("stub nunca inventa número nem ATCUD", async () => {
  const r = await new FornecedorStub().emitir(pedidoDoResumo(resumo, 6));
  assertEquals(r.estado, "pendente");
  assertEquals(r.modo, "stub");
  assertEquals(r.numero, undefined);
  assertEquals(r.atcud, undefined);
  assertEquals(r.erro, "sem_empresa_nem_software_certificado");
});

Deno.test("fornecedor desconhecido cai no stub", () => {
  assertEquals(escolherFornecedor("xpto", { get: () => undefined }).nome, "stub");
});

Deno.test("pedido com todos os campos da viagem", () => {
  const p = pedidoDoResumo(resumo, 6);
  assertEquals(p.codigoViagem, "E9E285CCA814496DADE0E8B6DFDAE53E");
  assertEquals(p.distanciaKm, 3.2);
  assertEquals(p.duracaoMin, 9);
  assertEquals(p.linhas[0].valorCents, 500);
  assertEquals(p.linhas[0].ivaPct, 6);
  assertEquals(validarPedido(p), null);
});

Deno.test("validação recusa NIF errado e viagem a 0 €", () => {
  assertEquals(validarPedido({ ...pedidoDoResumo(resumo, 6), clienteNif: "123" }), "nif_cliente_invalido");
  assertEquals(validarPedido(pedidoDoResumo({ ...resumo, total_pago_cents: 0 }, 6)), "sem_linhas");
});

Deno.test("InvoiceXpress sem credenciais falha com motivo claro, sem chamar a rede", async () => {
  let chamou = false;
  const f = new FornecedorInvoiceXpress(undefined, undefined, "teste", (() => {
    chamou = true;
    return Promise.reject(new Error("não devia chamar"));
  }) as typeof fetch);
  const r = await f.emitir(pedidoDoResumo(resumo, 6));
  assertEquals(r.estado, "falhou");
  assertEquals(r.erro, "sem_credenciais");
  assertEquals(chamou, false);
});

Deno.test("InvoiceXpress: preço sem IVA e número devolvido", async () => {
  let corpo: any = null;
  const f = new FornecedorInvoiceXpress("conta", "chave", "teste", ((_u: string, init: RequestInit) => {
    corpo = JSON.parse(String(init.body));
    return Promise.resolve(new Response(JSON.stringify({
      invoice_receipt: { sequence_number: "FR 1/2026", atcud: "ABCD1234-1", permalink: "https://x" },
    }), { status: 201 }));
  }) as typeof fetch);
  const r = await f.emitir(pedidoDoResumo(resumo, 6));
  assertEquals(corpo.invoice_receipt.items[0].unit_price, "4.7170");
  assertEquals(corpo.invoice_receipt.client.code, "999999990");
  assertEquals(r.estado, "emitida");
  assertEquals(r.atcud, "ABCD1234-1");
});

Deno.test("IMT: aguarda especificação, nunca diz válido", async () => {
  const a = escolherAdaptadorImt(true);
  assertEquals(a.nome, "aguarda_imt");
  assertEquals((await a.verificarMotorista("123456")).estado, "aguarda_imt");
  assertEquals((await a.verificarVeiculo("aa-12-bb")).estado, "aguarda_imt");
  assertEquals((await new AdaptadorAguardaImt().verificarOperador("12")).estado, "erro");
  assertEquals(normalizarMatricula("aa-12 bb"), "AA12BB");
});
