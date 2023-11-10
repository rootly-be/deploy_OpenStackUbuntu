. admin-openrc

GLANCE_DBPASS=$(openssl rand -hex $PASS_LEN)

mysql -uroot -p"$DB_ROOT_PASS" <<EOF
CREATE DATABASE glance;
GRANT ALL PRIVILEGES ON glance.* TO 'glance'@'localhost' IDENTIFIED BY '${GLANCE_DBPASS}';
GRANT ALL PRIVILEGES ON glance.* TO 'glance'@'%' IDENTIFIED BY '${GLANCE_DBPASS}';
FLUSH PRIVILEGES;
EOF

KEYSTONE_CON="mysql+pymysql://keystone:${KEYSTONE_DBPASS}@${HOSTNAME}/keystone"






cat << EOF >> admin-openrc
export GLANCE_DBPASS=$GLANCE_DBPASS

EOF