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
#  defaults: lib64 lib
# "$SKIP" names of the libraries you wish to skip, each enty space separated
# "$DEPLOY_QT" when set to 1 it enables the deploying of Qt plugins
# "$QT_PLUGINS" names of the Qt plugins to deploy
# defaults: audio bearer imageformats mediaservice platforminputcontexts 
#		   platformthemes xcbglintegrations iconengines
#
#~ set -x

# set vars
NOT_FOUND=""
BIN="$1"
APPDIR="$2"
TARGET="$(realpath "$(command -v "$BIN" 2>/dev/null)" 2>/dev/null)"
APPRUN="https://raw.githubusercontent.com/AppImage/AppImageKit/master/resources/AppRun"
FORBIDDEN="https://raw.githubusercontent.com/AppImageCommunity/pkg2appimage/master/excludelist"
[ -z "$LIB_DIRS" ] && LIB_DIRS="lib64 lib"
[ -z "$QT_PLUGINS" ] && QT_PLUGINS="audio bearer imageformats mediaservice \
					platforminputcontexts platformthemes \
					xcbglintegrations iconengines"
# safety checks
if [ -z "$1" ]; then
	cat <<-EOF
	"USAGE: $0 /path/to/binary"
	"USAGE: $0 /path/to/binary /path/to/AppDir"
	"USAGE: DEPLOY_QT=1 $0 /path/to/binary /path/to/AppDir"
	"USAGE: SKIP=\"libA.so libB.so\" $0 /path/to/binary /path/to/AppDir"
	EOF
	exit 1
elif ! command -v patchelf 1>/dev/null; then
	echo "ERROR: Missing patchelf dependency!"
	exit 1
elif ! command -v wget 1>/dev/null; then
	echo "ERROR: Missing wget dependency!"
	exit 1
elif [ -z "$TARGET" ]; then
	echo "ERROR: \"$1\" is not a valid argument or wasn't found"
	exit 1
fi

# checks target binary, creates appdir if needed and check systems dirs
_check_dirs_and_target() {
	if [ -n "$APPDIR" ]; then
		echo "Creating AppDir..."
		APPDIR="$(realpath "$APPDIR")"
		BINDIR="$APPDIR/usr/bin"
		LIB_DIR="$APPDIR/usr/lib"
		mkdir -p "$BINDIR" "$LIB_DIR" || exit 1
		cp "$TARGET" "$BINDIR"/"$1" || exit 1
		TARGET="$(command -v "$BINDIR"/"$BIN" 2>/dev/null)"
		[ -z "$TARGET" ] && exit 1
	else
		BINDIR="$(dirname $TARGET)"
		APPDIR="$(readlink -m $BINDIR/../../)"
		LIB_DIR="$(readlink -m $BINDIR/../lib)"
		mkdir -p "$BINDIR" "$LIB_DIR" || exit 1
	fi
	
	# Look for a lib dir next to each instance of PATH
	for libpath in $LIB_DIRS; do
		for path in $(printf $PATH | tr ':' ' '); do
			TRY_PATH="$(readlink -e "$path/../$libpath" 2>/dev/null)"
			[ -n "$TRY_PATH" ] && LIB_PATHS="$LIB_PATHS $TRY_PATH"
		done
	done
	TARGET_LIBS="$(patchelf --print-rpath $TARGET | tr ':' ' ')"
	LIB_PATHS="$(printf "$LIB_PATHS" "$TARGET_LIBS" | tr ' ' '\n' | sort -u)"
	cat <<-EOF
	------------------------------------------------------------
	Initial checks passed! deploying...
	AppDir = "$APPDIR"
	Deploy binary = "$TARGET"
	Deploy libs = "$LIB_DIR"
	I will look for host libraries in: $LIB_PATHS
	------------------------------------------------------------
	EOF
}

