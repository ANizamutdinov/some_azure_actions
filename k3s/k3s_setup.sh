#!/bin/bash

function Allocate_vms() {
  ##############
  # Allocate VMs
  ##############

  terraform init -backend-config=../lab.backend.hcl

  # Create Load balancers
  terraform plan -target=module.lb -out=lb_kctl.tfplan
  terraform plan -target=module.lb_wload -out=lb_wload.tfplan

  terraform apply -auto-approve=true lb_kctl.tfplan
  terraform apply -auto-approve=true lb_wload.tfplan

  # Create rest resources
  terraform plan -out=common.tfplan
  terraform apply -auto-approve=true common.tfplan
}

function setup_masters() {
  ###################
  # Master pool setup
  ###################

  MASTER_NODES=( $(terraform output  -json | jq -r .master_fqdns.value[][]) )
  LBFQDN=$(terraform output  -json | jq -r .lbfqdn.value[])


  for i in "${!MASTER_NODES[@]}"; do
    hostname="${MASTER_NODES[$i]}"
    ssh-keygen -R "$hostname"

    if [ "$i" -le 0 ]; then
  #    Install first K3s server and init embedded etcd
      ssh -q "$hostname" "curl -sfL https://get.k3s.io | sh -s - server --cluster-init --tls-san ${LBFQDN}"

  #    Get cluster token
      TOKEN=$(ssh -q "$hostname" "sudo cat /var/lib/rancher/k3s/server/node-token")
      MASTER_IP=$(ssh -q "$hostname" "ip -4 addr show eth0 | grep inet | xargs | cut -d \" \" -f 2 | cut -d \"/\" -f 1")

  #    Setup local kubeconfig
      ssh -q "$hostname" "sudo cp -v /etc/rancher/k3s/k3s.yaml \$HOME"
      ssh -q "$hostname" "sudo chown \$USER k3s.yaml"
      scp "$hostname":~/k3s.yaml ~/.kube/config
      sed -i "s/127.0.0.1/${LBFQDN}/g" ~/.kube/config

      sleep 150

    else

  #    Install K3s servers and attach them to existing one
      ssh -q "$hostname" "curl -sfL https://get.k3s.io | K3S_URL=https://${MASTER_IP}:6443 K3S_TOKEN=${TOKEN} sh -s - server --tls-san ${LBFQDN}"

    fi
  done
}

function setup_agents() {
  ##################
  # Agent pool setup
  ##################

  AGENT_NODES=( $(terraform output  -json | jq -r .agent_fqdns.value[][]) )
  for i in "${!AGENT_NODES[@]}"; do
    hostname="${AGENT_NODES[$i]}"
    ssh-keygen -R "$hostname"

  #  Install K3s agent nodes
    ssh -q "$hostname" "curl -sfL https://get.k3s.io | K3S_URL=https://${MASTER_IP}:6443 K3S_TOKEN=${TOKEN} sh -"
  done
}

function setup_deployment() {
    kubectl apply -f definitions/service_nginx.yaml
    kubectl apply -f definitions/service_php.yaml

    kubectl apply -f definitions/config_nginx.yaml

    kubectl apply -f definitions/deployment_nginx.yaml
    kubectl apply -f definitions/deployment_php.yaml
}

setup_deployment