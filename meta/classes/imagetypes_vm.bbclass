# This software is a part of ISAR.
# Copyright (C) 2019-2020 Siemens AG
#
# This class allows to generate images for VMware and VirtualBox
#

FILESEXTRAPATHS:prepend = "${LAYERDIR_core}/recipes-core/images:"
OVF_TEMPLATE_FILE ?= "virtualbox/vm-img-virtualbox.ovf.tmpl"
IMAGE_SRC_URI:ova = "file://${OVF_TEMPLATE_FILE}"

IMAGE_TYPEDEP:ova = "wic"
IMAGER_INSTALL:ova += "qemu-utils gawk uuid-runtime"

# virtual machine disk settings
SOURCE_IMAGE_FILE ?= "${IMAGE_FULLNAME}.wic"

# For VirtualBox, this needs to be "monolithicSparse" (default to it).
# VMware needs this to be "streamOptimized".
VMDK_SUBFORMAT ?= "monolithicSparse"

VIRTUAL_MACHINE_IMAGE_TYPE ?= "vmdk"
VIRTUAL_MACHINE_IMAGE_FILE = "${IMAGE_FULLNAME}-disk001.${VIRTUAL_MACHINE_IMAGE_TYPE}"
VIRTUAL_MACHINE_DISK = "${PP_DEPLOY}/${VIRTUAL_MACHINE_IMAGE_FILE}"

def set_convert_options(d):
   format = d.getVar("VIRTUAL_MACHINE_IMAGE_TYPE")
   if format == "vmdk":
      return "-o subformat=%s" % d.getVar("VMDK_SUBFORMAT")
   else:
      return ""


CONVERSION_OPTIONS = "${@set_convert_options(d)}"

convert_wic() {
    rm -f '${DEPLOY_DIR_IMAGE}/${VIRTUAL_MACHINE_IMAGE_FILE}'
    bbnote "Creating ${VIRTUAL_MACHINE_IMAGE_FILE} from ${SOURCE_IMAGE_FILE}"
    imager_run -p -d ${PP_WORK} -- \
    /usr/bin/qemu-img convert -f raw -O ${VIRTUAL_MACHINE_IMAGE_TYPE} ${CONVERSION_OPTIONS} \
        '${PP_DEPLOY}/${SOURCE_IMAGE_FILE}' '${VIRTUAL_MACHINE_DISK}'
}

# User settings for OVA
OVA_NAME ?= "${IMAGE_FULLNAME}"
OVA_MEMORY ?= "8192"
OVA_NUMBER_OF_CPU ?= "4"
OVA_VRAM ?= "64"
OVA_FIRMWARE ?= "efi"
OVA_ACPI ?= "true"
OVA_3D_ACCEL ?= "false"
OVA_SHA_ALG = "1"

# Generate random MAC addresses just as VirtualBox does, the format is
# their assigned prefix for the first 3 bytes followed by 3 random bytes.
VBOX_MAC_PREFIX = "080027"

macgen() {
    hexdump -n3 -e "\"${VBOX_MAC_PREFIX}%06X\n\"" /dev/urandom
}

OVA_VARS = "OVA_NAME OVA_MEMORY OVA_NUMBER_OF_CPU OVA_VRAM \
            OVA_FIRMWARE OVA_ACPI OVA_3D_ACCEL \
            OVA_SHA_ALG VIRTUAL_MACHINE_IMAGE_FILE VMDK_SUBFORMAT"

IMAGE_TEMPLATE_FILES:ova = "${OVF_TEMPLATE_FILE}"
IMAGE_TEMPLATE_VARS:ova = "${OVA_VARS}"

do_image_ova[prefuncs] += "convert_wic"
IMAGE_CMD:ova() {
    if [ ! ${VIRTUAL_MACHINE_IMAGE_TYPE} = "vmdk" ]; then
        exit 0
    fi
    rm -f '${DEPLOY_DIR_IMAGE}/${IMAGE_FULLNAME}.ova'
    rm -f '${DEPLOY_DIR_IMAGE}/${IMAGE_FULLNAME}.ovf'
    rm -f '${DEPLOY_DIR_IMAGE}/${IMAGE_FULLNAME}.mf'

    export PRIMARY_MAC=$(macgen)
    export LAST_CHANGE=$(date -u "+%Y-%m-%dT%H:%M:%SZ")
    export OVA_FIRMWARE_UPPERCASE=$(echo ${OVA_FIRMWARE} | tr '[a-z]' '[A-Z]')
    export OVF_TEMPLATE_STAGE2=$(echo ${OVF_TEMPLATE_FILE} | sed 's/.tmpl$//' )
    imager_run -p -d ${PP_WORK} <<'EOIMAGER'
        set -e
        export DISK_SIZE_BYTES=$(qemu-img info -f vmdk "${VIRTUAL_MACHINE_DISK}" \
                                 | gawk 'match($0, /^virtual size:.*\(([0-9]+) bytes\)/, a) {print a[1]}')
        export DISK_UUID=$(uuidgen)
        export VM_UUID=$(uuidgen)
        # create ovf
        cat ${PP_WORK}/${OVF_TEMPLATE_STAGE2} | envsubst > ${PP_DEPLOY}/${IMAGE_FULLNAME}.ovf
        tar -cvf ${PP_DEPLOY}/${IMAGE_FULLNAME}.ova -C ${PP_DEPLOY} ${IMAGE_FULLNAME}.ovf

        # VirtualBox needs here a manifest file. VMware does accept that format.
        if [ "${VMDK_SUBFORMAT}" = "monolithicSparse" ]; then
            echo "SHA${OVA_SHA_ALG}(${VIRTUAL_MACHINE_IMAGE_FILE})=$(sha${OVA_SHA_ALG}sum ${PP_DEPLOY}/${VIRTUAL_MACHINE_IMAGE_FILE} | cut -d' ' -f1)" >> ${PP_DEPLOY}/${IMAGE_FULLNAME}.mf
            echo "SHA${OVA_SHA_ALG}(${IMAGE_FULLNAME}.ovf)=$(sha${OVA_SHA_ALG}sum ${PP_DEPLOY}/${IMAGE_FULLNAME}.ovf | cut -d' ' -f1)" >> ${PP_DEPLOY}/${IMAGE_FULLNAME}.mf
            tar -uvf ${PP_DEPLOY}/${IMAGE_FULLNAME}.ova -C ${PP_DEPLOY} ${IMAGE_FULLNAME}.mf
        fi
        tar -uvf ${PP_DEPLOY}/${IMAGE_FULLNAME}.ova -C ${PP_DEPLOY} ${VIRTUAL_MACHINE_IMAGE_FILE}
EOIMAGER
}
IMAGE_CMD:ova[depends] = "${PN}:do_transform_template"
