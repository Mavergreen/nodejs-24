cmake_minimum_required(VERSION 3.16)
# Builds the Sparkle updater .app for this repo's Node.js line. Node itself is built by build/*.sh
# (pure shell); CMake exists here ONLY for the updater, as in mavergreen-clang and mavergreen-golang.
# Configure it through build/updater.sh, which passes NODE_FULL_VERSION from build/full-version.sh and
# the shipyard toolchain file (x86_64, 10.9, the pinned SDK) -- the updater runs where node runs.
project(NodeUpdater LANGUAGES OBJC)

find_package(MavericksShipyard REQUIRED)
include(Mavericks)
include(MavericksSparkle)

if(NOT NODE_FULL_VERSION)
  message(FATAL_ERROR "NODE_FULL_VERSION is not set -- configure with: sh build/updater.sh")
endif()
string(REGEX REPLACE "^([0-9]+)\\..*$" "\\1" NODE_LINE "${NODE_FULL_VERSION}")
if(NOT NODE_LINE MATCHES "^[0-9]+$")
  message(FATAL_ERROR "cannot derive the Node line from NODE_FULL_VERSION '${NODE_FULL_VERSION}'")
endif()

# No ICON: generic on purpose (-DMAVERICKS_ALLOW_GENERIC_ICON=ON); see updater/ICON-CREDIT.txt.
mavericks_add_updater_app(
  PRODUCT node${NODE_LINE}
  PRODUCT_NAME "Mavericks Node.js ${NODE_LINE}"
  VERSION "${NODE_FULL_VERSION}"
  LOG_PREFIX "MavNodeUpdater"
  CONFIRM_TITLE "Mavericks Node.js ${NODE_LINE} updated"
  CONFIRM_BODY "Node.js ${NODE_LINE} in /usr/local/mavergreen/node${NODE_LINE} was updated."
)
