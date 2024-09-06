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

function getSpecValue () {
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

function forceConfigSetting () {
	awk '
	BEGIN {
		key = ""
		lineno = 0

		delete config
		delete line

		# Required for RPM to build
		force["CONFIG_DEBUG_INFO_BTF"] = "y"
		force["CONFIG_DEBUG_INFO_DWARF_TOOLCHAIN_DEFAULT"] = "y"
		force["CONFIG_DEBUG_INFO_NONE"] = "NULL"
		force["CONFIG_DEBUG_INFO_REDUCED"] = "NULL"
		force["CONFIG_EFI_ZBOOT"] = "y"
		force["CONFIG_SECURITY_LOCKDOWN_LSM"] = "y"
		force["CONFIG_LSM"] = "\"lockdown,yama,integrity,selinux,bpf,landlock\""
		force["CONFIG_MODULE_SIG"] = "y"
		force["CONFIG_MODULE_SIG_KEY"] = "\"certs/signing_key.pem\""

		# Required for Fedora boot
		force["CONFIG_ZRAM"] = "m"
		force["CONFIG_ZRAM_DEF_COMP"] = "\"lzo-rle\""
		force["CONFIG_ZRAM_DEF_COMP_LZORLE"] = "y"
		force["CONFIG_ZRAM_MULTI_COMP"] = "y"
		force["CONFIG_XFS_DRAIN_INTENTS"] = "y"
		force["CONFIG_XFS_FS"] = "m"
		force["CONFIG_XFS_LIVE_HOOKS"] = "y"
		force["CONFIG_XFS_MEMORY_BUFS"] = "y"
		force["CONFIG_XFS_ONLINE_SCRUB"] = "y"
		force["CONFIG_XFS_POSIX_ACL"] = "y"
		force["CONFIG_XFS_QUOTA"] = "y"
		force["CONFIG_XFS_RT"] = "y"
		force["CONFIG_XFS_SUPPORT_ASCII_CI"] = "y"
		force["CONFIG_XFS_SUPPORT_V4"] = "y"


		# Enable MMC in Armbian default config
	}

	{
		line[++lineno] = $0

		switch ($0) {
		case /^# CONFIG_/:
			config[$2] = "NULL"
			break
		case /^CONFIG_/:
			split($0, a, /=/)
			config[a[1]] = a[2]
			break
		}
	}

	END {
		for (key in force) {
			config[key] = force[key]
			if (ENVIRON["DBG"] > 0)
				printf("forced %s=%s\n", key, config[key]) > "/dev/stderr"
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
	[ $# -gt 1 ] && local patchversion=$1; shift
	[ $# -eq 1 ] && local commitid=$1 || exit 1

	if [ -s "${TOPDIR}"/.cache/linux-"${patchversion}.${commitid}".tar.xz ]; then
		cp "${TOPDIR}"/.cache/linux-"${patchversion}.${commitid}".tar.xz "${ODIR}"
	else
		git archive --prefix=linux-"${patchversion}.${commitid}"/ "${commitid}" | xz -zc - >"${ODIR}"/linux-"${patchversion}.${commitid}".tar.xz

		cp "${ODIR}"/linux-"${patchversion}.${commitid}".tar.xz "${TOPDIR}"/.cache/
	fi
}

function usage () {
	local errno=0; [ $# -ge 1 ] && errno=$1 && shift

	echo 2>&1 "$PROG: [-h|--help][-d|--dryrun][-e|--extraversion=\"text\"][-m|--mainline][-r|--rawhide]"

	exit "$errno"
}

OPTARGS=$(getopt --options hde:mr --longoptions help,dryrun,extraversion:,mainline,rawhide --name "$PROG" -- ${1+"$@"}) || usage $?
eval "set -- $OPTARGS"

while true; do
	case "$1" in
	-h|--help)
		usage 0
		;;
	-d|--dryrun)
		DRYRUN="echo"
		shift
		;;
	-a|--armbian)
		ARMBIAN=0
		shift
		;;
	-c|--collabora)
		COLLABORA=0
		shift
		;;
	-e|--extraversion)
		EXTRAVERSION="$2"
		shift 2
		;;
	-m|--mainline)
		MAINLINE=0
		shift
		;;
	-r|--rawhide)
		RAWHIDE=0
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
COLLABORA=${COLLABORA:-1}
COLLABORA_SRCDIR="${TOPDIR}/../collabora/linux"
DRYRUN=${DRYRUN:-""}
EXTRAVERSION=${EXTRAVERSION:-""}
#FEDORA_SRPM="kernel-6.10.0-64.fc41.src.rpm"
FEDORA_SRPM="kernel-6.11.0-0.rc6.20240905gitc763c4339688.52.fc42.src.rpm"
FEDORA_ARMBIAN_SRPM="kernel-6.11.0-0.armbian.fc40.src.rpm"
FEDORA_COLLABORA_SRPM="kernel-6.11.0-0.collabora.fc40.src.rpm"
GID=$(getent passwd ${LOGNAME} | cut -d: -f4)
MAINLINE=${MAINLINE:-1}
PKGRELEASE="${SUBLEVEL:=0}"
#PODMAN_UMASK="0002"
#PODMAN_USERNS="keep-id:uid=1000,gid=127"
PODMAN_USERNS="keep-id:uid=0,gid=0"
RAWHIDE=${RAWHIDE:--1}
SPECFILE="${TOPDIR}"/SPECS/kernel.spec
#export ARCH PODMAN_USERNS PODMAN_UMASK
export ARCH PODMAN_USERNS

