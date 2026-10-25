# DSA / estatuto de comerciante — ciclo, quando reenviar
> Referência de `apple-conta-e-loja`; carregar só quando o SKILL.md mandar.

## 3. O ciclo do estatuto de comerciante (DSA) e o que a verificação exige
- Fluxo oficial (página da Apple, lida 16/09): contacto (morada/telefone/email) → validar
  email por código → validar **telefone por código** (verificação manual só se o número não
  receber códigos) → **documento actual que prove nome e morada** ("business or legal
  records") → rever → Confirmar. **Todos os comerciantes** dão dados da conta de pagamento se
  ainda não estiverem no App Store Connect; art. 30(1)(c) do DSA exige-os.
- A verificação compara **letra a letra**: nome do formulário = nome do documento = nome da
  inscrição; morada com número **e andar**; código postal. Um extracto bancário com o nome
  sem o "da" e um formulário sem o andar foram a inconsistência de 08/09.
- Documento certo para pessoa singular em Portugal: **Certidão de Domicílio Fiscal** do
  Portal das Finanças (Obter → Certidões → Efectuar Pedido → tipo "Domicílio Fiscal (Morada)";
  o PDF sai na hora, **bilingue PT/EN**, com código de validação). Complemento: título de
  residência frente/verso. O comprovativo de actividade não está nesse menu (fica opcional).
- Estados vistos no App Store Connect: "Em revisão" (13/09→) **sem botão** — não se edita nem
  se carrega nada; o link "Resubmit" do email só abre `/business`. A saída é o **suporte por
  escrito** (`developer.apple.com/contact` → App Setup → Availability and Pricing → Email),
  que devolve um Case ID e, quando precisa, um **link seguro** para o documento (fórum 818212,
  759771). Fila normal 1–3 semanas; há casos de >1 mês.
- Telefone: escolher **sempre** o código SMS. A verificação manual de 08/09 mandou documentos
  que não mostram o número — não tinha como ser verificada.

## 4. Quando reenviar e quando NÃO
- Reenviar só com **erro concreto provado** no que está em revisão, e **uma vez**. Reenviar
  às cegas volta ao fim da fila e repete a falha (o reenvio de 13/09 corrigiu o andar mas
  levou o mesmo documento com o nome errado).
- Se o que está em revisão já está certo → **não reenviar**; só o caso escrito a pedir o
  ponto de situação e o link seguro.
- Nunca declarar "não comerciante" para desbloquear: é falso (actividade aberta, a app é
  negócio) e a Apple remove a app. Nunca tirar a app de venda, mexer no Brasil, criar versão
  nova nem reenviar para revisão por causa do DSA — o bloqueio é da conta, não da app.
