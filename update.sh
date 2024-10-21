#!/bin/bash
#
DBG=${DBG:-0} && [ "0$DBG" -eq 0 ]; [ "$DBG" -eq 1 ] && set -x

PATH=/bin:/usr/bin:$PATH
export PATH

PROG=$(realpath "$0" | sed 's|^.*\/||')
TOPDIR=$(pwd)

function ensureKernelSRPM () {
	local repo="https://dl.fedoraproject.org/pub/fedora/linux/development/rawhide/Everything/source/tree/Packages/k/"
	local srpm=""

	if [ ! -f "${TOPDIR}"/SRPMS/"${FEDORA_SRPM}" ]; then
		[ -d "${TOPDIR}"/SRPMS ] || mkdir "${TOPDIR}"/SRPMS

		pushd "${TOPDIR}"/SRPMS &> /dev/null || exit 1
		# >>>
		srpm=$(wget -O - -q "${repo}" | awk '
			/href="kernel-[[:digit:]]*\.[[:digit:]]*\..*\.src\.rpm"/ {
				print gensub(/^(.*")(kernel-[[:digit:]]*\.[[:digit:]]*\..*\.src\.rpm)(".*)$/, "\\2", 1)
			}')

		[ "${srpm}" = "${FEDORA_SRPM}" ] && wget "${repo}/${FEDORA_SRPM}"

		if [ ! -f "${FEDORA_SRPM}" ]; then
			echo 1>&2 "${FEDORA_SRPM} not avaiable"
			if [ ${RAWHIDE} -eq 0 ]; then
				echo -e "\bFetching kernel SRPM from Fedora rawhide"
				wget ${repo}/${srpm}
				[ $? -eq 0 ] && FEDORA_SRPM="${srpm}"
			fi
		fi
		# <<<
		popd &> /dev/null || exit 1
	fi

	if [ -f "${TOPDIR}"/SRPMS/"${FEDORA_SRPM}" ]; then
		return 0
	else
		return 1
	fi
}

function forceConfigSetting () {
	[ $# -eq 1 ] && local build=$1 || exit 1

	awk -f "${TOPDIR}/force_buildreq.awk" -f "${TOPDIR}/force_${build}.awk" -e '
	BEGIN {
		key = ""

		delete config
	}

	{
		switch ($0) {
		case /^# CONFIG_/:
			config[$2] = "NULL"
			break
		case /^CONFIG_/:
			switch (split($0, a, /=/)) {
			case 0:
				printf("error: malformed %s\n", $0) > "/dev/stderr"
				break
			case 2:
				config[a[1]] = a[2]
				break
			default:
				config[a[1]] = substr($0, match($0, "=") + 1)
			}
		}
	}

	END {
		for (key in force) {
			if (ENVIRON["DBG"] > 0)
				printf("forced %s=<%s> [%s]\n", key, force[key], config[key]) > "/dev/stderr"

			if (length(force[key]) > 0)
				config[key] = force[key]
			else
				delete config[key]
		}

		printf("# arm64\n")

		for (key in config) {
			if (config[key] == "NULL")
				printf("# %s is not set\n", key)
			else
				printf("%s=%s\n", key, config[key])
		}

		exit(0)
	}'

	return
}

function resetGitTree () {
	[ $# -eq 1 ] && local commitid=$1 || exit 1

	git reset --hard "${commitid}"
	git clean -fx
	make clean mrproper
}

# make new patch-n.nn-redhat.patch
function remakeRedhatPatch () {
	[ $# -gt 1 ] && local patchversion=$1; shift
	[ $# -eq 1 ] && local buildid=$1 || exit 1

	patch -p1 < "${ODIR}"/patch-${patchversion}-redhat.patch

	git add --intent-to-add $(git status --untracked-files=yes --porcelain | awk '/^\?\?/ {print $2}')
	git diff --stat --patch --output "${ODIR}"/patch-${patchversion}-redhat${buildid}.patch
}

function archiveGitTree () {
	[ $# -ge 2 ] || exit 1
	local patchversion=$1; shift
	local commitid=$1; shift
	local baseid=""; [ $# -eq 1 ] && baseid=$1; shift
	[ $# -eq 0 ] || exit 1

	[ -d "${TOPDIR}"/.cache ] || mkdir "${TOPDIR}"/.cache

	baseid=${baseid:-"${commitid}"}
	if [ -s "${TOPDIR}"/.cache/linux-"${patchversion}.${baseid}".tar.xz ]; then
		cp "${TOPDIR}"/.cache/linux-"${patchversion}.${baseid}".tar.xz "${ODIR}"
	elif [ -s "${TOPDIR}"/.cache/linux-"${patchversion}.${baseid}".tar.xz ]; then
		cp "${TOPDIR}"/.cache/linux-"${patchversion}.${baseid}".tar.xz "${ODIR}"
	else
		git archive --prefix=linux-"${patchversion}.${baseid}"/ "${commitid}" | xz -zc - >"${ODIR}"/linux-"${patchversion}.${baseid}".tar.xz

		cp "${ODIR}"/linux-"${patchversion}.${baseid}".tar.xz "${TOPDIR}"/.cache/
	fi
}

function addPatches () {
	[ $# -eq 4 ] || exit 1
	local specfile=$1; shift
	local patchdir=$1; shift
	local kver=$1; shift
	local odir=$1

	local i=0
	local j=0
	local last=0
	local next=0
	local patch=""
	local patches=$(find "${patchdir}" -name \*.patch | sort)
	local range=$(wc -l <<< "${patches}")

	[ -z "${patches}" ] && return

	spectool --patches "${specfile}" | sed 's/^Patch\([0-9]*\):.*$/\1/' | sort -nr | while read -r i; do
		case "${i}" in
		999999) # RedHat reserves Patch999999 for testing and it has to be the last patch
			j=${i}
			continue
			;;
		[1-9]*) # patches start at 1
			if [ $(expr ${i} + ${range}) -ge ${j} ]; then
				j=${i}
				continue
			fi
			;;
		*)
			# got to the end of list without room to add all the patches
			return 1
			;;
		esac

		last=${i}
		while read -r patch; do
			grep -q $(basename ${patch}) <<< "${PATCH_BLACKLIST}" && continue

			cp "${patch}" "${odir}/patch-${kver}-$(basename ${patch})"

			next=$(expr ${last} + 1)
			sed -i "/^Patch${last}:/a Patch${next}: patch-${kver}-$(basename ${patch})" "${specfile}"

			# put all the patches ahead of Redhat's kernel version patch
			sed -i "/^ApplyOptionalPatch patch-%{patchversion}-redhat.patch/i ApplyOptionalPatch patch-${kver}-$(basename ${patch})" "${specfile}"

			last=${next}
		done <<< "${patches}"

		return
	done
}

function addSource () {
	[ $# -eq 2 ] || exit 1
	local specfile=$1; shift
	local source=$1

	local last=$(spectool --sources "${specfile}" | sed 's/^Source\([0-9]*\):.*$/\1/' | sort -n | tail -1)
	local next=$(expr ${last} + 1)
	sed -i "/^Source${last}:/a Source${next}: ${source}" "${specfile}"

	echo "${next}"
}

function usage () {
	local errno=0; [ $# -ge 1 ] && errno=$1 && shift

	echo 2>&1 "$PROG: [-h|--help][-a|--armbian][-c|--collabora][--rebase]"

	exit "$errno"
}

OPTARGS=$(getopt --options hacr --longoptions help,armbian,collabora,rebase --name "$PROG" -- ${1+"$@"}) || usage $?
eval "set -- $OPTARGS"

while true; do
	case "$1" in
	-h|--help)
		usage 0
		;;
	-a|--armbian)
		ARMBIAN=0
		shift
		;;
	-c|--collabora)
		COLLABORA=0
		shift
		;;
	-r|--rebase)
		REBASE=0
		shift
		;;
	--)
		shift
		break
		;;
	esac
done

[ $# -eq 0 ] || usage 1

ARCH="arm64"
ARMBIAN=${ARMBIAN:-1}
ARMBIAN_BUILDDIR="${TOPDIR}/../armbian/armbian-build"
ARMBIAN_PATCHDIR="${TOPDIR}/patches/armbian"
COLLABORA=${COLLABORA:-1}
COLLABORA_PATCHDIR="${TOPDIR}/patches/collabora"
COLLABORA_SRCDIR="${TOPDIR}/../collabora/linux"
FEDORA_SRPM="kernel-6.11.4-300.fc41.src.rpm"
PATCH_BLACKLIST=""
PATCHES="${TOPDIR}/patches"
REBASE=${REBASE:-1}
SOURCE=""
SPECFILE=""
SPEC_SRCNUMBER=""
TMPDIR=${TMPDIR:-"${XDG_RUNTIME_DIR}"}
export ARCH

if [ ${ARMBIAN} -eq 0 -a ${COLLABORA} -eq 0 ]; then
	exit 1
elif [ ${ARMBIAN} -eq 1 -a ${COLLABORA} -eq 1 ]; then
	exit 1
fi

ODIR=$(mktemp -d)
trap "[ ${DBG} -eq 0 ] && rm -rf \"${ODIR}\"" EXIT INT

[ -d SPECS ] && rm -f SPECS/* || mkdir SPECS
[ -d SOURCES ] && rm -f SOURCES/* || mkdir SOURCES

ensureKernelSRPM || exit 1

pushd "${ODIR}" &> /dev/null || exit 1
#
# >
cat "${TOPDIR}"/SRPMS/${FEDORA_SRPM} | rpm2archive - | tar xzf -

# ARMBIAN
#
if [ ${ARMBIAN} -eq 0 ]; then
	SPECFILE=kernel.armbian.spec
	[ -f ./kernel.spec ] && cp kernel.spec ${SPECFILE} || exit 1

	PATCH_BLACKLIST=$(cat -<< %E%O%T%
%E%O%T%
	)

	pushd "${ARMBIAN_BUILDDIR}" &> /dev/null || exit 1
	#
	# >>
	ARMBIAN_CONFIG=$(./compile.sh config-dump BOARD=orangepi5 BRANCH=edge 2>/dev/null)
	ARMBIAN_SRCDIR=$(jq -r '.LINUXSOURCEDIR' <<<"${ARMBIAN_CONFIG}")
	BASEID=$(git log main --pretty=format:"%H" --max-count=1)
	KERNEL_MAJOR_MINOR=$(jq -r '.WANT_ARTIFACT_KERNEL_INPUTS_ARRAY[] | match("KERNEL_MAJOR_MINOR=(.*).") | .captures[].string' <<<"${ARMBIAN_CONFIG}")

	KERNELPATCHDIR=$(jq -r '.WANT_ARTIFACT_KERNEL_INPUTS_ARRAY[] | match("KERNELPATCHDIR=(.*).") | "patch/kernel/" + .captures[].string' <<<"${ARMBIAN_CONFIG}")

	[ -d ./cache/sources/"${ARMBIAN_SRCDIR}" ] && rm -rf ./cache/sources/"${ARMBIAN_SRCDIR}"

	./compile.sh rewrite-kernel-patches BOARD=orangepi5 BRANCH=edge PREFER_DOCKER=yes WORKDIR_BASE_TMP=${XDG_RUNTIME_DIR}/armbian DOCKER_SERVER_REQUIRES_LOOP_HACKS=no KERNEL_GIT=shallow SKIP_LOG_ARCHIVE=yes

	[ $? -eq 0 ] || exit 1

	addPatches "${ODIR}/${SPECFILE}" "${KERNELPATCHDIR}" "${KERNEL_MAJOR_MINOR}" "${ODIR}"

	if [ -d "${KERNELPATCHDIR}"/dt ]; then
		mkdir -p "${ODIR}"/arch/arm64/boot/dts/rockchip || exit 1
		cp "${KERNELPATCHDIR}"/dt/* "${ODIR}"/arch/arm64/boot/dts/rockchip/
	fi

	if [ -d "${KERNELPATCHDIR}"/overlay ]; then
		mkdir -p "${ODIR}"/arch/arm64/boot/dts/rockchip/overlay || exit 1
		cp "${KERNELPATCHDIR}"/overlay/* "${ODIR}"/arch/arm64/boot/dts/rockchip/overlay/


	fi

	addPatches "${ODIR}/${SPECFILE}" "${ARMBIAN_PATCHDIR}" "${KERNEL_MAJOR_MINOR}" "${ODIR}"

	if [ ${REBASE} -eq 0 ]; then
		pushd ./cache/sources/"${ARMBIAN_SRCDIR}" &> /dev/null || exit 1
		#
		# >>>
		# Skip the summary patch
		COMMITID=$(git log --pretty=format:"%H" --max-count=2 | head -1)
		PATCHVERSION=$(make kernelversion | awk '{split($0, a, /\./); printf("%d.%d\n", a[1], a[2])}')

		# The Armbian kernel source tree (patched)
		archiveGitTree "${PATCHVERSION}" "${COMMITID}" "${BASEID}"
		remakeRedhatPatch "${PATCHVERSION}" ".armbian"

		# want the following kernel config to be based on just the Armbian sources
		resetGitTree "${COMMITID}"
		#
		# <<<
		popd &> /dev/null || exit 1
	fi

	#  
	./compile.sh rewrite-kernel-config BOARD=orangepi5 BRANCH=edge PREFER_DOCKER=yes WORKDIR_BASE_TMP=${XDG_RUNTIME_DIR}/armbian DOCKER_SERVER_REQUIRES_LOOP_HACKS=no KERNEL_GIT=shallow SKIP_LOG_ARCHIVE=yes

	forceConfigSetting "ARMBIAN" < ./cache/sources/"${ARMBIAN_SRCDIR}"/.config > "${ODIR}"/kernel-aarch64-fedora.armbian.config
	#
	# <<
	popd &> /dev/null || exit 1

	if [ -d  ./arch ]; then
		tar -cf armbian-dtree-files.tar ./arch
		rm -rf ./arch

		SPEC_SRCNUMBER=$(addSource "${SPECFILE}" armbian-dtree-files.tar)

		# Unpack the device tree files after the last patch and add Makefile glue
		sed -i "/^ApplyOptionalPatch linux-kernel-test.patch/a tar xvf %{SOURCE${SPEC_SRCNUMBER}}" "${SPECFILE}"
		sed -i "/^ApplyOptionalPatch linux-kernel-test.patch/a echo \"subdir-y := \$(dts-dirs) overlay\" >> arch/arm64/boot/dts/rockchip/Makefile" "${SPECFILE}"

	fi

	sed -i "s/^.*\(define buildid \).*\$/%\1.armbian/" ${SPECFILE}
	[ ${REBASE} -eq 0 ] && sed -i "s/^\(%define tarfile_release \).*\$/\1${PATCHVERSION}.${BASEID}/" ${SPECFILE}
fi

# COLLABORA
#
if [ ${COLLABORA} -eq 0 ]; then
	SPECFILE=kernel.collabora.spec
	cp kernel.spec ${SPECFILE}

	KERNEL_MAJOR_MINOR=$(awk '/%define patchversion / { print $3 + 1 }' kernel.spec)

	pushd "${COLLABORA_SRCDIR}" &> /dev/null || exit 1
	# >>
	#
	COMMITID=$(git log --pretty=format:"%H" --max-count=1)
	PATCHVERSION=$(make kernelversion | awk '{split($0, a, /\./); printf("%d.%d\n", a[1], a[2])}')

	resetGitTree "${COMMITID}"
	archiveGitTree "${PATCHVERSION}" "${COMMITID}"
	remakeRedhatPatch "${PATCHVERSION}" ".collabora"
	resetGitTree "${COMMITID}"
	make defconfig
	forceConfigSetting "COLLABORA" < .config > "${ODIR}"/kernel-aarch64-fedora.collabora.config
	#
	# <<
	popd &> /dev/null || exit 1

	addPatches "${ODIR}/${SPECFILE}" "${COLLABORA_PATCHDIR}" "${KERNEL_MAJOR_MINOR}" "${ODIR}"

	sed -i "s/^.*\(define buildid \).*\$/%\1.collabora/" ${SPECFILE}
	sed -i "s/^\(%define tarfile_release \).*\$/\1${PATCHVERSION}.${COMMITID}/" ${SPECFILE}
fi

PKGRELEASE=$(awk '/%define pkgrelease / { print $3 + 1 }' kernel.spec)
SPECRELEASE="${PKGRELEASE}%{?buildid}%{?dist}"

sed -i "s/^\(%define pkgrelease \).*\$/\1${PKGRELEASE}/" ${SPECFILE}
sed -i "s/^\(%define specrelease \).*\$/\1${SPECRELEASE}/" ${SPECFILE}
sed -i 's/^\(BuildRequires: openssl-devel openssl-devel-engine\)/%if 0%{fedora} > 40\n\1\n%else\nBuildRequires: openssl-devel\n%endif\n/' ${SPECFILE}

#
# <
popd &> /dev/null || exit 1

mv "${ODIR}"/kernel.spec SPECS/
[ -f "${ODIR}"/kernel.armbian.spec ] && mv "${ODIR}"/kernel.armbian.spec SPECS/
[ -f "${ODIR}"/kernel.collabora.spec ] && mv "${ODIR}"/kernel.collabora.spec SPECS/
[ -f "${ODIR}"/kernel.rawhide.spec ] && mv "${ODIR}"/kernel.rawhide.spec SPECS/
mv "${ODIR}"/* SOURCES/

[ $(find "${ODIR}" -mindepth 1 | wc -l) -ne 0 ] && echo 1>&2 "error: unprocessed file from SRPM" && exit 1

# vi: set wrap noexpandtab:
