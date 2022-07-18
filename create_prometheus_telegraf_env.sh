#!/bin/bash

VERSION="2.37.0"
AVERSION="0.24.0"

INSTALL_DOCKER=0
INSTALL_PROMETHEUS=0
INSTALL_ALERTMANAGER=0
INSTALL_WEBHOOK=0
INSTALL_TELEGRAF=0
INSTALL_GRAFANA=0
INSTALL_TELEGRAF_AGENTS=1


if [ $INSTALL_DOCKER -eq 1 ]
then

## Install docker
sudo apt-get remove docker docker-engine docker.io containerd runc
sudo apt-get update
sudo apt-get install ca-certificates curl gnupg lsb-release apt-transport-https software-properties-common -y

if [ ! -d -v /etc/apt/keyrings/ ]
then
sudo mkdir -p -v /etc/apt/keyrings/
fi

curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update
sudo apt-get install docker-ce docker-ce-cli containerd.io docker-compose-plugin
#sudo apt-get install docker-ce=<VERSION_STRING> docker-ce-cli=<VERSION_STRING> containerd.io docker-compose-plugin
sudo docker run hello-world
fi


if [ $INSTALL_PROMETHEUS -eq 1 ]
then

## Install prometheus
mkdir /opt/prometheus
cd /opt/prometheus
wget https://github.com/prometheus/prometheus/releases/download/v${VERSION}/prometheus-${VERSION}.linux-amd64.tar.gz
tar xvfz prometheus-${VERSION}.linux-amd64.tar.gz
cd prometheus-*.*-amd64


sudo useradd --no-create-home --shell /bin/false prometheus
sudo mkdir /etc/prometheus
sudo mkdir /etc/prometheus/alerts
sudo mkdir /var/lib/prometheus
sudo chown prometheus:prometheus /etc/prometheus
sudo chown prometheus:prometheus /etc/prometheus/alerts
sudo chown prometheus:prometheus /var/lib/prometheus
sudo chown prometheus:prometheus /opt/prometheus/prometheus-${VERSION}.linux-amd64/prometheus
sudo chown prometheus:prometheus /opt/prometheus/prometheus-${VERSION}.linux-amd64/promtool
sudo cp -r /opt/prometheus/prometheus-${VERSION}.linux-amd64/consoles /etc/prometheus
sudo cp -r /opt/prometheus/prometheus-${VERSION}.linux-amd64/console_libraries /etc/prometheus
sudo chown -R prometheus:prometheus /etc/prometheus/consoles
sudo chown -R prometheus:prometheus /etc/prometheus/console_libraries

cat > /etc/prometheus/prometheus.yml << EOF
global:
  scrape_interval: 15s

alerting:
  alertmanagers:
    - static_configs:
      - targets:
        - localhost:9093

rule_files:
  - 'alerts/*.yml'

scrape_configs:
  - job_name: 'prometheus'
    scrape_interval: 5s
    static_configs:
      - targets: ['localhost:9090']
  - job_name: 'alertmanager'
    static_configs:
    - targets: ['localhost:9093']
EOF

sudo chown prometheus:prometheus /etc/prometheus/prometheus.yml

#Start Skript erstellen
cat > /etc/systemd/system/prometheus.service << EOF
[Unit]
Description=prometheus
 
[Service]
User=prometheus
Group=prometheus
#EnvironmentFile=-/etc/sysconfig/prometheus
ExecStart=/opt/prometheus/prometheus-${VERSION}.linux-amd64/prometheus \
    --config.file /etc/prometheus/prometheus.yml \
    --storage.tsdb.path /var/lib/prometheus/ \
    --web.console.templates=/etc/prometheus/consoles \
    --web.console.libraries=/etc/prometheus/console_libraries \
    --enable-feature=remote-write-receiver
