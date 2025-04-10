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
server-id = 2
relay_log = /var/log/mysql/mysql-relay-bin.log
log_bin = /var/log/mysql/mysql-bin.log
binlog_do_db = accounts_db
read_only = 1
default_authentication_plugin=mysql_native_password
EOF

# Redémarrage de MySQL
systemctl restart mysql

mysql -e "CREATE DATABASE accounts_db CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"

# Importation du dump si disponible
if [ -f "/vagrant/accounts_db_dump.sql" ]; then
    echo "=== Importation du dump initial ==="
    mysql accounts_db < /vagrant/accounts_db_dump.sql
else
    echo "=== ATTENTION: Dump initial non trouvé, la réplication pourrait ne pas fonctionner correctement ==="
fi

# Récupération du statut du master
echo "=== Récupération du statut du master ==="
MASTER_STATUS=$(mysql -h 192.168.56.20 -u replica -ppassword -e "SHOW MASTER STATUS\G")

# Vérifier si la commande a réussi
if [ $? -ne 0 ]; then
    echo "ERREUR: Impossible de récupérer le statut du master. Vérifiez la connectivité."
    exit 1
fi

# Récupération du statut du master
echo "=== Récupération du statut du master ==="
MASTER_STATUS=$(mysql -h 192.168.56.20 -u replica -ppassword -e "SHOW MASTER STATUS\G")
MASTER_LOG_FILE=$(echo "$MASTER_STATUS" | grep "File:" | awk '{print $2}')
MASTER_LOG_POS=$(echo "$MASTER_STATUS" | grep "Position:" | awk '{print $2}')

echo "Master log file: $MASTER_LOG_FILE"
echo "Master log position: $MASTER_LOG_POS"

# Configuration de la réplication
mysql -u root -ppassword -e "STOP SLAVE;"
mysql -u root -ppassword -e "RESET SLAVE;"
mysql -u root -ppassword -e "CHANGE MASTER TO \
  MASTER_HOST='192.168.56.20', \
  MASTER_USER='replica', \
  MASTER_PASSWORD='password', \
  MASTER_LOG_FILE='$MASTER_LOG_FILE', \
  MASTER_LOG_POS=$MASTER_LOG_POS;"
mysql -u root -ppassword -e "START SLAVE;"

SHOW SLAVE STATUS;

# Création de l'utilisateur en lecture seule (séparé du bloc précédent)
mysql <<EOF
CREATE USER IF NOT EXISTS 'readonly_user'@'192.168.56.%' IDENTIFIED BY 'password';
GRANT SELECT ON accounts_db.* TO 'readonly_user'@'192.168.56.%';
FLUSH PRIVILEGES;
EOF

# Vérification de la configuration
echo "=== Vérification de la réplication ==="
mysql -e "SHOW SLAVE STATUS\G" | grep -E 'Slave_IO_Running|Slave_SQL_Running|Seconds_Behind_Master|Last_Error'
echo "=== Vérification des utilisateurs ==="
mysql -e "SELECT User, Host FROM mysql.user WHERE User IN ('readonly_user', 'replica');"
echo "=== Vérification des droits ==="
mysql -e "SHOW GRANTS FOR 'readonly_user'@'192.168.56.%';"