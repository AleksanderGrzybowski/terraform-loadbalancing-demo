#!/bin/bash

sudo apt-get update
sudo apt-get -y install nginx
echo "Hello from instance $(hostname)" | sudo tee /var/www/html/index.html