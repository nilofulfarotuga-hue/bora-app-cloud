import 'package:latlong2/latlong.dart';

import 'order_service_type.dart';

enum VehicleType {
  motorcycle,
  car,
  bicycle,
  // TVDE — Bora Motorista (transporte de passageiros). Valor canónico na DB:
  // 'carro_passageiros' (ver VehicleTypeDb). O matching de corridas filtra
  // SEMPRE pela coluna vehicle_type da DB, nunca por este enum.
  carPassengers,
}

enum DriverStatus { pending, approved, rejected }

extension DriverStatusLabel on DriverStatus {
  String get label {
    switch (this) {
      case DriverStatus.pending:
        return 'Pendente';
      case DriverStatus.approved:
        return 'Aprovado';
      case DriverStatus.rejected:
        return 'Rejeitado';
    }
  }
}

extension VehicleTypeLabel on VehicleType {
  String get label {
    switch (this) {
      case VehicleType.motorcycle:
        return 'Motociclo';
      case VehicleType.car:
        return 'Carro';
      case VehicleType.bicycle:
        return 'Bicicleta';
      case VehicleType.carPassengers:
        return 'Carro — Passageiros';
    }
  }
}

/// Mapeamento explícito enum ↔ coluna `drivers.vehicle_type` (TEXT).
/// Os 3 tipos de delivery usam `.name`; `carPassengers` mapeia para o valor
/// canónico 'carro_passageiros'. NÃO altera o fallback global (motorcycle)
/// para não partir motoristas atuais — só garante reconhecimento nos 2 sentidos.
extension VehicleTypeDb on VehicleType {
  /// Valor a gravar na coluna `vehicle_type`.
  String get dbValue =>
      this == VehicleType.carPassengers ? 'carro_passageiros' : name;

  /// Lê o valor da coluna `vehicle_type` para o enum.
  /// Aceita também a grafia legada 'carPassengers' (metadata/prefs antigos
  /// gravavam `.name`) — sem isto o TVDE caía no fallback motorcycle e a
  /// aba de passageiros desaparecia (P0 2026-07-02).
  static VehicleType fromDb(String? raw) {
    if (raw == 'carro_passageiros' || raw == 'carPassengers') {
      return VehicleType.carPassengers;
    }
    return VehicleType.values.firstWhere(
      (v) => v != VehicleType.carPassengers && v.name == (raw ?? ''),
      orElse: () => VehicleType.motorcycle,
    );
  }
}

class DriverModel {
  DriverModel({
    required this.id,
    required this.name,
    required this.location,
    required this.vehicleType,
    this.phone,
    this.licensePlate,
    this.isOnline = false,
    this.status = DriverStatus.approved,
    this.avgRating,
    this.ratingsCount = 0,
    List<DriverAssignmentInfo>? activeAssignments,
  }) : activeAssignments = activeAssignments ?? <DriverAssignmentInfo>[];

  final String id;
  String name;
  LatLng location;
  VehicleType vehicleType;
  String? phone;
  String? licensePlate;
  bool isOnline;
  DriverStatus status;

  /// BR §44 — média de avaliações (1.0-5.0) ou null se ainda sem ratings.
  double? avgRating;

  /// BR §44 — número de avaliações públicas + não flagged.
  int ratingsCount;

  final List<DriverAssignmentInfo> activeAssignments;

  bool supportsService(OrderServiceType serviceType,
      {bool requiresCar = false}) {
    // TVDE: carro de passageiros não faz delivery (vertical isolada).
    if (vehicleType == VehicleType.carPassengers) return false;

    if (vehicleType == VehicleType.car) return true;

    // carryGroceries (levar compras JÁ feitas) e caixas grandes exigem carro:
    // o volume/peso não cabe de forma fiável em mota ou bicicleta. Carro já
    // retornou true acima, por isso aqui só restam mota/bicicleta → false.
    if (serviceType == OrderServiceType.carryGroceries) return false;

    if (vehicleType == VehicleType.bicycle) {
      return serviceType == OrderServiceType.restaurant ||
          serviceType == OrderServiceType.storeShopping;
    }

    // Motorcycle cannot carry sendPackage orders that require a car.
    if (serviceType == OrderServiceType.sendPackage && requiresCar) {
      return false;
    }

    return serviceType == OrderServiceType.restaurant ||
        serviceType == OrderServiceType.storeShopping ||
        serviceType == OrderServiceType.sendPackage ||
        // FAVORES — mota aceita errand (entregas/recolhas/compras leves).
        serviceType == OrderServiceType.errand;
  }
}

class DriverAssignmentInfo {
  DriverAssignmentInfo({
    required this.orderId,
    required this.serviceType,
    required this.isPartnerOrder,
    this.vendorName,
    this.pickupLocation,
    this.pickupStreet,
  });

  final String orderId;
  final OrderServiceType serviceType;
  final bool isPartnerOrder;
  final String? vendorName;
  final LatLng? pickupLocation;
  final String? pickupStreet;
  bool hasBeenPickedUp = false;
}
