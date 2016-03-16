#!/bin/bash

VERSION=$1

if [[ -z "$VERSION" ]]; then
  echo "Pass the version of the images to remove."
  exit 1
fi

if [[ "$OS_USERNAME" != "admin" ]]; then
  echo "Setup must be done as OpenStack admin."
  exit 1
fi

echo -n "Enter 'yes' to delete all images matching nios-${VERSION}*:" 
read confirm
if [[ "$confirm" != "yes" ]]; then
  echo "Aborting"
  exit 0
fi

IMAGES=$(openstack image list --public -f csv -c ID -c Name | sed -e 's/ /_/g' -e 's/"//g')
for image in $IMAGES; do
  id=$(echo $image | cut -f 1 -d,)
  name=$(echo $image | cut -f 2 -d,)


  if [[ $name == nios-${VERSION}* ]]; then
    echo Deleting $name
    glance image-delete $id
  fi
done
