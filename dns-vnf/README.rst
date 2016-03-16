=============================
DNS-VNF Templates and Scripts
=============================

Usage
-----

::

  $ heat stack-create -f gm.yaml -P"external_network=<your-ext-net>" gm
  $ heat stack-show gm
  $ ./config-gm.sh <gm-floating-ip>
  $ heat stack-create -e gm-<gm-floating-ip>-env.yaml -f autoscale.yaml autoscale
  $ heat stack-show autoscale
