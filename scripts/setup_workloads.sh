#!/bin/bash
# setup_workloads.sh - VIC BP - Nginx + MariaDB + PHP-FPM workloads
set -euo pipefail
LOG=/root/setup_workloads.log
exec > >(tee -a "$LOG") 2>&1

echo "=== setup_workloads.sh start: $(date -Is) ==="
export DEBIAN_FRONTEND=noninteractive

apt-get install -y --no-install-recommends \
    nginx mariadb-server php-fpm php-mysql

# Detect PHP-FPM versie (Ubuntu 24.04 = php8.3-fpm)
PHP_SOCK="$(ls /run/php/php*-fpm.sock | head -1)"
echo "Gebruik PHP-FPM socket: $PHP_SOCK"

# --- Statisch testbestand ---
cat > /var/www/html/statisch.html <<'EOF'
<!DOCTYPE html><html><body><h1>STATISCH</h1></body></html>
EOF

# --- Dynamisch PHP-script (CPU loop) ---
cat > /var/www/html/dynamisch.php <<'EOF'
<?php
$start = microtime(true);
$x = 0.0;
for ($i = 0; $i < 500000; $i++) { $x += sqrt($i); }
$dur = microtime(true) - $start;
header('Content-Type: text/plain');
echo "ok dur=" . number_format($dur, 6) . " sum=" . $x;
EOF

# --- Nginx config: webserver (poort 80) MET PHP support ---
cat > /etc/nginx/sites-available/default <<EOF
server {
    listen 80 default_server;
    root /var/www/html;
    index index.html index.php;
    access_log off;  # off = lagere overhead, eerlijke I/O meting

    location / { try_files \$uri \$uri/ =404; }
    location ~ \\.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:${PHP_SOCK};
    }
}
EOF

# --- Nginx config: reverse proxy (poort 8080) ---
cat > /etc/nginx/sites-available/reverse_proxy <<'EOF'
server {
    listen 8080;
    access_log off;
    location / {
        proxy_pass http://127.0.0.1:80;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
EOF
ln -sf /etc/nginx/sites-available/reverse_proxy /etc/nginx/sites-enabled/reverse_proxy

# --- MariaDB ---
systemctl enable --now mariadb
mysql <<'SQL'
CREATE DATABASE IF NOT EXISTS sbtest;
CREATE USER IF NOT EXISTS 'vic_tester'@'localhost' IDENTIFIED BY 'geheim123';
GRANT ALL PRIVILEGES ON sbtest.* TO 'vic_tester'@'localhost';
FLUSH PRIVILEGES;
SQL

# --- Pre-load sysbench tabellen (anders meet je table-creatie i.p.v. queries) ---
sysbench oltp_read_write \
    --db-driver=mysql --mysql-user=vic_tester --mysql-password=geheim123 \
    --mysql-db=sbtest --tables=4 --table-size=10000 prepare

# --- Restart services en verify ---
nginx -t
systemctl restart nginx php*-fpm

# --- Smoke test ---
echo "=== Smoke tests ==="
curl -sf http://localhost/statisch.html | head -1
curl -sf http://localhost/dynamisch.php
curl -sf http://localhost:8080/statisch.html | head -1
mysql -uvic_tester -pgeheim123 -e "SHOW TABLES;" sbtest

echo "=== setup_workloads.sh klaar: $(date -Is) ==="
