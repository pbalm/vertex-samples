#!/bin/bash

sudo apt update
sudo apt upgrade
sudo apt install python3-pip

pip install google-cloud-aiplatform

install gcloud from the R Studio terminal

sudo apt-get install apt-transport-https ca-certificates gnupg curl python-is-python3 libcurl4-openssl-dev libssl-dev libxml2-dev

echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | sudo tee -a /etc/apt/sources.list.d/google-cloud-sdk.list

curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key --keyring /usr/share/keyrings/cloud.google.gpg add -

sudo apt-get update && sudo apt-get install google-cloud-cli
