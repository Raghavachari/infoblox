#!/bin/bash

FIP=$1

if [[ -z "$FIP" ]]; then
  echo "usage: $0 <gm-floating-ip>"
  exit 1
fi

ping -c 1 $FIP 1>/dev/null 2>&1
wait=$?
while [ "$wait" -ne "0" ]
do
  echo $(date): Could not ping $FIP yet...waiting...
  sleep 15
  ping -c 1 $FIP 1>/dev/null 2>&1
  wait=$?
done

echo
echo $(date): Ping $FIP successful.
echo

echo | openssl s_client -connect $FIP:443 >/dev/null 2>&1
wait=$?
while [ "$wait" -ne "0" ]
do
  echo $(date): Could not download certificate yet...waiting...
  sleep 15
  echo | openssl s_client -connect $FIP:443 >/dev/null 2>&1
  wait=$?
done

echo $(date): Downloading certificate for use in member join...
echo
echo | openssl s_client -connect $FIP:443 2>/dev/null | openssl x509 | sed -e 's/^/    /' > /tmp/gm-$FIP-cert.pem
echo $(date): Done

LAN1_IP=$(curl -sk -u admin:infoblox -X GET "https://$FIP/wapi/v2.3/member?host_name=infoblox.localdomain&_return_fields=vip_setting" | grep address | cut -d: -f 2 | tr -d '", ')
FIP_ID=$(neutron floatingip-list -c id -c floating_ip_address -f value | grep " $FIP\$" | cut -f 1 -d ' ')
FIP_NET_ID=$(neutron floatingip-show -c floating_network_id -f value $FIP_ID)
FIP_NET=$(neutron net-show -c name -f value $FIP_NET_ID)

cat > gm-$FIP-env.yaml <<EOF
# Heat environment for launching autoscale against GM $FIP
parameters:
  gm_lan1_ip: $LAN1_IP
  external_network: $FIP_NET
  gm_cert: |
EOF

cat >> gm-$FIP-env.yaml < /tmp/gm-$FIP-cert.pem

cat >> gm-$FIP-env.yaml <<EOF
parameter_defaults:
  wapi_url: https://$FIP/wapi/v2.3/
  wapi_username: admin
  wapi_password: infoblox
  wapi_sslverify: false
EOF

echo "Enabling SNMP..."
GRID_REF=$(curl -sk -u admin:infoblox https://$FIP/wapi/v2.3/grid | grep _ref | cut -d: -f2-3 | tr -d '," ')
echo $(curl -sk -u admin:infoblox -X PUT -H "Content-Type: application/json" -d '{"snmp_setting": {"queries_enable": true, "queries_community_string": "public"}}' https://$FIP/wapi/v2.3/$GRID_REF)

echo "Enabling DNS..."
GM_REF=$(curl -sk -u admin:infoblox https://$FIP/wapi/v2.3/member:dns?host_name=infoblox.localdomain | grep _ref | cut -d: -f2-3 | tr -d '," ')
echo $(curl -sk -u admin:infoblox -X PUT -H "Content-Type: application/json" -d '{"enable_dns": true}' https://$FIP/wapi/v2.3/$GM_REF)

echo "Adding a default nsgroup..."
echo $(curl -sk -u admin:infoblox -X POST -H "Content-Type: application/json" -d '{"name": "default", "is_grid_default": true, "grid_primary": [{"name": "infoblox.localdomain"}]}' https://$FIP/wapi/v2.3/nsgroup)

echo "Creating demo zones and records..."
ZONEIP=50
for fqdn in example.com foo.com bar.com foobar.com
do
	ZONEIP=$(expr $ZONEIP + 1)
	REF=$(curl -sk -u admin:infoblox -X POST -H "Content-Type: application/json" -d "{\"fqdn\": \"$fqdn\", \"ns_group\": \"default\"}" https://$FIP/wapi/v2.3/zone_auth)
        echo "Created $fqdn with ref $REF"
        echo "Adding A records..."
        for i in 100 101 102 103 104 105
        do
		echo $(curl -sk -u admin:infoblox -X POST -H "Content-Type: application/json" -d "{\"name\": \"host-${i}.$fqdn\", \"ipv4addr\": \"10.${ZONEIP}.0.${i}\"}" https://$FIP/wapi/v2.3/record:a)
	done
done

echo You may now create the autoscale stack with:
echo heat stack-create -e gm-$FIP-env.yaml -f autoscale.yaml autoscale
