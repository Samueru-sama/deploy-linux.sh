#!/bin/sh

# fork of https://github.com/lat9nq/deploy/tree/main
# made POSIX and extended with more functionality and improvements
#
# "USAGE: $0 /path/to/binary"
# "USAGE: $0 /path/to/binary /path/to/AppDir"
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
BIN="$1"
APPDIR="$2"
TOTAL_LIBS=0
TARGET="$(realpath "$(command -v "$BIN" 2>/dev/null)" 2>/dev/null)"
BIN_NAME="$(basename "$TARGET")"
FORBIDDEN="https://raw.githubusercontent.com/AppImageCommunity/pkg2appimage/master/excludelist"
LINE="----------------------------------------------------------------------"
RPATHS="/lib /lib64 /gconv /bin"
BACKUP_EXCLUDES="ld-linux.so.2 ld-linux-x86-64.so.2 libanl.so.1 libgmp.so.10 \
	libBrokenLocale.so.1 libcidn.so.1 libc.so.6 libdl.so.2 libm.so.6
	libmvec.so.1 libnss_compat.so.2 libnss_dns.so.2 libnss_files.so.2 \
	libnss_hesiod.so.2 libnss_nisplus.so.2 libnss_nis.so.2 libpthread.so.0 \
	libresolv.so.2 librt.so.1 libthread_db.so.1 libutil.so.1 libstdc++.so.6 \
	libGL.so.1 libEGL.so.1 libGLdispatch.so.0 libGLX.so.0 libOpenGL.so.0 \
	libdrm.so.2 libglapi.so.0 libgbm.so.1 libxcb.so.1 libX11.so.6 \
	libX11-xcb.so.1 libasound.so.2 libfontconfig.so.1 libfreetype.so.6 \
	libharfbuzz.so.0 libcom_err.so.2 libexpat.so.1 libgcc_s.so.1 \
	libgpg-error.so.0 libICE.so.6 libSM.so.6 libusb-1.0.so.0 libuuid.so.1 \
	libz.so.1 libgpg-error.so.0 libjack.so.0 libpipewire-0.3.so.0 \
	libxcb-dri3.so.0 libxcb-dri2.so.0 libfribidi.so.0"

APPRUN="$(cat <<-'EOF'
	#!/bin/sh
	# Autogenerated AppRun
	# Simplified version of the AppRun that go-appimage makes
	HERE="$(dirname "$(readlink -f "${0}")")"
	BIN="$ARGV0"
	unset ARGVO
	BIN_DIR="$HERE/usr/bin"
	LIB_DIR="$HERE/usr/lib"
	SHARE_DIR="$HERE/usr/share"
	SCHEMA_HERE="$SHARE_DIR/glib-2.0/runtime-schemas:$SHARE_DIR/glib-2.0/schemas"
	LD_LINUX="$(find "$HERE" -name 'ld-*.so.*' -print -quit)"
	PY_HERE="$(find "$LIB_DIR" -type d -name 'python*' -print -quit)"
	QT_HERE="$HERE/usr/plugins"
	GTK_HERE="$(find "$LIB_DIR" -name 'gtk-*' -type d -print -quit)"
	GDK_HERE="$(find "$HERE" -type d -regex '.*gdk.*loaders' -print -quit)"
	GDK_LOADER="$(find "$HERE" -type f -regex '.*gdk.*loaders.cache' -print -quit)"

	if [ ! -e "$BIN_DIR/$BIN" ]; then
		BIN="$(awk -F"=| " '/Exec=/{print $2; exit}' "$HERE"/*.desktop)"
	fi
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
	if [ -d "$GTK_HERE" ]; then
	    export GTK_PATH="$GTK_HERE" \
	      GTK_EXE_PREFIX="$HERE/usr" \
	      GTK_DATA_PREFIX="$HERE/usr"
	fi

	TARGET="$BIN_DIR/$BIN"
	# deploy everything mode
	if [ -n "$LD_LINUX" ] ; then
	    export GTK_THEME=Default \
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

# user defined vars
if [ -z "$LIB_DIRS" ]; then
	LIB_DIRS="lib64 lib"
fi
if [ -z "$QT_PLUGINS" ]; then
	QT_PLUGINS="audio bearer iconengines imageformats mediaservice styles \
	platforms platforminputcontexts platformthemes xcbglintegrations \
	wayland-decoration-client wayland-shell-integration \
	wayland-graphics-integration-client"
fi

