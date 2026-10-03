---
prioridade: MÉDIA 🟡
ficheiro: lib/services/driver_location_service.dart
bug_id: BUG-016
---

# BUG-016 — Dual GPS streams causam dados de localização divergentes

## Descrição
O `driver_location_service.dart` foi identificado como tendo dois streams de GPS simultâneos que produzem dados contraditórios. Os comentários no código indicam que isto já foi reconhecido mas não corrigido.

## Sintoma
- A posição do driver no mapa do cliente pode estar desactualizada ou incorrecta
- Possível conflito entre o stream da app e o stream do `DriverStore`
- Potencial consumo excessivo de bateria no dispositivo do driver

## Impacto
- Experiência de tracking degradada para o cliente
- Driver pode aparecer numa posição diferente da real
- Em casos extremos, o algoritmo de dispatch pode atribuir ordens ao driver errado

## Ficheiros Envolvidos
- `lib/services/driver_location_service.dart`
- `lib/stores/driver_store.dart`
- `lib/screens/driver_map_screen.dart`

## Solução Proposta
1. Consolidar para um único stream de GPS (usar `driver_location_service` como fonte única)
2. `DriverStore` deve subscrever ao stream em vez de criar o seu próprio
3. Adicionar debounce de 3-5 segundos para não enviar actualizações ao Supabase demasiado frequentemente
4. Testar com dois dispositivos reais (um driver, um cliente) para confirmar sincronização

## Acções Imediatas
- [ ] Ler o código completo do `driver_location_service.dart` para confirmar o problema
- [ ] Verificar se o `DriverStore` tem o seu próprio listener de geolocalização