if [ -n "${EXTRAVERSION}" ]; then
	PKGRELEASE="${SUBLEVEL}.${EXTRAVERSION}"
fi
SPECRELEASE="${PKGRELEASE}%{?buildid}%{?dist}"

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
	_SPECFILE=kernel.armbian.spec
	[ -f ./kernel.spec ] && cp kernel.spec ${_SPECFILE} || exit 1

	pushd "${ARMBIAN_BUILDDIR}" &> /dev/null || exit 1
	#
	# >>
	ARMBIAN_SRCDIR=$(./compile.sh config-dump BOARD=orangepi5 BRANCH=edge 2>/dev/null | jq -r '.LINUXSOURCEDIR')
	[ -d ./cache/sources/"${ARMBIAN_SRCDIR}" ] && rm -rf ./cache/sources/"${ARMBIAN_SRCDIR}"
	#mkdir -p ./cache/sources/"${ARMBIAN_SRCDIR}"

	${DRYRUN} ./compile.sh rewrite-kernel-patches BOARD=orangepi5 BRANCH=edge PREFER_DOCKER=yes WORKDIR_BASE_TMP=${XDG_RUNTIME_DIR}/tmp DOCKER_SERVER_REQUIRES_LOOP_HACKS=no KERNEL_GIT=full

	[ $? -eq 0 ] || exit 1

	pushd ./cache/sources/"${ARMBIAN_SRCDIR}" &> /dev/null || exit 1
	#
	# >>>
	# wind back to the base
	COMMITID=$(git log --author=auto.patch@armbian.com --pretty=format:"%P" --max-count=1) # parent of
	PATCHVERSION=$(make kernelversion | awk '{split($0, a, /\./); printf("%d.%d\n", a[1], a[2])}')

	${DRYRUN} archiveGitTree "${PATCHVERSION}" "${COMMITID}"
	${DRYRUN} git diff "${COMMITID}" HEAD --stat --patch --output "${ODIR}"/pre.patch
	${DRYRUN} remakeRedhatPatch "${PATCHVERSION}" ".post"

	${DRYRUN} resetGitTree "${COMMITID}"
	#
	# <<<
	popd &> /dev/null || exit 1

	${DRYRUN} ./compile.sh rewrite-kernel-config BOARD=orangepi5 BRANCH=edge PREFER_DOCKER=yes WORKDIR_BASE_TMP=${XDG_RUNTIME_DIR}/tmp DOCKER_SERVER_REQUIRES_LOOP_HACKS=no KERNEL_GIT=full

	${DRYRUN} forceConfigSetting < ./cache/sources/"${ARMBIAN_SRCDIR}"/.config > "${ODIR}"/kernel-aarch64-fedora.armbian.config
	#
	# <<
	popd &> /dev/null || exit 1

	# merge the patches
	${DRYRUN} cat pre.patch patch-${PATCHVERSION}-redhat.post.patch >patch-${PATCHVERSION}-redhat.armbian.patch
	rm pre.patch patch-${PATCHVERSION}-redhat.post.patch

	${DRYRUN} sed -i "s/^.*\(define buildid \).*\$/%\1.armbian/" ${_SPECFILE}
	${DRYRUN} sed -i "s/^\(%define pkgrelease \).*\$/\1${PKGRELEASE}/" ${_SPECFILE}
	${DRYRUN} sed -i "s/^\(%define tarfile_release \).*\$/\1${PATCHVERSION}.${COMMITID}/" ${_SPECFILE}
	${DRYRUN} sed -i "s/^\(%define specrelease \).*\$/\1${SPECRELEASE}/" ${_SPECFILE}
	${DRYRUN} sed -i 's/^\(BuildRequires: openssl-devel openssl-devel-engine\)/%if 0%{fedora} > 40\n\1\n%else\nBuildRequires: openssl-devel\n%endif\n/' ${_SPECFILE}