# safety checks
if [ -z "$1" ]; then
	cat <<-EOF
	USAGE: $0 /path/to/binary
	USAGE: $0 /path/to/binary /path/to/AppDir
	USAGE: SKIP="libA.so libB.so" $0 /path/to/binary /path/to/AppDir
	USAGE: EXTRA_LIBS="libA.so libB.so" $0 /path/to/binary /path/to/AppDir
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
	# TODO Find a better way to do this find lol
	find ./ ../ ../../ ../../../ ../../../../ \
	  -maxdepth 5 -type d -regex "$@" 2>/dev/null
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
		TARGET="$(command -v "$BINDIR/$BIN_NAME" 2>/dev/null)"
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
		for path in $(echo "$PATH" | tr ':' ' '); do
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
	# count how many libs are in the appdir before deploying
	LIBSNUM_OLD="$(find "$APPDIR" -type f \
	  -regex '.*\.so.*' 2>/dev/null | wc -l)"
}

_check_options_and_get_denylist() {
	echo "$LINE"
	if [ "$NO_QT" = 1 ]; then
		echo "Okay won't deploy Qt"
	elif [ "$DEPLOY_QT" = 1 ]; then
		echo 'Got it! Will be deploying Qt'
	fi
	if [ "$NO_GTK" = 1 ]; then
		echo "Okay won't deploy GTK"
	elif [ "$DEPLOY_GTK" = 1 ]; then
		echo 'Got it! Will be deploying GTK'
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
	if [ -n "$EXTRA_LIBS" ]; then
		echo "Got it! Will be also deploying:"
		echo "$EXTRA_LIBS" | tr ' ' '\n'
	fi
	echo "$LINE"
}

_check_if_qt_or_gtk() {
	if [ "$DEPLOY_QT" != 1 ] && [ "$NO_QT" != 1 ]; then
		if echo "$NEEDED_LIBS" | grep -q "libQt5Core"; then
			DEPLOY_QT=1
			QTVER="Qt5"
		elif echo "$NEEDED_LIBS" | grep -q "libQt6Core"; then
			DEPLOY_QT=1
			QTVER="Qt6"
		fi
		if [ "$DEPLOY_QT" = 1 ]; then
			RPATHS="$RPATHS $QT_PLUGINS"
		fi
	fi
	if [ "$DEPLOY_GTK" != 1 ] && [ "$NO_GTK" != 1 ]; then
		if echo "$NEEDED_LIBS" | grep -q "libgtk-3.so"; then
			DEPLOY_GTK=1
			GTKVER="gtk-3.0"
		elif echo "$NEEDED_LIBS" | grep -q "libgtk-4.so"; then
			DEPLOY_GTK=1
			GTKVER="gtk-4.0"
		fi
		if [ "$DEPLOY_GTK" = 1 ]; then
			RPATHS="$RPATHS /immodules /loaders /printbackends /modules"
		fi
	fi
}

# main function, gets and copies the needed libraries
_deploy_libs() {
	NEEDED_LIBS=$(patchelf --print-needed "$1" 2>/dev/null)
	DESTDIR="$2"
	# sanity check
	if [ -z "$NEEDED_LIBS" ]; then
		echo "$LINE"
		echo "$1 has no dependencies or it is not an ELF"
		echo "$LINE"
		return 1
	fi
	# check if we need to deploy Qt or GTK
	_check_if_qt_or_gtk
	# continue deploying
	for lib in $NEEDED_LIBS; do
		# check if there is an absolute path to lib and remove it
		if echo "$lib" | grep -q "^/"; then
			patchelf --replace-needed "$lib" "$(basename "$lib")" "$1"
		fi
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
		# escape special character so that find doesn't error out
		lib_to_find="$(echo $lib | sed 's|+|\\+|g')"
		# find the path to the lib and check it exists
		foundlib="$(find $LIB_PATHS -regex ".*$lib_to_find" \
		  -print -quit 2>/dev/null)"
		if [ -z "$foundlib" ]; then
			echo "ERROR: Could not find \"$lib\""
			echo "$lib" >> "$APPDIR"/NOT_FOUND_LIBS
			continue
		fi
		# copy libs and their dependencies to the appdir
		if echo "$foundlib" | grep -qi "ld-.*.so"; then
			cp -v "$foundlib" "$LIBDIR64"/"$lib" &
		else
			cp -v "$foundlib" "$DESTDIR"/"$lib" &
		fi
		# now find deps of found lib
		_deploy_libs "$foundlib" "$DESTDIR"
	done
}


