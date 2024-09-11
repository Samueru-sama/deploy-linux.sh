#!/bin/sh
# fork of https://github.com/lat9nq/deploy/tree/main
# made POSIX and extended with more functionality and improvements
#
# "USAGE: $0 /path/to/binary"
# "USAGE: $0 /path/to/binary /path/to/AppDir"
# "USAGE: DEPLOY_QT=1 $0 /path/to/binary /path/to/AppDir"
# "USAGE: SKIP=\"libA.so libB.so\" $0 /path/to/binary /path/to/AppDir"
#
#  user defined variables:
# "$LIB_DIRS" names of the library directories on the HOST system to search 
#  default: lib64 and lib
# "$SKIP" names of the libraries you wish to skip, space separated
# "$DEPLOY_QT" when set to 1 it enables the deploying of Qt plugins
# "$QT_PLUGINS" names of the Qt plugins to deploy
# defaults: audio bearer imageformats mediaservice platforminputcontexts 
#           platformthemes xcbglintegrations iconengines
#
#~ set -x

# set vars
NOT_FOUND=""
TARGET="$(command -v "$1" 2>/dev/null)"
[ -z "$LIB_DIRS" ] && LIB_DIRS="lib64 lib"
[ -z "$QT_PLUGINS" ] && QT_PLUGINS="audio bearer imageformats mediaservice \
                                platforminputcontexts platformthemes \
                                xcbglintegrations iconengines"
# safety checks
if [ -z "$1" ]; then
    echo "USAGE: $0 /path/to/binary"
    echo "USAGE: $0 /path/to/binary /path/to/AppDir"
    echo "USAGE: DEPLOY_QT=1 $0 /path/to/binary /path/to/AppDir"
    echo "USAGE: SKIP=\"libA.so libB.so\" $0 /path/to/binary /path/to/AppDir"
    exit 1
elif ! command -v patchelf 1>/dev/null; then
    echo "ERROR: Missing patchelf dependency!"
    exit 1
elif ! command -v wget 1>/dev/null; then
    echo "ERROR: Missing wget dependency!"
    exit 1
fi

# checks target binary, creates appdir if needed and check systems dirs
_check_dirs_and_target() {
    if ! command -v "$TARGET" 1>/dev/null; then
        echo "ERROR: \"$TARGET\" is not a valid argument or wasn't found"
        exit 1
    fi
    if [ -n "$2" ]; then
        APPDIR="$2"
        mkdir -p "$APPDIR"/usr/bin/../lib/../share/applications || exit 1
        LIB_DIR="$APPDIR/usr/lib"
    else
        LIB_DIR="$(readlink -m $(dirname $TARGET)/../lib)"
    fi
    mkdir -p "$LIB_DIR" || exit 1
    
    # Look for a lib dir next to each instance of PATH
    for libpath in $LIB_DIRS; do
        for path in $(printf $PATH | tr ':' ' '); do
            TRY_PATH="$(readlink -e "$path/../$libpath" 2>/dev/null)"
            [ -n "$TRY_PATH" ] && LIB_PATHS="$LIB_PATHS $TRY_PATH"
        done
    done
    TARGET_LIBS="$(patchelf --print-rpath $TARGET | tr ':' ' ')"
    LIB_PATHS="$(echo "$LIB_PATHS" "$TARGET_LIBS" | tr ' ' '\n' | sort -u)"
    printf '\n%s\n' "All checks passed! deploying..."
}

# get deny list
_get_deny_list() {
    FORBIDDEN="https://raw.githubusercontent.com/AppImageCommunity/pkg2appimage/master/excludelist"
    EXCLUDES="$(wget "$FORBIDDEN" -O - 2>/dev/null | sed 's/#.*//; /^$/d')"
    if [ -z "$EXCLUDES" ] && [ "$DEPLOY_ALL" != 1 ]; then
        echo "ERROR: Could not download the exclude list, no internet?"
        exit 1
    fi
    # add extra libs to the excludelist
    if [ -n "$SKIP" ]; then
        SKIP=$(echo "$SKIP" | tr ' ' '\n')
        printf '\n%s\n' 'Got it! Ignoring the following libraries:'
        printf '%s\n\n' "$SKIP"
        EXCLUDES=$(printf '%s\n%s' "$EXCLUDES" "$SKIP")
    fi
}

