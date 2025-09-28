{ name ? "talos-manager", ... }:
{
  cluster = {
    name = "pissiCluster";
    controlPlaneIP = "192.168.8.161";
    workerIPs = [
      "192.168.8.162"
      "192.168.8.163"
    ];
    diskName = "nvme";
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