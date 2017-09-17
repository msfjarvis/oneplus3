#!/bin/bash

rm .version 2>/dev/null

# Bash colors
CL_GRN='\033[01;32m'
CL_BOLD="\033[1m"
CL_INV="\033[7m"
CL_RED="\033[01;31m"
CL_RST="\033[0m"
CL_YLW="\033[01;33m"
CL_BLUE="\033[01;34m"


# Resources
THREAD="-j$(($(nproc --all) * 2))"
DEFCONFIG="oneplus3_defconfig"
KERNEL="Image.gz-dtb"

# Caesium Kernel Details
KERNEL_NAME="Caesium"
VER="CreepyMango"
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
MAKE="./makeparallel make O=${OUT_DIR}"

## Functions
# Prints a formatted header to let the user know what's being done
function echoText {
    echo -e ${CL_RED}
    echo -e "====$( for i in $( seq ${#1} ); do echo -e "=\c"; done )===="
    echo -e "==  ${1}  =="
    echo -e "====$( for i in $( seq ${#1} ); do echo -e "=\c"; done )===="
    echo -e ${CL_RST}
}

# Prints an error in bold red
function reportError {
    echo -e ""
    echo -e ${CL_RED}"${1}"${CL_RST}
    if [[ -z ${2} ]]; then
        echo -e ""
    fi
    exit 1
}

# Prints a warning in bold yellow
function reportWarning {
    echo -e ""
    echo -e ${CL_YLW}"${1}"${CL_RST}
    if [[ -z ${2} ]]; then
        echo -e ""
    fi
}

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
      echo -e "${CL_BOLD} Building clean ${CL_RST}" >&2
      CLEAN=true
      ;;
    b)
      echo -e "${CL_BOLD} Building ZIP only ${CL_RST}" >&2
      ONLY_ZIP=true
      ;;
    p)
      echo -e "${CL_BOLD} Will auto-push kernel ${CL_RST}" >&2
      PUSH=true
      ;;
    r)
      echo -e "${CL_BOLD} Regenerating defconfig ${CL_RST}" >&2
      REGEN_DEFCONFIG=true
      ;;
    s)
      echo -e "${CL_BOLD} Suppressing log output ${CL_RST}" >&2
      SILENT_BUILD=true
      ;;
    m)
      MODULE="${OPTARG}"
      [[ "${MODULE}" == */ ]] || MODULE="${MODULE}/"
      if [[ ! "$(ls ${MODULE}Kconfig*  2>/dev/null)" ]]; then
          echo -e "${CL_RED} Invalid module specified - ${MODULE} ${CL_RST}"
          return 1
      fi
      echo -e "${CL_BOLD} Building module ${MODULE} ${CL_RST}"
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

echo -e "${CL_GRN}"
echo "${FINAL_VER}.zip"
echo "------------------------------------------"
echo -e "${CL_RST}"

DATE_END=$(date +"%s")
DIFF=$((${DATE_END} - ${DATE_START}))
echo "Time: $(($DIFF / 60)) minute(s) and $(($DIFF % 60)) seconds."
echo " "

[ "${PUSH}" ] && push_to_device
[ "${BB_UPLOAD}" ] && bb_upload