# deploy dependencies
_get_deps() {
    DESTDIR=$2
    needed_libs=$(patchelf --print-needed $1 | tr '\n' ' ')
    for lib in $needed_libs; do
        # check lib is not in the exclude list or is not already deployed
        if [ "$DEPLOY_ALL" != 1 ] && echo "$EXCLUDES" | grep -q "$lib"; then
            echo "$lib is on the exclude list... skipping"
            continue
        elif [ -f $DESTDIR/$lib ]; then
            echo "$lib is already deployed... skipping"
            continue
        fi
        
        # find the path to the lib and check it exists
        foundlib="$(readlink -e $(find $LIB_PATHS \
            -regex ".*$(echo $lib | tr '+' '.')" -print -quit))"
        if [ -z "$foundlib" ]; then
            printf '\n%s\n\n' "ERROR: could not find \"$lib\""
            NOT_FOUND="$NOT_FOUND:$lib"
            continue
        fi
        
        # copy libs to appdir
        cp -v "$foundlib" $DESTDIR/$lib &
        _get_deps "$foundlib" "$DESTDIR"
    done
}

_deploy_qt() {
    [ "$DEPLOY_QT" != "1" ] && return 0
    PLUGIN_DIR="$LIB_DIR/../plugins"
    QT_PLUGIN_PATH="$(readlink -e "$(find $LIB_PATHS -type d \
      -regex '.*/plugins/platforms' 2>/dev/null | head -1)"/../)"
    
    mkdir -p $PLUGIN_DIR/platforms || exit 1
    cp -nv "$QT_PLUGIN_PATH/platforms/libqxcb.so" $PLUGIN_DIR/platforms/
    
    # Find any remaining libraries needed for Qt libraries
    _get_deps $PLUGIN_DIR/platforms/libqxcb.so $LIB_DIR
    for plugin in $QT_PLUGINS; do
        mkdir -p $PLUGIN_DIR/$plugin
        cp -rnv $QT_PLUGIN_PATH/$plugin/*.so $PLUGIN_DIR/$plugin
        find $PLUGIN_DIR/ \
        -type f -regex '.*\.so' \
        -exec patchelf --set-rpath '$ORIGIN/../../lib:$ORIGIN' {} ';'
        
        # Find any remaining libraries needed for Qt libraries
        for file in "$PLUGIN_DIR/$plugin"/*; do
            [ -f "$file" ] && _get_deps "$file" "$LIB_DIR"
        done
    done
    
    # make qt.conf file   
    QT_CONF=$LIB_DIR/../bin/qt.conf
    echo "[Paths]" > $QT_CONF
    echo "Prefix = ../" >> $QT_CONF
    echo "Plugins = plugins" >> $QT_CONF
    echo "Imports = qml" >> $QT_CONF
    echo "Qml2Imports = qml" >> $QT_CONF
}

# patch the rest of libraries and binary
_patch_libs_and_bin_path() {
  find $LIB_DIR -type f -exec patchelf --set-rpath '$ORIGIN' {} ';'
  patchelf --set-rpath '$ORIGIN/../lib' "$TARGET"
}

# output warning for missing libs
_check_not_found_libs() {
    if [ -n "$NOT_FOUND" ]; then
        echo ""
        echo "WARNING: Failed to find the following libraries:"
        echo $NOT_FOUND | tr ':' '\n' | sort -u
        echo ""
    fi
    if [ -n "$SKIP" ]; then
        echo ""
        echo "The following libraries were ignored:"
        echo "$SKIP"
        echo ""
    fi
    echo "All Done!"
}

# do the thing
_check_dirs_and_target
_get_deny_list
_get_deps $TARGET $LIB_DIR
_deploy_qt
_patch_libs_and_bin_path
_check_not_found_libs
