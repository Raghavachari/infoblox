#!/bin/bash

IMAGE_DIR=${1:-/home/openstack/images}

if [[ ! -d $IMAGE_DIR ]]; then
  echo "$IMAGE_DIR not found or not a directory - pass in correct directory."
  exit 1
fi

if [[ "$OS_USERNAME" != "admin" ]]; then
  echo "Setup must be done as OpenStack admin."
  exit 1
fi

for image in $IMAGE_DIR/*; do
  echo $image
  tmp=${image##$IMAGE_DIR/}
  tmp=${tmp/-201[56]-??-??-??-??-??/};
  tmp=${tmp/-disk1/};
  name=${tmp%.qcow2};
  echo "Loading $name from $image..."
  glance image-create --name $name --visibility public --container-format bare --disk-format qcow2 --file $image
done
