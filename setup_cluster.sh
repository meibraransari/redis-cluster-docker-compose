#!/bin/bash

echo "========================================"
echo "🚀 REDIS CLUSTER SETUP STARTING"
echo "========================================"

# ----------------------------------------
echo ""
echo "📦 Step 1: Creating .env file"
# ----------------------------------------
echo "COMPOSE_PROJECT_NAME=rediscluster" > .env
echo "✅ .env file created"

# ----------------------------------------
echo ""
echo "📁 Step 2: Creating directories for nodes"
# ----------------------------------------
mkdir -p 7000 7001 7002 7003 7004 7005
echo "✅ Directories 7000–7005 created"

# ----------------------------------------
echo ""
echo "⚙️ Step 3: Generating redis.conf files"
# ----------------------------------------
for port in 7000 7001 7002 7003 7004 7005
do
  cat <<EOF > $port/redis.conf
port $port
cluster-enabled yes
cluster-config-file nodes.conf
cluster-node-timeout 5000
appendonly yes
bind 0.0.0.0
EOF
done
echo "✅ redis.conf files created for all nodes"

# ----------------------------------------
echo ""
echo "🧠 Step 4: Preparing RedisInsight directory"
# ----------------------------------------
mkdir -p redisinsight
chmod 777 redisinsight
echo "✅ redisinsight directory ready"

# ----------------------------------------
echo ""
echo "⚖️ Step 5: Setting up HAProxy configuration"
# ----------------------------------------
mkdir -p haproxy/
chmod 777 haproxy/

cat > ./haproxy/haproxy.cfg << 'EOF'
global
    log stdout format raw local0

defaults
    mode tcp
    timeout connect 5s
    timeout client  30s
    timeout server  30s
    log global

# FRONTEND — Writes -> Masters
frontend redis_write_front
    bind *:6379
    default_backend redis_masters

backend redis_masters
    balance roundrobin
    option tcp-check
    tcp-check connect
    tcp-check send PING\r\n
    tcp-check expect string +PONG
    server redis-node-1 redis-node-1:7000 check inter 2s
    server redis-node-2 redis-node-2:7001 check inter 2s
    server redis-node-3 redis-node-3:7002 check inter 2s

# FRONTEND — Reads -> Replicas
frontend redis_read_front
    bind *:6380
    default_backend redis_replicas

backend redis_replicas
    balance leastconn
    option tcp-check
    tcp-check connect
    tcp-check send PING\r\n
    tcp-check expect string +PONG
    server redis-node-4 redis-node-4:7003 check inter 2s
    server redis-node-5 redis-node-5:7004 check inter 2s
    server redis-node-6 redis-node-6:7005 check inter 2s

# STATS UI
frontend stats
    mode http
    bind *:8080
    stats enable
    stats uri /stats
    stats refresh 5s
    stats show-legends
    stats show-node
EOF

echo "✅ HAProxy config created"

# ----------------------------------------
echo ""
echo "🐳 Step 6: Starting Docker containers"
# ----------------------------------------
docker compose up -d
echo "✅ Containers started"

# ----------------------------------------
echo ""
echo "⏳ Step 7: Waiting for cluster initialization"
# ----------------------------------------
sleep 10
echo "✅ Wait complete"

# ----------------------------------------
echo ""
echo "🔍 Step 8: Verifying cluster state"
# ----------------------------------------
docker exec -it $(docker ps -qf "name=redis-node-1") redis-cli -p 7000 CLUSTER INFO | grep -E "cluster_state|cluster_slots_assigned|cluster_size|cluster_known_nodes"

# ----------------------------------------
echo ""
echo "🎉 SETUP COMPLETE!"
# ----------------------------------------
echo "👉 RedisInsight: http://localhost:8001"
echo "👉 HAProxy Stats: http://localhost:8080/stats"
echo ""
echo "🔗 Connect RedisInsight using:"
echo "   Using Container"
echo "   redis://default@rediscluster-redis-node-1:7000"
echo "   or"
echo "   using HAProxy"
echo "   redis://default@redis-haproxy:6379"
echo "========================================"
