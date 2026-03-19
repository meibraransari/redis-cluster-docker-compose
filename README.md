# Redis True Cluster — Docker Compose Setup

A production-style 6-node Redis Cluster (3 masters + 3 replicas) with RedisInsight UI, fully managed via Docker Compose.

---

## Architecture

```
                     ┌──────────────────────────────────┐
                     │         Your Application         │
                     └───────────┬──────────────┬───────┘
                                 │              │
                          Writes │              │ Reads
                          :6379  │              │ :6380
                                 ▼              ▼
                     ┌──────────────────────────────────┐
                     │             HAProxy              │
                     │  :6379 → roundrobin → masters    │
                     │  :6380 → leastconn  → replicas   │
                     │  :8080 → /stats dashboard        │
                     └───┬──────────┬──────────┬────────┘
                         │          │          │
              ┌──────────▼─┐  ┌─────▼──────┐  ┌▼─────────────┐
              │  node-1    │  │   node-2   │  │   node-3     │  ← Masters
              │  :7000     │  │   :7001    │  │   :7002      │
              │  slots:0-5k│  │slots:5k-10k│  │slots:10k-16k │
              └──────┬─────┘  └─────┬──────┘  └──────┬───────┘
                     │ replicates   │ replicates     │ replicates
                     ▼              ▼                ▼
              ┌────────────┐ ┌────────────┐  ┌────────────────┐
              │  node-5    │ │  node-6    │  │   node-4       │  ← Replicas
              │  :7004     │ │  :7005     │  │   :7003        │
              └────────────┘ └────────────┘  └────────────────┘

              ┌──────────────────────────────────────────────┐
              │   RedisInsight UI  →  http://<host>:8001     │
              └──────────────────────────────────────────────┘
```

---

## Project Structure

```
redis/
├── compose.yaml        # Docker Compose with all 6 nodes + insight
├── setup.sh            # One-command setup script
├── README.md           # This file
├── 7000/
│   └── redis.conf
├── 7001/
│   └── redis.conf
├── 7002/
│   └── redis.conf
├── 7003/
│   └── redis.conf
├── 7004/
│   └── redis.conf
├── 7005/
│   └── redis.conf
├── haproxy
│   └── haproxy.cfg
└── redisinsight/       # Auto-created by setup.sh
```

## Slot Distribution

```
Master 1 (node-1:7000)  slots 0     - 5460   ←→  Replica: node-5:7004
Master 2 (node-2:7001)  slots 5461  - 10922  ←→  Replica: node-6:7005
Master 3 (node-3:7002)  slots 10923 - 16383  ←→  Replica: node-4:7003
```


---

## Quick Start

### 1. Place files

Take pull
```bash
git clone https://github.com/meibraransari/redis-cluster-docker-compose.git
cd redis-cluster-docker-compose
```

### 2. Run setup

```bash
chmod +x setup_cluster.sh
./setup_cluster.sh
```

This will:
- Create `7000`–`7005` directories with `redis.conf` for each node
- Create `redisinsight/` with correct permissions
- Start all containers via `docker compose up -d`
- Wait for nodes to be ready, then auto-initialize the cluster
- Verify cluster state

### 3. Access services

| Service        | URL / Address                          |
|----------------|----------------------------------------|
| RedisInsight   | `http://<your-server-ip>:8001`         |
| HAProxy Stats  | `http://<your-server-ip>:8080/stats`   |
| Redis Writes   | `<your-server-ip>:6379` (→ masters)    |
| Redis Reads    | `<your-server-ip>:6380` (→ replicas)   |

---

## Connecting RedisInsight to the Cluster

1. Open `http://<your-server-ip>:8001`
2. Click **Add Redis database**
3. Enter the connection URL:
```
# Direct connection
# redis://default@rediscluster-redis-node-1:7000
# HAProxy connection
redis://default@redis-haproxy:6379
```
4. Click **Add Database**

### Explore the Cluster

```
Select database → redis-haproxy:6379 → Analyze → Overview
```

You will see all **3 master nodes** with their slot ranges and replica assignments.

---

## Verify Cluster via CLI

```bash
# Check all nodes are running
docker ps --format "table {{.Names}}\t{{.Status}}" | grep redis-node

# Get current IPs
docker inspect -f '{{.Name}} → {{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' \
  rediscluster-redis-node-1-1 \
  rediscluster-redis-node-2-1 \
  rediscluster-redis-node-3-1 \
  rediscluster-redis-node-4-1 \
  rediscluster-redis-node-5-1 \
  rediscluster-redis-node-6-1
  
# Verify
docker exec -it rediscluster-redis-node-1-1 redis-cli -p 7000 CLUSTER INFO | grep -E "cluster_state|cluster_slots_assigned|cluster_size|cluster_known_nodes"

# Check overall cluster state
docker exec -it rediscluster-redis-node-1-1 redis-cli -p 7000 CLUSTER INFO

# Check master/replica roles and slot assignments
docker exec -it rediscluster-redis-node-1-1 redis-cli -p 7000 CLUSTER NODES

# Full health check
docker exec -it rediscluster-redis-node-1-1 redis-cli --cluster check redis-node-1:7000
```

Expected output from `CLUSTER INFO`:
```
cluster_state:ok
cluster_slots_assigned:16384
cluster_known_nodes:6
cluster_size:3
```


## HAProxy Load Balancer

### How traffic is routed

```
:6379  →  redis_masters   (roundrobin)  →  node-1:7000, node-2:7001, node-3:7002
:6380  →  redis_replicas  (leastconn)   →  node-4:7003, node-5:7004, node-6:7005
:8080  →  /stats          (HTTP)        →  live dashboard
```

### Final Architecture
```
Your App
    │
    ├── Writes → :6379 ──► HAProxy ──► roundrobin
    │                                  ├── rediscluster-redis-node-1:7000 (master)
    │                                  ├── rediscluster-redis-node-2:7001 (master)
    │                                  └── rediscluster-redis-node-3:7002 (master)
    │
    ├── Reads  → :6380 ──► HAProxy ──► leastconn
    │                                  ├── rediscluster-redis-node-4:7003 (replica)
    │                                  ├── rediscluster-redis-node-5:7004 (replica)
    │                                  └── rediscluster-redis-node-6:7005 (replica)
    │
    └── Stats  → :8080/stats (HAProxy dashboard)


```
### HAProxy Stats Dashboard

Open `http://<your-server-ip>:8080/stats`:

```
Backend: redis_masters   → node-1, node-2, node-3  (health, sessions, throughput)
Backend: redis_replicas  → node-4, node-5, node-6  (health, sessions, throughput)
```
---

## General Management Commands

```bash
# Start all services
docker compose up -d

# Stop all services
docker compose stop

# Stop and remove containers (keep volumes)
docker compose down

# Stop and remove everything including volumes
docker compose down -v

# Restart a specific node
docker compose restart rediscluster-redis-node-1

# View logs for all services
docker compose logs -f

# View logs for a specific node
docker logs rediscluster-redis-node-1-1 -f

# Check running containers and ports
docker ps
```


