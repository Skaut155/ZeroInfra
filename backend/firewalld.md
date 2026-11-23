
# Motive
As our virtual machines share the same subnet with every other virtual machine in nebula, we must install a firewall to restrict non-wanted traffic.

# Choice: Firewalld
Complex enough where we can limit who can acces which ports
Automatizable with Ansible

# Current status
For both Kubernetes nodes, only allow external connections to the following ports.
- 22, for ssh
- 6443, kubernetes API
- 10250, kubernetes metrics server
- 8080-8089, public ports

In the future we will harden the security whitelisting IPs for the following ports:
- 6443, kubernetes API
- 10250, kubernetes metrics server

They will only have white-listed the different node's ips.

# Installation
```sudo apt install firewalld```

# Basic Usage
### Get current status
```sudo firewall-cmd --state```

The firewall uses the systemctl service ```firewald```

To start/stop the firewall start/stop this service.

### Reload
```sudo firewall-cmd --reload```

### Add new port rule
```sudo firewall-cmd --add-port=<port-num/range>/<protocol>```

To make it permanent add the  flag ```--permanent``` , as otherwise these rules will be lost when firewall reeboots


