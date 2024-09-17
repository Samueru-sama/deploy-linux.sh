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
# "$QT_PLUGINS" names of Qt plugins to deploy, defaults to several plugins

[ "$DEBUG" = 1 ] && set -x
# set vars
NOT_FOUND=""
BIN="$1"
APPDIR="$2"
TOTAL_LIBS=0
TARGET="$(realpath "$(command -v "$BIN" 2>/dev/null)" 2>/dev/null)"
FORBIDDEN="https://raw.githubusercontent.com/AppImageCommunity/pkg2appimage/master/excludelist"
[ -z "$LIB_DIRS" ] && LIB_DIRS="lib64 lib"
[ -z "$QT_PLUGINS" ] && QT_PLUGINS="/bearer /generic /imageformats /styles \
  /platformthemes /platforms /iconengines /wayland-decoration-client \
  /wayland-graphics-integration-client /wayland-shell-integration \
  /platforminputcontexts /xcbglintegrations"
LINE="-----------------------------------------------------------"
RPATHS="/lib /lib64 /gconv /bin"
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
APPRUN="$(cat <<-'EOF'
	#!/bin/sh
	# Autogenerated AppRun
	# Simplified version of the AppRun that go-appimage makes
	HERE="$(dirname "$(readlink -f "${0}")")"
	BIN_DIR="$HERE/usr/bin"
	LIB_DIR="$HERE/usr/lib"
	SHARE_DIR="$HERE/usr/share"
	SCHEMA_HERE="$SHARE_DIR/glib-2.0/runtime-schemas:$SHARE_DIR/glib-2.0/schemas"
	BIN="$(awk -F"=| " '/Exec=/{print $2; exit}' "$HERE"/*.desktop)"
	LD_LINUX="$(find "$HERE" -name 'ld-*.so.*' -print -quit)"
	PY_HERE="$(find "$LIB_DIR" -type d -name 'python*' -print -quit)"
	QT_HERE="$HERE/usr/plugins"
	GTK_HERE="$(find "$LIB_DIR" -name 'gtk-*' -type d -print -quit)"
	GDK_HERE="$(find "$HERE" -type d -regex '.*gdk.*loaders' -print -quit)"
	GDK_LOADER="$(find "$HERE" -type f -regex '.*gdk.*loaders.cache' -print -quit)"

	export PATH="$BIN_DIR:$PATH"
	export XDG_DATA_DIRS="$SHARE_DIR:$XDG_DATA_DIRS"
	if [ -n "$PY_HERE" ]; then
	    export PYTHONHOME="$PY_HERE"
	fi
	if [ -d "$SHARE_DIR"/perl5 ] || [ -d "$LIB_DIR"/perl5 ]; then
	    export PERLLIB="$SHARE_DIR/perl5:$LIB_DIR/perl5:$PERLLIB"
	fi
	if [ -d "$QT_HERE" ]; then
	    export QT_PLUGIN_PATH="$QT_HERE"
	fi

	TARGET="$BIN_DIR/$BIN"
	# deploy everything mode
	if [ -n "$LD_LINUX" ] ; then
	    export \
	      GTK_THEME=Default \
	      GTK_PATH="$GTK_HERE" \
	      GCONV_PATH="$LIB_DIR"/gconv \
	      GDK_PIXBUF_MODULEDIR="$GDK_HERE" \
	      GDK_PIXBUF_MODULE_FILE="$GDK_LOADER" \
	      FONTCONFIG_FILE="/etc/fonts/fonts.conf" \
	      GSETTINGS_SCHEMA_DIR="$SCHEMA_HERE:$GSETTINGS_SCHEMA_DIR"
	    if echo "$LD_LINUX" | grep -qi musl; then
	        exec "$LD_LINUX" "$TARGET" "$@"
	    else
	        exec "$LD_LINUX" --inhibit-cache "$TARGET" "$@"
	    fi
	else
	    exec "$TARGET" "$@"
	fi
	EOF
)"

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
elif ! command -v realpath 1>/dev/null; then
	echo "ERROR: Missing realpath dependency!"
	exit 1
elif ! command -v strip 1>/dev/null; then
	echo "ERROR: Missing strip dependency! It is advised to install strip"
	echo "This script can work without it, so we are continuing..."
	NO_STRIP=true
	sleep 3
fi
if ! command -v wget 1>/dev/null; then
	cat <<-EOF
	ERROR: Missing wget dependency! I will continue by using an
	internal exclude list which may be outdated, please install wget
	EOF
	sleep 3
fi

