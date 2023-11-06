#!/bin/bash

# Vérifier si les arguments nécessaires sont fournis
if [ "$#" -ne 1 ]; then
    echo "Usage: $0 KEYSTONE_DBPASS" >&2
    exit 1
fi
# Assigner les arguments de ligne de commande à des variables
KEYSTONE_DBPASS=$1
CONTROLLER_HOSTNAME=$(hostname)

# Créer la base de données pour Keystone
mysql -u root -p -e "CREATE DATABASE keystone;"
mysql -u root -p -e "GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'localhost' IDENTIFIED BY '$KEYSTONE_DBPASS';"
mysql -u root -p -e "GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'%' IDENTIFIED BY '$KEYSTONE_DBPASS';"

# Installer Keystone
apt install keystone -y

# Configurer Keystone
sed -i "s/connection = .*/connection = mysql+pymysql:\/\/keystone:$KEYSTONE_DBPASS@$CONTROLLER_HOSTNAME\/keystone/" /etc/keystone/keystone.conf
sed -i "s/provider = .*/provider = fernet/" /etc/keystone/keystone.conf

# Peupler la base de données Identity service
su -s /bin/sh -c "keystone-manage db_sync" keystone

# Initialiser les dépôts de clés Fernet
keystone-manage fernet_setup --keystone-user keystone --keystone-group keystone
keystone-manage credential_setup --keystone-user keystone --keystone-group keystone

# Initialiser les services Identity
keystone-manage bootstrap --bootstrap-password ADMIN_PASS \
  --bootstrap-admin-url http://$CONTROLLER_HOSTNAME:5000/v3/ \
  --bootstrap-internal-url http://$CONTROLLER_HOSTNAME:5000/v3/ \
  --bootstrap-public-url http://$CONTROLLER_HOSTNAME:5000/v3/ \
  --bootstrap-region-id RegionOne

# Configurer Apache
echo "ServerName $CONTROLLER_HOSTNAME" >> /etc/apache2/apache2.conf

# Redémarrer Apache
service apache2 restart

# Configurer le compte administratif
export OS_USERNAME=admin
export OS_PASSWORD=ADMIN_PASS
export OS_PROJECT_NAME=admin
export OS_USER_DOMAIN_NAME=Default
export OS_PROJECT_DOMAIN_NAME=Default
export OS_AUTH_URL=http://$CONTROLLER_HOSTNAME:5000/v3
export OS_IDENTITY_API_VERSION=3

