# SSH
For ssh we use a single key used by all the nodes
.ssh/id_ed25519.pub
.ssh/id_ed25519

# For kubernetes
To access the kubernetes we use the kube config
.kube/config

# S3 terraform states
To access the terraform S3 bucket with the states we use the aws configuration.
For them to be picked by terraform, we must export AWS_PROFILE=terraform
.aws/config
.aws/credentials