# get deny list
_get_deny_list() {
	EXCLUDES="$(wget "$FORBIDDEN" -O - 2>/dev/null | sed 's/#.*//; /^$/d')"
	if [ -z "$EXCLUDES" ] && [ "$DEPLOY_ALL" != 1 ]; then
		echo "ERROR: Could not download the exclude list, no internet?"
		exit 1
	fi
	# add extra libs to the excludelist
	if [ -n "$SKIP" ]; then
		SKIP=$(echo "$SKIP" | tr ' ' '\n')
		echo ------------------------------------------------------------	
		echo 'Got it! Ignoring the following libraries:'
		echo "$SKIP"
		echo ------------------------------------------------------------	
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
	QT_CONF="$BINDIR"/qt.conf
	echo "[Paths]" > $QT_CONF
	echo "Prefix = ../" >> $QT_CONF
	echo "Plugins = plugins" >> $QT_CONF
	echo "Imports = qml" >> $QT_CONF
	echo "Qml2Imports = qml" >> $QT_CONF
}

_check_icon_and_desktop() {
	# find and copy .desktop
	NAME="$(echo "$TARGET" | awk -F"/" '{print $NF}')"
	if [ ! -f "$APPDIR"/*.desktop ]; then
		echo ------------------------------------------------------------
		echo "Trying to find .desktop for \"$TARGET\""...
		DESKTOP=$(find "$APPDIR" "$HOME" /usr/share /opt -type f -iregex \
			".*/applications/.*$NAME.*\.desktop" 2>/dev/null | head -1)
		if [ -n "$DESKTOP" ] && cp "$DESKTOP" "$APPDIR"/"$NAME".desktop; then
			echo "Found .desktop and added it to \"$APPDIR\""
		else
			printf '\n%s\n\n' "ERROR: Could not find .desktop for \"$TARGET\""
		fi
		echo ------------------------------------------------------------
	fi
	# find and copy icon
	if [ ! -f "$APPDIR"/.DirIcon ]; then
		echo ------------------------------------------------------------
		echo "Trying to find icon for \"$TARGET\""...
		ICON=$(find "$APPDIR" "$HOME" /usr/share /opt -type f -iregex \
			".*/icons/.*$NAME.*\.\(png\|svg\)" 2>/dev/null | head -1)
		if [ -n "$ICON" ] && cp "$ICON" "$APPDIR"/"$NAME"; then
			ln -s "$APPDIR"/"$NAME" "$APPDIR/.DirIcon"
			echo "Found icon and added it to \"$APPDIR\""
		else
			printf '\n%s\n\n' "ERROR: Could not find icon for \"$TARGET\""
		fi
		echo ------------------------------------------------------------	
	fi
}

_check_apprun() {
	if [ ! -f "$APPDIR"/AppRun ]; then
		echo ------------------------------------------------------------
		echo "No AppRun in \"$APPDIR\", downloading a generic one..."
		if wget "$APPRUN" -O "$APPDIR"/AppRun 2>/dev/null; then
			chmod +x "$APPDIR"/AppRun
			echo "Added generic AppRun to \"$APPDIR\""
			echo "Note that the generic AppRun may need some fixes to work"
		else
			echo "ERROR: Could not download generic AppRun, no internet?"
		fi
		echo ------------------------------------------------------------
	fi
}

# patch the rest of libraries and binary
_patch_libs_and_bin_path() {
	find $LIB_DIR -type f -exec patchelf --set-rpath '$ORIGIN' {} ';'
	patchelf --set-rpath '$ORIGIN/../lib' "$TARGET"
}

# output warning for missing libs
_check_not_found_libs() {
	if [ -n "$SKIP" ]; then
		echo ------------------------------------------------------------	
		echo "The following libraries were ignored:"
		echo "$SKIP"
		echo ------------------------------------------------------------	
	fi
	if [ -n "$NOT_FOUND" ]; then
		echo ------------------------------------------------------------	
		echo "WARNING: Failed to find the following libraries:"
		echo $NOT_FOUND | tr ':' '\n' | sort -u
		echo ------------------------------------------------------------	
	fi
	echo "All Done!"
}

# do the thing
_check_dirs_and_target "$@"
_get_deny_list
_get_deps $TARGET $LIB_DIR
_deploy_qt
_patch_libs_and_bin_path
_check_icon_and_desktop
_check_apprun
_check_not_found_libs
