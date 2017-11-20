#!/bin/bash -e

#set-env.cmd

set APP=%1
set ENV=%2
set COUNT=%3
set SIZE=%4

terraform init 
terraform apply -var "app_name=%APP%" -var "environment=%ENV%" -var "instance_type=%SIZE%"
set terraform_inventory=%terraform_inventory_path%
 

set PUBLIC_ACCESS_POINT=ubuntu-hello-world-dev-1292030207.us-east-1.elb.amazonaws.com

set DB_URL=ubuntu-hello-world-dev-1292030207.us-east-1.elb.amazonaws.com

set ansible_params=DB_HOST=%DB_URL% DB_USER=dummy -var DB_PASS=password

set TF_STATE=terraform.tfstate ansible-playbook --inventory-file=%terraform_inventory% ./playbooks/docker-wordpress.yml --extra-vars "%ansible_params%" --user ubuntu --private-key=%aws_private_key% -v


echo "%PUBLIC_ACCESS_POINT%"