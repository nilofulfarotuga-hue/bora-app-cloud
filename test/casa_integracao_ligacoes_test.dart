// CASA (missão casa-manutencao-2026-10-30): as ligações que só se vêem no
// código. Regra 1.18 do PADRAO_BORA: onde havia "lavagem ? x : limpeza" passa a
// haver um caso por papel, e a Casa tem o seu — nunca cai no ramo por omissão.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _ler(String p) => File(p).readAsStringSync();

void main() {
  test('tocar num aviso da Casa abre o ecrã do profissional (caso explícito)',
      () {
    final m = _ler('lib/main.dart');
    expect(m, contains("'casa' => const HandymanHomeScreen()"),
        reason: 'o ramo por omissão do abrirTrabalho é a Lavagem');
    expect(m, contains('ChangeNotifierProvider<CasaStore>('));
    expect(m, contains('ChangeNotifierProvider<HandymanStore>('));
    expect(m, contains('context.read<CasaStore>().refreshTracked();'));
  });

  test('o portão do prestador abre a Casa como entrada', () {
    final p = _ler('lib/widgets/portao_do_prestador.dart');
    expect(p,
        contains('EntradaDoPrestador.casa => const HandymanHomeScreen(comoEntrada: true)'));
    expect(p, contains('EntradaDoPrestador.casa => r?.handymanApproved'));
  });

  test('quem só faz Casa entra pela porta de quem trabalha', () {
    expect(_ler('lib/auth/auth_store.dart'), contains('!papeis.handymanApproved'));
    expect(_ler('lib/screens/driver_login_screen.dart'),
        contains('papeis.handymanApproved'));
  });

  test('o ladrilho Casa só aparece com a categoria aberta', () {
    final h = _ler('lib/screens/client_home_screen.dart');
    expect(h, contains('if (context.watch<CasaStore>().enabled)'));
    expect(h, contains('AppColors.tileCasa'));
    expect(h, contains("'Casa e\\nManutenção': 'tile_casa'"));
    expect(h, contains('const CasaCategoriaScreen()'));
    // Logo a seguir à Limpeza, antes da Lavagem Auto.
    expect(h.indexOf("label: 'Limpeza'"), lessThan(h.indexOf("label: 'Casa e\\nManutenção'")));
    expect(h.indexOf("label: 'Casa e\\nManutenção'"),
        lessThan(h.indexOf("label: 'Lavagem Auto'.tr")));
  });

  test('o atalho do trabalho em curso e a troca de papel conhecem a Casa', () {
    expect(_ler('lib/widgets/atalho_trabalho_em_curso.dart'),
        contains("'casa' => const HandymanHomeScreen()"));
    final troca = _ler('lib/widgets/trocar_de_papel.dart');
    expect(troca, contains("'handyman' => const HandymanHomeScreen()"));
    expect(troca, isNot(contains("d.papel == 'washer'\n")));
    final botao = _ler('lib/widgets/profile_switcher_button.dart');
    expect(botao, contains("'handyman' => 'casa'"));
    expect(botao, contains("'handyman' => const HandymanHomeScreen()"));
    expect(botao, isNot(contains("papel == 'washer' ? 'lavagem' : 'limpeza'")));
  });

  test('o último modo "casa" grava-se', () {
    expect(_ler('lib/stores/session_store.dart'),
        contains("{'estafeta', 'limpeza', 'lavagem', 'casa'}"));
  });

  test('os baldes privados da Casa abrem-se por URL assinado', () {
    final b = _ler('lib/widgets/private_bucket_image.dart');
    expect(b, contains("'handyman-documents'"));
    expect(b, contains("'casa-fotos'"));
  });

  test('o reenvio da Casa grava pela RPC do contrato e no balde dela', () {
    final r = _ler('lib/services/prestador_reenvio_service.dart');
    expect(r, contains("'casa_registar_documento'"));
    expect(r, contains("'handyman' => ProviderUploadService.bucketCasa"));
    expect(
        r,
        isNot(contains("papel == 'cleaner'\n"
            "              ? ProviderUploadService.bucketFaxineiro")),
        reason: 'o ternário de dois lados mandava a Casa para o balde da lavagem');
  });

  test('o perfil tem o atalho "A minha Casa" nas duas cópias do bloco', () {
    final p = _ler('lib/screens/profile_screen.dart');
    expect("'A minha Casa'.tr".allMatches(p).length, 2);
    expect('if (_roles.hasHandyman)'.allMatches(p).length, 2);
  });

  test('a pesquisa mostra a Casa só com a categoria aberta', () {
    final s = _ler('lib/screens/global_search_screen.dart');
    expect(s, contains("'casa' => Icons.handyman_outlined"));
    expect(s, contains("k != 'casa' || casa"));
  });

  test('os ganhos dão nome de gente ao papel handyman', () {
    expect(_ler('lib/screens/ganhos_screen.dart'),
        contains("'handyman' => 'Casa e manutenção'"));
  });
}