# these functions are used to find lib directories, used by other functions
_find_libdir() {
	find $LIB_PATHS -type d -regex "$@" -exec realpath {} ';' 2>/dev/null
}
_find_libdir_relative() {
	find ./ ../ ../../ ../../../ ../../../../ -type d -regex "$@" 2>/dev/null
}

# checks target binary, creates appdir if needed and check systems dirs
_check_dirs_and_target() {
	if [ -n "$APPDIR" ]; then
		echo "Creating AppDir..."
		APPDIR="$(realpath "$APPDIR")"
		BINDIR="$APPDIR/usr/bin"
		LIBDIR="$APPDIR/usr/lib"
		LIBDIR64="$APPDIR/usr/lib64"
		mkdir -p "$BINDIR" "$LIBDIR" || exit 1
		cp "$TARGET" "$BINDIR" || exit 1
		TARGET="$(command -v "$BINDIR"/* 2>/dev/null)"
		[ -z "$TARGET" ] && exit 1
	else
		BINDIR="$(dirname "$TARGET")"
		APPDIR="$(realpath "$BINDIR"/../../)"
		LIBDIR="$(realpath "$BINDIR"/../lib)"
		LIBDIR64="$(realpath "$BINDIR"/../lib64)"
		mkdir -p "$BINDIR" "$LIBDIR" || exit 1
	fi
	[ ! -w "$APPDIR" ] && echo "ERROR: Cannot write to \"$APPDIR\"" && exit 1
	[ "$DEPLOY_ALL" = 1 ] && mkdir -p "$LIBDIR64"
	# Look for a lib dir next to each instance of PATH
	for libpath in $LIB_DIRS; do
		for path in $(echo $PATH | tr ':' ' '); do
			TRY_PATH="${path%/*}/$libpath"
			if [ -d "$TRY_PATH" ] && [ ! -L "$TRY_PATH" ]; then
				LIB_PATHS="$LIB_PATHS $TRY_PATH"
			fi
		done
	done
	LIB_PATHS="$(echo "$LIB_PATHS $LD_LIBRARY_PATH" | tr ' |:' '\n' | sort -u)"
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
			We will be using a backup list in "$0", but be aware that
			it may be outdated and it is best to fix the internet issue
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
	echo "$LINE"
}

# main function, gets and copies the needed libraries
_get_deps() {
	NEEDED_LIBS=$(patchelf --print-needed "$1")
	DESTDIR="$2"
	for lib in $NEEDED_LIBS; do
		# check lib is not in the exclude list or is not already deployed
		if [ "$DEPLOY_ALL" != 1 ] && echo "$EXCLUDES" | grep -q "$lib"; then
			if ! echo $skippedlib | grep -q "$lib"; then
				echo "$lib is on the exclude list, skipping..."
			fi
			skippedlib="$skippedlib $lib" # avoid repeating message
			continue
		elif [ -f "$DESTDIR"/"$lib" ] || [ -f "$LIBDIR64"/"$lib" ]; then
			if ! echo $deployedlib | grep -q "$lib"; then
				echo "$lib is already deployed, skipping..."
			fi
			deployedlib="$deployedlib $lib" # avoid repeating message
			continue
		fi
		# find the path to the lib and check it exists
		foundlib="$(find $LIB_PATHS -regex ".*$(echo $lib | tr '+' '.')" \
		  -print -quit 2>/dev/null)"
		if [ -z "$foundlib" ]; then
			printf '\n%s\n\n' "ERROR: could not find \"$lib\""
			NOT_FOUND="$NOT_FOUND:$lib"
			continue
		fi
		# copy libs and their dependencies to the appdir
		if echo "$foundlib" | grep -qi "ld-.*.so"; then
			cp -v "$foundlib" "$LIBDIR64"/"$lib" &
		else
			cp -v "$foundlib" "$DESTDIR"/"$lib" &
		fi
		# now find deps of found lib
		_get_deps "$foundlib" "$DESTDIR"
		TOTAL_LIBS=$(( $TOTAL_LIBS + 1 ))
	done
}

