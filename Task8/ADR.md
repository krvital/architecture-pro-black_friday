# MP-ADR5 Стратегия выявления у устранения “горячих” шардов в MongoDB
**Дата:** 02.03.2026

**Автор:** Виталий Кравцов

### Контекст
В коллекции `products` категории «Электроника» произошла перегрузка одного из шардов  MongoDB, так как 70% запросов приходилось именно на эти товары. Это приводит к перегрузке шардов и ухудшению производительности. Необходимо:

- Разработать метрики для мониторинга состояния шардов.
- Предложить механизмы перераспределения данных и балансировки нагрузки.

### Решение

#### Сбор метрик для отслеживания состояния шардов

Для сбора и мониторинга метрик будем использовать сочетание MongoDB Exporter + Prometheus + Grafana.

Набор метрик, которые будем собирать

**Нагрузка на шард**

- `mongodb_opcounters_total` – количество операций
- `mongodb_connections_current` – активные соединения
- `mongodb_mem_resident_bytes` – используемая память
- `mongodb_network_bytes_total` – сетевой трафик

**Ресурсы шардов**

- CPU, RAM  `db.serverStatus()`
- Диск: `mongodb_storage_size_bytes`, `mongodb_index_size_bytes`

**Распределение и балансировка**

- `mongodb_shard_chunks_total` – общее количество чанков на шард
- `mongodb_shard_chunk_migration_in_progress` – сколько чанков мигрирует
- `mongodb_balancer_status` – включён/выключен balancer



#### Механизмы перераспределения данных

1. Принудительное закрепление диапазона ключей через `zone` sharding
   ```js
   sh.addShard('rs-electronics/mongo-elec-01:27017,mongo-elec-02:27017')
   
   sh.addShardToZone('rs-electronics', 'hot-electronics')
   
   sh.updateZoneKeyRange(
     'mydb.products',
     { category: 'Электроника', _id: MinKey },
     { category: 'Электроника', _id: MaxKey },
     'hot-electronics'
   )
   ```

2. Cмена шард-ключа. Если текущий ключ (category) изначально плохой, то можно выбрать и другой и произвести решардинг.
   ```js
   db.adminCommand({
     reshardCollection: 'mydb.products',
     key: { category: 1, _id: 1 }
   })
   ```

   

### 
