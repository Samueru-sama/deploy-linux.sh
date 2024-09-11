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

# safety checks and set vars
NOT_FOUND=""
TARGET="$(command -v "$1" 2>/dev/null)"
APPDIR="$2"
FORBIDDEN="https://raw.githubusercontent.com/AppImageCommunity/pkg2appimage/master/excludelist"
EXCLUDES="$(wget -q "$FORBIDDEN" -O - | sed 's/#.*//; /^$/d')"
if [ -z "$1" ]; then
    echo "USAGE: $0 /path/to/binary"
    echo "USAGE: $0 /path/to/binary /path/to/AppDir"
    exit 1
elif [ -z $TARGET ]; then
    echo "ERROR: Missing \"$1\"!"
    exit 1
elif ! command -v patchelf 1>/dev/null; then
    echo "ERROR: Missing patchelf dependency!"
    exit 1
elif ! command -v wget 1>/dev/null; then
    echo "ERROR: Missing wget dependency!"
    exit 1
elif [ -z "$EXCLUDES" ]; then
    echo "ERROR: Could not download the exclude list, no internet?"
    exit 1
fi
[ -z "$PREFIX" ] && PREFIX="/usr"
[ -z "$LIB_DIRS" ] && LIB_DIRS="lib64 lib"
[ -z "$QT_PLUGIN_PATH" ] && QT_PLUGIN_PATH="$PREFIX/lib64/qt5/plugins"
[ -z "$QT_PLUGINS" ] && QT_PLUGINS="audio bearer imageformats mediaservice \
                                platforminputcontexts platformthemes \
                                xcbglintegrations iconengines"
# Look for a lib dir next to each instance of PATH
for libpath in $LIB_DIRS; do
    for path in $(printf $PATH | tr ':' ' '); do
        TRY_PATH="$(readlink -e "$path/../$libpath" 2>/dev/null)"
        [ -n "$TRY_PATH" ] && LIB_PATHS="$LIB_PATHS $TRY_PATH"
    done
done
TARGET_LIBS="$(patchelf --print-rpath $TARGET | tr ':' ' ')"
LIB_PATHS="$(echo "$LIB_PATHS" "$TARGET_LIBS" | tr ' ' '\n' | sort -u)"
QT_PLUGIN_PATH="$(readlink -e "$(find $LIB_PATHS -type d \
    -regex '.*/plugins/platforms' 2>/dev/null | head -1)"/../)"
export EXCLUDES
export LIB_DIRS
export PREFIX
export QT_PLUGIN_PATH
export LIB_PATHS

_get_deps() {
    local DESTDIR=$2
    local needed_libs=$(patchelf --print-needed $1 | tr '\n' ' ')
    for i in $needed_libs; do
        # check it isn't in the exclude list or it is already deployed
        if echo "$EXCLUDES" | grep -q $i; then
            >&2 echo "$i is on the exclude list... skipping"
            continue
        elif [ -f $DESTDIR/$i ]; then
            >&2 echo "$i is already deployed... skipping"
            continue
        fi
        _LIB=""
        # this is cursed omg
        for lib in $LIB_PATHS; do
            _PATH=$(find $lib -regex ".*$(echo -n $i | tr '+' '.')" -print -quit)
            if [ -n "$_PATH" ]; then
                _LIB=$(readlink -e $_PATH | tr '\n' ' ') 
                if [ -z $_LIB ]; then
                    >&2 printf '\n%s\n\n' "ERROR: could not find \"$i\""
                    NOT_FOUND="$NOT_FOUND:$i"
                    continue
                fi
                break
            fi
        done
        # copy libs to appdir
        >&2 cp -v $_LIB $DESTDIR/$i &
        _get_deps $_LIB $DESTDIR
    done
}

export -f _get_deps # TODO GET RID OF BASHISM

LIB_DIR="$(readlink -m $(dirname $TARGET)/../lib)"
PLUGIN_DIR="$LIB_DIR/../plugins"
mkdir -p $LIB_DIR $PLUGIN_DIR
_get_deps $TARGET $LIB_DIR

if [ "$DEPLOY_QT" = "1" ]; then
  mkdir -p $PLUGIN_DIR/platforms
  cp -nv "${QT_PLUGIN_PATH}/platforms/libqxcb.so" $PLUGIN_DIR/platforms/
	# Find any remaining libraries needed for Qt libraries
  _get_deps $PLUGIN_DIR/platforms/libqxcb.so $LIB_DIR

  for i in $QT_PLUGINS; do
    mkdir -p $PLUGIN_DIR/${i}
    cp -rnv ${QT_PLUGIN_PATH}/${i}/*.so $PLUGIN_DIR/${i}
    find $PLUGIN_DIR/ \
    -type f -regex '.*\.so' \
    -exec patchelf --set-rpath '$ORIGIN/../../lib:$ORIGIN' {} ';'
    # Find any remaining libraries needed for Qt libraries
    find $PLUGIN_DIR/${i} -type f -exec bash -c "_get_deps {} $LIB_DIR" ';'
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
