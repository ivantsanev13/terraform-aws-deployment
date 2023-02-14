#!/bin/bash
sleep 30s
apt-get update
sleep 30s
apt-get install -y nodejs build-essential nfs-kernel-server nfs-common cifs-utils 
mkdir /home/ubuntu/efs-mount-point
mount -t nfs $1:/ /home/ubuntu/efs-mount-point
node /home/ubuntu/app.js > some.logs 2>1&