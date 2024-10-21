#!/bin/bash
#
DBG=${DBG:-0} && [ "0$DBG" -eq 0 ]; [ "$DBG" -eq 1 ] && set -x

PATH=/bin:/usr/bin:$PATH
export PATH
    
PROG=$(realpath "$0" | sed 's|^.*\/||')

getSpecValue () {
    local name=$(echo "$1" | tr -d '%{}')

    echo "%{${name}}" | rpmspec --shell ${SPECFILE} 2>/dev/null | awk -v name="${name}" '
    BEGIN {
        search = sprintf("> %%{%s}", name)
    }
    $0 ~ search {
        if (getline > 0) {
            if ($0 ~ name) {
                print ""
            } else {
                print
            }
        }
    }'
}

usage() {
    local errno=0; [ $# -ge 1 ] && errno=$1 && shift

    echo 2>&1 "$PROG: [-b:--build={prep,compile,binaries,installsource}] [armbian|collabora|fedora|mixed]"

    exit "$errno"
}

OPTARGS=$(getopt --options hb: --longoptions help,build: --name "$PROG" -- ${1+"$@"}) || usage $?
eval "set -- $OPTARGS"

while true; do
    case "$1" in
    -h|--help)
        usage 0
        break
        ;;
    -b|--build)
        case "$2" in
        prep)
            RPMBUILD_ARGS="-bp"
            ;;
        compile)
            RPMBUILD_ARGS="-bc"
            ;;
        binar*)
            RPMBUILD_ARGS="-bb"
            ;;
        install)
            RPMBUILD_ARGS="-bi"
            ;;
        source)
            RPMBUILD_ARGS="-bs"
            ;;
        esac

        shift 2
        ;;
    --)
        shift
        break
        ;;
    esac
done

if [ $# -eq 1 ]; then
    case "$1" in
    [Aa]rm*)
        CONFIG="armbian"
        KERNEL="armbian"
        PATCH="armbian"
        ;;
    [Cc]ol*)
        CONFIG="collabora"
        KERNEL="collabora"
        PATCH="collabora"
        ;;
    [Ff]ed*)
        CONFIG="fedora"
        KERNEL="fedora"
        PATCH="fedora"
        ;;
    mix*)
        CONFIG="fedora"
        KERNEL="armbian"
        PATCH="armbian"
        ;;
    *)
        usage 1
    esac
else
    usage 1
fi

# Defaults
CONFIG=${CONFIG:-armbian}
KERNEL=${KERNEL:-armbian}
PATCHVERSION=11
RPMBUILD_ARGS=${RPMBUILD_ARGS:--bp}
SPECFILE=SPECS/kernel.${KERNEL}.spec
TARGET=${TARGET:-aarch64-linux-gnu}

ARCH="arm64"
BUILDVER=$(cat .cache/buildver 2> /dev/null); BUILDVER=${BUILDVER:-0}
#BUILD_CFLAGS="-O2 -fexceptions -grecord-gcc-switches -pipe -Wall -Werror=format-security -Wp,-U_FORTIFY_SOURCE,-D_FORTIFY_SOURCE=3 -Wp,-D_GLIBCXX_ASSERTIONS -specs=/usr/lib/rpm/redhat/redhat-hardened-cc1 -fstack-protector-strong -specs=/usr/lib/rpm/redhat/redhat-annobin-cc1 -fasynchronous-unwind-tables -fstack-clash-protection"    # -g -Werror=implicit-function-declaration -Werror=implicit-int -mbranch-protection=standard
#BUILD_LDFLAGS="-Wl,-z,relro -Wl,--as-needed -Wl,-z,now -specs=/usr/lib/rpm/redhat/redhat-hardened-ld -specs=/usr/lib/rpm/redhat/redhat-annobin-cc1 -Wl,--build-id=sha1 -specs=/usr/lib/rpm/redhat/redhat-package-notes"
CROSS_COMPILE="${TARGET}-"
RPM_PACKAGE_NAME=$(getSpecValue name) # needed if make called outside of rpmbuild
RPM_PACKAGE_VERSION=$(getSpecValue version)
RPM_PACKAGE_RELEASE=$(getSpecValue pkgrelease)
TARFILE_RELEASE=$(getSpecValue tarfile_release)
TOPDIR=$(getSpecValue _topdir)
export ARCH CROSS_COMPILE RPM_PACKAGE_NAME RPM_PACKAGE_VERSION RPM_PACKAGE_RELEASE

cp SOURCES/* "${TOPDIR}"/SOURCES/

spectool -g -R ${SPECFILE}

if [ -d out ]; then
    rm -rf out/
fi

mkdir out || exit 1

cp "${TOPDIR}"/SOURCES/kernel-aarch64-fedora.${CONFIG}.config ${TOPDIR}/SOURCES/kernel-aarch64-fedora.config
cp "${TOPDIR}"/SOURCES/patch-6.${PATCHVERSION}-redhat.${PATCH}.patch  "${TOPDIR}"/SOURCES/patch-6.${PATCHVERSION}-redhat.patch

# Use .cache value to increment
[ -d .cache ] || mkdir .cache
if [ "${KERNEL}" = "armbian" ]; then
    sed -i "s/^\(%define buildid \).*$/\1.${BUILDVER}.armbian/" ${SPECFILE}
elif [ "${KERNEL}" = "collabora" ]; then
    sed -i "s/^\(%define buildid \).*$/\1.${BUILDVER}.collabora/" ${SPECFILE}
fi

# Armbian patches fail on GCC14
#[ "$(gcc -dumpversion)" -ge 14 ] && sed -i 's/^CONFIG_DRM_WERROR=.*$/# CONFIG_DRM_WERROR is not set/' "${TOPDIR}"/SOURCES/kernel-aarch64-fedora.config

#    --with vanilla \
#    --without configchecks \
#    --define="build_cflags ${BUILD_CFLAGS}" \
#    --define="build_ldflags ${BUILD_LDFLAGS}" \
#    --define="make_opts ${MAKE_OPTS}" \
#    --without debuginfo \
(rpmbuild -v ${RPMBUILD_ARGS} \
    --with baseonly \
    --without configchecks \
    --with cross \
    --with verbose \
    --target=${TARGET} \
    --define="cross_opts ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE}" \
    ${SPECFILE}

if [ $? -eq 0 ]; then
    BUILDVER=$(expr ${BUILDVER} + 1)
    echo ${BUILDVER} > .cache/buildver
fi
) 2>out/rpmbuild.err | tee out/rpmbuild.out

exit
# vi: set wrap:
