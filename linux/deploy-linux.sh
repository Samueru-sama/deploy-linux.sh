#!/bin/bash
# [DEPLOY_QT=1] deploy-linux.sh <executable>
#   (Simplified) bash re-implementation of [linuxdeploy](https://github.com/linuxdeploy).
#   Reads [executable] and copies required libraries to [AppDir]/usr/lib
#   Copies the desktop and svg icon to [AppDir]
#   Respects the AppImage excludelist
#
# Unlike linuxdeploy, this does not:
# - Copy any icon other than svg (too lazy to add that without a test case)
# - Do any verification on the desktop file
# - Run any linuxdeploy plugins
# - *Probably other things I didn't know linuxdeploy can do*
#
# It notably also does not copy unneeded libraries, unlike linuxdeploy. On a desktop system, this
# can help reduce the end AppImage's size, although in a production system this script proved
# unhelpful.
#~ set -x
# safety checks
NOT_FOUND=""
[ -z "$1" ] && echo "USAGE: $0 </path/to/executable> [AppDir]" && exit 1
TARGET="$(command -v "$1" 2>/dev/null)"
APPDIR="$2"
[ -z $TARGET ] && echo "ERROR: missing $1" && exit 1
! command -v patchelf 1>/dev/null && echo "ERROR: missing patchelf" && exit 1
! command -v wget 1>/dev/null && echo "ERROR: missing wget" && exit 1
export _PREFIX="/usr"
export LIB_DIRS="lib64 lib"
[ -z "$QT_PLUGIN_PATH" ] && export QT_PLUGIN_PATH="${_PREFIX}/lib64/qt5/plugins"
FORBIDDEN="https://raw.githubusercontent.com/AppImageCommunity/pkg2appimage/master/excludelist"
export EXCLUDES="$(wget -q "$FORBIDDEN" -O - | sed 's/#.*//; /^$/d')"
[ -z "$EXCLUDES" ] && exit 1
[ -z "$QT_PLUGIN_NAMES" ] && QT_PLUGIN_NAMES="audio bearer imageformats \
    mediaservice platforminputcontexts platformthemes xcbglintegrations"

# Get possible system library paths
export SYSTEM_PATHS=$(printf $PATH | tr ":" " ")
export SEARCH_PATHS=
for i in ${LIB_DIRS}; do
  for j in ${SYSTEM_PATHS}; do
    TRY_PATH="$(readlink -e "$j/../$i" || true)"
    if [ -n "$TRY_PATH" ]; then
      SEARCH_PATHS="$SEARCH_PATHS $TRY_PATH"
    fi
  done
done
SEARCH_PATHS="$SEARCH_PATHS $(patchelf --print-rpath $TARGET | tr ':' ' ')"
# Get a list of only unique ones
SEARCH_PATHS=$(printf "$SEARCH_PATHS" | sed 's/ /\n/g' | sort -u)

# this is cursed omg
_get_deps() {
  local DESTDIR=$2
  for i in $(patchelf --print-needed $1 | tr '\n' ' '); do
    if echo "$EXCLUDES" | grep -q $i; then
      >&2 echo "$i is on the exclude list... skipping"
      continue
    fi
    [ -f $DESTDIR/$i ] && continue
    for lib in $SEARCH_PATHS; do
        _PATH=$(find $lib -regex ".*$(echo -n $i | tr '+' '.')" -print -quit)
        [ -n "$_PATH" ] && break
    done
    _LIB=""
    [ -n "$_PATH" ] && _LIB=$(readlink -e $_PATH | tr '\n' ' ')
    if [ -z $_LIB ]; then
        echo -n "$i:"
        continue
    fi
    >&2 cp -v $_LIB $DESTDIR/$i &
    _get_deps $_LIB $DESTDIR
  done
}

export -f _get_deps

LIB_DIR="$(readlink -m $(dirname $TARGET)/../lib)"
mkdir -p $LIB_DIR
NOT_FOUND=$(_get_deps $TARGET $LIB_DIR)

if [ "${DEPLOY_QT}" == "1" ]; then
  # Find Qt path from search paths
  for i in $SEARCH_PATHS; do
    _QT_CORE_LIB=$(find ${i} -type f -regex '.*/libQt5Core\.so.*' | head -1)
    if [ -n "${_QT_CORE_LIB}" ]; then
      _QT_PATH=$(dirname ${_QT_CORE_LIB})/../
      break
    fi
  done
  
  QT_PLUGIN_PATH=$(readlink -e $(find ${_QT_PATH} -type d -regex '.*/plugins/platforms' | head -1)/../)

  mkdir -p ${LIB_DIR}/../plugins/platforms
  cp -nv "${QT_PLUGIN_PATH}/platforms/libqxcb.so" ${LIB_DIR}/../plugins/platforms/
	# Find any remaining libraries needed for Qt libraries
  NOT_FOUND+=$(_get_deps ${LIB_DIR}/../plugins/platforms/libqxcb.so $LIB_DIR)

  for i in $QT_PLUGIN_NAMES; do
    mkdir -p ${LIB_DIR}/../plugins/${i}
    cp -rnv ${QT_PLUGIN_PATH}/${i}/*.so ${LIB_DIR}/../plugins/${i}
    find ${LIB_DIR}/../plugins/ \
    -type f -regex '.*\.so' \
    -exec patchelf --set-rpath '$ORIGIN/../../lib:$ORIGIN' {} ';'
    # Find any remaining libraries needed for Qt libraries
    NOT_FOUND+=$(find ${LIB_DIR}/../plugins/${i} -type f -exec bash -c "_get_deps {} $LIB_DIR" ';')
  done
  
  QT_CONF=${LIB_DIR}/../bin/qt.conf
  echo "[Paths]" > $QT_CONF
  echo "Prefix = ../" >> $QT_CONF
  echo "Plugins = plugins" >> $QT_CONF
  echo "Imports = qml" >> $QT_CONF
  echo "Qml2Imports = qml" >> $QT_CONF
fi

# Fix rpath of libraries and executable so they can find the packaged libraries
find ${LIB_DIR} -type f -exec patchelf --set-rpath '$ORIGIN' {} ';'
patchelf --set-rpath '$ORIGIN/../lib' $TARGET

if [ -n "$NOT_FOUND" ]; then
  echo "WARNING: failed to find the following libraries:"
  printf $NOT_FOUND | tr ':' '\n' | sort -u
fi
