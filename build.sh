#!/bin/bash

rm .version 2>/dev/null

# Bash colors
green='\033[01;32m'
red='\033[01;31m'
cyan='\033[01;36m'
blue='\033[01;34m'
blink_red='\033[05;31m'
restore='\033[0m'

clear

# Resources
THREAD="-j$(($(nproc --all) * 2))"
DEFCONFIG="oneplus3_defconfig"
KERNEL="Image.gz-dtb"

# Caesium Kernel Details
KERNEL_NAME="Caesium"
VER="JuicyApple"
VER="-$(date +"%Y%m%d"-"%H%M%S")-$VER"
DEVICE="-oneplus3"
FINAL_VER="${KERNEL_NAME}""${DEVICE}""${VER}"

# Vars
export ARCH=arm64
export SUBARCH=arm64
export KBUILD_BUILD_USER=MSF
export KBUILD_BUILD_HOST=jarvisbox

# Paths
WORKING_DIR=$(pwd)
ANYKERNEL_DIR="${WORKING_DIR}/AnyKernel2"
TOOLCHAIN_DIR="${WORKING_DIR}/../../toolchains/aarch64-linux-gnu/"
REPACK_DIR="${ANYKERNEL_DIR}"
OUT_DIR="${WORKING_DIR}/out/"
ZIP_MOVE="${WORKING_DIR}/zips/"
MAKE="make O=${OUT_DIR}"

# Functions
function make_kernel() {
  [ "${CLEAN}" ] && ${MAKE} clean && ${MAKE} mrproper
  ${MAKE} "${DEFCONFIG}" "${THREAD}"
  [ "${REGEN_DEFCONFIG}" ] && cp "${OUT_DIR}".config arch/"${ARCH}"/configs/"${DEFCONFIG}" && exit 1
  if [ "${MODULE}" ]; then
      ${MAKE} "${MODULE}" "${THREAD}"
  else
      ${MAKE} "${KERNEL}" "${THREAD}"
  fi
  BUILT_KERNEL="out/arch/${ARCH}/boot/${KERNEL}"
  [ -f "${BUILT_KERNEL}" ] && cp -vr "${BUILT_KERNEL}" "${REPACK_DIR}" && return 0 || return 1
}

function make_zip() {
  cd "${REPACK_DIR}"
  zip -ur kernel_temp.zip *
  mkdir -p "${ZIP_MOVE}"
  cp  kernel_temp.zip "${ZIP_MOVE}/${FINAL_VER}.zip"
  cd "${WORKING_DIR}"
}

function push_to_device() {
  adb push "${ZIP_MOVE}"/${FINAL_VER}.zip /sdcard/Caesium/
}

while getopts ":cbprsm:" opt; do
  case $opt in
    c)
      echo -e "${cyan} Building clean ${restore}" >&2
      CLEAN=true
      ;;
    b)
      echo -e "${cyan} Building ZIP only ${restore}" >&2
      ONLY_ZIP=true
      ;;
    p)
      echo -e "${cyan} Will auto-push kernel ${restore}" >&2
      PUSH=true
      ;;
    r)
      echo -e "${cyan} Regenerating defconfig ${restore}" >&2
      REGEN_DEFCONFIG=true
      ;;
    s)
      echo -e "${cyan} Suppressing log output ${restore}" >&2
      SILENT_BUILD=true
      ;;
    m)
      MODULE="${OPTARG}"
      [[ "${MODULE}" == */ ]] || MODULE="${MODULE}/"
      if [[ ! "$(ls ${MODULE}Kconfig*  2>/dev/null)" ]]; then
          echo -e "${red} Invalid module specified - ${MODULE} ${restore}"
          return 1
      fi
      echo -e "${cyan} Building module ${MODULE} ${restore}"
      ;;
    \?)
      echo "Invalid option: -${OPTARG}" >&2
      ;;
  esac
done

DATE_START=$(date +"%s")

# TC tasks
export CROSS_COMPILE=$TOOLCHAIN_DIR/bin/aarch64-linux-gnu-
export LD_LIBRARY_PATH=$TOOLCHAIN_DIR/lib/
cd "${WORKING_DIR}"

# Make
if [ "${ONLY_ZIP}" ]; then
  make_zip
else
  [[ ${SILENT_BUILD} ]] && make_kernel |& ag "error:|warning|${KERNEL}" || make_kernel
  [[ $? == 0 ]] || exit 256
  make_zip
fi

echo -e "${green}"
echo "${FINAL_VER}.zip"
echo "------------------------------------------"
echo -e "${restore}"

DATE_END=$(date +"%s")
DIFF=$((${DATE_END} - ${DATE_START}))
echo "Time: $(($DIFF / 60)) minute(s) and $(($DIFF % 60)) seconds."
echo " "

[ "${PUSH}" ] && push_to_device
[ "${BB_UPLOAD}" ] && bb_upload
