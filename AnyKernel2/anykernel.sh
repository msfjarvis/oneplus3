# AnyKernel2 Ramdisk Mod Script
# osm0sis @ xda-developers

## AnyKernel setup
properties() {
kernel.string=Caesium by MSF Jarvis
do.devicecheck=1
do.modules=0
do.cleanup=1
do.cleanuponabort=1
device.name1=OnePlus3T
device.name2=oneplus3t
device.name3=OnePlus3
device.name4=oneplus3
device.name5=
} # end properties

# shell variables
block=/dev/block/bootdevice/by-name/boot;
is_slot_device=0;

## AnyKernel methods (DO NOT CHANGE)
# import patching functions/variables - see for reference
. /tmp/anykernel/tools/ak2-core.sh;


## AnyKernel permissions
# set permissions for included ramdisk files
chmod -R 755 $ramdisk

## Alert of unsupported Android version
android_ver=$(mount /system; grep "^ro.build.version.release" /system/build.prop | cut -d= -f2; umount /system);
case "$android_ver" in
  "6.0"|"6.0.1") compatibility_string="your version is unsupported, expect no support!";;
  "7.0"|"7.1"|"7.1.1"|"7.1.2") compatibility_string="your version is supported!";;
esac;

ui_print "Running Android $android_ver, $compatibility_string";

## AnyKernel install
dump_boot;

# begin ramdisk changes
insert_line init.qcom.rc "init.spectrum.rc" after "import init.target.rc" "import /init.spectrum.rc"

# end ramdisk changes

write_boot;

## end install

