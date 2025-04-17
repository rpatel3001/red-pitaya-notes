#! /bin/sh

apps_dir=/media/mmcblk0p1/apps

source $apps_dir/stop.sh

cat $apps_dir/hfdl_receiver/hfdl_receiver.bit > /dev/xdevcfg

# gdb -batch -ex 'set confirm off' -ex 'handle SIGTERM nostop print pass' -ex 'handle SIGINT nostop print pass' -ex run -ex 'bt full' --args $apps_dir/hfdl_receiver/hfdl-receiver >> /run/receiver.log 2>&1 &

$apps_dir/hfdl_receiver/hfdl-receiver >> /run/receiver.log 2>&1 &
