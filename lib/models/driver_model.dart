import 'package:latlong2/latlong.dart';

import 'order_service_type.dart';

enum VehicleType {
  motorcycle,
  car,
}

extension VehicleTypeLabel on VehicleType {
  String get label {
    switch (this) {
      case VehicleType.motorcycle:
        return 'Motociclo';
      case VehicleType.car:
        return 'Carro';
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
    this.isOnline = true,
    List<DriverAssignmentInfo>? activeAssignments,
  }) : activeAssignments = activeAssignments ?? <DriverAssignmentInfo>[];

  final String id;
  String name;
  LatLng location;
  VehicleType vehicleType;
  String? phone;
  String? licensePlate;
  bool isOnline;
  final List<DriverAssignmentInfo> activeAssignments;

  bool supportsService(OrderServiceType serviceType) {
    if (vehicleType == VehicleType.car) {
      return true;
    }

    return serviceType == OrderServiceType.restaurant;
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
