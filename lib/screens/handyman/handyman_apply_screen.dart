import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../config/maps_config.dart';
import '../../l10n/tr.dart';
import '../../models/casa_models.dart';
import '../../services/legal_fields_service.dart';
import '../../services/place_autocomplete_service.dart';
import '../../services/provider_upload_service.dart';
import '../../services/push_token_service.dart';
import '../../stores/handyman_store.dart';
import '../../utils/io_compat.dart';
import '../../widgets/address_autocomplete_field.dart';
import '../../widgets/bora/bora.dart';
import '../../widgets/legal_fields_section.dart';
import '../shared/comprovativo_atividade_screen.dart';
import '../prestador/como_o_bora_decide_screen.dart';
import 'casa_camara.dart';
import 'handyman_disponibilidade_screen.dart';
import 'handyman_documentos_screen.dart' show pedirNumeroEValidade;

/// CASA — candidatura a profissional de Casa e manutenção (`casa_candidatura`).
/// Molde do `CleanerApplyScreen` (mesmo construtor, mesmo pré-preenchimento,
/// mesma gravação dos dados legais e o mesmo ecrã do comprovativo de
/// atividade no fim). O admin aprova a pessoa e cada ofício no painel.
class HandymanApplyScreen extends StatefulWidget {
  const HandymanApplyScreen({super.key, this.prefill});

  /// MULTI-PAPEL: dados comuns (name/phone/email/nif/photo_url) vindos de
  /// outro papel, para não obrigar a reescrever tudo.
  final Map<String, dynamic>? prefill;

  @override
  State<HandymanApplyScreen> createState() => _HandymanApplyScreenState();
}

/// Um documento escolhido no formulário, antes de ser enviado.
class _DocEscolhido {
  _DocEscolhido(this.ficheiro, {this.numero, this.validade});
  final XFile ficheiro;
  final String? numero;
  final DateTime? validade;
}

