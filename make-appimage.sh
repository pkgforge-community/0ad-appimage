#!/bin/bash

set -ev

if [ -z "$DOCKER_BUILD" ]; then
  echo "This script is only meant to be used with the linuxdeploy build"
  echo "helper container."
  echo "See the 0ad-appimage README for details."
  exit 1
fi

if [ -z "$VERSION" ]; then
  echo "VERSION must be set"
  exit 1
fi

if [[ "$WORKSPACE" != /* ]]; then
  echo "The workspace path must be absolute"
  exit 1
fi
test -d "$WORKSPACE"

SOURCE_ROOT="$WORKSPACE/0ad-$VERSION"
if [[ "$SOURCE_ROOT" != /* ]]; then
  echo "The source root path must be absolute"
  exit 1
fi

APPDIR=${APPDIR:-"/tmp/$USER-AppDir"}
if [ -d "$APPDIR" ]; then
  rm -rf "$APPDIR"
else
  mkdir -v -p "$APPDIR"
fi

env
export -p

URI="https://releases.wildfiregames.com"

cd $WORKSPACE
if [ ! -e "AppRun" ]; then
  echo "You must be in the same directory where the AppRun file resides"
  exit 1
fi

cd "$WORKSPACE"

sudo DEBIAN_FRONTEND=noninteractive -i sh -c "apt update && apt -y upgrade &&
    libboost-dev
    libboost-filesystem-dev
    libboost-system-dev
    libcurl4-gnutls-dev
    libenet-dev
    libfmt-dev
    libfreetype6-dev
    libgloox-dev
    libicu-dev
    libminiupnpc-dev
    libogg-dev
    libopenal-dev
    libpng-dev
    libsdl2-dev
    libsodium-dev
    libvorbis-dev
    libwxgtk3.0-gtk3-dev
    libxml2-dev
    llvm
    m4
    patchelf
    python3
    rustc
    zlib1g-dev
"

PREMAKE="premake-5.0.0-beta4-linux.tar.gz"
if [ ! -f "$PREMAKE" ]; then
  wget https://github.com/premake/premake-core/releases/download/v5.0.0-beta4/$PREMAKE
  tar -xvf "$PREMAKE"
  sudo mv premake5 /usr/bin
fi

source=0ad-$VERSION-unix-build.tar.xz
source_sum=$source.sha1sum
for file in $source $source_sum; do
  if [ ! -f "$file" ]; then
    curl -LO "$URI/$file"
  fi
done
sha1sum -c $source_sum

if [ ! -r "$SOURCE_ROOT/source/main.cpp" ]; then
  tar -xJf $source
fi

cd "$SOURCE_ROOT/libraries"
/bin/bash -c 'JOBS=$(nproc) ./build-source-libs.sh \
    -j$(nproc)'

cd "$SOURCE_ROOT/build/workspaces"
/bin/bash -c './update-workspaces.sh \
    --without-pch \
    -j$(nproc) && \
  make config=release -C gcc -j$(nproc)'

cd $WORKSPACE
data=0ad-$VERSION-unix-data.tar.xz
data_sum=$data.sha1sum
for file in $data $data_sum; do
  if [ ! -f "$file" ]; then
    curl -LO "$URI/$file"
  fi
done
sha1sum -c $data_sum

cd "$WORKSPACE"
if [ ! -f "$SOURCE_ROOT/binaries/data/config/default.cfg" ]; then
  echo "Extracting data"
  tar -xJf $data
fi

# name: prepare AppDir

  #if [ -n "${URI##*/rc*}" ] && [ ! -r $URI/$data.minisig ]; then
      #curl -LO $URI/$data.minisig
  #fi

  #$MINISIGN_PATH -Vm $data -P $MINISIGN_KEY

cd "$SOURCE_ROOT"
install -s binaries/system/pyrogenesis -Dt $APPDIR/usr/bin
install -s binaries/system/ActorEditor -Dt $APPDIR/usr/bin
cd $APPDIR/usr/bin
ln -s pyrogenesis 0ad
for lib in libmozjs78-ps-release.so \
  libnvcore.so    \
  libnvimage.so   \
  libnvmath.so    \
  libnvtt.so
do
  patchelf --set-rpath $lib:$SOURCE_ROOT/binaries/system pyrogenesis
done
patchelf --set-rpath libthai.so.0:$APPDIR/usr/lib ActorEditor
patchelf --set-rpath libAtlasUI.so:$SOURCE_ROOT/binaries/system ActorEditor
# Note that binaries/system{libmoz*.so, libnv*.so, libAtlasUI.so} will be copied into
# the $APPDIR folder automatically when linuxdeploy is run below.
cd $SOURCE_ROOT
install binaries/system/libCollada.so -Dt $APPDIR/usr/lib
install build/resources/0ad.appdata.xml -Dt $APPDIR/usr/share/metainfo
install build/resources/0ad.png -Dt $APPDIR/usr/share/pixmaps
mkdir -p "$APPDIR/usr/data/config"
cp -a binaries/data/config/default.cfg $APPDIR/usr/data/config
cp -a binaries/data/l10n $APPDIR/usr/data
cp -a binaries/data/tools $APPDIR/usr/data # for Atlas
mkdir -p $APPDIR/usr/data/mods
cp -a binaries/data/mods/mod $APPDIR/usr/data/mods

cd $SOURCE_ROOT
cp -a binaries/data/mods/public $APPDIR/usr/data/mods

cd "$WORKSPACE"

# Set up output directory
OUT_DIR="$WORKSPACE/out"
if [ ! -d "$OUT_DIR" ]; then
  mkdir "$OUT_DIR"
fi
cd "$OUT_DIR"

# Set LinuxDeploy output version
export LINUXDEPLOY_OUTPUT_VERSION="$VERSION"

# Create the image
if [ -z "$ACTION_WORKSPACE" ]; then
export DEPLOY_GTK_VERSION=3
ARCH=$(uname -m)
# Variable used by gtk plugin
linuxdeploy \
    -d $SOURCE_ROOT/build/resources/0ad.desktop \
    --icon-file=$SOURCE_ROOT/build/resources/0ad.png \
    --icon-filename=0ad \
    --executable $APPDIR/usr/bin/pyrogenesis \
    --library=/usr/lib/$ARCH-linux-gnu/libthai.so.0 \
    --custom-apprun=$WORKSPACE/AppRun \
    --appdir $APPDIR \
    --plugin gtk
fi

OUT_APPIMAGE="0ad-$VERSION-$ARCH.AppImage"

REPO="0ad-appimage"
TAG="latest"
GITHUB_REPOSITORY_OWNER="${GITHUB_REPOSITORY_OWNER:-0ad-matters}"
UPINFO="gh-releases-zsync|$GITHUB_REPOSITORY_OWNER|$REPO|$TAG|*$ARCH.AppImage.zsync"

appimagetool --comp zstd --mksquashfs-opt -Xcompression-level --mksquashfs-opt 20 \
	-u "$UPINFO" \
	"$APPDIR" "$OUT_APPIMAGE"

sha1sum $OUT_APPIMAGE > "$OUT_APPIMAGE.sha1sum"
cat "$OUT_APPIMAGE.sha1sum"

exit 0
