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

[ "$DEBUG" = 1 ] && set -x
# set vars
NOT_FOUND=""
BIN="$1"
APPDIR="$2"
TOTAL_LIBS=0
TARGET="$(realpath "$(command -v "$BIN" 2>/dev/null)" 2>/dev/null)"
APPRUN="https://raw.githubusercontent.com/Samueru-sama/deploy/main/AppRun"
FORBIDDEN="https://raw.githubusercontent.com/AppImageCommunity/pkg2appimage/master/excludelist"
[ -z "$LIB_DIRS" ] && LIB_DIRS="lib64 lib"
[ -z "$QT_PLUGINS" ] && QT_PLUGINS="/bearer /generic /imageformats /styles \
			/platformthemes /mediaservice /platforms /iconengines \
			/platforminputcontexts /xcbglintegrations"
LINE="-----------------------------------------------------------"
RPATHS="/lib /lib64"
BACKUP_EXCLUDES="ld-linux.so.2 ld-linux-x86-64.so.2 libanl.so.1 libgmp.so.10 \
libBrokenLocale.so.1 libcidn.so.1 libc.so.6 libdl.so.2 libm.so.6 libmvec.so.1 \
libnss_compat.so.2 libnss_dns.so.2 libnss_files.so.2 libnss_hesiod.so.2 \
libnss_nisplus.so.2 libnss_nis.so.2 libpthread.so.0 libresolv.so.2 librt.so.1 \
libthread_db.so.1 libutil.so.1 libstdc++.so.6 libGL.so.1 libEGL.so.1 \
libGLdispatch.so.0 libGLX.so.0 libOpenGL.so.0 libdrm.so.2 libglapi.so.0 \
libgbm.so.1 libxcb.so.1 libX11.so.6 libX11-xcb.so.1 libasound.so.2 \
libfontconfig.so.1 libfreetype.so.6 libharfbuzz.so.0 libcom_err.so.2 \
libexpat.so.1 libgcc_s.so.1 libgpg-error.so.0 libICE.so.6 libSM.so.6 \
libusb-1.0.so.0 libuuid.so.1 libz.so.1 libgpg-error.so.0 libjack.so.0 \
libpipewire-0.3.so.0 libxcb-dri3.so.0 libxcb-dri2.so.0 libfribidi.so.0"

# safety checks
if [ -z "$1" ]; then
	cat <<-EOF
	"USAGE: $0 /path/to/binary"
	"USAGE: $0 /path/to/binary /path/to/AppDir"
	"USAGE: DEPLOY_QT=1 $0 /path/to/binary /path/to/AppDir"
	"USAGE: SKIP=\"libA.so libB.so\" $0 /path/to/binary /path/to/AppDir"
	EOF
	exit 1
elif ! command -v find 1>/dev/null; then
	echo "ERROR: Missing find dependency!"
	exit 1
elif ! command -v patchelf 1>/dev/null; then
	echo "ERROR: Missing patchelf dependency!"
	exit 1
elif [ -z "$TARGET" ]; then
	echo "ERROR: \"$1\" is not a valid argument or wasn't found"
	exit 1
elif ! command -v strip 1>/dev/null; then
	echo "ERROR: Missing strip dependency! It is advised to install strip"
	echo "This script can work without it, so we are continuing..."
	NO_STRIP=true
	sleep 3
fi
if ! command -v wget 1>/dev/null; then
	echo "ERROR: Missing wget dependency! I will continue without wget"
	echo "but be aware I won't be able to get an AppRun scipt, I will"
	echo "also be using an internal exclude list, which may be outdated"
	echo "Please install wget"
	sleep 3
fi