# adds extra libs and then runs _deploy_libs on them to get their dependencies
# note that this extra libs can be located in $HOME and /opt
_deploy_extra_libs() {
	for lib in $EXTRA_LIBS; do
		# escape special character so that find doesn't error out
		lib_to_find="$(echo $lib | sed 's|+|\\+|g')"
		# find the path to the lib and check it exists
		foundlib="$(find ./ $LIB_PATHS $HOME /opt -regex ".*$lib_to_find" \
		  -print -quit 2>/dev/null)"
		if [ -z "$foundlib" ]; then
			echo "ERROR: could not find \"$lib\""
			echo "$lib" >> "$APPDIR"/NOT_FOUND_LIBS
			continue
		fi
		# copy lib to appdir
		if echo "$foundlib" | grep -qi "ld-.*.so"; then
			cp -v "$foundlib" "$LIBDIR64" &
		else
			cp -v "$foundlib" "$LIBDIR" &
		fi
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
	elif [ -f "$LIBDIR"/libc.musl*.so* ]; then
		LDMUSL="$(find $LIB_PATHS -type f \
		  -regex '.*ld-musl.*' -print -quit 2>/dev/null)"
		if [ -z "$LDMUSL" ]; then
			echo "$LINE"
			echo "ERROR: Could not find ld-musl.so"
			echo "$LINE"
			exit 1
		fi
		cp -rnv "$LDMUSL" "$LIBDIR64"
	fi
}

_deploy_qt() {
	# where the Qt plugins will be placed
	PLUGIN_DIR="$APPDIR"/usr/plugins
	# find the right Qt plugin dir
	if [ -z "$QT_PLUGIN_PATH" ]; then
		FOUND_QT="$(_find_libdir '.*/plugins/platforms')"
		if [ "$QTVER" = "Qt6" ]; then
			FOUND_QT="$(echo "$FOUND_QT" | grep -vi "Qt5" | head -1)"
		elif [ "$QTVER" = "Qt5" ]; then
			FOUND_QT="$(echo "$FOUND_QT" | grep -vi "Qt6" | head -1)"
		fi
		QT_PLUGIN_PATH="${FOUND_QT%/*}"
	fi
	if [ ! -d "$QT_PLUGIN_PATH" ]; then
		echo "ERROR: Could not find the path to the Qt plugins dir"
		exit 1
	fi

	# copy qt plugins
	for plugin in $QT_PLUGINS; do
		if [ -d "$QT_PLUGIN_PATH"/"$plugin" ]; then
			mkdir -p "$PLUGIN_DIR"/"$plugin" || continue
			cp -rnv "$QT_PLUGIN_PATH"/"$plugin" "$PLUGIN_DIR"
		else
			echo "ERROR: Could not find \"$plugin\" on system"
			echo "$plugin" >> "$APPDIR"/NOT_FOUND_QT_PLUGINS
		fi
	done
	# Find any remaining libraries needed for Qt libraries
	find "$PLUGIN_DIR" -type f -regex '.*\.so.*' | while IFS= read -r LIB; do
		_deploy_libs "$LIB" "$LIBDIR"
	done
	# make qt.conf file.
	cat <<-EOF > "$BINDIR"/qt.conf
	[Paths]
	Prefix = ../
	Plugins = plugins
	Imports = qml
	Qml2Imports = qml
	EOF
}

