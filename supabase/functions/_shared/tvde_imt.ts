// Integração com as bases de dados do IMT (Lei 45/2018 na versão da Lei
// 59/2026, arts. 17.º-A n.º 2 a), 20.º n.os 5–7 e 20.º-A).
//
// Estado a 30/09/2026: o IMT NÃO publicou especificação técnica nem API
// pública; a portaria que regula a partilha de dados ainda não saiu (a
// pesquisa da missão tvde-conformidade-lei-59-2026 confirmou-o). Por isso só
// existe a interface e um adaptador "aguarda IMT" que nunca diz que um
// documento é válido — devolve sempre `aguarda_imt`, e a verificação continua
// a ser a do admin no painel. Quando o IMT publicar, implementa-se um novo
// adaptador com a mesma interface e liga-se `tvde_imt_integration_enabled`.

export type EstadoImt = "valido" | "invalido" | "nao_encontrado" | "aguarda_imt" | "erro";

export interface RespostaImt {
  estado: EstadoImt;
  validade?: string | null;
  detalhe?: string;
  consultadoEm: string;
}

export interface AdaptadorImt {
  readonly nome: string;
  verificarMotorista(cmtvde: string): Promise<RespostaImt>;
  verificarVeiculo(matricula: string): Promise<RespostaImt>;
  verificarOperador(nipc: string): Promise<RespostaImt>;
}

export function normalizarMatricula(m: string): string {
  return m.toUpperCase().replace(/[^A-Z0-9]/g, "");
}

export class AdaptadorAguardaImt implements AdaptadorImt {
  readonly nome = "aguarda_imt";
  private resposta(detalhe: string): Promise<RespostaImt> {
    return Promise.resolve({
      estado: "aguarda_imt",
      detalhe,
      consultadoEm: new Date().toISOString(),
    });
  }
  verificarMotorista(cmtvde: string) {
    return this.resposta(`CMTVDE ${cmtvde.trim()}: especificação do IMT ainda não publicada`);
  }
  verificarVeiculo(matricula: string) {
    return this.resposta(`Veículo ${normalizarMatricula(matricula)}: especificação do IMT ainda não publicada`);
  }
  verificarOperador(nipc: string) {
    if (!/^[0-9]{9}$/.test(nipc.trim())) {
      return Promise.resolve({ estado: "erro" as const, detalhe: "nipc_invalido", consultadoEm: new Date().toISOString() });
    }
    return this.resposta(`Operador ${nipc.trim()}: especificação do IMT ainda não publicada`);
  }
}

export function escolherAdaptadorImt(_ativo: boolean): AdaptadorImt {
  // Sem especificação oficial não há outro adaptador — mesmo com o
  // interruptor ligado, fica o "aguarda IMT".
  return new AdaptadorAguardaImt();
}
