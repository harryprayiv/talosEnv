{ name ? "talos-manager", ... }:
{
  cluster = {
    name = "pissiCluster";
    endpoint = "192.168.8.160";
    controlPlaneIP = "192.168.8.161";
    workerIPs = [
      "192.168.8.162"
      "192.168.8.163"
    ];
    diskName = "nvme0n1";
    # diskName = "nvme"; 
    configDir = "$HOME/.talos";
    backupRetention = 30; # days to keep backups
  };
  
  network = {
    apiPort = 6443;
    kubeletPort = 10250;
    etcdPort = 2379;
  };
  
  settings = {
    bootstrapTimeout = 10; # seconds to wait after bootstrap
    interactiveMode = true;
    insecureMode = true; # for initial setup
  };
}

/* 

Available commands from TalosCTL:
  apply-config        Apply a new configuration to a node
  bootstrap           Bootstrap the etcd cluster on the specified node.
  cgroups             Retrieve cgroups usage information
  cluster             A collection of commands for managing local docker-based or QEMU-based clusters
  completion          Output shell completion code for the specified shell (bash, fish or zsh)
  config              Manage the client configuration file (talosconfig)
  conformance         Run conformance tests
  containers          List containers
  copy                Copy data out from the node
  dashboard           Cluster dashboard with node overview, logs and real-time metrics
  dmesg               Retrieve kernel logs
  edit                Edit a resource from the default editor.
  etcd                Manage etcd
  events              Stream runtime events
  gen                 Generate CAs, certificates, and private keys
  get                 Get a specific resource or list of resources (use 'talosctl get rd' to see all available resource types).
  health              Check cluster health
  help                Help about any command
  image               Manage CRI container images
  inject              Inject Talos API resources into Kubernetes manifests
  inspect             Inspect internals of Talos
  kubeconfig          Download the admin kubeconfig from the node
  list                Retrieve a directory listing
  logs                Retrieve logs for a service
  machineconfig       Machine config related commands
  memory              Show memory usage
  meta                Write and delete keys in the META partition
  mounts              List mounts
  netstat             Show network connections and sockets
  patch               Update field(s) of a resource using a JSON patch.
  pcap                Capture the network packets from the node.
  processes           List running processes
  read                Read a file on the machine
  reboot              Reboot a node
  reset               Reset a node
  restart             Restart a process
  rollback            Rollback a node to the previous installation
  rotate-ca           Rotate cluster CAs (Talos and Kubernetes APIs).
  service             Retrieve the state of a service (or all services), control service state
  shutdown            Shutdown a node
  stats               Get container stats
  support             Dump debug information about the cluster
  time                Gets current server time
  upgrade             Upgrade Talos on the target node
  upgrade-k8s         Upgrade Kubernetes control plane in the Talos cluster.
  usage               Retrieve a disk usage
  validate            Validate config
  version             Prints the version
  wipe                Wipe block device or volumes

Use "talosctl [command] --help" for more information about a command. 

*/