#!/bin/bash

TENANT_NAME=${1:-nios}
IMAGE_DIR=${2:-/home/openstack/images}
PUBLIC_NET=${3:-public-138-net}

if [[ "$OS_USERNAME" != "admin" ]]; then
  echo "Setup must be done as OpenStack admin."
  exit 1
fi

openstack project create $TENANT_NAME
openstack user create nios --project $TENANT_NAME --password infoblox
openstack role add --user nios --project $TENANT_NAME user
openstack role add --user admin --project $TENANT_NAME user

nova flavor-create --is-public true vnios-100.55 auto 1024 55 1 --swap 0 --ephemeral 0
nova flavor-create --is-public true vnios-810.55 auto 2048 55 2 --swap 0 --ephemeral 0
nova flavor-create --is-public true vnios-820.55 auto 3584 55 2 --swap 0 --ephemeral 0
nova flavor-create --is-public true vnios-CP-V800.160 auto 2052 160 2 --swap 0 --ephemeral 0
nova flavor-create --is-public true vnios-1410.160 auto 14848 160 4 --swap 0 --ephemeral 0
nova flavor-create --is-public true vnios-1420.160 auto 14848 160 4 --swap 0 --ephemeral 0
nova flavor-create --is-public true vnios-2210.160 auto 14848 160 4 --swap 0 --ephemeral 0
nova flavor-create --is-public true vnios-2220.160 auto 14848 160 4 --swap 0 --ephemeral 0

for image in $IMAGE_DIR/*; do
  echo $image
  tmp=${image##$IMAGE_DIR/}
  tmp=${tmp/-201[56]-??-??-??-??-??/};
  tmp=${tmp/-disk1/};
  name=${tmp%.qcow2};
#  echo "Loading $name from $image..."
#  glance image-create --name $name --visibility public --container-format bare --disk-format qcow2 --file $image
done

TENANT_ID=$(openstack project show $TENANT_NAME -f value -c id)
neutron net-create --tenant-id $TENANT_ID management-net
neutron net-create --tenant-id $TENANT_ID service-net
neutron net-create --tenant-id $TENANT_ID service-2-net
neutron net-create --tenant-id $TENANT_ID ha-net

neutron subnet-create --name management management-net --tenant-id $TENANT_ID --disable-dhcp 10.1.0.0/24
neutron subnet-create --name service service-net --tenant-id $TENANT_ID --disable-dhcp 10.2.0.0/24
neutron subnet-create --name service-2 service-2-net --tenant-id $TENANT_ID --disable-dhcp 10.3.0.0/24
neutron subnet-create --name ha ha-net --tenant-id $TENANT_ID --disable-dhcp 10.4.0.0/24

ROUTER=$TENANT_NAME-router
neutron router-create $ROUTER --tenant-id $TENANT_ID
neutron router-gateway-set $ROUTER $PUBLIC_NET
neutron router-interface-add $ROUTER service
neutron router-interface-add $ROUTER management

SEC_GROUPS=$(neutron security-group-list -f value -c id -c name | cut -f 1 -d ' ')
for id in $SEC_GROUPS
do
#   echo "Checking for $TENANT_ID in $id"
   if neutron security-group-show $id | grep -q $TENANT_ID ; then
     neutron security-group-rule-create --direction ingress $id
   fi
done

