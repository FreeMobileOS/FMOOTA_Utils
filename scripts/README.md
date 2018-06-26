# Scripts to prepare OTA package for FMO devices

Note: currently script works for only for angler device

## Generate OTA and factory package

**Requirements:**
+ AOSP code should be build first
+ bash shell

**How to use it:**

\# Build the AOSP code first                                                     
\# script usage                 

    $ cd <AOSP ROOT>
    $ ./<SCRIPT DIR ROOT>/fmo_release.sh -d <device> -b <build id> -r <custom recovery image dir, in case we want to use custom recovery>
    
    e.g.
    ./script/fmo_release.sh -d angler -b eng.xyz -r <recovery dir>

    For using custom ota script, binary or other options
    ./script/fmo_release.sh --help

    Default output (if not specified using -o option) path is <AOSP_ROOT>/out

\# output packages

    Factory Package : <out dir>/release-<device>-<buildid>/*factory*.zip
    Ota Package     : <out dir>/*ota*.zip


\# how to flash factory images
    - Download factory image
    - unzip <factory.zip>
    - put device in bootloader mode
    - ./flash-all.sh