# checks target binary, creates appdir if needed and check systems dirs
_check_dirs_and_target() {
	if [ -n "$APPDIR" ]; then
		echo "Creating AppDir..."
		APPDIR="$(realpath "$APPDIR")"
		BINDIR="$APPDIR/usr/bin"
		LIBDIR="$APPDIR/usr/lib"
		mkdir -p "$BINDIR" "$LIBDIR" || exit 1
		cp "$TARGET" "$BINDIR" || exit 1
		TARGET="$(command -v "$BINDIR"/* 2>/dev/null)"
		[ -z "$TARGET" ] && exit 1
	else
		BINDIR="$(dirname $TARGET)"
		APPDIR="$(readlink -m $BINDIR/../../)"
		LIBDIR="$(readlink -m $BINDIR/../lib)"
		mkdir -p "$BINDIR" "$LIBDIR" || exit 1
	fi
	[ ! -w "$APPDIR" ] && echo "ERROR: Cannot write to \"$APPDIR\"" && exit 1
	[ "$DEPLOY_ALL" = 1 ] && mkdir -p "$APPDIR"/lib64
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
	$LINE
	Initial checks passed! deploying...
	AppDir = "$APPDIR"
	Deploy binary = "$TARGET"
	Deploy libs in = "$LIBDIR"
	I will look for host libraries in: $LIB_PATHS
	$LINE
	EOF
}

_check_options_and_get_denylist() {
	echo "$LINE"
	if [ "$DEPLOY_QT" = 1 ]; then
		echo 'Got it! Will be deploying Qt'
		PLUGIN_DIR="$LIBDIR"/../plugins
		RPATHS="$RPATHS $QT_PLUGINS"
	fi
	if [ "$DEPLOY_GTK" = 1 ]; then
		echo 'Got it! Will be deploying GTK'
		RPATHS="$RPATHS /immodules /loaders /printbackends /modules"
	fi
	# get exclude list if not deplying everything
	if [ "$DEPLOY_ALL" = 1 ]; then
		echo 'Got it! Ignoring exclude list and deploy all libs'
	else
		EXCLUDES="$(wget --tries=20 "$FORBIDDEN" -O - 2>/dev/null)"
		if [ -z "$EXCLUDES" ]; then
			cat <<-EOF
			ERROR: Could not download the exclude list, no internet?
			We will be using a backup list in "$0", but be aware
			that it may be outdated and it is best to fix the internet issue
			EOF
			EXCLUDES="$(echo "$BACKUP_EXCLUDES" | tr ' ' '\n')"
			sleep 2
		fi
	fi
	# filter only the libs from the exclude list
	EXCLUDES="$(echo "$EXCLUDES" | sed 's/#.*//; /^$/d')"
	# add extra libs to the excludelist
	if [ -n "$SKIP" ]; then
		SKIP="$(echo "$SKIP" | tr ' ' '\n')"
		echo 'Got it! Ignoring the following libraries:'
		EXCLUDES="$(printf '%s\n%s' "$EXCLUDES" "$SKIP")"
	fi
}

# main function, gets and copies the needed libraries
_get_deps() {
	needed_libs=$(patchelf --print-needed "$1")
	DESTDIR="$2"
	for lib in $needed_libs; do
		# check lib is not in the exclude list or is not already deployed
		if [ "$DEPLOY_ALL" != 1 ] && echo "$EXCLUDES" | grep -q "$lib"; then
			if ! echo $skippedlib | grep -q "$lib"; then
				echo "$lib is on the exclude list, skipping..."
			fi
			skippedlib="$skippedlib $lib" # avoid repeating message
			continue
		elif [ -f "$DESTDIR"/"$lib" ] || [ -f "$APPDIR"/lib64/"$lib" ]; then
			if ! echo $deployedlib | grep -q "$lib"; then
				echo "$lib is already deployed, skipping..."
			fi
			deployedlib="$deployedlib $lib" # avoid repeating message
			continue
		fi
		# find the path to the lib and check it exists
		foundlib="$(readlink -e $(find $LIB_PATHS -regex \
		  ".*$(echo $lib | tr '+' '.')" -print -quit))"
		if [ -z "$foundlib" ]; then
			printf '\n%s\n\n' "ERROR: could not find \"$lib\""
			NOT_FOUND="$NOT_FOUND:$lib"
			continue
		fi
		# copy libs and their dependencies to the appdir
		if echo "$foundlib" | grep -qi "ld-linux.*.so"; then
			cp -v "$foundlib" "$APPDIR"/lib64 &
		else
			cp -v "$foundlib" $DESTDIR/$lib &
		fi
		_get_deps "$foundlib" "$DESTDIR"
		TOTAL_LIBS=$(( $TOTAL_LIBS + 1 ))
	done
}

