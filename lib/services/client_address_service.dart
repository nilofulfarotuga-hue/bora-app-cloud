import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/client_address.dart';

/// CRUD para `client_addresses`. Tabela com RLS — apenas o próprio user vê
/// os seus endereços (policy user_id = auth.uid()).
class ClientAddressService {
  ClientAddressService._();
  static final instance = ClientAddressService._();

  final _supa = Supabase.instance.client;

  Future<List<ClientAddress>> list() async {
    final uid = _supa.auth.currentUser?.id;
    if (uid == null) return const [];
    final res = await _supa
        .from('client_addresses')
        .select()
        .eq('user_id', uid)
        .order('is_default', ascending: false)
        .order('updated_at', ascending: false);
    return (res as List)
        .map((e) => ClientAddress.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }

  Future<ClientAddress> create({
    required String label,
    required String address,
    String? street,
    String? city,
    String? postalCode,
    double? lat,
    double? lng,
    bool isDefault = false,
  }) async {
    final uid = _supa.auth.currentUser!.id;
    if (isDefault) await _clearDefault(uid);
    final res = await _supa
        .from('client_addresses')
        .insert({
          'user_id': uid,
          'label': label,
          'address': address,
          if (street != null) 'street': street,
          if (city != null) 'city': city,
          if (postalCode != null) 'postal_code': postalCode,
          if (lat != null) 'lat': lat,
          if (lng != null) 'lng': lng,
          'is_default': isDefault,
        })
        .select()
        .single();
    return ClientAddress.fromJson(res.cast<String, dynamic>());
  }

  Future<ClientAddress> update({
    required String id,
    String? label,
    String? address,
    String? street,
    String? city,
    String? postalCode,
    double? lat,
    double? lng,
    bool? isDefault,
  }) async {
    final uid = _supa.auth.currentUser!.id;
    if (isDefault == true) await _clearDefault(uid);
    final patch = <String, dynamic>{
      if (label != null) 'label': label,
      if (address != null) 'address': address,
      if (street != null) 'street': street,
      if (city != null) 'city': city,
      if (postalCode != null) 'postal_code': postalCode,
      if (lat != null) 'lat': lat,
      if (lng != null) 'lng': lng,
      if (isDefault != null) 'is_default': isDefault,
    };
    final res = await _supa
        .from('client_addresses')
        .update(patch)
        .eq('id', id)
        .eq('user_id', uid)
        .select()
        .single();
    return ClientAddress.fromJson(res.cast<String, dynamic>());
  }

  Future<void> delete(String id) async {
    final uid = _supa.auth.currentUser!.id;
    await _supa
        .from('client_addresses')
        .delete()
        .eq('id', id)
        .eq('user_id', uid);
  }

  Future<void> setDefault(String id) async {
    final uid = _supa.auth.currentUser!.id;
    await _clearDefault(uid);
    await _supa
        .from('client_addresses')
        .update({'is_default': true})
        .eq('id', id)
        .eq('user_id', uid);
  }

  Future<void> _clearDefault(String uid) async {
    await _supa
        .from('client_addresses')
        .update({'is_default': false})
        .eq('user_id', uid)
        .eq('is_default', true);
  }
}
