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
[ "$DEBUG" = 1 ] && set -x
# set vars
NOT_FOUND=""
BIN="$1"
APPDIR="$2"
TOTAL_LIBS=0
TARGET="$(realpath "$(command -v "$BIN" 2>/dev/null)" 2>/dev/null)"
APPRUN="https://raw.githubusercontent.com/AppImage/AppImageKit/master/resources/AppRun"
APPRUN_ALL="https://raw.githubusercontent.com/Samueru-sama/deploy/main/AppRun"
FORBIDDEN="https://raw.githubusercontent.com/AppImageCommunity/pkg2appimage/master/excludelist"
[ -z "$LIB_DIRS" ] && LIB_DIRS="lib64 lib"
[ -z "$QT_PLUGINS" ] && QT_PLUGINS="audio bearer imageformats mediaservice \
					platforminputcontexts platformthemes \
					xcbglintegrations iconengines"
LINE="-----------------------------------------------------------"
[ "$DEPLOY_ALL" = 1 ] && APPRUN="$APPRUN_ALL"

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
		cp "$TARGET" "$BINDIR" || exit 1
		TARGET="$(command -v "$BINDIR"/* 2>/dev/null)"
		[ -z "$TARGET" ] && exit 1
	else
		BINDIR="$(dirname $TARGET)"
		APPDIR="$(readlink -m $BINDIR/../../)"
		LIB_DIR="$(readlink -m $BINDIR/../lib)"
		mkdir -p "$BINDIR" "$LIB_DIR" || exit 1
	fi
	[ ! -w "$APPDIR" ] && echo "ERROR: Cannot write to \"$APPDIR\"" && exit 1
	# these symlinks are made for compatibility with deploy all mode
	[ ! -d "$APPDIR"/usr/lib64 ] && ln -s ./lib "$APPDIR"/usr/lib64
	[ ! -d "$APPDIR"/lib64 ]     && ln -s ./usr/lib "$APPDIR"/lib64

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
	"$LINE"
	Initial checks passed! deploying...
	AppDir = "$APPDIR"
	Deploy binary = "$TARGET"
	Deploy libs = "$LIB_DIR"
	I will look for host libraries in: $LIB_PATHS
	"$LINE"
	EOF
}

# check for skipped libraries and get deny list
_check_skip_and_get_denylist() {
	# add extra libs to the excludelist
	if [ -n "$SKIP" ]; then
		SKIP=$(echo "$SKIP" | tr ' ' '\n')
		echo "$LINE"	
		echo 'Got it! Ignoring the following libraries:'
		echo "$SKIP"
		echo "$LINE"	
		EXCLUDES=$(printf '%s\n%s' "$EXCLUDES" "$SKIP")
	fi
	if [ "$DEPLOY_QT" = "1" ]; then
		echo "$LINE"	
		echo 'Got it! Will be deploying Qt'
		echo "$LINE"
	fi
	if [ "$DEPLOY_ALL" = 1 ]; then
		echo "$LINE"	
		echo 'Got it! Ignoring exclude list and deploy all libs'
		echo "$LINE"
	else
		EXCLUDES="$(wget "$FORBIDDEN" -O - 2>/dev/null | sed 's/#.*//; /^$/d')"
		if [ -z "$EXCLUDES" ]; then
			echo "ERROR: Could not download the exclude list, no internet?"
			exit 1
		fi
	fi
}

# deploy dependencies
_get_deps() {
	needed_libs=$(patchelf --print-needed "$1" | tr '\n' ' ')
	DESTDIR="$2"	
	for lib in $needed_libs; do
		# check lib is not in the exclude list or is not already deployed
		if [ "$DEPLOY_ALL" != 1 ] && echo "$EXCLUDES" | grep -q "$lib"; then
			echo "$lib is on the exclude list... skipping"
			continue
		elif [ -f $DESTDIR/$lib ]; then
			if ! echo $deployedlib | grep -q "$lib"; then
				echo "$lib is already deployed... skipping"
			fi
			deployedlib="$deployedlib $lib" # avoid repeating message
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
		# copy libs and their dependencies to the appdir
		cp -v "$foundlib" $DESTDIR/$lib &
		_get_deps "$foundlib" "$DESTDIR"
		TOTAL_LIBS=$(( $TOTAL_LIBS + 1 ))
	done
}

