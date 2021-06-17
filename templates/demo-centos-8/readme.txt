Stackable cluster setup files (CentOS 7)

This folder contains files that help you set up a running Stackable cluster in the cloud.

WARNING! Although we put much effort into it and do not know of any flaw, this cluster setup package 
is provided "as is", without warranty of any kind. You use it at your own risk.

What does this package provide?

In this package you find all the Terraform and Ansible files you need to create a working Stackable 
cluster in the IONOS cloud (https://cloud.ionos.de/).

What do I need?

* an account for the IONOS cloud
* Terraform v0.15.0 or higher
* Ansible v2.9.16 or higher
* at least one of the private SSH keys matching one of the public keys provided during generation of this package

How do I provision the Stackable cluster?

Terraform

To run the Terraform scripts you need to provide the following variables

* ionos_username
* ionos_password
* cluster_name

You can either just type them when prompted to do so or put them into an environment variable beforehand. 
If doing the latter, remember to add the prefix 'TF_VAR_' to the variable name.

To create the resources with Terraform:

* run 'terraform init'
* run 'terraform plan'
* run 'terraform apply'

Besides the obvious resources created (datacenter, networks, servers), Terraform will create files in this
directory. On the one hand, there are files needed by Ansible (next step). On the other hand, there are files
you might need later on (convenient way to SSH into cluster, VPN setup stuff...)

Ansible

If the creation of Terraform resources was successful, you can execute the provided Ansible playbook:

* run 'ansible-playbook launch.yml'

The explanation of all the steps Ansible performs here would go way beyond the scope of this readme.
Please feel free to have a look into the files and find out yourselves ;-)

Update the Stackable components in the cluster

The scripts update_agent.sh and update_operator.sh help you to update (or downgrade) the Stackable components
in the cluster. 

* The script update_agent.sh shows you the available and installed versions of the agent and prompts you to 
  type the version you like to install. Then an Ansible playbook is started and does the actual up- or downgrade.
* The script update_operator.sh shows you the available operators and lets you choose the operator to up- or downgrade.
  Then it shows you the available and installed versions of the chosen operator and prompts you to 
  type the version you like to install. Then an Ansible playbook is started and does the actual up- or downgrade.

Access the cluster (without VPN)

To use the cluster without a VPN, you can use the 'Stackable client script' to interact with the cluster
via SSH. This script is created for you in the resources/ folder and is named 'stackable.sh'

The script expects the private SSH key to be in your keystore (~/.ssh/ in Linux). If you keep it outside of 
your keystore, you can provide the path to the private key with the '-i' option.

To ssh into a host, just provide the hostname as the single parameter, e.g.

./stackable.sh orchestrator

If you want to execute a command on the host, you can add a command as a second param, e.g.

./stackable.sh orchestrator "kubectl get nodes"

VPN

In the folder resources/wireguard-client-config/ you find a bunch of prepared Wireguard configs to access
the cluster via a VPN. Please refer to the Wireguard docs for your OS to learn how to apply the config.
You only need one of the files, we provide several of them if you are using the cluster with multiple users.