_deploy_qt() {
	[ "$DEPLOY_QT" != 1 ] && return 0
	echo "$LINE"
	echo 'Deploying Qt...'
	echo "$LINE"
	QT_PLUGIN_PATH="$(readlink -e "$(find $LIB_PATHS -type d \
	  -regex '.*/plugins/platforms' 2>/dev/null | head -1)"/../)"
	# copy qt plugins
	for plugin in $QT_PLUGINS; do
		mkdir -p "$PLUGIN_DIR"/$plugin
		cp -rnv "$QT_PLUGIN_PATH"/$plugin/*.so "$PLUGIN_DIR"/$plugin
	done
	if [ ! -f "$PLUGIN_DIR"/platforms/libqxcb.so ]; then
		echo "ERROR: Could not deploy libqxcb.so plugin"
		exit 1
	fi
	# Find any remaining libraries needed for Qt libraries
	for file in $(find "$PLUGIN_DIR"/* -type f -regex '.*\.so.*'); do
		[ -f "$file" ] && _get_deps "$file" "$LIBDIR"
	done
	# make qt.conf file. NOTE go-appimage does not make this file
	# while linuxdeploy does make it, not sure if needed.
	cat <<-EOF > "$BINDIR"/qt.conf
	[Paths]
	Prefix = ../
	Plugins = plugins
	Imports = qml
	Qml2Imports = qml
	EOF
}

_deploy_gtk() {
	[ "$DEPLOY_GTK" != 1 ] && return 0
	# determine gtk version
	needed_lib="$(patchelf --print-needed "$TARGET" | tr ' ' '\n')"
	echo "$LINE"
	if echo "$needed_lib" | grep -q "libgtk-3.so"; then
		echo "Deploying GTK3..."
		GTKVER="gtk-3.0"
	elif echo "$needed_lib" | grep -q "libgtk-4.so"; then
		echo "Deploying GTK4..."
		GTKVER="gtk-4.0"
	else
		echo "ERROR: This application has no gtk dependency!"
		return 1
	fi
	echo "$LINE"
	# find path to the gtk and gdk dirs (gdk needed by gtk)
	GTK_PATH="$(readlink -e "$(find $LIB_PATHS -type d \
	  -regex ".*/$GTKVER" 2>/dev/null | head -1)")"
	GDK_PATH="$(readlink -e "$(find $LIB_PATHS -type d \
	  -regex ".*/gdk-pixbuf-.*" 2>/dev/null | head -1)")"
	if [ -z "$GTK_PATH" ] || [ -z "$GDK_PATH" ]; then
		echo "ERROR: Could not find all gtk and/or gdk-pixbuf libs on system"
		exit 1
	fi
	# deploy gtk libs
	if cp -nrv "$GTK_PATH" "$LIBDIR" && cp -nrv "$GDK_PATH" "$LIBDIR"; then
		echo "Found and copied GTK and Gdk libs to \"$LIBDIR\""
	else
		echo "ERROR: Could not deploy GTK and Gdk to \"$LIBDIR\""
		exit 1
	fi
	# Find any remaining libraries needed for gtk libraries
	for file in $(find "$LIBDIR"/*/* -type f -regex '.*\.so.*'); do
		[ -f "$file" ] && _get_deps "$file" "$LIBDIR"
	done

}

_check_icon_and_desktop() {
	cd "$APPDIR" || exit 1
	# find and copy .desktop
	NAME="$(echo "$TARGET" | awk -F"/" '{print $NF}')"
	if [ ! -f ./*.desktop ]; then
		echo "$LINE"
		echo "Trying to find .desktop for \"$TARGET\""...
		DESKTOP=$(find ./ /usr/share /usr/local -type f -iregex \
		  ".*/applications/$NAME.desktop" 2>/dev/null | head -1)
		DESKTOP2=$(find ./ /usr/share /usr/local -type f -iregex \
		  ".*/applications/.*$NAME.*.desktop" 2>/dev/null | head -1)
		if cp -n "${DESKTOP:-$DESKTOP2}" ./"$NAME".desktop 2>/dev/null; then
			echo "Found .desktop and added it to \"$APPDIR\""
		else
			echo "ERROR: Could not find .desktop for \"$TARGET\""
		fi
		echo "$LINE"
	fi
	# find and copy icon
	if [ ! -f ./.DirIcon ]; then
		# first try to find an icon in the AppDir
		echo "$LINE"
		echo "Trying to find icon for \"$TARGET\""...
		ICON_NAME="$(grep "Icon=" ./*.desktop 2>/dev/null \
		  | awk -F"=" '{print $NF}')"
		if [ -n "$ICON_NAME" ]; then
			find ./ -type f -regex ".*$ICON_NAME.*\.\(png\|svg\)" -exec \
			  ln -s {} ./.DirIcon ';' 2>/dev/null
		fi
	fi
	if [ ! -f ./.DirIcon ]; then
		# now try to find it on the system
		ICON="$(find /usr/share /usr/local -type f -iregex \
		  ".*/${ICON_NAME:-$NAME}.*\.\(png\|svg\)" 2>/dev/null | head -1)"
		cp -n "$ICON" ./${ICON_NAME:-$NAME} 2>/dev/null
	fi
	# make sure what we got is an image
	if file ./${ICON_NAME:-$NAME} 2>/dev/null | grep -qi image; then
		ln -s ./"${ICON_NAME:-$NAME}" "./.DirIcon"
		echo "Found icon and added it to \"$APPDIR\""
	else
		echo "ERROR: Could not find icon for \"$TARGET\""
	fi
	echo "$LINE"
}

