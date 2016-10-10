#!/bin/bash

# This script downloads and builds the iOS, tvOS and Mac openSSL libraries with Bitcode enabled

# Credits:
# https://github.com/st3fan/ios-openssl
# https://github.com/x2on/OpenSSL-for-iPhone/blob/master/build-libssl.sh
# https://gist.github.com/foozmeat/5154962
# Peter Steinberger, PSPDFKit GmbH, @steipete.
# Felix Schwarz, IOSPIRIT GmbH, @felix_schwarz.

set -e

usage ()
{
	echo "usage: $0 [iOS SDK version (defaults to latest)] [tvOS SDK version (defaults to latest)] [OS X minimum deployment target (defaults to 10.7)]"
	exit 127
}

if [ $1 -e "-h" ]; then
	usage
fi

if [ -z $1 ]; then
	IOS_SDK_VERSION="" #"9.1"
	IOS_MIN_SDK_VERSION="8.0"
	
	TVOS_SDK_VERSION="" #"9.0"
	TVOS_MIN_SDK_VERSION="9.0"
	
	OSX_DEPLOYMENT_TARGET="10.7"
else
	IOS_SDK_VERSION=$1
	TVOS_SDK_VERSION=$2
	OSX_DEPLOYMENT_TARGET=$3
fi

OPENSSL_VERSION="openssl-1.0.2d"
DEVELOPER=`xcode-select -print-path`

buildMac()
{
	ARCH=$1

	echo "Building ${OPENSSL_VERSION} for ${ARCH}"

	TARGET="darwin-i386-cc"

	if [[ $ARCH == "x86_64" ]]; then
		TARGET="darwin64-x86_64-cc"
	fi

	export CC="${BUILD_TOOLS}/usr/bin/clang -fembed-bitcode -mmacosx-version-min=${OSX_DEPLOYMENT_TARGET}"

	pushd . > /dev/null
	cd "${OPENSSL_VERSION}"
	./Configure no-asm ${TARGET} --openssldir="/tmp/${OPENSSL_VERSION}-${ARCH}" &> "/tmp/${OPENSSL_VERSION}-${ARCH}.log"
	make >> "/tmp/${OPENSSL_VERSION}-${ARCH}.log" 2>&1
	make install_sw >> "/tmp/${OPENSSL_VERSION}-${ARCH}.log" 2>&1
	make clean >> "/tmp/${OPENSSL_VERSION}-${ARCH}.log" 2>&1
	popd > /dev/null
}

buildIOS()
{
	ARCH=$1

	pushd . > /dev/null
	cd "${OPENSSL_VERSION}"
  
	if [[ "${ARCH}" == "i386" || "${ARCH}" == "x86_64" ]]; then
		PLATFORM="iPhoneSimulator"
	else
		PLATFORM="iPhoneOS"
		sed -ie "s!static volatile sig_atomic_t intr_signal;!static volatile intr_signal;!" "crypto/ui/ui_openssl.c"
	fi
  
	export $PLATFORM
	export CROSS_TOP="${DEVELOPER}/Platforms/${PLATFORM}.platform/Developer"
	export CROSS_SDK="${PLATFORM}${IOS_SDK_VERSION}.sdk"
	export BUILD_TOOLS="${DEVELOPER}"
	export CC="${BUILD_TOOLS}/usr/bin/gcc -fembed-bitcode -arch ${ARCH}"
   
	echo "Building ${OPENSSL_VERSION} for ${PLATFORM} ${IOS_SDK_VERSION} ${ARCH}"

	if [[ "${ARCH}" == "x86_64" ]]; then
		./Configure no-asm darwin64-x86_64-cc --openssldir="/tmp/${OPENSSL_VERSION}-iOS-${ARCH}" &> "/tmp/${OPENSSL_VERSION}-iOS-${ARCH}.log"
	else
		./Configure iphoneos-cross --openssldir="/tmp/${OPENSSL_VERSION}-iOS-${ARCH}" &> "/tmp/${OPENSSL_VERSION}-iOS-${ARCH}.log"
	fi
	# add -isysroot to CC=
	sed -ie "s!^CFLAG=!CFLAG=-isysroot ${CROSS_TOP}/SDKs/${CROSS_SDK} -miphoneos-version-min=${IOS_MIN_SDK_VERSION} !" "Makefile"

	make >> "/tmp/${OPENSSL_VERSION}-iOS-${ARCH}.log" 2>&1
	make install_sw >> "/tmp/${OPENSSL_VERSION}-iOS-${ARCH}.log" 2>&1
	make clean >> "/tmp/${OPENSSL_VERSION}-iOS-${ARCH}.log" 2>&1
	popd > /dev/null
}

