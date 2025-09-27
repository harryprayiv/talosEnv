## README.md

```markdown
# Talos Manager

A Nix-based development environment for managing Talos Linux clusters with interactive installation scripts and pinned tool versions.

## Overview

This project provides a reproducible development environment for Talos Linux cluster management, including automated installation scripts, status checking, and safe configuration cleanup with mandatory backups.

## Prerequisites

- Nix package manager (with flakes enabled)
- Network access to target nodes
- Target machines ready for Talos installation

## Installation

### Using Flakes (Recommended)
```bash
nix develop
```

### Using nix-shell
```bash
nix-shell
```

## Available Commands

### Core Tools
- `talosctl` - Talos CLI (pinned to v1.11.1)
- `talhelper` - Talos configuration helper
- `kubectl` - Kubernetes CLI
- `helm` - Kubernetes package manager
- `kustomize` - Kubernetes configuration management
- `rpi-imager` - Raspberry Pi Imager
- `yq-go` / `jq` - YAML/JSON processors

### Custom Scripts

#### `install_talos`
Interactive Talos cluster installation with 11 guided steps:
1. Initial node configuration
2. Cluster setup (IPs, name)
3. Disk selection
4. Configuration generation
5. Control plane configuration
6. Worker node configuration
7. Endpoint configuration
8. Cluster bootstrap
9. Kubeconfig retrieval
10. Health check
11. Node verification

**Default values:**
- Control Plane IP: 192.168.8.161
- Worker IPs: 192.168.8.162, 192.168.8.163
- Cluster Name: pissiCluster
- Disk: nvme

#### `check_talos`
Check cluster health and status. Searches for configuration in:
1. `$TALOS_DIR/talosconfig` (default: `~/.talos/talosconfig`)
2. `./talosconfig`
3. `$TALOSCONFIG` environment variable

Usage:
```bash
check_talos                    # Uses default control plane IP
check_talos 192.168.8.100      # Specify control plane IP
```

#### `cleanup_talos`
**⚠️ CRITICAL: Always creates backups before deletion**

Safely removes Talos configuration files with mandatory backup:
- Option 1: Remove only YAML files (SAFE - regeneratable)
- Option 2: Remove everything including talosconfig (DANGEROUS - requires typing "DELETE EVERYTHING")

Backups are stored in: `~/.talos/backups/YYYYMMDD_HHMMSS/`

## Configuration

### Environment Variables

```bash
# Set custom Talos configuration directory (default: ~/.talos)
export TALOS_DIR=/path/to/talos/config

# Set specific talosconfig file location
export TALOSCONFIG=/path/to/talosconfig
```

### File Structure

After installation, your `~/.talos/` directory will contain:
```
~/.talos/
├── talosconfig          # CRITICAL: Authentication certificates (DO NOT LOSE)
├── controlplane.yaml    # Control plane configuration
├── worker.yaml         # Worker node configuration
├── config              # Additional configuration (if present)
└── backups/            # Timestamped backups from cleanup operations
    └── YYYYMMDD_HHMMSS/
        ├── talosconfig
        ├── controlplane.yaml
        └── worker.yaml
```

## ⚠️ Critical Security Information

**The `talosconfig` file contains UNIQUE authentication certificates and keys.**

- **NEVER DELETE** without a backup
- **LOSING THIS FILE** = permanent loss of cluster access
- **NO RECOVERY** possible without this file
- Always use `cleanup_talos` which forces backup creation

### Recovery from Backup

If you accidentally delete your talosconfig:
```bash
# List available backups
ls -la ~/.talos/backups/

# Restore from backup
cp ~/.talos/backups/YYYYMMDD_HHMMSS/talosconfig ~/.talos/
```

## Typical Workflow

### Fresh Installation
```bash
# Enter development environment
nix develop

# Run interactive installation
install_talos

# Verify cluster health
check_talos
```

### Existing Cluster Management
```bash
# Enter development environment
nix develop

# Check cluster status
check_talos

# Use standard tools
kubectl get nodes
talosctl --talosconfig=~/.talos/talosconfig health
```

### Cleanup and Reinstall
```bash
# Safely backup and clean configuration
cleanup_talos  # Choose option 1 for safe cleanup

# Run new installation
install_talos
```

## Troubleshooting

### "talosconfig not found" Error
```bash
# Set environment variable to your config location
export TALOS_DIR=~/.talos
# or
export TALOSCONFIG=~/.talos/talosconfig
```

### Cannot Access Nodes After Cleanup
```bash
# Check for backups
ls -la ~/.talos/backups/

# Restore most recent backup
cp ~/.talos/backups/*/talosconfig ~/.talos/
```

### Wrong Talos Version
The flake is pinned to nixpkgs revision `8bffdd4ccfc94eedd84b56d346adb9fac46b5ff6` which provides talosctl v1.11.1. To update:
1. Find new revision with desired version
2. Update `nixpkgs.url` in `flake.nix`
3. Run `nix flake update`

## Direct Tool Execution

Run tools without entering the shell:
```bash
# Using flake
nix run .#install_talos
nix run .#check_talos
nix run .#cleanup_talos

# Standard tools
nix run .#talosctl -- version
nix run .#kubectl -- get nodes
```

## License

This project provides tooling for Talos Linux management. Talos Linux is licensed under MPL-2.0.
```

This README provides comprehensive documentation including safety warnings, usage examples, and recovery procedures. The critical security information about the talosconfig is prominently featured to prevent accidental loss of cluster access.