_check_apprun() {
	echo "$LINE"
	# check if there is no AppRun and get one
	if [ ! -f "$APPDIR"/AppRun ]; then
		echo "Downloading AppRun..."
		if wget --tries=20 "$APPRUN" -O "$APPDIR"/AppRun 2>/dev/null; then
			echo "Added AppRun to \"$APPDIR\""
			echo "AppRun source: \"$APPRUN\""
			echo "Note that this AppRun may need some fixes to work"
		else
			echo "ERROR: Could not download generic AppRun, no internet?"
		fi
	elif [ "$DEPLOY_ALL" = 1 ]; then
		cat <<-EOF
		I detected you provided your own AppRun with DEPLOY_ALL=1
		Note that when deploying everything a specific AppRun is needed
		If you wish to use it, do not create it and I will download and
		place the specific AppRun in $APPDIR
		EOF
	fi
	echo "$LINE"
	# give exec perms to apprun and binaries
	chmod +x "$APPDIR"/AppRun "$BINDIR"/*
}

_patch_away_absolute_paths() {
	echo "Removing absolute paths..."
	# remove absolute paths from the ld-linux.so (DEPLOY_ALL)
	find "$APPDIR"/lib64 -type f -regex '.*ld-linux.*.so.*' -exec \
	  sed -i 's|/usr|/xxx|g; s|/lib|/XXX|g; s|/etc|/EEE|g' {} ';' 2>/dev/null
	# patch qt_prfxpath from the main Qt library
	# NOTE go-appimage sets this '..' while others just leave it empty?
	find "$LIBDIR" -type f -regex '.*libQt.*Core.*.so.*' -exec \
	  sed -i 's|qt_prfxpath=/usr|qt_prfxpath=\.\.|g;
	  s|qt_prfxpath=|qt_prfxpath=\.\.|g' {} ';' 2>/dev/null
	# patch the gdk loaders.cache file to remove absolute paths
	find "$LIBDIR" -type f -regex '.*gdk.*loaders.cache' -exec \
	  sed -i 's|/.*lib.*/gdk-pixbuf.*/.*/loaders/||g' {} ';' 2>/dev/null
}

