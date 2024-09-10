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
command -v patchelf 1>/dev/null || { echo ERROR: missing patchelf; exit 1; }
command -v wget 1>/dev/null || { echo ERROR: missing wget; exit 1; }
export _PREFIX="/usr"
export _LIB_DIRS="lib64 lib"
[ -z "$_QT_PLUGIN_PATH" ] && export _QT_PLUGIN_PATH="${_PREFIX}/lib64/qt5/plugins"
FORBIDDEN="https://raw.githubusercontent.com/AppImageCommunity/pkg2appimage/master/excludelist"
export EXCLUDES="$(wget -q "$FORBIDDEN" -O - | sed 's/#.*//; /^$/d')"
[ -z "$EXCLUDES" ] && exit 1
export TARGET="$1"

# Get possible system library paths
export _SYSTEM_PATHS=$(echo -n $PATH | tr ":" " ")
export SEARCH_PATHS=
for lib in ${_LIB_DIRS}; do
  for path in ${_SYSTEM_PATHS}; do
    _TRY_PATH="$(readlink -e "$path/../$lib" || true)"
    [ -n "${_TRY_PATH}" ] && SEARCH_PATHS="${SEARCH_PATHS} ${_TRY_PATH}"
  done
done
SEARCH_PATHS="${SEARCH_PATHS} $(patchelf --print-rpath $TARGET | tr ':' ' ')"
# Get a list of only unique ones
SEARCH_PATHS=$(echo -n "${SEARCH_PATHS}" | sed 's/ /\n/g' | sort -u)

# find_library [library]
#  Finds the full path of partial name [library] in SEARCH_PATHS
#  This is a time-consuming function.
NOT_FOUND=""
find_library() {
  local _PATH=""
  for i in ${SEARCH_PATHS}; do
    _PATH=$(find $i -regex ".*$(echo -n $1 | tr '+' '.')" -print -quit)
    [ -n "$_PATH" ] && break
  done
  [ -n "$_PATH" ] && readlink -e $_PATH | tr ':' ' '
}

# get_dep_names [object]
#  Returns a space-separated list of all required libraries needed by [object].
get_dep_names() {
  patchelf --print-needed $1 | tr '\n' ' '
}

# get_deps [object] [library_path]
#  Finds and installs all libraries required by [object] to [library_path].
#  This is a recursive function that also depends on find_library.
get_deps() {
  local _DEST=$2
  for i in $(get_dep_names $1); do
    _EXCL=`echo "$EXCLUDES" | tr ' ' '\n' | grep $i`
    if [ "$_EXCL" != "" ]; then
      #printf '\n%s\n' "$i is on the exclude list... skipping"
      continue
    fi
    [ -f $_DEST/$i ] && continue
    local _LIB=$(find_library $i)
    if [ -z $_LIB ]; then
      echo "$i:"
      continue
    fi
    >&2 cp -v $_LIB $_DEST/$i &
    get_deps $_LIB $_DEST
  done
}

export -f get_deps
export -f get_dep_names
export -f find_library

_ERROR=0
[ -z "$TARGET" ] && _ERROR=1
if [ "$_ERROR" -eq 1 ]; then
  echo "USAGE: $0 </path/to/executable> [AppDir]"
  exit 1
fi

LIB_DIR="$(readlink -m $(dirname $TARGET)/../lib)"
mkdir -p $LIB_DIR
NOT_FOUND=$(get_deps $TARGET $LIB_DIR)

if [ "$DEPLOY_QT" = "1" ]; then
  # Find Qt path from search paths
  for lib in ${SEARCH_PATHS}; do
    _QT_CORE_LIB=$(find $lib -type f -regex '.*/libQt5Core\.so.*' | head -n 1)
    if [ -n "$_QT_CORE_LIB" ]; then
      _QT_PATH=$(dirname $_QT_CORE_LIB)/../
      break
    fi
  done
  
  _QT_PLUGIN_PATH=$(readlink -e $(find ${_QT_PATH} -type d -regex '.*/plugins/platforms' | head -n 1)/../)

  mkdir -p ${LIB_DIR}/../plugins/platforms
  cp -nv "${_QT_PLUGIN_PATH}/platforms/libqxcb.so" ${LIB_DIR}/../plugins/platforms/
	# Find any remaining libraries needed for Qt libraries
  NOT_FOUND+=$(get_deps ${LIB_DIR}/../plugins/platforms/libqxcb.so $LIB_DIR)

  for i in audio bearer imageformats mediaservice platforminputcontexts platformthemes xcbglintegrations; do
    mkdir -p ${LIB_DIR}/../plugins/${i}
    cp -rnv ${_QT_PLUGIN_PATH}/${i}/*.so ${LIB_DIR}/../plugins/${i}
    find ${LIB_DIR}/../plugins/ -type f -regex '.*\.so' -exec patchelf --set-rpath '$ORIGIN/../../lib:$ORIGIN' {} ';'
    # Find any remaining libraries needed for Qt libraries
    NOT_FOUND+=$(find ${LIB_DIR}/../plugins/${i} -type f -exec bash -c "get_deps {} $LIB_DIR" ';')
  done
  
  _QT_CONF=${LIB_DIR}/../bin/qt.conf
  echo "[Paths]" > ${_QT_CONF}
  echo "Prefix = ../" >> ${_QT_CONF}
  echo "Plugins = plugins" >> ${_QT_CONF}
  echo "Imports = qml" >> ${_QT_CONF}
  echo "Qml2Imports = qml" >> ${_QT_CONF}
fi

# Fix rpath of libraries and executable so they can find the packaged libraries
find ${LIB_DIR} -type f -exec patchelf --set-rpath '$ORIGIN' {} ';'
patchelf --set-rpath '$ORIGIN/../lib' $TARGET

_APPDIR=$2
cd ${_APPDIR}

if [ -n "${NOT_FOUND}" ]; then
  echo "WARNING: failed to find the following libraries:"
  echo "$(pritnf $NOT_FOUND | tr ':' '\n' | sort -u)"
fi
