/// URLs canónicas do fluxo de recuperação de palavra-passe.
///
/// ⚠️ URL CANÓNICA — NÃO RENOMEAR.
/// [passwordResetRedirect] fica gravada em três sítios fora do código:
///   1. Supabase Auth → URL Configuration → Redirect URLs (allow-list)
///   2. Supabase Auth → Email Templates → "Reset Password" (o `{{ .ConfirmationURL }}`)
///   3. Os emails já enviados a utilizadores reais, que continuam válidos 1h.
/// Mudá-la parte todos os links de recuperação em trânsito.
///
/// Porque é uma URL https e não o deep link `pt.boraapp.bora://`:
/// o deep link só funciona em telemóvel COM a app instalada. Um cliente que
/// abra o email no portátil, ou que tenha desinstalado a app, ficava sem
/// caminho nenhum. A página web funciona sempre, em qualquer dispositivo.
library;

/// Base do Bora no browser (mesmo codebase Flutter, Cloudflare Pages).
// 2026-08-28: passou para o dominio proprio. A allow-list do Supabase Auth
// foi actualizada NA MESMA PASSAGEM e continua a aceitar o endereco antigo,
// para os emails de recuperacao ja enviados nao morrerem.
const String boraWebBaseUrl = 'https://app.boraguarda.com';

/// Rota (hash) da página de redefinição de palavra-passe.
const String passwordResetRouteName = '/redefinir-palavra-passe';

/// Destino do `redirectTo` de `resetPasswordForEmail`.
const String passwordResetRedirect =
    '$boraWebBaseUrl/#$passwordResetRouteName';

/// Deep link legado (custom scheme). Continua declarado no AndroidManifest e
/// tratado em `main.dart`; mantido para os emails antigos que ainda apontem
/// para aqui não morrerem. Não usar em `redirectTo` novo.
const String passwordResetDeepLinkLegacy = 'pt.boraapp.bora://reset-password';