[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl start prometheus
systemctl enable prometheus
systemctl status prometheus

fi

###

if [ $INSTALL_ALERTMANAGER -eq 1 ]
then

mkdir /opt/alertmanager
cd /opt/alertmanager
wget https://github.com/prometheus/alertmanager/releases/download/v${AVERSION}/alertmanager-${AVERSION}.linux-amd64.tar.gz
tar xvfz alertmanager-${AVERSION}.linux-amd64.tar.gz
cd alertmanager-*.*-amd64

sudo useradd --no-create-home --shell /bin/false alertmanager
sudo mkdir -v /opt/alertmanager/data

alertmanager-${AVERSION}.linux-amd64

cp /opt/alertmanager/alertmanager-${AVERSION}.linux-amd64/alertmanager /opt/alertmanager
cp /opt/alertmanager/alertmanager-${AVERSION}.linux-amd64/alertmanager.yml /opt/alertmanager
cp /opt/alertmanager/alertmanager-${AVERSION}.linux-amd64/amtool /opt/alertmanager

#Start Skript erstellen
cat > /etc/systemd/system/alertmanager.service << EOF
[Unit]
Description=Alertmanager for prometheus
[Service]
Restart=always
User=alertmanager
ExecStart=/opt/alertmanager/alertmanager --config.file=/opt/alertmanager/alertmanager.yml --storage.path=/opt/alertmanager/data            
ExecReload=/bin/kill -HUP $MAINPID
TimeoutStopSec=20s
SendSIGKILL=no
[Install]
WantedBy=multi-user.target
EOF

cat > /etc/prometheus/rules.yml << EOF
groups:
 - name: test
   rules:
   - alert: InstanceDown
     expr: up == 0
     for: 1m
EOF

cat > /opt/alertmanager/alertmanager.yml << EOF
route:
  group_by: ['alertname']
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 1h
  receiver: 'web.hook'
receivers:
  - name: 'web.hook'
    webhook_configs:
      - url: 'http://127.0.0.1:5001/api/print'
  - name: 'gmail'
    email_configs:
    - to: '<google-username>@gmail.com'
      from: '<google-username>@gmail.com'
      smarthost: smtp.gmail.com:587
      auth_username: '<google-username>@gmail.com'
      auth_identity: '<google-username>@gmail.com'
      auth_password: '<google-app-password>'
inhibit_rules:
  - source_match:
      severity: 'critical'
    target_match:
      severity: 'warning'
    equal: ['alertname', 'dev', 'instance']
EOF
sudo chown -Rfv alertmanager:alertmanager /opt/alertmanager

sudo systemctl daemon-reload
sudo systemctl start alertmanager.service
sudo systemctl enable alertmanager.service
sudo systemctl status alertmanager.service

sudo systemctl restart prometheus.service
sudo systemctl status prometheus.service

# sudo journalctl --follow --no-pager --boot --unit alertmanager.service

fi

if [ $INSTALL_WEBHOOK -eq 1 ]
then
sudo useradd --no-create-home --shell /bin/false webhook
 
if [ ! -d -v /opt/webhook/webhook/ ]
then
sudo mkdir -p -v /opt/webhook/webhook/
fi


cd /opt/webhook/
sudo apt upgrade
sudo apt install -y python3 python3-pip build-essential libssl-dev python3-dev python3-venv
cd /opt/webhook/
python3 -m venv venv
chown -R webhook:webhook /opt/webhook/
source ./venv/bin/activate
python3 -m pip install --upgrade pip

cat > /opt/webhook/requirements.txt << EOF
flask
urllib3
gunicorn
EOF
python3 -m pip install -r requirements.txt

cat > /opt/webhook/webhook.py << EOF
import json
from datetime import datetime
from urllib.parse import urlparse
from flask import Flask, jsonify, request

app = Flask(__name__)

@app.route("/", methods=["GET"])
def index():
    return("online", 200, None)

@app.route("/api/print", methods=["POST"])
def printlog():
    payload = request.json
    print(f"payload: {payload}") 
    now = datetime.now()
    dt_string = now.strftime("%d/%m/%Y %H:%M:%S\n")
    with open("/opt/webhook/LOG.txt", "a+") as file:
        file.write(dt_string)
        file.write(request.base_url)
        file.write(json.dumps(payload, indent=4, sort_keys=True))
        file.write("\n")
        return ("", 200, None)
    return ("", 404, None)

if __name__ == '__main__':
    app.run(debug=True, port=5001, host='127.0.0.1', use_reloader=True)
EOF

cat > /opt/webhook/wsgi.py << EOF
from webhook import app
if __name__ == "__main__":
    app.run()
EOF

chown -R webhook:webhook /opt/webhook/

sudo cat > /etc/systemd/system/webhook.service << EOF
[Unit]
Description=webhook service
Documentation=https://docs.python.org/3/library/http.server.html
After=network.target

[Service]
Type=simple
User=webhook
Group=webhook
WorkingDirectory=/opt/webhook/
Environment="VIRTUAL_ENV=/opt/webhook/venv/"
Environment="PATH=$VIRTUAL_ENV/bin:$PATH"
Environment="FLASK_CONFIG=production"
ExecStart=/opt/webhook/venv/bin/gunicorn --workers 3 -b localhost:5001 -w 4 --chdir /opt/webhook/ webhook:app
Restart=always

[Install]
WantedBy=multi-user.target
EOF


sudo systemctl daemon-reload
sudo systemctl start webhook.service
sudo systemctl enable webhook.service
sudo systemctl status webhook.service


curl -X POST -H 'Content-Type: application/json' -d '{"message": "hallo"}' http://localhost:5001/api/print
fi

###

if [ $INSTALL_TELEGRAF -eq 1 ]
then

cat <<EOF | sudo tee /etc/apt/sources.list.d/influxdata.list
deb https://repos.influxdata.com/ubuntu $(lsb_release -cs) stable
EOF
sudo curl -sL https://repos.influxdata.com/influxdb.key | sudo apt-key add -
sudo apt update
sudo apt install telegraf
#sudo systemctl enable --now telegraf
#sudo systemctl status telegraf

/usr/bin/telegraf -config /etc/telegraf/telegraf_agent.conf

fi

###

if [ $INSTALL_GRAFANA -eq 1 ]
then

sudo curl -sL https://packages.grafana.com/gpg.key | sudo apt-key add -
sudo add-apt-repository "deb https://packages.grafana.com/oss/deb stable main"
sudo apt update
sudo apt install grafana
sudo systemctl start grafana-server
sudo systemctl status grafana-server
sudo systemctl enable grafana-server

fi

###

if [ $INSTALL_TELEGRAF_AGENTS -eq 1 ]
then

if [ ! -d /opt/telegraf/agents ]
then
mkdir -p /opt/telegraf/agents
fi


cat > /opt/telegraf/telegraf_agent.conf << EOF
[global_tags]
[agent]
 interval = "10s"
 round_interval = true
 metric_batch_size = 1000
 metric_buffer_limit = 10000
 collection_jitter = "0s"
 flush_interval = "10s"
 flush_jitter = "0s"
 precision = "0s"
 hostname = "agentAGeNTiD"
 omit_hostname = false
[[inputs.cpu]]
 percpu = true
 totalcpu = true
 collect_cpu_time = false
 report_active = false
[[inputs.disk]]
 ignore_fs = ["tmpfs", "devtmpfs", "devfs", "iso9660", "overlay", "aufs", "squashfs"]
[[inputs.diskio]]
[[inputs.kernel]]
[[inputs.mem]]
[[inputs.processes]]
[[inputs.swap]]
[[inputs.system]]
[[inputs.kernel_vmstat]]
   # no configuration
[[inputs.linux_sysctl_fs]]
[[inputs.net]]
[[inputs.net_response]]
  protocol = "tcp"
  address = "localhost:80"
  timeout = "1s"
[[inputs.netstat]]
[[inputs.nstat]]
  proc_net_netstat = "/proc/net/netstat"
  proc_net_snmp = "/proc/net/snmp"
  proc_net_snmp6 = "/proc/net/snmp6"
  dump_zeros       = true
[[outputs.http]]
 url = "http://4.159.215.142:9090/api/v1/write"
 data_format = "prometheusremotewrite"
  [outputs.http.headers]
     Content-Type = "application/x-protobuf"
     Content-Encoding = "snappy"
     X-Prometheus-Remote-Write-Version = "0.1.0"
[[inputs.exec]]
  commands = ["date '+%s'"]
  timeout = "1s"
  name_override="unixtime"
  data_format="value"
  data_type="integer"
EOF

for i in {1..100}
do
  echo "starting agent$i..."
  sed -e 's/AGeNTiD/'"${i}"'/' /opt/telegraf/telegraf_agent.conf > /opt/telegraf/agents/telegraf_agent_${i}.conf
  docker run -d -v /opt/telegraf/agents/telegraf_agent_${i}.conf:/etc/telegraf/telegraf.conf:ro telegraf
done

fi



# Shell Kommandos
# docker ps -a | awk -F" " '{system("docker stop "$1); system("docker rm "$1)}'
# cp /home/olli/telegraf_agent2.conf /etc/telegraf/telegraf_agent.conf
# /home/olli/create_prometheus_telegraf_env.sh 
# docker ps -a | awk -F" " '{system("docker logs "$1) }'
# docker logs 
# ip a
# staticone_value{host ~= "$server$"}
# staticone_value{host ~= "$server$"}
# absent(up{host ~= "$server$"})

# systemctl reset-failed webhook.service
# journalctl -u webhook.service

# changes(unixtime_value{host="agent99"}[10s])
# avg_over_time(unixtime_value[10s])
#                avg_over_time(unixtime_value[1m])



# docker stop 968cba046d2d618fd7ac11f1a22c09a69f01fbef00bbf468166fedd5c248c9aa ; sleep 10 ; docker start 968cba046d2d618fd7ac11f1a22c09a69f01fbef00bbf468166fedd5c248c9aa
# vim /etc/prometheus/alerts/telegraf_up.yml
# /usr/local/bin/promtool check config /etc/prometheus/prometheus.yml
# systemctl restart prometheus
# systemctl status prometheus







### mkdir /opt/node_exporter
### cd /opt/node_exporter
### wget https://github.com/prometheus/node_exporter/releases/download/v1.3.1/node_exporter-1.3.1.linux-amd64.tar.gz
### tar xvfz node_exporter-1.3.1.linux-amd64.tar.gz
### cd node_exporter-*.*-amd64
### ./node_exporter
###
###
###
### #Start Skript erstellen
### cat > /etc/systemd/system/node_exporter.service << EOF
### [Unit]
### Description=Node Exporter
###  
### [Service]
### User=root
### Group=root
### #EnvironmentFile=-/etc/sysconfig/node_exporter
### ExecStart=/opt/node_exporter/node_exporter-1.3.1.linux-amd64/node_exporter
###  
### [Install]
### WantedBy=multi-user.target
### EOF
###
###
### systemctl daemon-reload
### systemctl start node_exporter
### systemctl enable node_exporter
### systemctl status node_exporter
###
###
### docker run -d \
###   --net="host" \
###   --pid="host" \
###   --name=NOEX \
###   --restart=always \
###   -v "/:/host:ro,rslave" \
###   quay.io/prometheus/node-exporter:latest \
###   --path.rootfs=/host
