#!/bin/bash

# Stop script on any error
set -e

# Configuring needrestart
sed -i 's/#$nrconf{restart} = '"'"'i'"'"';/$nrconf{restart} = '"'"'a'"'"';/g' /etc/needrestart/needrestart.conf

# Updating and installing necessary packages
apt update && apt upgrade -y
apt install inetutils-ping crudini chrony python3-openstackclient mariadb-server python3-pymysql vim rabbitmq-server memcached python3-memcache etcd keystone -y

# Length for generated passwords
PASS_LEN=25

# Network configuration
INTERFACE="ens18"
IP_LAN=$(ip -4 addr show $INTERFACE | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
sed -i "s/127.0.1.1/$IP_LAN/g" /etc/hosts

# MariaDB configuration
cat << EOF | tee /etc/mysql/mariadb.conf.d/99-openstack.cnf > /dev/null
[mysqld]
bind-address = ${IP_LAN}
default-storage-engine = innodb
innodb_file_per_table = on
max_connections = 4096
collation-server = utf8_general_ci
character-set-server = utf8
EOF

DB_ROOT_PASS=$(openssl rand -hex $PASS_LEN)

# Configuring MariaDB database
mysql_secure_installation <<EOF
y
$DB_ROOT_PASS
$DB_ROOT_PASS
y
y
y
y
EOF

systemctl restart mariadb
systemctl enable mariadb

# Installing and configuring RabbitMQ
RABBIT_PASS=$(openssl rand -hex $PASS_LEN)
rabbitmqctl add_user openstack $RABBIT_PASS
rabbitmqctl set_permissions openstack ".*" ".*" ".*"
systemctl restart rabbitmq-server
systemctl enable rabbitmq-server

# Configuring Memcached
sed -i "s/-l 127.0.0.1/-l $IP_LAN/g" /etc/memcached.conf 
systemctl restart memcached
systemctl enable memcached

# Configuring ETCD
cat << EOF |tee -a /etc/default/etcd > /dev/null
ETCD_NAME="$HOSTNAME"
ETCD_DATA_DIR="/var/lib/etcd"
ETCD_INITIAL_CLUSTER_STATE="new"
ETCD_INITIAL_CLUSTER_TOKEN="etcd-cluster-01"
ETCD_INITIAL_CLUSTER="$HOSTNAME=http://$IP_LAN:2380"
ETCD_INITIAL_ADVERTISE_PEER_URLS="http://$IP_LAN:2380"
ETCD_ADVERTISE_CLIENT_URLS="http://$IP_LAN:2379"
ETCD_LISTEN_PEER_URLS="http://0.0.0.0:2380"
ETCD_LISTEN_CLIENT_URLS="http://$IP_LAN:2379"
EOF

systemctl restart etcd
systemctl enable etcd

# Configuring Keystone
KEYSTONE_DBPASS=$(openssl rand -hex $PASS_LEN)
KEYSTONE_CON="mysql+pymysql://keystone:${KEYSTONE_DBPASS}@${HOSTNAME}/keystone"

mysql -uroot -p"$DB_ROOT_PASS" <<EOF
CREATE DATABASE keystone;
GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'localhost' IDENTIFIED BY '${KEYSTONE_DBPASS}';
GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'%' IDENTIFIED BY '${KEYSTONE_DBPASS}';
FLUSH PRIVILEGES;
EOF

crudini --set /etc/keystone/keystone.conf database connection $KEYSTONE_CON
crudini --set /etc/keystone/keystone.conf token provider fernet
su -s /bin/sh -c "keystone-manage db_sync" keystone
keystone-manage fernet_setup --keystone-user keystone --keystone-group keystone
keystone-manage credential_setup --keystone-user keystone --keystone-group keystone

# Initial configuration for Keystone
ADMIN_PASS=$(openssl rand -hex $PASS_LEN)
keystone-manage bootstrap --bootstrap-password $ADMIN_PASS --bootstrap-admin-url http://$HOSTNAME:5000/v3/ --bootstrap-internal-url http://$HOSTNAME:5000/v3/ --bootstrap-public-url http://$HOSTNAME:5000/v3/ --bootstrap-region-id RegionOne

sed -i "1 i\ServerName $HOSTNAME" /etc/apache2/apache2.conf

systemctl restart apache2.service
systemctl enable apache2.service

# Creating OpenStack environment variables file
cat << EOF > admin-openrc
export OS_USERNAME=admin
export OS_PASSWORD=$ADMIN_PASS
export OS_PROJECT_NAME=admin
export OS_USER_DOMAIN_NAME=Default
export OS_PROJECT_DOMAIN_NAME=Default
export OS_AUTH_URL=http://$HOSTNAME:5000/v3
export OS_IDENTITY_API_VERSION=3
EOF

# Displaying generated passwords
echo "DB ROOT PASSWORD : $DB_ROOT_PASS"
echo "RABBIT PASSWORD : $RABBIT_PASS"
echo "ADMIN PASSWORD : $ADMIN_PASS"
echo "KEYSTONE DB PASS : $KEYSTONE_DBPASS"
