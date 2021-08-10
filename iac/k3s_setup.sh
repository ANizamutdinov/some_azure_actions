#!/bin/bash


##################
# Master pool setup

MASTER_NODES=( $(terraform output  -json | jq -r .master_fqdns.value[][]) )
LBFQDN=$(terraform output  -json | jq -r .lbfqdn.value[])


for i in "${!MASTER_NODES[@]}"; do
  hostname="${MASTER_NODES[$i]}"
  ssh-keygen -R "$hostname"

  if [ $i -le 0 ]; then
#    Install first K3s server and init embedded etcd
    ssh -q "$hostname" "curl -sfL https://get.k3s.io | sh -s - server --cluster-init --tls-san ${LBFQDN}"

#    Get cluster token
    TOKEN=$(ssh -q "$hostname" "sudo cat /var/lib/rancher/k3s/server/node-token")

#    Setup local kubeconfig
    ssh -q "$hostname" "sudo cp -v /etc/rancher/k3s/k3s.yaml \$HOME"
    ssh -q "$hostname" "sudo chown \$USER k3s.yaml"
    scp "$hostname":~/k3s.yaml ~/.kube/config
    sed -i "s/127.0.0.1/${LBFQDN}/g" ~/.kube/config

    sleep 150

  else

#    Install K3s servers and attach them to existing one
    ssh -q "$hostname" "curl -sfL https://get.k3s.io | K3S_URL=https://172.19.0.36:6443 K3S_TOKEN=${TOKEN} sh -s - server --tls-san ${LBFQDN}"

  fi
done


##################
# Agent pool setup

AGENT_NODES=( $(terraform output  -json | jq -r .agent_fqdns.value[][]) )
for i in "${!AGENT_NODES[@]}"; do
  hostname="${AGENT_NODES[$i]}"
  ssh-keygen -R "$hostname"

#  Install K3s agent nodes
  ssh -q "$hostname" "curl -sfL https://get.k3s.io | K3S_URL=https://172.19.0.36:6443 K3S_TOKEN=${TOKEN} sh -"
done
