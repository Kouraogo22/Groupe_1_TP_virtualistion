#!/bin/bash

# Mise à jour et installation de MySQL
apt-get update
apt-get install -y mysql-server
systemctl enable mysql
systemctl start mysql

# Modification de l'adresse de liaison
sudo sed -i '/^\s*bind-address\s*=/ s/=.*/= 0.0.0.0/' /etc/mysql/mysql.conf.d/mysqld.cnf

# Configuration de la réplication
cat > /etc/mysql/mysql.conf.d/replication.cnf <<EOF
[mysqld]
server-id=1
log_bin=/var/log/mysql/mysql-bin.log
binlog_do_db=accounts_db
binlog_format=ROW
expire_logs_days=7
max_binlog_size=100M
sync_binlog=1
default_authentication_plugin=mysql_native_password
EOF

# Redémarrage de MySQL
systemctl restart mysql

# Création de la base de données et des utilisateurs
mysql <<MYSQL_SCRIPT
CREATE DATABASE accounts_db CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

USE accounts_db;

CREATE TABLE accounts (
    id INT AUTO_INCREMENT PRIMARY KEY,
    nom VARCHAR(100) NOT NULL,
    email VARCHAR(100) NOT NULL UNIQUE,
    password VARCHAR(255) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Utilisateur réplication
CREATE USER 'replica'@'192.168.56.21' IDENTIFIED BY 'password';
GRANT REPLICATION SLAVE ON *.* TO 'replica'@'192.168.56.21';

-- Utilisateur application web
CREATE USER 'web_user'@'192.168.56.%' IDENTIFIED BY 'password';
GRANT ALL PRIVILEGES ON accounts_db.* TO 'web_user'@'192.168.56.%';

-- Modifier l'utilisateur de réplication pour utiliser mysql_native_password
ALTER USER 'replica'@'192.168.56.21' IDENTIFIED WITH mysql_native_password BY 'password';

GRANT REPLICATION CLIENT ON *.* TO 'replica'@'192.168.56.21';

FLUSH PRIVILEGES;

MYSQL_SCRIPT

mysqldump --single-transaction --master-data=1 accounts_db > /vagrant/accounts_db_dump.sql
chmod 644 /vagrant/accounts_db_dump.sql

# Vérification de la configuration
echo "=== Vérification ==="
mysql -e "SHOW DATABASES;"
mysql -e "SELECT User, Host FROM mysql.user;"
mysql -e "SHOW MASTER STATUS;"