fi

# COLLABORA
#
if [ ${COLLABORA} -eq 0 ]; then
	_SPECFILE=kernel.collabora.spec
	cp kernel.spec ${_SPECFILE}

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
	forceConfigSetting < .config > "${ODIR}"/kernel-aarch64-fedora.collabora.config
	#
	# <<
	popd &> /dev/null || exit 1

	sed -i "s/^.*\(define buildid \).*\$/%\1.collabora/" ${_SPECFILE}
	sed -i "s/^\(%define pkgrelease \).*\$/\1${PKGRELEASE}/" ${_SPECFILE}
	sed -i "s/^\(%define tarfile_release \).*\$/\1${PATCHVERSION}.${COMMITID}/" ${_SPECFILE}
	sed -i "s/^\(%define specrelease \).*\$/\1${SPECRELEASE}/" ${_SPECFILE}
	sed -i 's/^\(BuildRequires: openssl-devel openssl-devel-engine\)/%if 0%{fedora} > 40\n\1\n%else\nBuildRequires: openssl-devel\n%endif\n/' ${_SPECFILE}

fi

if [ ${RAWHIDE} -eq 0 ]; then
	_SPECFILE=kernel.rawhide.spec
	cp kernel.spec ${_SPECFILE}

	REPO="https://dl.fedoraproject.org/pub/fedora/linux/development/rawhide/Everything/source/tree/Packages/k/"
	SRPM=$(wget -O - -q ${REPO} | awk '
		/href="kernel-[[:digit:]]*\.[[:digit:]]*\..*\.src\.rpm"/ {
			print gensub(/^(.*")(kernel-[[:digit:]]*\.[[:digit:]]*\..*\.src\.rpm)(".*)$/, "\\2", 1)
		}') 

	if [ "${SRPM}" = "${FEDORA_SRPM}" ]; then
		cat "${TOPDIR}"/SRPMS/${FEDORA_SRPM} | rpm2archive - | tar xzf -
	else
		echo -e "\bRawhide has newer version of kernel RPM"
		wget -O - ${REPO}/${SRPM} | rpm2archive - | tar xzf -
	fi

	tarfile_release=$(SPECFILE=${_SPECFILE} getSpecValue tarfile_release)
	patchversion=$(SPECFILE=${_SPECFILE} getSpecValue patchversion)
	if [ ${MAINLINE} -eq 0 ]; then
		# remove kernel provided in .rpm
		${DRYRUN} rm linux-${tarfile_release}.tar.xz

		tarfile_release=${patchversion}${EXTRAVERSION:+-${EXTRAVERSION}}
		if [ -z "${DRYRUN}" ]; then
			wget -O - https://github.com/torvalds/linux/archive/refs/tags/v${tarfile_release}.tar.gz > linux-${tarfile_release}.tar.gz
	   else
			printf "%s > %s\n" "wget -O - https://github.com/torvalds/linux/archive/refs/tags/v${tarfile_release}.tar.gz" "linux-${tarfile_release}.tar.gz"
	   fi
	fi

	sed -i "s/^\(%define pkgrelease \).*\$/\1${PKGRELEASE}/" ${_SPECFILE}
	sed -i "s/^\(%define tarfile_release \).*\$/\1${PATCHVERSION}.${COMMITID}/" ${_SPECFILE}
	sed -i "s/^\(%define specrelease \).*\$/\1${SPECRELEASE}/" ${_SPECFILE}
	sed -i 's/^\(BuildRequires: openssl-devel openssl-devel-engine\)/%if 0%{fedora} > 40\n\1\n%else\nBuildRequires: openssl-devel\n%endif\n/' ${_SPECFILE}

fi

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
