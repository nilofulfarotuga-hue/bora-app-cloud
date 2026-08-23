/// Preview pública da categoria **Festas**.
///
/// Ligada só por `--dart-define=FESTAS_PREVIEW=true`. Num build normal
/// (Play Store, bora-app-web) isto é `false` e nada muda: a app arranca como
/// sempre, pelo `RoleScreen`.
///
/// O que muda quando está ligada:
///   • a app abre directamente na categoria Festas, sem escolher perfil nem
///     iniciar sessão (o voltar leva ao início normal do cliente);
///   • nada mais. Preços, taxas e as guardas do servidor ficam iguais.
const bool kFestasPreview =
    bool.fromEnvironment('FESTAS_PREVIEW', defaultValue: false);
