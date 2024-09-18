# deploy-linux.sh

POSIX(ish) shell script that deploys dependencies for AppImages, similar to linuxdeploy, linuxdeploy-qt, go-appimage and others.

**Automatically deploys Qt or GTK.**

USAGE EXAMPLES:

`./deploy-linux.sh /path/to/binary` Assumes the binary is on an AppDir structure and will deploy libs and get the needed files.

`./deploy-linux.sh /path/to/binary /path/to/AppDir` Will create the AppDir, deploy libs and get the needed files.

`SKIP="libA.so libB.so" ./deploy-linux.sh /path/to/binary /path/to/AppDir` Ignores given libraries from being deployed.

`EXTRA_LIBS="libA.so libB.so" ./deploy-linux.sh /path/to/binary /path/to/AppDir` Deploys extra libraries.

`DEPLOY_AL=1 ./deploy-linux.sh /path/to/binary /path/to/AppDir` Will ignore the [excludelist](https://github.com/AppImageCommunity/pkg2appimage/blob/master/excludelist) and deploy ALL libraries.

# Credits

Forked from https://github.com/lat9nq/deploy

AppRun was taken from [go-appimage](https://github.com/probonopd/go-appimage/blob/master/src/appimagetool/appdirtool.go#L41-L146) and simplified. 
