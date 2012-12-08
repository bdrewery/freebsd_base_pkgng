#! /bin/sh

SRC_BASE=$1

if [ $# -ne 1 ]; then
	echo "Usage: $0 <src_path>" >&2
	exit 1
fi

export __MAKE_CONF=/dev/null
export KERNCONF=GENERIC
export SRCCONF=${SRC_BASE}/../etc/src.conf
MAKE_JOBS="-j$(sysctl -n kern.smp.cpus)"
export BUILD_FLAGS="${MAKE_JOBS} -DNO_CLEAN -DNO_KERNELCLEAN"

CCACHE_PATH=/usr/local/libexec/ccache
if [ -d ${CCACHE_PATH} ]; then
	export CXX="${CCACHE_PATH}/world/c++"
	export CC="${CCACHE_PATH}/world/cc"
fi

BUILDDIR=$(mktemp -d -t package)
DISTDIR=${BUILDDIR}/dist
MANIFESTDIR=${BUILDDIR}/manifest
PKGDIR=${BUILDDIR}/packages
mkdir -p ${MANIFESTDIR}
mkdir -p ${PKGDIR}
trap "find ${BUILDDIR} -flags schg -exec chflags noschg {} +; rm -rf ${BUILDDIR}" EXIT
echo "Building in ${BUILDDIR}"
/usr/bin/time make -s -C ${SRC_BASE} ${BUILD_FLAGS} buildworld buildkernel
/usr/bin/time make -s -C ${SRC_BASE} distributekernel DISTDIR=${DISTDIR}
/usr/bin/time make -s -C ${SRC_BASE} distributeworld DISTDIR=${DISTDIR}
mkdir -p ${DISTDIR}/kernel-symbols/boot/kernel
mv ${DISTDIR}/kernel/boot/kernel/*.symbols ${DISTDIR}/kernel-symbols/boot/kernel

eval `grep "^[RB][A-Z]*=" ${JAILMNT}/usr/src/sys/conf/newvers.sh`
# REVISION, BRANCH, RELEASE
VERSION=${REVISION}
OSVERSION=$(awk '/^\#define[[:blank:]]__FreeBSD_version/ {print $3}' ${SRC_BASE}/sys/sys/param.h)
ARCH=$(uname -m)

# Use pkg(8) to determine ARCH from the base dist
ARCH=$(pkg -c ${DISTDIR}/base/ -vv|awk '$1 == "abi:" {print $2}')


# Create pkgng packages
for dist in ${DISTDIR}/*; do
	dist=${dist#${DISTDIR}/}
	mkdir ${MANIFESTDIR}/${dist}
#osversion:     ${OSVERSION}
	DIST_SIZE=$(find ${DISTDIR}/${dist} -type f -exec stat -f %z {} + | awk 'BEGIN {s=0} {s+=$1} END {print s}')
	{
		cat << EOF
name:          freebsd-${dist}
version:       ${VERSION}
origin:        freebsd/${dist}
comment:       FreeBSD ${dist} distribution
arch:          ${ARCH}
www:           http://www.freebsd.org
maintainer:    re@FreeBSD.org
prefix:        /
licenselogic:  single
licenses:      [BSD]
flatsize:      ${DIST_SIZE}
desc:          "FreeBSD ${dist} distribution"
categories:    [freebsd]
EOF
		# Add files in
		echo "files:"
		find ${DISTDIR}/${dist} -type f -exec sha256 -r {} + |
			awk '{print "    " $2 ": " $1}'
		# Add symlinks in
		find ${DISTDIR}/${dist} -type l |
			awk "{print \"    \" \$1 \": '-'\"}"

		# Add directories in
		echo "directories:"
		find ${DISTDIR}/${dist} -type d -mindepth 1 |
			awk '{print "    " $1 ": y"}'

	} | sed -e "s:${DISTDIR}/${dist}::" > ${MANIFESTDIR}/${dist}/+MANIFEST

	# Create the package
	pkg create -r ${DISTDIR}/${dist} -m ${MANIFESTDIR}/${dist} -o ${PKGDIR} ignored #ignored is due to pkg-create(8) bug
done

echo $BUILDDIR
