{ pkgs ? import <nixpkgs> {} }:

let
  # Import configuration
  talosConfig = import ./talos-config.nix { name = "talos-manager"; };
  
  # Convert worker IPs list to space-separated string for bash
  workerIPsString = builtins.concatStringsSep " " talosConfig.cluster.workerIPs;
  
  install_talos = pkgs.writeShellScriptBin "install_talos" ''
    #!/usr/bin/env bash
    set -euo pipefail

    # Color codes for output
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    NC='\033[0m' # No Color

    # Function for colored output
    log_info() { echo -e "''${BLUE}[INFO]''${NC} $1"; }
    log_success() { echo -e "''${GREEN}[SUCCESS]''${NC} $1"; }
    log_warning() { echo -e "''${YELLOW}[WARNING]''${NC} $1"; }
    log_error() { echo -e "''${RED}[ERROR]''${NC} $1"; }

    # Function to prompt for confirmation
    confirm() {
        local prompt="$1"
        local response
        echo -e "''${YELLOW}$prompt (y/n): ''${NC}"
        read -r response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            log_warning "Operation cancelled by user"
            exit 1
        fi
    }

    # Function to prompt for input with default value
    prompt_with_default() {
        local prompt="$1"
        local default="$2"
        local response
        echo -e "''${BLUE}$prompt [''${default}]: ''${NC}"
        read -r response
        echo "''${response:-$default}"
    }

    # Set TALOS_DIR from config - can be overridden by environment variable
    TALOS_DIR=''${TALOS_DIR:-"${talosConfig.cluster.configDir}"}
    # Expand $HOME if present
    TALOS_DIR=$(eval echo "$TALOS_DIR")
    
    # Default values from configuration
    DEFAULT_CONTROL_PLANE="${talosConfig.cluster.controlPlaneIP}"
    DEFAULT_CLUSTER_NAME="${talosConfig.cluster.name}"
    DEFAULT_WORKER_IPS="${workerIPsString}"
    DEFAULT_DISK_NAME="${talosConfig.cluster.diskName}"
    API_PORT="${toString talosConfig.network.apiPort}"
    BOOTSTRAP_TIMEOUT="${toString talosConfig.settings.bootstrapTimeout}"
    
    clear
    echo "==========================================="
    echo "       Talos Cluster Installation"
    echo "==========================================="
    echo ""
    echo "Configuration loaded from: nix/talos-config.nix"
    echo "Talos config directory: $TALOS_DIR"
    echo ""

    # Ask if user wants to use existing config or create new
    if [ -d "$TALOS_DIR" ] && [ -f "$TALOS_DIR/talosconfig" ]; then
        log_info "Found existing Talos configuration in $TALOS_DIR"
        confirm "Use existing configuration directory?"
    else
        log_info "Creating Talos configuration directory: $TALOS_DIR"
        mkdir -p "$TALOS_DIR"
    fi

    # Step 1: Initial node configuration
    log_info "Step 1: Initial Node Configuration"
    echo ""
    
    INITIAL_NODE=$(prompt_with_default "Enter the initial node IP for configuration" "$DEFAULT_CONTROL_PLANE")
    
    log_info "Applying initial configuration to node $INITIAL_NODE..."
    confirm "This will apply configuration in interactive mode. Continue?"
    
    ${if talosConfig.settings.insecureMode then "--insecure" else ""} \
    ${if talosConfig.settings.interactiveMode then "--mode=interactive" else ""} \
    talosctl apply-config --nodes "$INITIAL_NODE"
    
    if [ $? -eq 0 ]; then
        log_success "Initial configuration applied successfully"
    else
        log_error "Failed to apply initial configuration"
        exit 1
    fi
    
    echo ""
    sleep 2

    # Step 2: Set cluster configuration
    log_info "Step 2: Cluster Configuration Setup"
    echo ""
    
    export CONTROL_PLANE_IP=$(prompt_with_default "Enter Control Plane IP" "$DEFAULT_CONTROL_PLANE")
    export CLUSTER_NAME=$(prompt_with_default "Enter Cluster Name" "$DEFAULT_CLUSTER_NAME")
    
    # Get worker IPs
    log_info "Enter Worker Node IPs (press Enter with empty input when done):"
    log_info "Default workers: $DEFAULT_WORKER_IPS"
    WORKER_IPS=()
    
    # Ask if user wants to use defaults
    if confirm "Use default worker IPs ($DEFAULT_WORKER_IPS)?"; then
        IFS=' ' read -r -a WORKER_IPS <<< "$DEFAULT_WORKER_IPS"
    else
        while true; do
            worker_ip=$(prompt_with_default "Worker IP (empty to finish)" "")
            if [ -z "$worker_ip" ]; then
                break
            fi
            WORKER_IPS+=("$worker_ip")
        done
    fi
    
    echo ""
    log_info "Configuration Summary:"
    echo "  Control Plane IP: $CONTROL_PLANE_IP"
    echo "  Cluster Name: $CLUSTER_NAME"
    echo "  Worker IPs: ''${WORKER_IPS[*]}"
    echo ""
    confirm "Is this configuration correct?"
    
    # Step 3: Get disk information
    log_info "Step 3: Disk Configuration"
    echo ""
    
    log_info "Fetching available disks from control plane..."
    talosctl get disks --insecure --nodes "$CONTROL_PLANE_IP"
    
    echo ""
    export DISK_NAME=$(prompt_with_default "Enter disk name to use for installation (e.g., nvme, sda)" "$DEFAULT_DISK_NAME")
    
    # Step 4: Generate configuration
    log_info "Step 4: Generating Talos Configuration"
    echo ""
    
    log_info "Generating config for cluster '$CLUSTER_NAME' in $TALOS_DIR..."
    cd "$TALOS_DIR"
    talosctl gen config "$CLUSTER_NAME" "https://$CONTROL_PLANE_IP:$API_PORT" --install-disk "/dev/$DISK_NAME"
    
    if [ $? -eq 0 ]; then
        log_success "Configuration files generated successfully"
        log_info "Generated files in $TALOS_DIR:"
        ls -la "$TALOS_DIR"/*.yaml "$TALOS_DIR"/talosconfig 2>/dev/null || true
    else
        log_error "Failed to generate configuration"
        exit 1
    fi
    
    echo ""
    sleep 2

    # Step 5: Apply configuration to control plane
    log_info "Step 5: Configuring Control Plane"
    echo ""
    
    confirm "Apply configuration to control plane at $CONTROL_PLANE_IP?"
    
    talosctl apply-config --insecure --nodes "$CONTROL_PLANE_IP" --file "$TALOS_DIR/controlplane.yaml"
    
    if [ $? -eq 0 ]; then
        log_success "Control plane configuration applied"
    else
        log_error "Failed to apply control plane configuration"
        exit 1
    fi
    
    echo ""
    sleep 2

    # Step 6: Apply configuration to workers
    log_info "Step 6: Configuring Worker Nodes"
    echo ""
    
    for ip in "''${WORKER_IPS[@]}"; do
        log_info "Applying config to worker node: $ip"
        talosctl apply-config --insecure --nodes "$ip" --file "$TALOS_DIR/worker.yaml"
        
        if [ $? -eq 0 ]; then
            log_success "Worker $ip configured successfully"
        else
            log_warning "Failed to configure worker $ip (continuing...)"
        fi
        sleep 1
    done
    
    echo ""
    sleep 2

    # Step 7: Configure endpoints
    log_info "Step 7: Configuring Talos Endpoints"
    echo ""
    
    talosctl --talosconfig="$TALOS_DIR/talosconfig" config endpoints "$CONTROL_PLANE_IP"
    
    if [ $? -eq 0 ]; then
        log_success "Endpoints configured"
    else
        log_error "Failed to configure endpoints"
        exit 1
    fi
    
    echo ""
    sleep 2

    # Step 8: Bootstrap the cluster
    log_info "Step 8: Bootstrapping Cluster"
    echo ""
    
    log_warning "Bootstrapping will initialize the cluster. This should only be done once!"
    confirm "Bootstrap the cluster now?"
    
    talosctl bootstrap --nodes "$CONTROL_PLANE_IP" --talosconfig="$TALOS_DIR/talosconfig"
    
    if [ $? -eq 0 ]; then
        log_success "Cluster bootstrapped successfully"
    else
        log_error "Failed to bootstrap cluster"
        exit 1
    fi
    
    echo ""
    log_info "Waiting for cluster to initialize ($BOOTSTRAP_TIMEOUT seconds)..."
    sleep $BOOTSTRAP_TIMEOUT

    # Step 9: Get kubeconfig
    log_info "Step 9: Retrieving Kubeconfig"
    echo ""
    
    talosctl kubeconfig --nodes "$CONTROL_PLANE_IP" --talosconfig="$TALOS_DIR/talosconfig"
    
    if [ $? -eq 0 ]; then
        log_success "Kubeconfig retrieved and merged"
        log_info "You can now use kubectl to interact with your cluster"
    else
        log_error "Failed to retrieve kubeconfig"
        exit 1
    fi
    
    echo ""
    sleep 2

    # Step 10: Health check
    log_info "Step 10: Running Health Check"
    echo ""
    
    log_info "Checking cluster health..."
    talosctl --nodes "$CONTROL_PLANE_IP" --talosconfig="$TALOS_DIR/talosconfig" health
    
    echo ""
    sleep 2

    # Step 11: Show nodes
    log_info "Step 11: Verifying Kubernetes Nodes"
    echo ""
    
    log_info "Fetching node status..."
    kubectl get nodes
    
    echo ""
    echo "==========================================="
    log_success "Talos cluster installation completed!"
    echo "==========================================="
    echo ""
    echo "Configuration files saved in: $TALOS_DIR"
    echo ""
    echo "Next steps:"
    echo "  1. Check node status: kubectl get nodes"
    echo "  2. Deploy workloads: kubectl apply -f <manifest>"
    echo "  3. Monitor cluster: talosctl --nodes $CONTROL_PLANE_IP --talosconfig=$TALOS_DIR/talosconfig health"
    echo ""
    echo "To use talosctl with this configuration:"
    echo "  export TALOSCONFIG=$TALOS_DIR/talosconfig"
    echo ""
  '';

  cleanup_talos = pkgs.writeShellScriptBin "cleanup_talos" ''
    #!/usr/bin/env bash
    set -euo pipefail

    RED='\033[0;31m'
    YELLOW='\033[1;33m'
    GREEN='\033[0;32m'
    BLUE='\033[0;34m'
    NC='\033[0m'

    # Set TALOS_DIR from config
    TALOS_DIR=''${TALOS_DIR:-"${talosConfig.cluster.configDir}"}
    TALOS_DIR=$(eval echo "$TALOS_DIR")
    BACKUP_RETENTION="${toString talosConfig.cluster.backupRetention}"

    echo "==========================================="
    echo "       Talos Configuration Cleanup"
    echo "==========================================="
    echo ""
    
    echo -e "''${RED}[CRITICAL WARNING]''${NC}"
    echo "The talosconfig file contains UNIQUE authentication certificates!"
    echo "Without these, you will PERMANENTLY lose access to your nodes!"
    echo ""
    
    # Create backup directory with timestamp
    BACKUP_DIR="$TALOS_DIR/backups/$(date +%Y%m%d_%H%M%S)"
    
    echo -e "''${BLUE}[INFO]''${NC} Creating backup directory: $BACKUP_DIR"
    mkdir -p "$BACKUP_DIR"
    
    # Backup critical files if they exist
    echo -e "''${YELLOW}[BACKUP]''${NC} Backing up configuration files..."
    
    if [ -f "$TALOS_DIR/talosconfig" ]; then
        cp "$TALOS_DIR/talosconfig" "$BACKUP_DIR/"
        echo "  ✓ Backed up talosconfig (CRITICAL - contains authentication)"
    fi
    
    if [ -f "$TALOS_DIR/config" ]; then
        cp "$TALOS_DIR/config" "$BACKUP_DIR/"
        echo "  ✓ Backed up config"
    fi
    
    if [ -f "$TALOS_DIR/controlplane.yaml" ]; then
        cp "$TALOS_DIR/controlplane.yaml" "$BACKUP_DIR/"
        echo "  ✓ Backed up controlplane.yaml"
    fi
    
    if [ -f "$TALOS_DIR/worker.yaml" ]; then
        cp "$TALOS_DIR/worker.yaml" "$BACKUP_DIR/"
        echo "  ✓ Backed up worker.yaml"
    fi
    
    # Also backup from current directory if present
    if [ -f "./talosconfig" ]; then
        cp "./talosconfig" "$BACKUP_DIR/talosconfig.local"
        echo "  ✓ Backed up local talosconfig"
    fi
    
    echo ""
    echo -e "''${GREEN}[SUCCESS]''${NC} Backup completed in: $BACKUP_DIR"
    echo ""
    
    # Clean up old backups
    echo -e "''${BLUE}[INFO]''${NC} Cleaning backups older than $BACKUP_RETENTION days..."
    find "$TALOS_DIR/backups" -type d -mtime +$BACKUP_RETENTION -exec rm -rf {} + 2>/dev/null || true
    
    echo "What would you like to clean up?"
    echo "  1) Only YAML files (controlplane.yaml, worker.yaml) - SAFE"
    echo "  2) Everything INCLUDING talosconfig - DANGEROUS!"
    echo "  3) Cancel"
    echo ""
    echo -e "''${BLUE}Select option [1-3]: ''${NC}"
    read -r option
    
    case $option in
        1)
            echo -e "''${YELLOW}Removing only YAML files...''${NC}"
            rm -f "$TALOS_DIR/controlplane.yaml" "$TALOS_DIR/worker.yaml"
            rm -f ./controlplane.yaml ./worker.yaml
            echo -e "''${GREEN}[SUCCESS]''${NC} YAML files removed. Talosconfig preserved."
            ;;
        2)
            echo ""
            echo -e "''${RED}[EXTREME WARNING]''${NC}"
            echo "This will delete your talosconfig!"
            echo "You will LOSE ACCESS to your nodes unless you have a backup!"
            echo ""
            echo "Your backup is saved in: $BACKUP_DIR"
            echo ""
            echo -e "''${RED}Type 'DELETE EVERYTHING' to confirm: ''${NC}"
            read -r confirmation
            
            if [ "$confirmation" = "DELETE EVERYTHING" ]; then
                rm -f "$TALOS_DIR/controlplane.yaml" "$TALOS_DIR/worker.yaml" "$TALOS_DIR/talosconfig"
                rm -f ./controlplane.yaml ./worker.yaml ./talosconfig
                echo -e "''${RED}[DONE]''${NC} All configuration files removed."
                echo -e "''${YELLOW}[IMPORTANT]''${NC} Your backup is in: $BACKUP_DIR"
                echo "To restore access: cp $BACKUP_DIR/talosconfig $TALOS_DIR/"
            else
                echo "Cleanup cancelled - confirmation not received"
            fi
            ;;
        *)
            echo "Cleanup cancelled"
            ;;
    esac
    
    # List recent backups
    echo ""
    echo "Recent backups in $TALOS_DIR/backups/:"
    ls -lt "$TALOS_DIR/backups/" 2>/dev/null | head -5 || echo "  No backups found"
  '';

  check_talos = pkgs.writeShellScriptBin "check_talos" ''
    #!/usr/bin/env bash
    set -euo pipefail

    BLUE='\033[0;34m'
    GREEN='\033[0;32m'
    RED='\033[0;31m'
    NC='\033[0m'

    echo "==========================================="
    echo "       Talos Cluster Status Check"
    echo "==========================================="
    echo ""

    # Set TALOS_DIR from config
    TALOS_DIR=''${TALOS_DIR:-"${talosConfig.cluster.configDir}"}
    TALOS_DIR=$(eval echo "$TALOS_DIR")
    DEFAULT_CONTROL_PLANE="${talosConfig.cluster.controlPlaneIP}"
    
    # Try to find talosconfig in multiple locations
    TALOSCONFIG=""
    if [ -f "$TALOS_DIR/talosconfig" ]; then
        TALOSCONFIG="$TALOS_DIR/talosconfig"
        echo -e "''${GREEN}[INFO]''${NC} Using talosconfig from: $TALOS_DIR"
    elif [ -f "./talosconfig" ]; then
        TALOSCONFIG="./talosconfig"
        echo -e "''${GREEN}[INFO]''${NC} Using talosconfig from current directory"
    elif [ -n "''${TALOSCONFIG:-}" ] && [ -f "''${TALOSCONFIG}" ]; then
        echo -e "''${GREEN}[INFO]''${NC} Using talosconfig from TALOSCONFIG env var: $TALOSCONFIG"
    else
        echo -e "''${RED}[ERROR]''${NC} talosconfig not found!"
        echo ""
        echo "Searched locations:"
        echo "  - $TALOS_DIR/talosconfig"
        echo "  - ./talosconfig"
        echo "  - \$TALOSCONFIG environment variable"
        echo ""
        echo "Run install_talos first, or set TALOS_DIR or TALOSCONFIG environment variable"
        exit 1
    fi

    CONTROL_PLANE_IP=''${1:-$DEFAULT_CONTROL_PLANE}
    
    echo -e "''${BLUE}[INFO]''${NC} Checking control plane: $CONTROL_PLANE_IP"
    echo ""
    
    echo "Cluster Health:"
    echo "---------------"
    talosctl --nodes "$CONTROL_PLANE_IP" --talosconfig="$TALOSCONFIG" health || true
    
    echo ""
    echo "Kubernetes Nodes:"
    echo "-----------------"
    kubectl get nodes || true
    
    echo ""
    echo "Talos Services:"
    echo "---------------"
    talosctl --nodes "$CONTROL_PLANE_IP" --talosconfig="$TALOSCONFIG" services || true
  '';

in
pkgs.mkShell {
  buildInputs = with pkgs; [
    # Talos tools
    talosctl
    talhelper
    
    # Omni Stuff
    # omnix
    # omnictl

    # Raspberry Pi tools  
    rpi-imager
    
    # Kubernetes tools
    kubectl
    kubernetes-helm
    kustomize
    yq-go
    jq
    
    # Custom scripts
    install_talos
    cleanup_talos
    check_talos
  ];

  shellHook = ''
    echo "Talos Manager Development Environment"
    echo ""
    echo "Configuration: nix/talos-config.nix"
    echo "  Cluster: ${talosConfig.cluster.name}"
    echo "  Control Plane: ${talosConfig.cluster.controlPlaneIP}"
    echo "  Workers: ${workerIPsString}"
    echo "  Config Dir: ${talosConfig.cluster.configDir}"
    echo ""
    echo "Available tools:"
    echo "  • talosctl - Talos CLI"
    echo "  • talhelper - Talos configuration helper"
    echo "  • rpi-imager - Raspberry Pi Imager"
    echo "  • kubectl - Kubernetes CLI"
    echo "  • helm - Kubernetes package manager"
    echo ""
    echo "Talos Installation Scripts:"
    echo "  • install_talos  - Interactive Talos cluster installation"
    echo "  • cleanup_talos  - Remove generated configuration files"
    echo "  • check_talos    - Check cluster status"
    echo ""
    echo "To override defaults, set environment variables or edit nix/talos-config.nix"
    echo ""
  '';
}