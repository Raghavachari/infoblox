#!/bin/bash

USERNAME=${1:-dev}
LAUNCHPAD_ID=${2:-}
PUBLIC_NET=${3:-public-138-net}
TENANT_NAME=$USERNAME

if [[ "$OS_USERNAME" != "admin" ]]; then
  echo "Project creation must be done as OpenStack admin."
  exit 1
fi

openstack project create $TENANT_NAME
openstack user create $USERNAME --project $TENANT_NAME --password infoblox
openstack role add --user $USERNAME --project $TENANT_NAME user
openstack role add --user admin --project $TENANT_NAME user

TENANT_ID=$(openstack project show $TENANT_NAME -f value -c id)
MGMT_NET=$(neutron net-create --tenant-id $TENANT_ID -c id -f value mgmt-net | tail -1)
LAN1_NET=$(neutron net-create --tenant-id $TENANT_ID -c id -f value lan1-net | tail -1)
LAN2_NET=$(neutron net-create --tenant-id $TENANT_ID -c id -f value lan2-net | tail -1)
DEV_NET=$(neutron net-create --tenant-id $TENANT_ID -c id -f value dev-net | tail -1)

neutron subnet-create --name dev $DEV_NET --tenant-id $TENANT_ID --dns-nameserver 172.23.27.169 10.1.0.0/24
neutron subnet-create --name mgmt $MGMT_NET --tenant-id $TENANT_ID --disable-dhcp 10.2.0.0/24
neutron subnet-create --name lan1 $LAN1_NET --tenant-id $TENANT_ID --disable-dhcp 10.3.0.0/24
neutron subnet-create --name lan2 $LAN2_NET --tenant-id $TENANT_ID --disable-dhcp 10.4.0.0/24

SEC_GROUPS=$(neutron security-group-list -f value -c id -c name | cut -f 1 -d ' ')
for id in $SEC_GROUPS
do
#   echo "Checking for $TENANT_ID in $id"
   if neutron security-group-show $id | grep -q $TENANT_ID ; then
     neutron security-group-rule-create --direction ingress $id
   fi
done

SAVE_OS_PASSWORD=$OS_PASSWORD

export OS_PROJECT_DOMAIN_ID=default
export OS_USER_DOMAIN_ID=default
export OS_PROJECT_NAME=$TENANT_NAME
export OS_TENANT_NAME=$TENANT_NAME
export OS_USERNAME=$TENANT_NAME
export OS_PASSWORD=infoblox

ROUTER=$TENANT_NAME-router
neutron router-create $ROUTER
neutron router-gateway-set $ROUTER $PUBLIC_NET
neutron router-interface-add $ROUTER dev
neutron router-interface-add $ROUTER mgmt
neutron router-interface-add $ROUTER lan1


if [ -n "$LAUNCHPAD_ID" ]; then
  AUTH=$'    \nssh-import-id: $LAUNCHPAD_ID\n'
fi

USERDATA=/tmp/$TENANT_NAME-user_data.$$.yaml
cat > $USERDATA <<EOF
#cloud-config

ssh_pwauth: true
password: infoblox

users:
  - default
  - name: $USERNAME
    password: infoblox
    $AUTH
    sudo: ALL=(ALL) NOPASSWD:ALL

write_files:
  - path: /home/$USERNAME/$USERNAME-openrc.sh
    owner: $USERNAME:$USERNAME
    permissions: '0755'
    content: |
        export OS_PROJECT_DOMAIN_ID=default
        export OS_USER_DOMAIN_ID=default
        export OS_PROJECT_NAME=$TENANT_NAME
        export OS_TENANT_NAME=$TENANT_NAME
        export OS_USERNAME=$USERNAME
        export OS_PASSWORD=infoblox
        export OS_AUTH_URL=$OS_AUTH_URL
        export OS_IDENTITY_API_VERSION=3
        export OS_IMAGE_API_VERSION=2

apt_sources:
  - source: deb http://ubuntu-cloud.archive.canonical.com/ubuntu trusty-updates/liberty main

package_upgrade: true

runcmd:
  - apt-get install ubuntu-cloud-keyring

packages:
  - python-ceilometerclient
  - python-cinderclient
  - python-glanceclient
  - python-heatclient
  - python-keystoneclient
  - python-neutronclient
  - python-novaclient
  - python-openstackclient
  - python-os-client-config
  - python-swiftclient
  - python-troveclient
EOF

PORT_ID=$(neutron port-create -f value -c id dev-net | tail -1)
FLOATING_IP_ID=$(neutron floatingip-create -f value -c id $PUBLIC_NET | tail -1)
FIP=$(neutron floatingip-show $FLOATING_IP_ID -f value -c floating_ip_address)
neutron floatingip-associate $FLOATING_IP_ID $PORT_ID

nova boot --image 'Ubuntu Trusty 14.04' --flavor m1.large --nic port-id=$PORT_ID --user-data $USERDATA $USERNAME-dev

echo The machine will be available on $FIP
