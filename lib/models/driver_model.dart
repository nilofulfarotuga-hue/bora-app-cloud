import 'package:latlong2/latlong.dart';

import 'order_service_type.dart';

enum VehicleType {
  motorcycle,
  car,
  bicycle,
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
    }
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
  final List<DriverAssignmentInfo> activeAssignments;

  bool supportsService(OrderServiceType serviceType,
      {bool requiresCar = false}) {
    if (vehicleType == VehicleType.car) return true;

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
        serviceType == OrderServiceType.sendPackage;
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