_deploy_gtk() {
	# find path to the gtk and gdk dirs (gdk needed by gtk)
	if [ -z "$GTK_PATH" ]; then
		GTK_PATH="$(_find_libdir ".*/$GTKVER" -print -quit)"
	fi
	if [ -z "$GDK_PIXBUF_MODULEDIR" ]; then
		GDK_PATH="$(_find_libdir ".*/gdk-pixbuf-.*" -print -quit)"
	else
		GDK_PATH="$GDK_PIXBUF_MODULEDIR"
	fi
	if [ ! -d "$GTK_PATH" ] || [ ! -d "$GDK_PATH" ]; then
		echo "ERROR: Could not find all GTK/gdk-pixbuf dirs on system"
		exit 1
	fi
	# copy gtk libs
	if cp -nrv "$GTK_PATH" "$LIBDIR" && cp -nrv "$GDK_PATH" "$LIBDIR"; then
		echo "Found and copied GTK and Gdk libs to \"$LIBDIR\""
	else
		echo "ERROR: Could not deploy GTK and Gdk to \"$LIBDIR\""
		exit 1
	fi
	# Find any remaining libraries needed for gtk libraries
	find "$LIBDIR"/*/* -type f -regex '.*\.so.*' | while IFS= read -r LIB; do
		_deploy_libs "$LIB" "$LIBDIR"
	done
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
		[ ! -f ./.DirIcon ] && find /usr/share /usr/local -type f \
		  -regex ".*$ICON_NAME.*\.\(png\|svg\)" \
		  -exec cp -n {} ./.DirIcon ';' 2>/dev/null
		# make sure what we got is an image
		if file ./.DirIcon 2>/dev/null | grep -qi image; then
			echo "Found icon and added it to \"$APPDIR\""
		else
			echo "ERROR: Could not find icon for \"$TARGET\""
		fi
		echo "$LINE"
	fi
}

_check_apprun() {
	# check if there is no AppRun and get one
	if [ ! -f "$APPDIR"/AppRun ]; then
		echo "$LINE"
		echo "Adding AppRun..."
		echo "$LINE"
		echo "$APPRUN" > "$APPDIR"/AppRun
	elif [ "$DEPLOY_ALL" = 1 ]; then
		cat <<-EOF
		$LINE
		I detected you provided your own AppRun with DEPLOY_ALL=1
		Note that when using DEPLOY_ALL a specific AppRun is needed
		which I can generate if you don not provide your own AppRun
		$LINE
		EOF
	fi
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
#	find "$LIBDIR" -type f -regex '.*libQt.*Core.*.so.*' -exec \
#	  sed -i 's|qt_prfxpath=/usr|qt_prfxpath=\.\.|g;
#	  s|qt_prfxpath=|qt_prfxpath=\.\.|g' {} ';' 2>/dev/null
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
		for dir in $RPATHS; do
			module="$(_find_libdir_relative ".*$dir" -print -quit)"
			# this avoids adding a libdir outside the AppDir to rpath
			if [ -z "$module" ]; then
				continue
			elif [ "${module##*/}" = "${libdir##*/}" ]; then
				continue
			elif ! realpath "$module" | grep -qi "$APPDIR"; then
				continue
			fi
			# remove leading "./" and store path in a variable
			patch="$patch:\$ORIGIN/${module#./}"
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
	if [ -f "$APPDIR"/NOT_FOUND_LIBS ]; then
		echo "$LINE"
		echo "WARNING: Failed to find the following libraries:"
		sort -u "$APPDIR"/NOT_FOUND_LIBS
		echo "$LINE"
	fi
	echo "$LINE"
	echo "All Done!"
	# count libs again and compare to determine if we deployed anything
	LIBSNUM_NEW="$(find "$APPDIR" -type f \
	  -regex '.*\.so.*' 2>/dev/null | wc -l)"
	if [ "$LIBSNUM_OLD" != "$LIBSNUM_NEW" ]; then
		echo "Deployed $(( LIBSNUM_NEW - LIBSNUM_OLD )) libraries"
	else
		echo "WARNING: No libraries have been deployed"
		echo "Did you run $0 more than once?"
	fi
	echo "$LINE"
}

_check_glibc_ver() {
	GLIBCV=2.31
	if ldd --version | awk -v g="$GLIBCV" 'NR==1 {if ($NF>g) exit 1}'; then
		return 0
	fi
	cat <<-EOF
	$LINE
	WARNING: Host glibc version is higher than the ideal version $GLIBCV
	this means the AppImage cannot work on distros that use glibc $GLIBCV
	such as some still supported LTS distros and debian stable

	Please build the AppImage on a system that uses glibc $GLIBCV or older

	You can also try using DEPLOY_ALL=1 to avoid those issues
	since this mode bundles glibc into the AppImage
	$LINE
	EOF
}

# do the thing
_check_dirs_and_target
_check_options_and_get_denylist
if [ -n "$EXTRA_LIBS" ]; then
	printf '\n%s\n%s\n\n' "$LINE" "Deploying extra libraries..."
	_deploy_extra_libs
	printf '\n%s\n%s\n\n' "Deployed extra libraries" "$LINE"
fi
# find the dependencies of any existing lib before deploying
for LIB in $(find "$APPDIR" -type f -regex '.*\.so.*' 2>/dev/null); do
	_deploy_libs "$LIB" "$LIBDIR"
done
# find the dependencies of all bins in BINDIR
for BIN in $(find "$BINDIR" -type f 2>/dev/null); do
	_deploy_libs "$BIN" "$LIBDIR"
done
_deploy_all_check
if [ "$DEPLOY_QT" = 1 ]; then
	printf '\n%s\n%s\n\n' "$LINE" "Deploying $QTVER..."
	_deploy_qt
	printf '\n%s\n%s\n\n' "Deployed $QTVER" "$LINE"
fi
if [ "$DEPLOY_GTK" = 1 ]; then
	printf '\n%s\n%s\n\n' "$LINE" "Deploying $GTKVER..."
	_deploy_gtk
	printf '\n%s\n%s\n\n' "Deployed $GTKVER" "$LINE"
fi
_check_icon_and_desktop
_check_apprun
_patch_away_absolute_paths
_patch_libs_and_bin_rpath
_strip_and_check_not_found_libs
if [ "$DEPLOY_ALL" != 1 ]; then
	_check_glibc_ver
fi
