#!/bin/bash

MODEL=${1:-1420}
TENANT_NAME=${2:-nios}
IMAGE_CL=${3:-311805}

if [[ "$OS_USERNAME" != $TENANT_NAME ]]; then
  echo "OS_USERNAME should be set to $TENANT_NAME"
  exit 1
fi

MGMT_NET=$(neutron net-list -c id -c name -f csv | grep management | cut -f 1 -d ',' | tr -d \")
SERVICE_NET=$(neutron net-list -c id -c name -f csv | grep service | cut -f 1 -d ',' | tr -d \")
neutron port-create -c id -c fixed_ips service-net > /tmp/port.$$
SERVICE_IP=$(cat /tmp/port.$$ | grep fixed_ips | cut -f 2 -d, | cut -f 2 -d : | tr -d '"}| ')
SERVICE_PORT=$(cat /tmp/port.$$ |  grep ' id ' | cut -f 2 -d, | cut -f 3 -d \| | tr -d '"}| ')
SERVICE_SUBNET=$(cat /tmp/port.$$ | grep fixed_ips | cut -f 1 -d, | cut -f 2 -d : | tr -d '"}| ')
SERVICE_GW=$(neutron subnet-show -f value -c gateway_ip $SERVICE_SUBNET)

FLOATING_IP_ID=$(neutron floatingip-create -f value -c id public-138 | tail -1)
FIP=$(neutron floatingip-show $FLOATING_IP_ID -f value -c floating_ip_address)

neutron floatingip-associate $FLOATING_IP_ID $SERVICE_PORT

cat > /tmp/user_data.$$.yaml <<EOF
#infoblox-config

remote_console_enabled: true
default_admin_password: infoblox
temp_license: vnios,enterprise,cloud,dns,dhcp
lan1:
 v4_addr: $SERVICE_IP
 v4_netmask: 255.255.255.0
 v4_gw: $SERVICE_GW
EOF

nova boot --config-drive True --image nios-7.3.0-Alpha-$IMAGE_CL-160G-$MODEL --flavor vnios-$MODEL.160 --nic net-id=$MGMT_NET --nic port-id=$SERVICE_PORT --user-data /tmp/user_data.$$.yaml gm

wait=1
while [ "$wait" -ne "0" ]
do
  echo $(date): Could not ping $FIP yet...waiting...$wait
  sleep 15
  ping -c 1 $FIP 1>/dev/null 2>&1
  wait=$?
done

echo
echo $(date): Ping $FIP successful.
echo

wait=1
while [ "$wait" -ne "0" ]
do
  echo $(date): Could not download certificate...waiting...$wait
  sleep 15
  echo | openssl s_client -connect $FIP:443 >/dev/null 2>&1
  wait=$?
done

echo $(date): Downloading certificate for use in member join
echo
echo | openssl s_client -connect $FIP:443 2>/dev/null | openssl x509 | tr -d \\n > gm.cert
echo $(date): Stored in gm.cert

echo "Adding a default nsgroup..."

echo $(curl -k -u admin:infoblox -X POST -H "Content-Type: application/json" -d '{"name": "default", "is_grid_default": true}' https://$FIP/wapi/v2.2.1/nsgroup)
