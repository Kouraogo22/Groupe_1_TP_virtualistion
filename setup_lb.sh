#!/bin/bash
apt-get update
apt-get install -y nginx
systemctl enable nginx
systemctl start nginx
# Configurer Nginx comme Load Balancer
echo "
upstream backend {
    server 192.168.56.11;
    server 192.168.56.12;
}
server {
    listen 80;
    location / {
        proxy_pass http://backend;
    }
}" > /etc/nginx/sites-available/default
systemctl restart nginx