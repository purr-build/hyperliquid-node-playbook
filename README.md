# Hyperliquid non-validator node playbook

Ansible playbooks for setting up a non-validator Hyperliquid node.

## Requirements

- A Linux host that meets the [Hyperliquid node machine specs](https://github.com/hyperliquid-dex/node?tab=readme-ov-file#machine-specs).
- Ansible installed on your local machine.
- Required Ansible roles and collections installed:

```bash
ansible-galaxy install -r requirements.yml
```

## Configuration

Check `vars.yml` for defaults. Put machine-specific overrides in `vars.local.yml`.

```bash
cp hosts.example.yml hosts.yml
cp vars.yml vars.local.yml
```

### `gossip_config`

`gossip_config` defines the gossip configuration for the Hyperliquid node. By default, `download_peers` fetches recent active peers from the Hyperliquid API:

```bash
curl -X POST --header "Content-Type: application/json" --data '{ "type": "gossipRootIps" }' https://api.hyperliquid.xyz/info
```

Set `download_peers: false` and provide `gossip_config.ip` if you want to pin a custom peer list.

### `visor`

`visor` configures the systemd service that runs the node. Customize `visor.exec_start` to choose which node data is written.

### `edge_sync`

Sync specific paths to edge nodes. Disabled by default.

```yaml
edge_sync:
  enabled: true
  targets:
    - host: 192.0.2.10
      user: hlmirror
      ssh_key_path: /path/to/edge-sync-key
  config_path: /etc/hl-edge-sync.yml
  script_path: /usr/local/bin/hl-edge-sync.py
  sync_items:
    - name: node_fills
      type: directory
      source: /home/{{ node_user }}/hl/data/node_fills/
      destination: /srv/public_data/node_fills/
      delete: true
    - name: periodic_abci_states_today
      type: latest_by_name
      source: /home/{{ node_user }}/hl/data/periodic_abci_states
      destination: /srv/public_data/periodic_abci_states
      date_subdir: true
      pattern: "*.rmp"
      delete: true
```

Each sync item supports `type: directory` for a full directory sync and `type: latest_by_name` for copying only the newest matching file. When `latest_by_name` uses `date_subdir: true` with `delete: true`, cleanup removes older matching files from the destination root.

```bash
/usr/local/bin/hl-edge-sync.py --config /etc/hl-edge-sync.yml --dry-run
/usr/local/bin/hl-edge-sync.py --config vars.local.yml --plan
```

### `clickhouse`

`clickhouse` is disabled by default. It runs a ClickHouse server in Docker, published only on the loopback interface. To enable:

```yaml
clickhouse:
  enabled: true
  image: clickhouse/clickhouse-server:24.8
  # Published only on this host interface. Keep it on loopback (or a private
  # address) so ClickHouse is not exposed externally.
  bind_host: 127.0.0.1
  http_port: 8123
  native_port: 9000
  data_dir: /var/lib/clickhouse-docker
  user: default
  password: "change-me"
  db: default
  memory_limit: "4g"          # Docker container memory cap; "0" disables it
  max_server_memory_usage: 0  # ClickHouse soft memory limit in bytes; 0 disables it
  metrics:
    enabled: true
    port: 9363
    endpoint: /metrics
    scrape: true
```

### `monitoring`

`monitoring` is disabled by default. It runs Prometheus, Grafana, and node_exporter in Docker.

```yaml
monitoring:
  enabled: true
  prometheus:
    bind_host: 127.0.0.1
    port: 9090
    retention_time: 15d
    extra_scrape_configs:
      - job_name: hl-node
        static_configs:
          - targets: ["host.docker.internal:8080"]
  grafana:
    bind_host: 127.0.0.1
    port: 3000
    domain: node.example.com
    admin_user: admin
    admin_password: "change-me"
  node_exporter:
    enabled: true
```

### `caddy`

Runs a local caddy server. Right now only used to serve Grafana.

```
caddy:
  enabled: false
  package_name: caddy
  service_name: caddy
  config_path: /etc/caddy/Caddyfile

  monitoring:
    grafana:
      enabled: true
      # Set to the public hostname for Grafana (e.g. grafana.example.com).
      domain: ""
      proxy_pass: http://127.0.0.1:3000
```

## Roles

Run a specific role by selecting its playbook:

```bash
ansible-playbook playbooks/<role>.yml -i hosts.yml
```

### `base`

Installs node dependencies, disables IPv6, and opens required firewall ports.

### `users`

Creates the dedicated system user for running the Hyperliquid node.

### `node`

Downloads the Hyperliquid visor binary, verifies its signature, writes configuration, and starts the systemd service.

### `pruner`

Installs a cron job to prune old node data. Configure the path, schedule, and retention period with `pruner`.

### `edge_sync`

Installs `/usr/local/bin/hl-edge-sync.py`, writes `/etc/hl-edge-sync.yml`, configures systemd service/timer units, and syncs configured public data paths to mirror hosts.

### `clickhouse`

Runs a ClickHouse server in Docker, bound to the loopback interface only. Configure the image, ports, credentials, and resource limits with `clickhouse`.

### `monitoring`

Runs Prometheus, Grafana, and node_exporter in Docker with loopback-bound Prometheus and Grafana ports.

### `caddy`

Runs local caddy server with HTTPS for Grafana.

## Usage

Run the full node playbook:

```bash
ansible-playbook playbooks/hl-node.yml -i hosts.yml
```

Run only one role:

```bash
ansible-playbook playbooks/node.yml -i hosts.yml
ansible-playbook playbooks/pruner.yml -i hosts.yml
ansible-playbook playbooks/edge-sync.yml -i hosts.yml
ansible-playbook playbooks/clickhouse.yml -i hosts.yml
ansible-playbook playbooks/monitoring.yml -i hosts.yml
ansible-playbook playbooks/nginx.yml -i hosts.yml
```

## Roadmap

- [x] Cron job to prune old data.
- [x] Nginx reverse proxy for Grafana and Prometheus.
- [x] Monitoring with Prometheus and Grafana.

## License

MIT
