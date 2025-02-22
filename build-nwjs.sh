#!/bin/bash

set -e

export NWJS_BRANCH="$1"
export WORKDIR="/usr/docker"
export NWJSDIR=${WORKDIR}/nwjs
export DEPOT_TOOLS_DIRECTORY=${WORKDIR}/depot_tools
export PATH=${PATH}:${DEPOT_TOOLS_DIRECTORY}
export LC_ALL=C.UTF-8
export GYP_CHROMIUM_NO_ACTION=0

function applyPatch {
  # See https://gist.github.com/llamasoft/33af03b73945a84d7624460d67b922ab
  # For nwjs_sdk=false builds, some required(?) files never get built.
  # As a workaround, always use the SDK's GRIT input regardless of the flag.
  # See: https://github.com/nwjs/chromium.src/issues/145
  cd $NWJSDIR/src
  patch -p0 --ignore-whitespace << 'PATCH'
--- chrome/browser/BUILD.gn
+++ chrome/browser/BUILD.gn
@@ -6356,11 +6356,7 @@ grit("resources") {
   # TODO(crbug.com / 1112471): Get this to run cleanly under Python 3.
   run_under_python2 = true

-  if (nwjs_sdk) {
-    source = "browser_resources.grd"
-  } else {
-    source = "nwjs_resources.grd"
-  }
+  source = "browser_resources.grd"

   # Required due to flattenhtml = "true" on a generated file.
   enable_input_discovery_for_gn_analyze = false
PATCH

    patch -p0 --ignore-whitespace << 'PATCH'
--- build/config/linux/atk/BUILD.gn
+++ build/config/linux/atk/BUILD.gn
@@ -10,7 +10,7 @@ import("//build/config/ui.gni")
 assert(!is_chromeos)

 # These packages should _only_ be expected when building for a target.
-assert(current_toolchain == default_toolchain)
+# assert(current_toolchain == default_toolchain)

 if (use_atk) {
   assert(use_glib, "use_atk=true requires that use_glib=true")
PATCH

    patch -p0 --ignore-whitespace << 'PATCH'
--- content/nw/src/api/nw_app_api.cc
+++ content/nw/src/api/nw_app_api.cc
@@ -1,5 +1,8 @@
 #include "content/nw/src/api/nw_app_api.h"

+#include "build/build_config.h"
+#include "third_party/widevine/cdm/buildflags.h"
+
 #include "chrome/browser/lifetime/browser_close_manager.h"
 #include "chrome/browser/lifetime/application_lifetime.h"
 #include "content/public/common/content_features.h"
@@ -104,10 +107,14 @@ NwAppCloseAllWindowsFunction::Run() {

 ExtensionFunction::ResponseAction
 NwAppEnableComponentFunction::Run() {
+#if BUILDFLAG(ENABLE_WIDEVINE)
   component_updater::RegisterWidevineCdmComponent(g_browser_process->component_updater(),
                                                   base::BindOnce(&NwAppEnableComponentFunction::OnRegistered,
                                                                  this));
   return RespondLater();
+#else
+  return RespondNow(NoArguments());
+#endif
 }

 void NwAppEnableComponentFunction::OnRegistered() {
PATCH
}

function build {
  cd $NWJSDIR/src
  gn gen out/nw --args="${1} enable_widevine=false is_component_ffmpeg=true is_debug=false symbol_level=1 target_os=\"linux\" target_cpu=\"arm\" arm_float_abi=\"hard\""
  $NWJSDIR/src/build/gyp_chromium -I third_party/node-nw/common.gypi third_party/node-nw/node.gyp
  ninja -C out/nw nwjs
  ninja -C out/Release node
  ninja -C out/nw copy_node
  temp_dir=$(mktemp -d)
  OLD_PATH="${PATH}"
  export PATH="${temp_dir}:${PATH}"

  # Typically under `third_party/llvm-build/Release+Asserts/bin`, but search for it just in case.
  objcopy=$(find . -type f -name "llvm-objcopy" | head -1 | xargs -n 1 realpath)
  cat > "${temp_dir}/strip" <<STRIP_SCRIPT
#!/bin/sh
"${objcopy}" --strip-unneeded "\$@"
STRIP_SCRIPT
  chmod +x "${temp_dir}/strip"

  ninja -C out/nw dump

  export PATH="${OLD_PATH}"
  rm -rf "${temp_dir}"

  ninja -C out/nw dist
}

applyPatch

if [ -d "${WORKDIR}/dist" ]; then rm -r ${WORKDIR}/dist; fi

COMMON_GYP_DEFINES="enable_widevine=0 building_nw=1 buildtype=Official clang=1 OS=linux target_arch=arm target_cpu=arm arm_float_abi=hard"

export GYP_DEFINES="nwjs_sdk=0 disable_nacl=1 $COMMON_GYP_DEFINES"
build "nwjs_sdk=false enable_nacl=false"
mkdir -p ${WORKDIR}/dist/nwjs-chromium-ffmpeg-branding
cp ${NWJSDIR}/src/out/nw/dist/** ${WORKDIR}/dist/nwjs-chromium-ffmpeg-branding

export GYP_DEFINES="nwjs_sdk=0 disable_nacl=1 $COMMON_GYP_DEFINES"
build "nwjs_sdk=false enable_nacl=false ffmpeg_branding=\"Chrome\""
mkdir -p ${WORKDIR}/dist/nwjs-chrome-ffmpeg-branding
cp ${NWJSDIR}/src/out/nw/dist/** ${WORKDIR}/dist/nwjs-chrome-ffmpeg-branding

export GYP_DEFINES="nwjs_sdk=1 disable_nacl=0 $COMMON_GYP_DEFINES"
build "nwjs_sdk=true enable_nacl=true"
mkdir -p ${WORKDIR}/dist/nwjs-sdk-chromium-ffmpeg-branding
cp ${NWJSDIR}/src/out/nw/dist/** ${WORKDIR}/dist/nwjs-sdk-chromium-ffmpeg-branding

export GYP_DEFINES="nwjs_sdk=1 disable_nacl=0 $COMMON_GYP_DEFINES"
build "nwjs_sdk=true enable_nacl=true ffmpeg_branding=\"Chrome\""
mkdir -p ${WORKDIR}/dist/nwjs-sdk-chrome-ffmpeg-branding
cp ${NWJSDIR}/src/out/nw/dist/** ${WORKDIR}/dist/nwjs-sdk-chrome-ffmpeg-branding
