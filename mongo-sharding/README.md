# Настройка шардированного кластера MongoDB с репликацией и кэшированием Redis

## Шаг 1. Запуск контейнеров

```bash
docker compose up -d
```

Дождитесь, пока все контейнеры перейдут в состояние `healthy`:

```bash
docker compose ps
```

Все mongo-контейнеры и redis должны показывать статус `healthy`. Если какой-то контейнер ещё запускается, подождите и проверьте повторно.

## Шаг 2. Инициализация реплика-сета config-серверов

Подключитесь к `configSrv1` и инициализируйте реплика-сет:

```bash
docker compose exec -T configSrv1 mongosh --port 27017 --eval '
rs.initiate({
  _id: "configSrvReplSet",
  configsvr: true,
  members: [
    { _id: 0, host: "configSrv1:27017" },
    { _id: 1, host: "configSrv2:27017" },
    { _id: 2, host: "configSrv3:27017" }
  ]
});
'
```

Убедитесь, что один из узлов стал PRIMARY:

```bash
docker compose exec -T configSrv1 mongosh --port 27017 --quiet --eval 'rs.status().members.forEach(m => print(m.name, m.stateStr))'
```

Один из трёх узлов должен показывать `PRIMARY`, остальные — `SECONDARY`.

## Шаг 3. Инициализация реплика-сета шарда 1

```bash
docker compose exec -T shard1a mongosh --port 27018 --eval '
rs.initiate({
  _id: "shard1ReplSet",
  members: [
    { _id: 0, host: "shard1a:27018" },
    { _id: 1, host: "shard1b:27018" },
    { _id: 2, host: "shard1c:27018" }
  ]
});
'
```

Проверка:

```bash
docker compose exec -T shard1a mongosh --port 27018 --quiet --eval 'rs.status().members.forEach(m => print(m.name, m.stateStr))'
```

## Шаг 4. Инициализация реплика-сета шарда 2

```bash
docker compose exec -T shard2a mongosh --port 27019 --eval '
rs.initiate({
  _id: "shard2ReplSet",
  members: [
    { _id: 0, host: "shard2a:27019" },
    { _id: 1, host: "shard2b:27019" },
    { _id: 2, host: "shard2c:27019" }
  ]
});
'
```

Проверка:

```bash
docker compose exec -T shard2a mongosh --port 27019 --quiet --eval 'rs.status().members.forEach(m => print(m.name, m.stateStr))'
```

## Шаг 5. Добавление шардов в роутер

Подключитесь к роутеру и зарегистрируйте оба шарда:

```bash
docker compose exec -T router1 mongosh --port 27020 --eval '
sh.addShard("shard1ReplSet/shard1a:27018,shard1b:27018,shard1c:27018");
sh.addShard("shard2ReplSet/shard2a:27019,shard2b:27019,shard2c:27019");
'
```

Проверьте, что шарды добавлены:

```bash
docker compose exec -T router1 mongosh --port 27020 --quiet --eval 'sh.status()'
```

В выводе должны отображаться оба шарда: `shard1ReplSet` и `shard2ReplSet`.

## Шаг 6. Включение шардирования и создание коллекции

Включите шардирование для базы данных `somedb` и настройте хешированное шардирование коллекции `helloDoc` по полю `name`:

```bash
docker compose exec -T router1 mongosh --port 27020 --eval '
sh.enableSharding("somedb");
sh.shardCollection("somedb.helloDoc", { "name": "hashed" });
'
```

## Шаг 7. Наполнение базы тестовыми данными

Вставьте 1500 документов:

```bash
docker compose exec -T router1 mongosh --port 27020 --eval '
use somedb;
const docs = [];
for (var i = 0; i < 1500; i++) {
  docs.push({ age: i, name: "ly" + i });
}
db.helloDoc.insertMany(docs);
print("Вставлено документов: " + db.helloDoc.countDocuments());
'
```

## Шаг 8. Проверка распределения данных по шардам

```bash
docker compose exec -T router1 mongosh --port 27020 --quiet --eval '
db.getSiblingDB("somedb").helloDoc.getShardDistribution()
'
```

В выводе должно быть видно, что документы распределены между `shard1ReplSet` и `shard2ReplSet`.

## Шаг 9. Проверка работы приложения

Приложение `pymongo_api` доступно на порту 8080:

```bash
curl http://localhost:8080
```