_patch_libs_and_bin_rpath() {
	# find all directories that contain libraries and patch them
	# to point their rpaths to each other lib directory
	LIBDIRS="$(find "$APPDIR" -type f -regex '.*/.*.so.*' 2>/dev/null \
	  | sed 's/\/[^/]*$//' | sort -u)"
	for libdir in $LIBDIRS; do
		cd "$libdir" 2>/dev/null || continue
		echo "Patching rpath of libraries in \"$libdir\"..."
		for dir in $RPATHS; do # TODO Find a better way to do this find lol
			module="$(find ./ ../ ../../ ../../../ ../../../../ -maxdepth 5 \
			  -type d -regex ".*$dir" 2>/dev/null | head -1 | sed 's|^\./|/|')"
			check="$(realpath -e $module 2>/dev/null)"
			case "$check" in # just in case find picks an absolute path
				'/lib'|'/lib64'|'/usr/lib'|'/usr/lib64'|"$libdir"|\
				'/usr/local/lib'|'/usr/local/lib64'|"$HOME/.local/lib")
					continue
					;;
				'')
					continue
					;;
			esac
			# store path in a variable
			patch="$patch:\$ORIGIN/"$module""
		done
		find ./ -maxdepth 1 -type f -regex '.*\.so.*' -exec \
		  patchelf --set-rpath \$ORIGIN"$patch" {} ';' 2>/dev/null
		patch=""
	done
	# add the rest of lib dirs to rpath of binaries
	cd "$BINDIR" || exit 1
	for dir in $RPATHS; do
		module="$(find ../ ../../ -maxdepth 5 -type d \
		  -regex ".*$dir" 2>/dev/null | head -1)"
		[ -z "$module" ] && continue
		# store path in a variable
		patch="$patch:\$ORIGIN/"$module""
	done
	find "$BINDIR"/* -maxdepth 1 -type f -exec \
	  patchelf --add-rpath \$ORIGIN"$patch" {} ';' 2>/dev/null
	patch=""
	# likely overkill
	cd "$LIBDIR" && find ./*/* -type f -regex '.*\.so.*' -exec \
	  ln -s {} "$LIBDIR" ';' 2>/dev/null
}

_strip_and_check_not_found_libs() {
	# strip uneeded symbols
	if [ "$NO_STRIP" != "true" ]; then
		echo "Stripping uneeded symbols..."
		strip --strip-debug "$LIBDIR"/* 2>/dev/null
		strip --strip-unneeded "$BINDIR"/* 2>/dev/null
	fi
	# output skipped libs
	if [ -n "$SKIP" ]; then
		echo "$LINE"
		echo "The following libraries were ignored:"
		echo "$SKIP"
		echo "$LINE"
	fi
	# output not found libs
	if [ -n "$NOT_FOUND" ]; then
		echo "$LINE"
		echo "WARNING: Failed to find the following libraries:"
		echo $NOT_FOUND | tr ':' '\n' | sort -u
		echo "$LINE"
	fi
	echo "$LINE"
	echo "All Done!"
	if [ "$TOTAL_LIBS" -gt 0 ]; then
		if [ "$DEPLOY_GTK" = 1 ] || [ "$DEPLOY_QT" = 1 ]; then
			extra_libs="$(find "$LIBDIR"/gdk*/* "$LIBDIR"/gtk*/* \
			   "$PLUGIN_DIR" -type f -regex '.*so.*' 2>/dev/null | wc -l)"
			TOTAL_LIBS=$(( $TOTAL_LIBS + $extra_libs ))
		fi
		echo "Deployed $TOTAL_LIBS libraries"
	else
		echo "WARNING: No libraries have been deployed"
		echo "Did you run $0 more than once?"
	fi
	echo "$LINE"
}

#######################################
# TODO AVOID PATCHING LD-LINUX
#######################################
# do the thing
_check_dirs_and_target
_check_options_and_get_denylist
_get_deps "$TARGET" "$LIBDIR"
_deploy_qt
_deploy_gtk
_check_icon_and_desktop
_check_apprun
_patch_away_absolute_paths
_patch_libs_and_bin_rpath
_strip_and_check_not_found_libs
