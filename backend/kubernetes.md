# Configuration
To be able to manage the cubernetes cluster, we first need to install its secrets and kubectl tool.
Then we need to be connected to the forticlient VPN, and create an ssh tunnel to the port 6443, by doing:
```ssh_PTI1_tunnel```

An alias equivalent to:
```ssh -N -L 6443:127.0.0.1:6443 alumne@nattech.fib.upc.edu -p 22037```

# Freelens
We can use this program to monitor our kubernetes cluster.
It has the same requirements as kubectl, so as far as you have the forticlient VPN and ssh tunnel you should be fine