# adds gconv or ld-musl if needed
_deploy_all_check() {
	[ "$DEPLOY_ALL" != 1 ] && return 1
	if [ -f "$LIBDIR"/libc.so* ]; then
		GCONV="$(_find_libdir '.*/gconv' -print -quit)"
		if [ -z "$GCONV" ]; then
			echo "$LINE"
			echo "ERROR: Could not find gconv modules needed by libc"
			echo "$LINE"
			exit 1
		fi
		mkdir -p "$LIBDIR"/gconv || exit 1
		cp -rnv "$GCONV"/*.so "$LIBDIR"/gconv
		# count gconv libs
		extra_libs="$(find "$LIBDIR"/gconv -type f \
		-regex '.*\.so.*' 2>/dev/null | wc -l)"
		TOTAL_LIBS=$(( $TOTAL_LIBS + $extra_libs ))
	elif [ -f "$LIBDIR"/libc.musl*.so* ]; then
		LDMUSL="$(find $LIB_PATHS -type f \
		  -regex '.*ld-musl.*' -print -quit 2>/dev/null)"
		if [ -z "$LDMUSL" ]; then
			echo "$LINE"
			echo "ERROR: Could not find ld-musl.so"
			echo "$LINE"
			exit 1
		fi
		cp -rnv "$LDMUSL" "$LIBDIR64" && TOTAL_LIBS=$(( $TOTAL_LIBS + 1 ))
	fi
}

_deploy_qt() {
	[ "$DEPLOY_QT" != 1 ] && return 0
	echo "$LINE"
	checkqt="$(patchelf --print-needed "$TARGET" | tr ' ' '\n')"
	if echo "$checkqt" | grep -q "libQt5Core"; then
		echo "Deploying Qt5..."
		QTVER="Qt5"
	elif echo "$checkqt" | grep -q "libQt6Core"; then
		echo "Deploying Qt6..."
		QTVER="Qt6"
	else
		echo "ERROR: This application has no Qt dependency!"
		return 1
	fi
	# find the right Qt plugin dir
	QT_PLUGIN_PATH="$(_find_libdir '.*/plugins/platforms')"
	if [ "$QTVER" = "Qt6" ]; then
		QT_PLUGIN_PATH="$(echo "$QT_PLUGIN_PATH" | grep -vi "Qt5" | head -1)"
	elif [ "$QTVER" = "Qt5" ]; then
		QT_PLUGIN_PATH="$(echo "$QT_PLUGIN_PATH" | grep -vi "Qt6" | head -1)"
	fi
	if [ ! -d "$QT_PLUGIN_PATH" ]; then
		echo "ERROR: Could not find the path to the Qt plugins dir"
		exit 1
	fi
	QT_PLUGIN_PATH="${QT_PLUGIN_PATH%/*}"

	# copy qt plugins
	for plugin in $QT_PLUGINS; do
		mkdir -p "$PLUGIN_DIR"/"$plugin" || continue
		if [ -d "$QT_PLUGIN_PATH"/"$plugin" ]; then
			cp -rnv "$QT_PLUGIN_PATH"/"$plugin" "$PLUGIN_DIR"
		else
			echo "ERROR: Could not find \"$plugin\" on system"
		fi
	done
	if [ ! -f "$PLUGIN_DIR"/platforms/libqxcb.so ]; then
		echo "ERROR: Could not deploy libqxcb.so plugin"
		exit 1
	fi
	# Find any remaining libraries needed for Qt libraries
	for file in $(find "$PLUGIN_DIR"/* -type f -regex '.*\.so.*'); do
		_get_deps "$file" "$LIBDIR"
	done
	# make qt.conf file. NOTE go-appimage does not make this file
	# while linuxdeploy does make it, not sure if needed?
	cat <<-EOF > "$BINDIR"/qt.conf
	[Paths]
	Prefix = ../
	Plugins = plugins
	Imports = qml
	Qml2Imports = qml
	EOF
	# count Qt libs
	extra_libs="$(find "$PLUGIN_DIR" -type f \
	  -regex '.*\.so.*' 2>/dev/null | wc -l)"
	TOTAL_LIBS=$(( $TOTAL_LIBS + $extra_libs ))
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
		echo "ERROR: This application has no GTK dependency!"
		return 1
	fi
	echo "$LINE"
	# find path to the gtk and gdk dirs (gdk needed by gtk)
	GTK_PATH="$(_find_libdir ".*/$GTKVER" -print -quit)"
	GDK_PATH="$(_find_libdir ".*/gdk-pixbuf-.*" -print -quit)"
	if [ -z "$GTK_PATH" ] || [ -z "$GDK_PATH" ]; then
		echo "ERROR: Could not find all GTK/gdk-pixbuf libs on system"
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
	# count gtk libs
	extra_libs="$(find "$LIBDIR"/gtk*/* "$LIBDIR"/gdk*/* -type f \
	  -regex '.*\.so.*' 2>/dev/null | wc -l)"
	TOTAL_LIBS=$(( $TOTAL_LIBS + $extra_libs ))
}

_check_icon_and_desktop() {
	cd "$APPDIR" || exit 1
	# find and copy .desktop
	NAME="${TARGET##*/}"
	if [ ! -f ./*.desktop ]; then
		echo "$LINE"
		echo "Trying to find .desktop for \"$TARGET\""...
		DESKTOP_ALL="$(find ./ /usr/*/applications /usr/*/*/applications \
		  -type f -regex '.*.desktop' 2>/dev/null)"
		DESKTOP="$(echo "$DESKTOP_ALL" | grep /"$NAME".desktop | head -1)"
		DESKTOP2="$(echo "$DESKTOP_ALL" | grep -i "$NAME" | head -1)"
		DESKTOP="${DESKTOP:-$DESKTOP2}"
		if cp -n "$DESKTOP" ./"$NAME".desktop 2>/dev/null; then
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
		ICON_NAME="$(awk -F"=" '/Icon/ {print $2}' ./*.desktop 2>/dev/null)"
		ICON_NAME="${ICON_NAME:-$NAME}"
		find ./ -type f -regex ".*$ICON_NAME.*\.\(png\|svg\)" \
		  -exec cp -n {} ./.DirIcon ';' 2>/dev/null
		# now try to find it on the system
		[ ! -f ./DirIcon ] && find /usr/share /usr/local -type f \
		  -regex ".*$ICON_NAME.*\.\(png\|svg\)" \
		  -exec cp -n {} ./.DirIcon ';' 2>/dev/null
		# make sure what we got is an image
		if file ./.DirIcon 2>/dev/null | grep -qi image; then
			echo "Found icon and added it to \"$APPDIR\""
		else
			echo "ERROR: Could not find icon for \"$TARGET\""
		fi
	fi
	echo "$LINE"
}

_check_apprun() {
	echo "$LINE"
	# check if there is no AppRun and get one
	if [ ! -f "$APPDIR"/AppRun ]; then
		echo "Adding AppRun..."
		echo "$APPRUN" > "$APPDIR"/AppRun
	elif [ "$DEPLOY_ALL" = 1 ]; then
		cat <<-EOF
		I detected you provided your own AppRun with DEPLOY_ALL=1
		Note that when using DEPLOY_ALL a specific AppRun is needed
		which I can generate if you don not provide your own AppRun
		EOF
	fi
	echo "$LINE"
	# give exec perms to apprun and binaries
	chmod +x "$APPDIR"/AppRun "$BINDIR"/*
}

_patch_away_absolute_paths() {
	echo "Removing absolute paths..."
	# remove absolute paths from the ld-linux.so (DEPLOY_ALL)
	find "$LIBDIR64" -type f -regex '.*ld-linux.*.so.*' -exec \
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
	for libdir in $LIBDIRS $BINDIR; do
		cd "$libdir" 2>/dev/null || continue
		echo "Patching rpath of files in \"$libdir\"..."
		for dir in $RPATHS; do # TODO Find a better way to do this find lol
			module="$(_find_libdir_relative ".*$dir" -print -quit)"
			# this avoids adding a libdir outside the AppDir to rpath
			if [ -z "$module" ]; then
				continue
			elif echo "$module" | grep -qi "${APPDIR##*/}"; then
				continue
			elif [ "${module##*/}" = "${libdir##*/}" ]; then
				continue
			fi
			# remove leading "./" and store path in a variable
			module="${module#./}"
			patch="$patch:\$ORIGIN/$module"
		done
		# patch the libs/binaries
		find ./ -maxdepth 1 -type f ! -name 'ld-*.so.*' \
		  -exec patchelf --set-rpath \$ORIGIN"$patch" {} ';' 2>/dev/null
		patch=""
	done
	# likely overkill
	cd "$LIBDIR" && find ./*/* -type f -regex '.*\.so.*' \
	  ! -regex '.*/gconv.*' -exec ln -s {} "$LIBDIR" ';' 2>/dev/null
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
		echo "Deployed $TOTAL_LIBS libraries"
	else
		echo "WARNING: No libraries have been deployed"
		echo "Did you run $0 more than once?"
	fi
	echo "$LINE"
}

# do the thing
_check_dirs_and_target
_check_options_and_get_denylist
_get_deps "$TARGET" "$LIBDIR"
_deploy_all_check
_deploy_qt
_deploy_gtk
_check_icon_and_desktop
_check_apprun
_patch_away_absolute_paths
_patch_libs_and_bin_rpath
_strip_and_check_not_found_libs
