enum OrderServiceType {
  restaurant,
  storeShopping,
  carryGroceries,
  sendPackage,
}

extension OrderServiceTypeLabel on OrderServiceType {
  String get label {
    switch (this) {
      case OrderServiceType.restaurant:
        return "Restaurantes";
      case OrderServiceType.storeShopping:
        return "Compras em loja";
      case OrderServiceType.carryGroceries:
        return "Entregar compras";
      case OrderServiceType.sendPackage:
        return "Enviar pacote";
    }
  }

  String get description {
    switch (this) {
      case OrderServiceType.restaurant:
        return "Pedido em restaurante parceiro";
      case OrderServiceType.storeShopping:
        return "Compra em loja não parceira";
      case OrderServiceType.carryGroceries:
        return "Entrega das compras do cliente";
      case OrderServiceType.sendPackage:
        return "Envio de encomenda";
    }
  }
}
