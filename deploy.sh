#!/bin/bash
# Initialise the configuration
terraform init
# Plan and deploy
terraform plan 
terraform apply -auto-approve
