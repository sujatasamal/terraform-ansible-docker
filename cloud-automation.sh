#!/bin/bash -e

source ./set-env.sh

APP="$1"
ENV="$2"
COUNT="$3"
INSTANCE="$4"

terraform apply -var "app_name=${APP}" -var "environment=${ENV}" -var "count=${COUNT}" -var "instance_type=${INSTANCE}"
export terraform_inventory=${terraform_inventory_path}
export PUBLIC_ACCESS_POINT=$(terraform output | grep app_entrypoint_address | cut -d = -f2)
export DB_URL=$(cat terraform.tfstate | grep endpoint | cut -d : -f2- | tr -d '"' | tr -d , | tr -d ' ')
export ansible_params="DB_HOST=${DB_URL} DB_USER=${DB_USERNAME} -var DB_PASS=${DB_PASSWORD}"
TF_STATE=terraform.tfstate ansible-playbook --inventory-file=${terraform_inventory} ./playbooks/docker-wordpress.yml --extra-vars "${ansible_params}" --user ubuntu --private-key=${aws_private_key}/ -v


echo "${PUBLIC_ACCESS_POINT}"