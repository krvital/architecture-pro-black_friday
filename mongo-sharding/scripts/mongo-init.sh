#!/bin/bash

###
# Setting up sharding and initialize db with data
###

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

wait_for_healthy configSrv

docker compose exec -T configSrv mongosh --port 27017 <<EOF
rs.initiate({
    _id: "config_server",
    configsvr: true,
    members: [{ _id: 0, host: "configSrv:27017" }]
});
exit();
EOF

wait_for_primary configSrv 27017
wait_for_healthy shard1

docker compose exec -T shard1 mongosh --port 27018 <<EOF
rs.initiate({
    _id: "shard1",
    members: [{ _id: 0, host: "shard1:27018" }]
});
exit();
EOF

wait_for_primary shard1 27018
wait_for_healthy shard2

docker compose exec -T shard2 mongosh --port 27019 <<EOF
rs.initiate({
    _id: "shard2",
    members: [{ _id: 0, host: "shard2:27019" }]
});
exit();
EOF

wait_for_primary shard2 27019
wait_for_healthy mongos_router

docker compose exec -T mongos_router mongosh --port 27020 <<EOF
sh.addShard("shard1/shard1:27018");
sh.addShard("shard2/shard2:27019");

sh.enableSharding("somedb");
sh.shardCollection("somedb.helloDoc", { "name": "hashed" });

use somedb;

for(var i = 0; i < 1500; i++) db.helloDoc.insertOne({ age: i, name: "ly"+i})

exit();
EOF
