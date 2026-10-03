// Faturação TVDE (Lei 45/2018 na versão da Lei 59/2026, art. 15.º n.º 8).
//
// A fatura só pode sair de software CERTIFICADO pela AT (ATCUD + código QR,
// comunicação e-fatura, SAF-T). O Bora ainda não tem empresa, por isso o
// fornecedor por defeito é o STUB: nunca inventa número, ATCUD nem QR — devolve
// "pendente" com o motivo. Um "Resumo da viagem" gerado pelo Bora NUNCA é
// apresentado como fatura.
//
// Para ligar um fornecedor real: platform_settings.tvde_invoicing_provider =
// 'invoicexpress' (ou outro) + segredos nas Edge Functions, e só depois
// tvde_invoicing_enabled = true (ver relatório tvde-interruptores-dia-da-licenca).

export interface LinhaFatura {
  descricao: string;
  valorCents: number; // com IVA incluído
  ivaPct: number;
}

export interface PedidoFatura {
  rideId: string;
  codigoViagem: string;
  data: string; // ISO
  clienteNome?: string | null;
  clienteNif?: string | null;
  clienteEmail?: string | null;
  origem: string;
  destino: string;
  distanciaKm: number | null;
  duracaoMin: number | null;
  linhas: LinhaFatura[];
}

export interface ResultadoFatura {
  estado: "pendente" | "emitida" | "falhou";
  modo: "stub" | "teste" | "producao";
  fornecedor: string;
  numero?: string;
  atcud?: string;
  documentoUrl?: string;
  erro?: string;
}

export interface FornecedorFaturacao {
  readonly nome: string;
  emitir(pedido: PedidoFatura): Promise<ResultadoFatura>;
}

/** Valida o pedido antes de o mandar a qualquer fornecedor. */
export function validarPedido(p: PedidoFatura): string | null {
  if (!p.rideId) return "sem_viagem";
  if (!p.linhas.length) return "sem_linhas";
  for (const l of p.linhas) {
    if (!Number.isInteger(l.valorCents) || l.valorCents < 0) return "valor_invalido";
    if (l.ivaPct < 0 || l.ivaPct > 23) return "iva_invalido";
  }
  if (p.clienteNif && !/^[0-9]{9}$/.test(p.clienteNif)) return "nif_cliente_invalido";
  return null;
}

/** Sem empresa: não emite nada, não inventa números. */
export class FornecedorStub implements FornecedorFaturacao {
  readonly nome = "stub";
  emitir(p: PedidoFatura): Promise<ResultadoFatura> {
    const erro = validarPedido(p);
    return Promise.resolve({
      estado: erro ? "falhou" : "pendente",
      modo: "stub",
      fornecedor: this.nome,
      erro: erro ?? "sem_empresa_nem_software_certificado",
    });
  }
}

/**
 * InvoiceXpress (software certificado pela AT). Esqueleto pronto: precisa de
 * INVOICEXPRESS_ACCOUNT e INVOICEXPRESS_API_KEY; sem eles falha com motivo
 * claro. `modo` 'teste' usa a conta de testes da InvoiceXpress.
 * Documento: fatura-recibo (pagamento já feito na app).
 */
export class FornecedorInvoiceXpress implements FornecedorFaturacao {
  readonly nome = "invoicexpress";
  constructor(
    private readonly conta: string | undefined,
    private readonly chave: string | undefined,
    private readonly modo: "teste" | "producao",
    private readonly fetcher: typeof fetch = fetch,
  ) {}

  async emitir(p: PedidoFatura): Promise<ResultadoFatura> {
    const base = { modo: this.modo, fornecedor: this.nome } as const;
    const erro = validarPedido(p);
    if (erro) return { ...base, estado: "falhou", erro };
    if (!this.conta || !this.chave) return { ...base, estado: "falhou", erro: "sem_credenciais" };
    const corpo = {
      invoice_receipt: {
        date: p.data.slice(0, 10).split("-").reverse().join("/"),
        due_date: p.data.slice(0, 10).split("-").reverse().join("/"),
        reference: p.codigoViagem,
        observations: `Viagem TVDE ${p.origem} → ${p.destino}` +
          (p.distanciaKm != null ? ` · ${p.distanciaKm} km` : "") +
          (p.duracaoMin != null ? ` · ${p.duracaoMin} min` : ""),
        client: {
          name: p.clienteNome || "Consumidor final",
          code: p.clienteNif || "999999990",
          fiscal_id: p.clienteNif || undefined,
          email: p.clienteEmail || undefined,
        },
        items: p.linhas.map((l) => ({
          name: l.descricao,
          unit_price: (l.valorCents / 100 / (1 + l.ivaPct / 100)).toFixed(4),
          quantity: 1,
          tax: { name: `IVA${l.ivaPct}` },
        })),
      },
    };
    const url = `https://${this.conta}.app.invoicexpress.com/invoice_receipts.json?api_key=${this.chave}`;
    try {
      const r = await this.fetcher(url, {
        method: "POST",
        headers: { "Content-Type": "application/json", Accept: "application/json" },
        body: JSON.stringify(corpo),
      });
      const j = await r.json().catch(() => ({}));
      if (!r.ok) return { ...base, estado: "falhou", erro: `http_${r.status}` };
      const doc = j?.invoice_receipt ?? {};
      // O número e o ATCUD só existem depois de o documento ser finalizado
      // (passo seguinte da API); até lá fica pendente.
      return {
        ...base,
        estado: doc.inverted_sequence_number || doc.sequence_number ? "emitida" : "pendente",
        numero: doc.inverted_sequence_number ?? doc.sequence_number ?? undefined,
        atcud: doc.atcud ?? undefined,
        documentoUrl: doc.permalink ?? undefined,
      };
    } catch (e) {
      return { ...base, estado: "falhou", erro: String(e).slice(0, 200) };
    }
  }
}

export function escolherFornecedor(
  nome: string,
  env: { get(k: string): string | undefined },
): FornecedorFaturacao {
  switch (nome) {
    case "invoicexpress":
      return new FornecedorInvoiceXpress(
        env.get("INVOICEXPRESS_ACCOUNT"),
        env.get("INVOICEXPRESS_API_KEY"),
        env.get("INVOICEXPRESS_MODO") === "producao" ? "producao" : "teste",
      );
    default:
      return new FornecedorStub();
  }
}

/** Monta o pedido a partir do "Resumo da viagem" (_tvde_recibo). */
export function pedidoDoResumo(resumo: Record<string, unknown>, ivaPct: number): PedidoFatura {
  const total = Number(resumo["total_pago_cents"] ?? 0);
  return {
    rideId: String(resumo["ride_id"] ?? ""),
    codigoViagem: String(resumo["codigo_viagem"] ?? resumo["numero"] ?? ""),
    data: String(resumo["data"] ?? new Date().toISOString()),
    origem: String(resumo["origem"] ?? ""),
    destino: String(resumo["destino"] ?? ""),
    distanciaKm: resumo["distancia_km"] == null ? null : Number(resumo["distancia_km"]),
    duracaoMin: resumo["duracao_min"] == null ? null : Number(resumo["duracao_min"]),
    linhas: total > 0 ? [{ descricao: "Transporte em veículo descaracterizado (TVDE)", valorCents: total, ivaPct }] : [],
  };
}
