#!/bin/bash

sudo apt update

sudo apt install mysql-server -y

sudo ./secure_mysql.expect $1

sudo systemctl restart mysql.service

sudo systemctl status mysql.service