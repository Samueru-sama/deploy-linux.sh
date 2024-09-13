# deploy

POSIX(ish) shell script that deploys dependencies for AppImages, similar to linuxdeploy, linuxdeploy-qt, go-appimage and others.

USAGE EXAMPLES:

`./deploy-linux.sh /path/to/binary` Assumes the binary is on an AppDir structure and will deploy libs and get the needed files.

`./deploy-linux.sh /path/to/binary /path/to/AppDir` .Will create the AppDir, deploy libs and get the needed files.

`DEPLOY_QT=1 ./deploy-linux.sh /path/to/binary /path/to/AppDir` .Also deploys Qt plugins.

`DEPLOY_GTK=1 ./deploy-linux.sh /path/to/binary /path/to/AppDir` Also deploys GTK libs.

`SKIP=\"libA.so libB.so\" ./deploy-linux.sh /path/to/binary /path/to/AppDir` Ignores given libraries from being deployed.

`DEPLOY_AL=1 ./deploy-linux.sh /path/to/binary /path/to/AppDir` Will ignore the [excludelist](https://github.com/AppImageCommunity/pkg2appimage/blob/master/excludelist) and deploy ALL libraries, however you still need to use `DEPLOY_GTK=1` or `DEPLOY_QT=1` if needed.