buildTVOS()
{
	ARCH=$1

	pushd . > /dev/null
	cd "${OPENSSL_VERSION}"
  
	if [[ "${ARCH}" == "i386" || "${ARCH}" == "x86_64" ]]; then
		PLATFORM="AppleTVSimulator"
	else
		PLATFORM="AppleTVOS"
		sed -ie "s!static volatile sig_atomic_t intr_signal;!static volatile intr_signal;!" "crypto/ui/ui_openssl.c"
	fi
  
	export $PLATFORM
	export CROSS_TOP="${DEVELOPER}/Platforms/${PLATFORM}.platform/Developer"
	export CROSS_SDK="${PLATFORM}${TVOS_SDK_VERSION}.sdk"
	export BUILD_TOOLS="${DEVELOPER}"
	export CC="${BUILD_TOOLS}/usr/bin/gcc -fembed-bitcode -arch ${ARCH}"
   
	echo "Building ${OPENSSL_VERSION} for ${PLATFORM} ${TVOS_SDK_VERSION} ${ARCH}"

	# Patch apps/speed.c to not use fork() since it's not available on tvOS
	LANG=C sed -i -- 's/define HAVE_FORK 1/define HAVE_FORK 0/' "./apps/speed.c"

	# Patch Configure to build for tvOS, not iOS
	LANG=C sed -i -- 's/D\_REENTRANT\:iOS/D\_REENTRANT\:tvOS/' "./Configure"
	chmod u+x ./Configure

	if [[ "${ARCH}" == "x86_64" ]]; then
		./Configure no-asm darwin64-x86_64-cc --openssldir="/tmp/${OPENSSL_VERSION}-tvOS-${ARCH}" &> "/tmp/${OPENSSL_VERSION}-tvOS-${ARCH}.log"
	else
		./Configure iphoneos-cross --openssldir="/tmp/${OPENSSL_VERSION}-tvOS-${ARCH}" &> "/tmp/${OPENSSL_VERSION}-tvOS-${ARCH}.log"
	fi
	# add -isysroot to CC=
	sed -ie "s!^CFLAG=!CFLAG=-isysroot ${CROSS_TOP}/SDKs/${CROSS_SDK} -mtvos-version-min=${TVOS_MIN_SDK_VERSION} !" "Makefile"

	make >> "/tmp/${OPENSSL_VERSION}-tvOS-${ARCH}.log" 2>&1
	make install_sw >> "/tmp/${OPENSSL_VERSION}-tvOS-${ARCH}.log" 2>&1
	make clean >> "/tmp/${OPENSSL_VERSION}-tvOS-${ARCH}.log" 2>&1
	popd > /dev/null
}


echo "Cleaning up"
rm -rf include/openssl/* lib/*

mkdir -p lib
mkdir -p include/openssl/

rm -rf "/tmp/${OPENSSL_VERSION}-*"
rm -rf "/tmp/${OPENSSL_VERSION}-*.log"

rm -rf "${OPENSSL_VERSION}"

if [ ! -e ${OPENSSL_VERSION}.tar.gz ]; then
	echo "Downloading ${OPENSSL_VERSION}.tar.gz"
	curl -O https://www.openssl.org/source/${OPENSSL_VERSION}.tar.gz
else
	echo "Using ${OPENSSL_VERSION}.tar.gz"
fi

echo "Unpacking openssl"
tar xfz "${OPENSSL_VERSION}.tar.gz"

echo "${OPENSSL_VERSION}.tar.gz" > .gitignore

buildIOS "armv7"
buildIOS "armv7s"
buildIOS "arm64"
buildIOS "x86_64"
buildIOS "i386"

echo "Building iOS libraries"
lipo \
	"/tmp/${OPENSSL_VERSION}-iOS-armv7/lib/libcrypto.a" \
	"/tmp/${OPENSSL_VERSION}-iOS-armv7s/lib/libcrypto.a" \
	"/tmp/${OPENSSL_VERSION}-iOS-i386/lib/libcrypto.a" \
	"/tmp/${OPENSSL_VERSION}-iOS-arm64/lib/libcrypto.a" \
	"/tmp/${OPENSSL_VERSION}-iOS-x86_64/lib/libcrypto.a" \
	-create -output lib/libcrypto.a

lipo \
	"/tmp/${OPENSSL_VERSION}-iOS-armv7/lib/libssl.a" \
	"/tmp/${OPENSSL_VERSION}-iOS-armv7s/lib/libssl.a" \
	"/tmp/${OPENSSL_VERSION}-iOS-i386/lib/libssl.a" \
	"/tmp/${OPENSSL_VERSION}-iOS-arm64/lib/libssl.a" \
	"/tmp/${OPENSSL_VERSION}-iOS-x86_64/lib/libssl.a" \
	-create -output lib/libssl.a

echo "Copying headers"
cp /tmp/${OPENSSL_VERSION}-iOS-arm64/include/openssl/* include/openssl/

echo "Cleaning up"
rm -rf /tmp/${OPENSSL_VERSION}-*
rm -rf ${OPENSSL_VERSION}

echo "Done"
