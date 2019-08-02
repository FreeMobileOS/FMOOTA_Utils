#!/usr/bin/env bash

set -e # fail on unhandled error
set -o xtrace # to debug, print all commands

usage() {
echo "Error aborting..."

cat <<_EOF
Usage: $(basename "$0") -d <device> -b <build number> [options]
    OPTIONS:
	-d|--device <name> : Device codename (angler,  etc.), must be passed
	-b|--build  <name> : build number (usually prensent in build_number.txt), must be passed
	-s|--script		   : custom script to be package with ota
	-u|--update_binary : custom binrary to be used while generating ota
	-o|--output		   : output directory for images. defult is out/
	-k|--keydir		   : key dir to sign images, if not passed test key will be used	
	-r|--recovery      : custom recovery image dir (if custom recovery required to package in factory images	
_EOF
  exit 1
}

# Realpath implementation in bash
readonly SCRIPTS_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
readonly REALPATH_SCRIPT="$SCRIPTS_ROOT/util-scr/realpath.sh"

# include util-scr path
trap "abort 1" SIGINT SIGTERM
. "$REALPATH_SCRIPT"

# global variables
BUILD_OUT_DIR=$OUT
AOSP_ROOT=$ANDROID_BUILD_TOP
TARGET_ZIP_FILE=`find $OUT -name ${TARGET_PRODUCT}-target_files*.zip -print`
IMG_OUT=$AOSP_ROOT/out

KEY_DIR=""
DEVICE=""
CUSTOM_SCRIPT=""
CUSTOM_UPDATE_BIN=""
CUSTOM_RECOVERY_PATH=""

echo "BUILD_OUT_DIR:$OUT"
echo "TARGET_PRODUCT:$TARGET_PRODUCT"
echo "TARGET_ZIP_FILE:$TARGET_ZIP_FILE"
echo "ANDROID_BUILD_TOP:$ANDROID_BUILD_TOP"
source ./device/common/clear-factory-images-variables.sh

# arguments capture
while [[ $# -gt 0 ]]
do
  arg="$1"
  case $arg in
    -o|--output)
      IMG_OUT="$(_realpath "$2")"
      shift
      ;;
    -d|--device)
      DEVICE=$(echo "$2" | tr '[:upper:]' '[:lower:]')
      shift
      ;;
    -b|--build)
      BUILD_NUMBER=$(echo "$2" | tr '[:upper:]' '[:lower:]')
      shift
      ;;
    -s|--script)
      CUSTOM_SCRIPT="$(_realpath "$2")"
      shift
      ;;
    -u|--update_binary)
      CUSTOM_UPDATE_BIN="$(_realpath "$2")"
      shift
      ;;
    -k|--keydir)
      KEY_DIR="$(_realpath "$2")"
      shift
      ;;
    -r|--recovery)
      CUSTOM_RECOVERY_PATH="$(_realpath "$2")"
      shift
      ;;
    *)
      echo "[-] Invalid argument '$1'"
      usage
      ;;
  esac
  shift
done
echo "DEVICE:$DEVICE"
echo "BUILD_NUMBER:$BUILD_NUMBER"
echo "CUSTOM_SCRIPT:$CUSTOM_SCRIPT"
echo "CUSTOM_UPDATE_BIN:$CUSTOM_UPDATE_BIN"
echo "KEY_DIR:$KEY_DIR"
echo "CUSTOM_RECOVERY_PATH:$CUSTOM_RECOVERY_PATH"

# validate the path
if  [ ! -d "$BUILD_OUT_DIR" ] || 
	[ ! -d "$AOSP_ROOT" ] ||
	[ ! -n "$DEVICE" ] ||
	[ ! -n "$BUILD_NUMBER" ]
then
	echo "Invalid arguments"
	usage
fi

# create img out with device id
IMG_OUT=out/release-$DEVICE-$BUILD_NUMBER
PRODUCT=$DEVICE # dependency generate factory image
mkdir -p $IMG_OUT || exit 1

# generate target files if not generated
if [ -z $TARGET_ZIP_FILE ] || 
   [ ! -e "$TARGET_ZIP_FILE" ]
then
    # run make target command, export variable if custom recovery is used
    if [ -d "$CUSTOM_RECOVERY_PATH" ]; then 
        export USE_CUSTOM_RECOVERY=true
    fi
    cd $AOSP_ROOT
    make dist DIST_DIR=$IMG_OUT -j18
fi

TARGET_ZIP_FILE=`find $OUT -name ${TARGET_PRODUCT}-target_files*.zip -print`
echo "TARGET_ZIP_FILE:$TARGET_ZIP_FILE"
echo "USE_CUSTOM_RECOVERY:$USE_CUSTOM_RECOVERY"

# generate target files if not generated
if [ ! -e $TARGET_ZIP_FILE ]; then
    echo "Invalid target files, something wrong:$TARGET_ZIP_FILE"
    usage
fi


get_radio_image() {
  grep -Po "require version-$1=\K.+" vendor/$2/vendor-board-info.txt | tr '[:upper:]' '[:lower:]'
}

