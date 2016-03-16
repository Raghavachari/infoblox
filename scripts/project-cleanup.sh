#!/bin/bash

TENANT_NAME=${1:-nios}

if [[ "$OS_USERNAME" != "admin" ]]; then
  echo "Cleanup must be done as OpenStack admin."
  exit 1
fi

# instances
IDS=$(openstack --os-project-name $TENANT_NAME server list -c ID -f value)
for id in $IDS
do
    openstack --os-project-name $TENANT_NAME server delete $id
done

# floating IPs
IDS=$(openstack --os-project-name $TENANT_NAME ip floating list -c ID -f value)
for id in $IDS
do
    openstack --os-project-name $TENANT_NAME ip floating delete $id
done

# routers
IDS=$(neutron --os-project-name $TENANT_NAME router-list -f value -c id)
for id in $IDS
do
	SUBNETS=$(neutron --os-project-name $TENANT_NAME router-port-list $id -f value | sed -e 's/.*subnet_id": "//' | cut -f 1 -d \")
	for subnet in $SUBNETS
	do
		neutron --os-project-name $TENANT_NAME router-interface-delete $id $subnet
	done
	neutron --os-project-name $TENANT_NAME router-delete $id
done

# ports and networks and security groups
for obj in port net security-group
do
	IDS=$(neutron --os-project-name $TENANT_NAME $obj-list -c id -f value)
	for id in $IDS
	do
    		neutron --os-project-name $TENANT_NAME $obj-delete $id
	done
done

# volumes
# flavors
# images

#openstack --os-user-name $USERNAME keypair delete $USERNAME-cloud-key
# tenant

openstack project delete $TENANT_NAME
