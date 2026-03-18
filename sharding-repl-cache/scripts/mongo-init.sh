#!/bin/bash

wait_for_healthy() {
  for svc in "$@"; do
    echo "Waiting for $svc to become healthy..."
    until [ "$(docker inspect -f '{{.State.Health.Status}}' "$svc")" = "healthy" ]; do
      sleep 1
    done
    echo "$svc is healthy"
  done
}

wait_for_primary() {
  local container=$1
  local port=$2

  echo "Waiting for PRIMARY on $container..."

  until docker compose exec -T $container mongosh --quiet --port $port --eval \
    "rs.status().members.some(m => m.stateStr === 'PRIMARY')" 2>/dev/null | grep -q "true"; do
    sleep 1
  done

  echo "Replica set on $container has a PRIMARY"
}

wait_for_healthy configSrv1 configSrv2 configSrv3

docker compose exec -T configSrv1 mongosh --port 27017 <<EOF
rs.initiate({
    _id: "configSrvReplSet",
    configsvr: true,
    members: [
        { _id: 0, host: "configSrv1:27017" },
        { _id: 1, host: "configSrv2:27017" },
        { _id: 2, host: "configSrv3:27017" }
    ]
});
exit();
EOF

wait_for_primary configSrv1 27017

wait_for_healthy shard1a
wait_for_healthy shard1b
wait_for_healthy shard1c

docker compose exec -T shard1a mongosh --port 27018 <<EOF
rs.initiate({
    _id: "shard1ReplSet",
    members: [
        { _id: 0, host: "shard1a:27018" },
        { _id: 1, host: "shard1b:27018" },
        { _id: 2, host: "shard1c:27018" }
    ]
});
exit();
EOF

wait_for_primary shard1a 27018
wait_for_healthy shard2a shard2b shard2c

docker compose exec -T shard2a mongosh --port 27019 <<EOF
rs.initiate({
    _id: "shard2ReplSet",
    members: [
        { _id: 0, host: "shard2a:27019" },
        { _id: 1, host: "shard2b:27019" },
        { _id: 2, host: "shard2c:27019" }
    ]
});
exit();
EOF

wait_for_primary shard2a 27019
wait_for_healthy router1

docker compose exec -T router1 mongosh --port 27020 <<EOF
sh.addShard("shard1ReplSet/shard1a:27018,shard1b:27018,shard1c:27018");
sh.addShard("shard2ReplSet/shard2a:27019,shard2b:27019,shard2c:27019");


sh.enableSharding("somedb");
sh.shardCollection("somedb.helloDoc", { "name": "hashed" });

use somedb;

for(var i = 0; i < 1500; i++) db.helloDoc.insertOne({ age: i, name: "ly"+i})

exit();
EOF

