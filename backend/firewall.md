# Rules to implement
Nodes A and B represent our kubernetes nodes.
- Between any Node A and Node B, no filtering
- Allow external traffic for the following ports:
    - ssh (port 22)
    - public ports (8080-8089)

In case that during development or troubleshooting we need to have visibility of other ports from our working computers, we will use an ssh tunnel to expose them securly.

# Firewall
To implement these rules we will use the nftables.

## Installation
```apt install nftables```

## Configuration
Nftables saves its configuration in:
```/etc/nftables.conf```

To write the rule sets configured in runtime, we write them to the conf file and restart the service.

```
nft list ruleset > /etc/nftables.conf
systemctl restart nftables.service
```

## Table
A table is a logical container to organize firewall configuration.It contains related chains, sets, maps, and flowtables under a specific network address family.

## Chain
A chain is a group of rules defined for a specific hook, meaning when the ruleset should be used: INPUT, OUTPUT, PREROUTING, FORWARDING, ...

A chain has a default policy (accept / drop). When a packet enters the chain, it will go through all of the rules, in the order they are defined. In case a condition with the packet its met, it will apply the policy attached to that rule.

If no rule is matched, it will have the default policy applied.

## Our configuration
Each node will have the following configuration

We create a trusted ip adresses group, with all our node's ips. Communication incomming from one of these ips will be let trough. 

Any external will only be allowed the port 22 (ssh), the public ports (8080-8089).

One important thing is that we must leave the forwarding to accept all by default, as kubernetes can route traffic between them, when pods communicate between each other.
```
#!/usr/sbin/nft -f

flush ruleset

table inet firewall {

    # Trusted IP addresses (IPv4)
    set trusted_ipv4 {
        type ipv4_addr
        flags interval
        elements = {
            172.16.4.37,
            172.16.4.33
        }
    }

    chain input {
        type filter hook input priority filter;
        policy drop;

        # Allow loopback
        iifname "lo" accept

        # Allow established and related connections
        ct state established,related accept

        # Drop invalid packets
        ct state invalid drop

        # Allow EVERYTHING from trusted IPv4 addresses
        ip saddr @trusted_ipv4 accept

        # Allow selected TCP ports from everyone else
        tcp dport { 22, 8080-8089 } accept

        # Everything else is dropped by default
    }

    chain forward {
        type filter hook forward priority filter;
        policy accept;
    }

    chain output {
        type filter hook output priority filter;
        policy accept;
    }
}
```