if [[ ${DEVICE} == "angler" ]]; then
	BOOTLOADER=$(get_radio_image bootloader huawei/$DEVICE)
	RADIO=$(get_radio_image baseband huawei/$DEVICE)
	PREFIX=aosp_
elif [[ ${DEVICE} == "mido" ]]; then
	echo "Nothing to be done for mido"
else
	echo "device not supported:$DEVICE"
	usage
fi

echo "BOOTLOADER:$BOOTLOADER"
echo "RADIO:$RADIO"

BUILD=$BUILD_NUMBER
VERSION=$(grep -Po "export BUILD_ID=\K.+" build/core/build_id.mk | tr '[:upper:]' '[:lower:]')
SEARCH_PATH=(-p "$OUT/../../../host/linux-x86/")

TARGET_FILES=$DEVICE-target_files-$BUILD.zip

if [[ -d "$KEY_DIR" ]]; then	
    VERITY_SWITCHES=(--replace_verity_public_key "$KEY_DIR/verity_key.pub" --replace_verity_private_key "$KEY_DIR/verity"
                     --replace_verity_keyid "$KEY_DIR/verity.x509.pem")
fi

# set custom script and custom binary arguments
if [ ! -n "$CUSTOM_SCRIPT" ]; then
	unset CUSTOM_SCRIPT
else
	CUSTOM_SCRIPT=(-e "$CUSTOM_SCRIPT")
fi

if [ ! -n "$CUSTOM_UPDATE_BIN" ]; then
	unset CUSTOM_UPDATE_BIN
else
	CUSTOM_UPDATE_BIN=(-b "$CUSTOM_UPDATE_BIN")
fi

if [ -d "$KEYDIR" ]; then
	KEY_MAP_ARG=(-d "$KEY_DIR")
	KEY_PKG_ARG=(-k "$KEY_DIR/releasekey")
fi

# sign apk
build/tools/releasetools/sign_target_files_apks -o "${KEY_MAP_ARG[@]}" "${VERITY_SWITCHES[@]}" "${SEARCH_PATH[@]}"\
	$TARGET_ZIP_FILE $IMG_OUT/$TARGET_FILES || exit 1

# generate ota
build/tools/releasetools/ota_from_target_files --block  "${CUSTOM_SCRIPT[@]}" "${CUSTOM_UPDATE_BIN[@]}" \
	"${KEY_PKG_ARG[@]}" "${EXTRA_OTA[@]}" "${SEARCH_PATH[@]}" \
	$IMG_OUT/$TARGET_FILES $IMG_OUT/$DEVICE-ota_update-$BUILD.zip || exit 1

if [ -d $CUSTOM_RECOVERY_PATH ]; then
    build/tools/releasetools/img_from_target_files $IMG_OUT/$TARGET_FILES \
        $IMG_OUT/$DEVICE-img-$BUILD.zip $CUSTOM_RECOVERY_PATH || exit 1
else
    build/tools/releasetools/img_from_target_files $IMG_OUT/$TARGET_FILES \
        $IMG_OUT/$DEVICE-img-$BUILD.zip || exit 1
fi

cd $IMG_OUT || exit 1

# generate factory image
echo "PRODUCT IS:$PRODUCT"

# if device is angler, then package radio & bootloader with factory image
if [[ ${DEVICE} == "angler" ]]; then
source $SCRIPTS_ROOT/generate-factory-images-common.sh -u $BUILD_OUT_DIR/userdata.img -b $SCRIPTS_ROOT/../angler/images/bootloader-angler-angler-03.84.img -r $SCRIPTS_ROOT/../angler/images/radio-angler-angler-03.88.img
else
source $SCRIPTS_ROOT/generate-factory-images-common.sh -u $BUILD_OUT_DIR/userdata.img
fi

# prepare server hosting image format
REL_VERSION=$(grep -Po "ro.build.version.release=\K.+" $BUILD_OUT_DIR/system/build.prop)
REL_DATE=$(grep -Po "org.fmo.build_date=\K.+" $BUILD_OUT_DIR/system/build.prop | head -c 8)
REL_TYPE=$(grep -Po "ro.build.type=\K.+" $BUILD_OUT_DIR/system/build.prop)
REL_DEVICE_DIR=release_pkg/$DEVICE/$REL_DATE

mkdir -p $REL_DEVICE_DIR || exit 1
mkdir -p $REL_DEVICE_DIR/prebuilt/ || exit 1
mv *factory*.zip $REL_DEVICE_DIR/prebuilt/
mv *ota_update*.zip $REL_DEVICE_DIR/fmo-$REL_VERSION-$REL_DATE-$REL_TYPE-$DEVICE-signed.zip
cp $BUILD_OUT_DIR/system/build.prop $REL_DEVICE_DIR/fmo-$REL_VERSION-$REL_DATE-$REL_TYPE-$DEVICE-signed.zip.prop

echo "Release package generated successfully..!!"
