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

`vars.yml` contains safe defaults that can be committed. Put machine-specific overrides in `vars.local.yml`; that file is ignored by Git.

```bash
cp hosts.example.yml hosts.yml
cp vars.yml vars.local.yml
```

Edit `hosts.yml` and `vars.local.yml` before running the playbooks.

### `gossip_config`

`gossip_config` defines the gossip configuration for the Hyperliquid node. By default, `download_peers` fetches recent active peers from the Hyperliquid API:

```bash
curl -X POST --header "Content-Type: application/json" --data '{ "type": "gossipRootIps" }' https://api.hyperliquid.xyz/info
```

Set `download_peers: false` and provide `gossip_config.ip` if you want to pin a custom peer list.

### `visor`

`visor` configures the systemd service that runs the node. Customize `visor.exec_start` to choose which node data is written.

### `edge_sync`

`edge_sync` is disabled by default. Enable it from `vars.local.yml` and configure one or more mirror targets:

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

Each sync item supports `type: directory` for a full directory sync and `type: latest_by_name` for copying only the newest matching file. When `latest_by_name` uses `date_subdir: true` with `delete: true`, cleanup removes older matching files from the destination root, not only from today's subdirectory.

The installed script accepts the same `edge_sync` structure from a rendered config file or a full `vars.local.yml`-style file:

```bash
/usr/local/bin/hl-edge-sync.py --config /etc/hl-edge-sync.yml --dry-run
/usr/local/bin/hl-edge-sync.py --config vars.local.yml --plan
```

Use `--dry-run` to print the rsync itemized changes and remote files that would be deleted without applying them. Use `--list-changes` during a real run if you want rsync itemized output in the service logs.

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
```

## Roadmap

- [x] Cron job to prune old data.
- [ ] Nginx service to serve info endpoint.
- [ ] Monitoring with Prometheus and Grafana.

## License

MIT
