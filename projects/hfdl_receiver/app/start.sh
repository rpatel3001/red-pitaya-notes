#! /bin/sh

apps_dir=/media/mmcblk0p1/apps

source $apps_dir/stop.sh

cat $apps_dir/hfdl_receiver/hfdl_receiver.bit > /dev/xdevcfg

$apps_dir/hfdl_receiver/hfdl-receiver >> /run/receiver.log 2>&1 &