class _HandymanApplyScreenState extends State<HandymanApplyScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _nifCtrl = TextEditingController();
  final _bioCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  double _radiusKm = 15;
  ll.LatLng? _baseCoords;
  bool _temCarrinha = false;
  bool _temFerramentas = true;
  List<CasaSlot> _slots = const [];

  late final LegalFieldsController _legal =
      LegalFieldsController(nif: _nifCtrl);

  XFile? _photo;
  _DocEscolhido? _cartao;
  _DocEscolhido? _seguro;

  /// Documento exigido por ofício (fase 2), por código do ofício.
  final Map<String, _DocEscolhido> _docsOficio = {};
  final Set<String> _oficios = {};

  bool _uploading = false;

  // Retoma sem repetir o que já ficou gravado (a candidatura, cada
  // documento, os dados legais) — como o `_legalPending` da limpeza.
  bool _candidaturaFeita = false;
  final Set<String> _docsFeitos = {};

  String _prefillPhotoUrl = '';
  bool get _fromOtherRole => widget.prefill != null;

  @override
  void initState() {
    super.initState();
    final user = Supabase.instance.client.auth.currentUser;
    _emailCtrl.text = user?.email ?? '';
    final name = user?.userMetadata?['full_name'] ?? user?.userMetadata?['name'];
    if (name is String) _nameCtrl.text = name;
    final p = widget.prefill;
    if (p != null) {
      if ((p['name'] as String?)?.isNotEmpty == true) _nameCtrl.text = p['name'];
      if ((p['phone'] as String?)?.isNotEmpty == true) {
        _phoneCtrl.text = p['phone'];
      }
      if ((p['email'] as String?)?.isNotEmpty == true) {
        _emailCtrl.text = p['email'];
      }
      if ((p['nif'] as String?)?.isNotEmpty == true) _nifCtrl.text = p['nif'];
      _prefillPhotoUrl = (p['photo_url'] as String?) ?? '';
    }
    _legal.legalName.text = _nameCtrl.text;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<HandymanStore>().loadConfig();
    });
  }

  @override
  void dispose() {
    _legal.dispose();
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _nifCtrl.dispose();
    _bioCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  Future<void> _escolherFoto() async {
    final x = await casaTirarFoto(context,
        fonte: ImageSource.gallery, maxWidth: 1400, imageQuality: 85);
    if (x == null || !mounted) return;
    setState(() => _photo = x);
  }

  /// Escolhe a imagem de um documento e, quando o tipo leva, o número e a
  /// validade.
  Future<_DocEscolhido?> _escolherDocumento(String tipo) async {
    final fonte = await casaEscolherFonte(context);
    if (fonte == null || !mounted) return null;
    final x = await casaTirarFoto(context, fonte: fonte, imageQuality: 85);
    if (x == null || !mounted) return null;
    if (casaDocumentoPedeNumero(tipo) || tipo == 'cartao_cidadao') {
      final r = await pedirNumeroEValidade(context, tipo: tipo);
      if (r == null) return null;
      return _DocEscolhido(x, numero: r.numero, validade: r.validade);
    }
    return _DocEscolhido(x);
  }

  Future<ll.LatLng?> _resolveBaseCoords() async {
    if (_baseCoords != null) return _baseCoords;
    final addr = _addressCtrl.text.trim();
    if (addr.isEmpty) return null;
    final svc = createPlaceAutocompleteService(googleApiKey);
    try {
      return await svc.geocodeAddress(addr);
    } catch (e) {
      debugPrint('HandymanApply geocode falhou => $e');
      return null;
    } finally {
      svc.dispose();
    }
  }

  void _snack(String texto) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(texto)));

  /// Ofícios que a pessoa pode escolher: os da fase 1 abertos e os da fase 2
  /// (com a nota do documento).
  List<CasaOficio> _oficiosVisiveis(CasaConfig c) =>
      c.oficios.where((o) => o.fase >= 2 || o.ativo).toList();

  Future<void> _submit() async {
    if (_uploading) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final falta = await _legal.validateAndReveal();
    if (!mounted) return;
    if (falta != null) {
      _snack('Falta: {0}'.trArgs([falta]));
      return;
    }
    if (_photo == null && _prefillPhotoUrl.isEmpty) {
      _snack('Adiciona uma foto de perfil — os clientes escolhem pela foto.'.tr);
      return;
    }
    if (_cartao == null) {
      _snack('Anexa o cartão de cidadão.'.tr);
      return;
    }
    if (_seguro == null) {
      _snack('Anexa a apólice do seguro de acidentes de trabalho.'.tr);
      return;
    }
    if (_oficios.isEmpty) {
      _snack('Escolhe pelo menos um ofício.'.tr);
      return;
    }
    final config = context.read<HandymanStore>().config;
    for (final o in config.oficios) {
      final exigido = o.documentoExigido;
      if (!_oficios.contains(o.codigo) || exigido == null || exigido.isEmpty) {
        continue;
      }
      if (_docsOficio[o.codigo] == null) {
        _snack('Falta o documento de {0}.'.trArgs([o.nome]));
        return;
      }
    }

    final store = context.read<HandymanStore>();
    setState(() => _uploading = true);
    var stage = 'coords';
    try {
      if (!_candidaturaFeita) {
        final coords = await _resolveBaseCoords();
        if (!mounted) return;
        stage = 'uploads';
        final photoUrl = _photo != null
            ? await ProviderUploadService.uploadAvatar(_photo!)
            : _prefillPhotoUrl;
        if (!mounted) return;
        stage = 'candidatura';
        await store.candidatura(
          nome: _nameCtrl.text.trim(),
          telefone: _phoneCtrl.text.trim(),
          email: _emailCtrl.text.trim(),
          fotoUrl: photoUrl ?? '',
          bio: _bioCtrl.text.trim(),
          nif: _nifCtrl.text.trim(),
          moradaBase: _addressCtrl.text.trim(),
          baseLat: coords?.latitude,
          baseLng: coords?.longitude,
          raioKm: _radiusKm,
          temCarrinha: _temCarrinha,
          temFerramentas: _temFerramentas,
          oficios: _oficios.toList(),
          disponibilidade: _slots,
        );
        _candidaturaFeita = true;
        // O aparelho fica registado logo na candidatura (lição da limpeza,
        // 02/10/2026: aprovada sem abrir o painel = primeira oferta sem aviso).
        PushTokenService.registerForRole('handyman').ignore();
        if (!mounted) return;
      }

      stage = 'documentos';
      final envios = <({String chave, String tipo, String? oficio, _DocEscolhido doc})>[
        (chave: 'cartao_cidadao', tipo: 'cartao_cidadao', oficio: null, doc: _cartao!),
        (chave: 'seguro_acidentes', tipo: 'seguro_acidentes', oficio: null, doc: _seguro!),
        for (final o in config.oficios)
          if (_oficios.contains(o.codigo) &&
              (o.documentoExigido ?? '').isNotEmpty &&
              _docsOficio[o.codigo] != null)
            (
              chave: '${o.documentoExigido}_${o.codigo}',
              tipo: o.documentoExigido!,
              oficio: o.codigo,
              doc: _docsOficio[o.codigo]!,
            ),
      ];
      for (final e in envios) {
        if (_docsFeitos.contains(e.chave)) continue;
        await store.registarDocumento(
          ficheiro: e.doc.ficheiro,
          tipo: e.tipo,
          oficio: e.oficio,
          numero: e.doc.numero,
          validade: e.doc.validade,
          recarregarPerfil: false,
        );
        _docsFeitos.add(e.chave);
        if (!mounted) return;
      }

      stage = 'legal';
      await _legal.save('handyman');
      if (!mounted) return;
      _snack('Candidatura enviada! Vamos rever os teus dados e cada ofício.'.tr);
      _relerEmFundo(store);
      await ComprovativoAtividadeScreen.depoisDaCandidatura(context);
      if (!mounted) return;
      Navigator.pop(context);
    } on LegalFieldsException catch (e) {
      if (!mounted) return;
      debugPrint('HandymanApply legal FAILED code=${e.code} msg=${e.message}');
      _snack('{0} A candidatura já ficou registada — toca em "Enviar candidatura" para gravar os dados fiscais.'.trArgs([e.message]));
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString();
      String friendly;
      if (msg.contains('empty_file')) {
        friendly = 'Não foi possível ler a imagem. Tira ou escolhe a foto de novo.'.tr;
      } else if (stage == 'uploads' ||
          (stage == 'documentos' &&
              (e is StorageException || msg.contains('storage')))) {
        final detail =
            e is StorageException ? ' [${e.statusCode}: ${e.message}]' : '';
        friendly = 'Falha ao enviar a foto{0}. Tenta escolher ou tirar a foto de novo.'.trArgs([detail]);
      } else if (stage == 'documentos') {
        friendly = '{0} A candidatura já ficou registada — toca em "Enviar candidatura" para enviar os documentos que faltam.'.trArgs([casaErroTexto(e)]);
      } else {
        friendly = casaErroTexto(e);
      }
      debugPrint('HandymanApply submit FAILED stage=$stage error=$e');
      _snack(friendly);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  /// Relê o perfil em fundo (o ecrã principal mostra logo "Em análise").
  void _relerEmFundo(HandymanStore store) {
    store.loadProfile().ignore();
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<HandymanStore>();
    final oficios = _oficiosVisiveis(store.config);
    return Scaffold(
      appBar: BoraScreenAppBar(title: 'Ser profissional de Casa'.tr),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: EdgeInsets.fromLTRB(Spacing.lg, Spacing.lg, Spacing.lg,
              BoraBottomActionBar.folgaInferior(context)),
          children: [
            Text(
              'Faz pequenos trabalhos de casa perto de ti: montar móveis, pendurar e fixar, pequenas reparações, jardim e pequenas mudanças. Tu escolhes os ofícios, os dias e a zona.'.tr,
              style: const TextStyle(color: AppColors.textSecondary, height: 1.4),
            ),
            if (_fromOtherRole) ...[
              const SizedBox(height: Spacing.md),
              Container(
                padding: const EdgeInsets.all(Spacing.md),
                decoration: BoxDecoration(
                  color: AppColors.primaryWash,
                  borderRadius: BorderRadius.circular(Radii.md),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle,
                        color: AppColors.primary, size: 20),
                    const SizedBox(width: Spacing.sm),
                    Expanded(
                      child: Text(
                        'Já preenchemos os teus dados a partir do teu outro perfil. Só falta o que é da Casa.'.tr,
                        style: const TextStyle(
                            color: AppColors.textPrimary, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: Spacing.lg),
            Center(
              child: GestureDetector(
                onTap: _escolherFoto,
                child: CircleAvatar(
                  radius: 48,
                  backgroundColor: AppColors.primaryWash,
                  backgroundImage: _photo != null
                      ? boraLocalImage(_photo!.path)
                      : (_prefillPhotoUrl.isNotEmpty
                          ? NetworkImage(_prefillPhotoUrl)
                          : null),
                  child: (_photo == null && _prefillPhotoUrl.isEmpty)
                      ? const Icon(Icons.add_a_photo,
                          color: AppColors.primary, size: 28)
                      : null,
                ),
              ),
            ),
            const SizedBox(height: Spacing.xs),
            Center(
              child: Text('Foto de perfil *'.tr,
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 12)),
            ),
            const SizedBox(height: Spacing.lg),
            _DocTile(
              label: 'Cartão de cidadão *'.tr,
              picked: _cartao != null,
              onTap: () async {
                final d = await _escolherDocumento('cartao_cidadao');
                if (d != null && mounted) {
                  setState(() {
                    _cartao = d;
                    _docsFeitos.remove('cartao_cidadao');
                  });
                }
              },
            ),
            const SizedBox(height: Spacing.lg),
            TextFormField(
              controller: _nameCtrl,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                  labelText: 'Nome completo *'.tr,
                  prefixIcon: const Icon(Icons.person_outline)),
              validator: (v) =>
                  (v ?? '').trim().length < 3 ? 'Indica o teu nome.'.tr : null,
            ),
            const SizedBox(height: Spacing.md),
            TextFormField(
              controller: _phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                  labelText: 'Telemóvel *'.tr,
                  prefixIcon: const Icon(Icons.phone_outlined)),
              validator: (v) => (v ?? '').trim().length < 9
                  ? 'Indica um telemóvel válido.'.tr
                  : null,
            ),
            const SizedBox(height: Spacing.md),
            TextFormField(
              controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                  labelText: 'Email'.tr,
                  prefixIcon: const Icon(Icons.email_outlined)),
            ),
            const SizedBox(height: Spacing.lg),
            // NIF, nome legal, morada pessoal, IBAN, data de nascimento e
            // autocertificação (DSA art. 30 + DAC7) — mesmo bloco da limpeza.
            LegalFieldsSection(controller: _legal, enabled: !_uploading),
            const SizedBox(height: Spacing.lg),

            // ── Ofícios ──────────────────────────────────────────────────
            _Titulo('Os teus ofícios *'.tr),
            Text(
              'Cada ofício é aprovado à parte. Só recebes trabalhos dos ofícios aprovados.'.tr,
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: Spacing.sm),
            if (!store.configCarregada)
              const Padding(
                padding: EdgeInsets.all(Spacing.md),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (oficios.isEmpty)
              Row(
                children: [
                  Expanded(
                    child: Text(
                        'Não foi possível carregar os ofícios.'.tr,
                        style: const TextStyle(color: AppColors.textSecondary)),
                  ),
                  TextButton(
                    onPressed: store.loadConfig,
                    child: Text('Tentar de novo'.tr),
                  ),
                ],
              )
            else
              for (final o in oficios) ...[
                CheckboxListTile(
                  key: ValueKey('casa_oficio_${o.codigo}'),
                  value: _oficios.contains(o.codigo),
                  onChanged: _uploading
                      ? null
                      : (v) => setState(() {
                            if (v == true) {
                              _oficios.add(o.codigo);
                            } else {
                              _oficios.remove(o.codigo);
                            }
                          }),
                  title: Text(o.nome,
                      style: const TextStyle(color: AppColors.textPrimary)),
                  subtitle: Text(
                    [
                      if (o.descricao.trim().isNotEmpty) o.descricao.trim(),
                      if ((o.documentoExigido ?? '').isNotEmpty)
                        'Precisa de documento DGEG/IMPIC.'.tr,
                    ].join(' '),
                    style: const TextStyle(fontSize: 12.5),
                  ),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  activeColor: AppColors.primary,
                ),
                if (_oficios.contains(o.codigo) &&
                    (o.documentoExigido ?? '').isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(
                        left: Spacing.xl, bottom: Spacing.sm),
                    child: _DocTile(
                      label: '${casaNomeDocumento(o.documentoExigido!)} *',
                      picked: _docsOficio[o.codigo] != null,
                      onTap: () async {
                        final d = await _escolherDocumento(o.documentoExigido!);
                        if (d != null && mounted) {
                          setState(() {
                            _docsOficio[o.codigo] = d;
                            _docsFeitos
                                .remove('${o.documentoExigido}_${o.codigo}');
                          });
                        }
                      },
                    ),
                  ),
              ],
            const SizedBox(height: Spacing.lg),

            // ── Seguro ───────────────────────────────────────────────────
            _Titulo('Seguro de acidentes de trabalho *'.tr),
            Text(
              'Anexa a apólice. Pedimos o número e a validade para te avisar antes de caducar.'.tr,
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: Spacing.sm),
            _DocTile(
              label: 'Apólice do seguro *'.tr,
              picked: _seguro != null,
              detalhe: _seguro?.validade == null
                  ? null
                  : 'Válido até {0}'.trArgs([
                      '${casaDiaMes(_seguro!.validade!)}/${_seguro!.validade!.year}',
                    ]),
              onTap: () async {
                final d = await _escolherDocumento('seguro_acidentes');
                if (d != null && mounted) {
                  setState(() {
                    _seguro = d;
                    _docsFeitos.remove('seguro_acidentes');
                  });
                }
              },
            ),
            const SizedBox(height: Spacing.lg),

            // ── Zona ─────────────────────────────────────────────────────
            AddressAutocompleteField(
              controller: _addressCtrl,
              labelText: 'Zona base (morada ou localidade)'.tr,
              prefixIcon: const Icon(Icons.home_outlined),
              onSelected: (address, coords) {
                setState(() => _baseCoords = coords);
              },
              onChanged: (_) {
                if (_baseCoords != null) setState(() => _baseCoords = null);
              },
            ),
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 12),
              child: Text(
                'Escolhe uma sugestão para te mostrarmos trabalhos perto de ti.'.tr,
                style: const TextStyle(color: AppColors.textSubtle, fontSize: 12),
              ),
            ),
            const SizedBox(height: Spacing.lg),
            Text('Raio de serviço: {0} km'.trArgs([_radiusKm.round()]),
                style: const TextStyle(
                    fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
            Slider(
              value: _radiusKm,
              min: 5,
              max: 50,
              divisions: 9,
              activeColor: AppColors.primary,
              label: '${_radiusKm.round()} km',
              onChanged: (v) => setState(() => _radiusKm = v),
            ),
            const SizedBox(height: Spacing.md),

            // ── Carrinha e ferramentas ───────────────────────────────────
            SwitchListTile(
              value: _temCarrinha,
              onChanged: (v) => setState(() => _temCarrinha = v),
              title: Text('Tenho carrinha'.tr),
              subtitle: Text('Para pequenas mudanças e transporte de móveis.'.tr),
              activeThumbColor: AppColors.primary,
              contentPadding: EdgeInsets.zero,
            ),
            SwitchListTile(
              value: _temFerramentas,
              onChanged: (v) => setState(() => _temFerramentas = v),
              title: Text('Tenho as minhas ferramentas'.tr),
              subtitle: Text('Berbequim, chaves, nível, escada…'.tr),
              activeThumbColor: AppColors.primary,
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: Spacing.md),
            TextFormField(
              controller: _bioCtrl,
              maxLines: 3,
              maxLength: 300,
              decoration: InputDecoration(
                labelText: 'Apresentação (opcional)'.tr,
                hintText: 'Ex.: 10 anos a montar cozinhas, tenho escada e berbequim…'.tr,
              ),
            ),
            const SizedBox(height: Spacing.lg),

            // ── Disponibilidade ──────────────────────────────────────────
            _Titulo('A tua disponibilidade'.tr),
            Text(
              'Sem disponibilidade marcada não recebes ofertas. Podes mudar depois.'.tr,
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: Spacing.sm),
            CasaDisponibilidadeEditor(
              slots: _slots,
              enabled: !_uploading && !_candidaturaFeita,
              onChanged: (s) => setState(() => _slots = s),
            ),
            const SizedBox(height: Spacing.md),
            // [01/11/2026 · B8] Diretiva 2024/2831: como a app decide.
            const LigacaoComoOBoraDecide(),
            BoraPrimaryButton(
              label: _uploading ? 'A enviar…'.tr : 'Enviar candidatura'.tr,
              icon: Icons.send,
              loading: _uploading,
              onPressed: _submit,
            ),
            const SizedBox(height: Spacing.md),
            Text(
              'Depois de aprovado, ligas e desligas cada ofício no teu painel.'.tr,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSubtle, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _Titulo extends StatelessWidget {
  const _Titulo(this.texto);
  final String texto;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: Spacing.xs),
        child: Text(texto,
            style: const TextStyle(
                fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
      );
}

class _DocTile extends StatelessWidget {
  const _DocTile({
    required this.label,
    required this.picked,
    required this.onTap,
    this.detalhe,
  });
  final String label;
  final bool picked;
  final VoidCallback onTap;
  final String? detalhe;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(Radii.md),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(Spacing.md),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(Radii.md),
          border: Border.all(
            color: picked ? AppColors.primary : AppColors.divider,
            width: picked ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(picked ? Icons.check_circle : Icons.upload_file,
                color: picked ? AppColors.primary : AppColors.textSecondary),
            const SizedBox(width: Spacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    picked ? '{0} — anexado'.trArgs([label]) : label,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary),
                  ),
                  if (detalhe != null)
                    Text(detalhe!,
                        style: const TextStyle(
                            color: AppColors.textSecondary, fontSize: 12)),
                ],
              ),
            ),
            if (picked)
              Text('Trocar'.tr,
                  style: const TextStyle(
                      color: AppColors.primary, fontWeight: FontWeight.w600))
            else
              const Icon(Icons.chevron_right, color: AppColors.textSubtle),
          ],
        ),
      ),
    );
  }
}