_deploy_qt() {
	if [ "$DEPLOY_QT" = "1" ]; then
		echo "$LINE"	
		echo 'Deploying Qt...'
		echo "$LINE"
	else
		return 0
	fi
	PLUGIN_DIR="$LIB_DIR"/../plugins
	QT_PLUGIN_PATH="$(readlink -e "$(find $LIB_PATHS -type d \
	  -regex '.*/plugins/platforms' 2>/dev/null | head -1)"/../)"
	
	mkdir -p "$PLUGIN_DIR"/platforms || exit 1
	cp -nv "$QT_PLUGIN_PATH"/platforms/libqxcb.so "$PLUGIN_DIR"/platforms/
	
	# Find any remaining libraries needed for Qt libraries
	_get_deps "$PLUGIN_DIR"/platforms/libqxcb.so "$LIB_DIR"
	
	for plugin in $QT_PLUGINS; do
		mkdir -p $PLUGIN_DIR/$plugin
		cp -rnv $QT_PLUGIN_PATH/$plugin/*.so $PLUGIN_DIR/$plugin
		find $PLUGIN_DIR/ -type f -regex '.*\.so' \
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
		echo "$LINE"
		echo "Trying to find .desktop for \"$TARGET\""...
		DESKTOP=$(find "$APPDIR" "$HOME" /usr/share /opt -type f -iregex \
			".*/applications/.*$NAME.*\.desktop" 2>/dev/null | head -1)
		if [ -n "$DESKTOP" ] && cp "$DESKTOP" "$APPDIR"/"$NAME".desktop; then
			echo "Found .desktop and added it to \"$APPDIR\""
		else
			echo "ERROR: Could not find .desktop for \"$TARGET\""
		fi
		echo "$LINE"
	fi
	# find and copy icon
	if [ ! -f "$APPDIR"/.DirIcon ]; then
		echo "$LINE"
		echo "Trying to find icon for \"$TARGET\""...
		ICON=$(find "$APPDIR" "$HOME" /usr/share /opt -type f -iregex \
			".*/icons/.*$NAME.*\.\(png\|svg\)" 2>/dev/null | head -1)
		if [ -n "$ICON" ] && cp "$ICON" "$APPDIR"/"$NAME"; then
			ln -s "$APPDIR"/"$NAME" "$APPDIR/.DirIcon"
			echo "Found icon and added it to \"$APPDIR\""
		else
			echo "ERROR: Could not find icon for \"$TARGET\""
		fi
		echo "$LINE"	
	fi
}

_check_apprun() {
	if [ ! -f "$APPDIR"/AppRun ]; then
		echo "$LINE"
		echo "Downloading AppRun..."
		if wget "$APPRUN" -O "$APPDIR"/AppRun 2>/dev/null; then
			chmod +x "$APPDIR"/AppRun
			echo "Added AppRun to \"$APPDIR\""
			echo "AppRun source: \"$APPRUN\""
			echo "Note that this AppRun may need some fixes to work"
		else
			echo "ERROR: Could not download generic AppRun, no internet?"
		fi
		echo "$LINE"
	elif [ "$DEPLOY_ALL" = 1 ]; then
		cat <<-EOF
		$LINE
		I detected you provided your own AppRun with DEPLOY_ALL=1
		Note that when deploying everything a specific AppRun is needed
		If you wish to use it, do not create it and I will download and
		place the specific AppRun in $APPDIR
		$LINE
		EOF
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
		echo "$LINE"	
		echo "The following libraries were ignored:"
		echo "$SKIP"
		echo "$LINE"
	fi
	if [ -n "$NOT_FOUND" ]; then
		echo "$LINE"	
		echo "WARNING: Failed to find the following libraries:"
		echo $NOT_FOUND | tr ':' '\n' | sort -u
		echo "$LINE"	
	fi
	echo "$LINE"
	echo "All Done!"
	if [ "$TOTAL_LIBS" -gt 0 ]; then
		echo "Deployed a total of $TOTAL_LIBS libraries"
	else
		echo "WARNING: No libraries have been deployed"
		echo "Did you run $0 more than once?"
	fi
	echo "$LINE"
}

# do the thing
_check_dirs_and_target
_check_skip_and_get_denylist
_get_deps $TARGET $LIB_DIR
_deploy_qt
_patch_libs_and_bin_path
_check_icon_and_desktop
_check_apprun
_check_not_found_libs
