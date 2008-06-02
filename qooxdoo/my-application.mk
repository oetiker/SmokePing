################################################################################
#
#  qooxdoo - the new era of web development
#
#  http://qooxdoo.org
#
#  Copyright:
#    2006-2008 1&1 Internet AG, Germany, http://www.1und1.de
#
#  License:
#    LGPL: http://www.gnu.org/licenses/lgpl.html
#    EPL: http://www.eclipse.org/org/documents/epl-v10.php
#    See the LICENSE file in the project's top-level directory for details.
#
#  Authors:
#    * Sebastian Werner (wpbasti)
#    * Andreas Ecker (ecker)
#    * Fabian Jakobs (fjakobs)
#
################################################################################

################################################################################
# INCLUDE EXTERNAL MAKEFILES
################################################################################

include $(QOOXDOO_PATH)/frontend/framework/tool/make/framework.mk
include $(QOOXDOO_PATH)/frontend/framework/tool/make/apiviewer.mk
include $(QOOXDOO_PATH)/frontend/framework/tool/make/testrunner.mk
include $(QOOXDOO_PATH)/frontend/framework/tool/make/buildtool.mk





################################################################################
# REQUIRED SETTINGS
################################################################################

#
# Path to the folder of your qooxdoo distribution.
# Can either be
# a) a relative path to the location of this Makefile (preferred) or
# b) an absolute path starting at the root of your file system
# Example: If you put the skeleton folder next to the qooxdoo SDK folder,
# you can use the following relative path:
# QOOXDOO_PATH = ../qooxdoo-0.6.5-sdk
# Please note that Windows users should always use relative paths.
# It should end with the last directory. Please omit a trailing slash.
#
ifndef QOOXDOO_PATH
  QOOXDOO_PATH = PLEASE_DEFINE_QOOXDOO_PATH
endif

#
# Namespace of your application e.g. custom
# Even complexer namespaces are possible like: net.sf.custom
#
ifndef APPLICATION_NAMESPACE
  APPLICATION_NAMESPACE = custom
endif







################################################################################
# BASIC SETTINGS
################################################################################

#
# Full application classname
#
ifndef APPLICATION_CLASSNAME
  APPLICATION_CLASSNAME = Application
endif

#
# Similar to QOOXDOO_PATH, but from the webserver point of view.
# Starting point is now the application HTML file in the source folder
# (source/index.html by default). In most cases just prepend a "../" to
# QOOXDOO_PATH from above.
# Example: QOOXDOO_URI = ../../qooxdoo-0.6.5-sdk
# The assigned value should end in a directory name. Please omit trailing
# slashes.
#
ifndef QOOXDOO_URI
  QOOXDOO_URI = ../$(QOOXDOO_PATH)
endif

#
# Namespace defined as a directory path.
# Even complexer stuff is possible like: net/sf/custom
# Normally the namespace given will be automatically translated.
#
ifndef APPLICATION_NAMESPACE_PATH
  APPLICATION_NAMESPACE_PATH := $(shell echo $(APPLICATION_NAMESPACE) | sed s:\\.:/:g)
endif

#
# Title used during the make process.
# Default is the uppercase variant of your normal title.
#
ifndef APPLICATION_MAKE_TITLE
  APPLICATION_MAKE_TITLE := $(shell echo $(APPLICATION_NAMESPACE) | tr "[:lower:]" "[:upper:]")
endif

#
# Title used in your API viewer
# Default is identical to your custom namespace.
#
ifndef APPLICATION_API_TITLE
  APPLICATION_API_TITLE := $(APPLICATION_NAMESPACE)
endif

#
# Files that will be copied from the source directory into the build
# directory (space separated list). The default list is empty.
#
ifndef APPLICATION_FILES
  APPLICATION_FILES =
endif

#
# Locales to use (space separated list)
# To set a specific locale like "en_US" the generic locale "en" has to be added as well
# Example: APPLICATION_LOCALES = en en_US de de_DE es
#
ifndef APPLICATION_LOCALES
  APPLICATION_LOCALES =
endif

#
# Defines the position of the HTML/PHP etc. file used to include your
# application JavaScript code in relation to root directory. The root
# directory meant here is your source or build directory. Even if we
# this is about directories all the time, this setting configure the
# URI and not a file system path.
#
# If your HTML file is placed directly in source/build you can simply use
# the default "." (without quotation) here.
#
# If your HTML file is placed in source/html/page.html you can configure
# this setting to "../" (without quotation) for example.
#
ifndef APPLICATION_HTML_TO_ROOT_URI
  APPLICATION_HTML_TO_ROOT_URI = .
endif

#
# By default the complete command line of the called programs is
# hidden. Setting VERBOSE to true shows the complete commands.
#
SILENCE=
ifneq ($(VERBOSE),true)
SILENCE=@
endif




################################################################################
# GENERATOR OPTIONS
################################################################################

#
# Whether all JavaScript files of only the files needed by the application
# should be included into the build version of the program.
#
ifndef APPLICATION_COMPLETE_BUILD
  APPLICATION_COMPLETE_BUILD = false
endif

#
# Whether all JavaScript files of only the files needed by the application
# should be included into the source version of the program.
#
ifndef APPLICATION_COMPLETE_SOURCE
  APPLICATION_COMPLETE_SOURCE = true
endif

ifndef APPLICATION_COMPLETE_API
  APPLICATION_COMPLETE_API = true
endif

#
# Customize line break settings
# If enabled line breaks are inserted into the compiled application.
# This makes the generated code better readable and produces saner error
# messages, but bigger, too.
#
ifndef APPLICATION_LINEBREAKS_BUILD
  APPLICATION_LINEBREAKS_BUILD = true
endif

#
# Customize line break settings
# If enabled line breaks are added to the loader script of the source version.
#
ifndef APPLICATION_LINEBREAKS_SOURCE
  APPLICATION_LINEBREAKS_SOURCE = true
endif

#
# Enables string optimization for the build version.
# String optimization gives a perforcmance boost on the Internet Explorer 6,
# obfuscates the code and may reduce the size. This should always be enabled for
# deployment versions.
#
ifndef APPLICATION_OPTIMIZE_STRINGS
  APPLICATION_OPTIMIZE_STRINGS = true
endif

#
# Renames local variables to shorter names for the build version.
# This option reduces the code size and obfuscates the code.
# Warning: If local variable names are used inside of "eval" statement
# this may break the code.
#
ifndef APPLICATION_OPTIMIZE_VARIABLES
  APPLICATION_OPTIMIZE_VARIABLES = true
endif

#
# Inlines calls to "this.base(arguments)" to speed up calls to the super class.
# It is safe to enable this setting.
#
ifndef APPLICATION_OPTIMIZE_BASE_CALL
  APPLICATION_OPTIMIZE_BASE_CALL = true
endif

#
# Renames private methods and fields (methods/fields starting with "__") to shorter names.
# This makes it impossible for other classes to call private methods because the new names
# of the private members is unknown outside the class.
#
# This setting obfuscates the code and can help to enforce the privacy of methods.
#
ifndef APPLICATION_OPTIMIZE_PRIVATE
  APPLICATION_OPTIMIZE_PRIVATE = false
endif

#
# This setting obfuscates the code
#
ifndef APPLICATION_OBFUSCATE_ACCESSORS
  APPLICATION_OBFUSCATE_ACCESSORS = false
endif

#
# If enabled optimized builds for each supported browser given in
# APPLICATION_INDIVIDUAL_BROWSERS and a generic loader script are generated.
#
# This increases the time to build the application but optimizes both code size and runtime
# of the application.
#
ifndef APPLICATION_OPTIMIZE_BROWSER
  APPLICATION_OPTIMIZE_BROWSER = false
endif

#
# Individual browsers that an optimized build is generated for, if
# APPLICATION_OPTIMIZE_BROWSER is enabled.
#
ifndef APPLICATION_INDIVIDUAL_BROWSERS
  APPLICATION_INDIVIDUAL_BROWSERS = gecko mshtml opera webkit
endif

#
# Remove debug code.
#
# This sets the variant qx.debug to "off" and removes all code paths for qx.debug "on".
# Production code should set this always to true, because qooxdoo uses extensive runtime
# checks, which will be disabled by this setting.
#
ifndef APPLICATION_OPTIMIZE_REMOVE_DEBUG
  APPLICATION_OPTIMIZE_REMOVE_DEBUG = true
endif

#
# Remove compatibility for qooxdoo 0.6 style class declarations.
#
ifndef APPLICATION_OPTIMIZE_REMOVE_COMPATIBILITY
  APPLICATION_OPTIMIZE_REMOVE_COMPATIBILITY = false
endif

#
# Remove AOP support
#
ifndef APPLICATION_OPTIMIZE_REMOVE_ASPECTS
  APPLICATION_OPTIMIZE_REMOVE_ASPECTS = true
endif

#
# Configure if support for widgets should be included
#
# If enabled qooxdoo initializes the whole widget and event stack.
# Disable this if you don't need the qooxdoo widgets but want to use only
# the core functionality of qooxdoo (e.g. RPC, Ajax, DOM, XML, ...)
#
ifndef APPLICATION_ENABLE_GUI
  APPLICATION_ENABLE_GUI = true
endif

#
# Configure resource filter
# If enabled all application classes needs a #embed
# configuration, too.
#
ifndef APPLICATION_RESOURCE_FILTER
  APPLICATION_RESOURCE_FILTER = false
endif


#
# List of directories containing contributions or external projects
# to include code from. Additionally qooxdoo-contrib includes can be 
# used by using the following URL scheme:
# contrib://ProgressBar/0.1
#
ifndef APPLICATION_INCLUDES
  APPLICATION_INCLUDES = false
endif




################################################################################
# RUNTIME SETTINGS
################################################################################

#
# Set the default meta theme.
#
ifndef APPLICATION_THEME
  APPLICATION_THEME = qx.theme.ClassicRoyale
endif

#
# Set the default color theme.
#
ifndef APPLICATION_THEME_COLOR
  APPLICATION_THEME_COLOR =
endif

#
# Set the default border theme.
#
ifndef APPLICATION_THEME_BORDER
  APPLICATION_THEME_BORDER =
endif

#
# Set the default font theme.
#
ifndef APPLICATION_THEME_FONT
  APPLICATION_THEME_FONT =
endif

#
# Set the default icon theme
#
ifndef APPLICATION_THEME_ICON
  APPLICATION_THEME_ICON =
endif

#
# Set the default widget theme
#
ifndef APPLICATION_THEME_WIDGET
  APPLICATION_THEME_WIDGET =
endif

#
# Set the default appearance theme.
#
ifndef APPLICATION_THEME_APPEARANCE
  APPLICATION_THEME_APPEARANCE =
endif








#
# Set the default log level for the source version
#
ifndef APPLICATION_SOURCE_LOG_LEVEL
  APPLICATION_SOURCE_LOG_LEVEL = debug
endif

#
# Set the default log level for the build version
#
ifndef APPLICATION_BUILD_LOG_LEVEL
  APPLICATION_BUILD_LOG_LEVEL = debug
endif

#
# Set the default log appender for the source version
#
ifndef APPLICATION_SOURCE_LOG_APPENDER
  APPLICATION_SOURCE_LOG_APPENDER = qx.log.appender.Native
endif

#
# Set the default log appender for the build version
#
ifndef APPLICATION_BUILD_LOG_APPENDER
  APPLICATION_BUILD_LOG_APPENDER = qx.log.appender.Native
endif






################################################################################
# SOURCE TEMPLATE SETUP
################################################################################

#
# Template to patch (e.g. XHTML mode)
#
ifndef APPLICATION_TEMPLATE_INPUT
  APPLICATION_TEMPLATE_INPUT =
endif

ifndef APPLICATION_TEMPLATE_OUTPUT
  APPLICATION_TEMPLATE_OUTPUT =
endif

ifndef APPLICATION_TEMPLATE_REPLACE
  APPLICATION_TEMPLATE_REPLACE = <!-- qooxdoo-script-block -->
endif







################################################################################
# DETAILED PATH CONFIGURATION
################################################################################

#
# The source folder of your application from the directory which contains the
# Makefile (if defined relatively). This folder should contain all your
# application class files and resources. The default is ./source.
#
ifndef APPLICATION_SOURCE_PATH
  APPLICATION_SOURCE_PATH = ./source
endif

#
# The build folder of your application relative to the directory, which contains the
# Makefile (if defined relatively). This is the folder where the application
# self-contained build is generated to. The default is ./build.
#
ifndef APPLICATION_BUILD_PATH
  APPLICATION_BUILD_PATH = ./build
endif

#
# The API folder of your application from the directory which contains the
# Makefile (if defined relatively). This is the destination target where the
# self-contained API viewer should resist after a "make api".
# The default is ./api.
#
ifndef APPLICATION_API_PATH
  APPLICATION_API_PATH = ./api
endif

#
# Define the debug location from the directory which contains the
# Makefile (if defined relatively). The default is ./debug.
#
ifndef APPLICATION_DEBUG_PATH
  APPLICATION_DEBUG_PATH = ./debug
endif

#
# Define the publishing location from the directory which contains the
# Makefile (if defined relatively). Could be any rsync compatible url/path
# The default is ./publish.
#
ifndef APPLICATION_PUBLISH_PATH
  APPLICATION_PUBLISH_PATH = ./publish
endif

#
# The folder that will contain a unit test appliction for your classes, defined
# from the directory which contains the Makefile (if defined relatively). This
# is the destination folder for the "make test" target.  The default is ./test.
#
ifndef APPLICATION_TEST_PATH
  APPLICATION_TEST_PATH = ./test
endif
 
#
# The folder that will contain assorted tools (e.g. buildtool) that can be
# generated for the current application, defined from the directory which
# contains the Makefile (if defined relatively). This is the destination folder
# for targets like "make buildtool", which will create its own subfolder.  The
# default is ./tool.
#
ifndef APPLICATION_TOOL_PATH
  APPLICATION_TOOL_PATH = ./tool
endif
 
#
# The folder that will contain the buildtool application, defined from the
# directory which contains the Makefile (if defined relatively). This is the
# destination folder for the "make buildtool" target.  The default is
# $(APPLICATION_TOOL_PATH)/tool.
#
ifndef APPLICATION_BUILDTOOL_PATH
  APPLICATION_BUILDTOOL_PATH = $(APPLICATION_TOOL_PATH)/buildtool
endif
 





################################################################################
# OUTPUT OPTIONS
################################################################################

#
# Redefine folder names (inside build/source)
# It is not recommended to change these fundamental settings.
#
ifndef APPLICATION_SCRIPT_FOLDERNAME
  APPLICATION_SCRIPT_FOLDERNAME = script
endif

ifndef APPLICATION_CLASS_FOLDERNAME
  APPLICATION_CLASS_FOLDERNAME = class
endif

ifndef APPLICATION_TRANSLATION_FOLDERNAME
  APPLICATION_TRANSLATION_FOLDERNAME = translation
endif

#
# File name of the generated script
#
ifndef APPLICATION_SCRIPT_FILENAME
  APPLICATION_SCRIPT_FILENAME = $(APPLICATION_NAMESPACE).js
endif






################################################################################
# LINT OPTIONS
################################################################################

#
# A list of valid global identifiers. These identifiers will not be reported
# as errors.
#
ifndef LINT_ALLOWED_GLOBALS
  LINT_ALLOWED_GLOBALS = 
endif






################################################################################
# PROFILER OPTIONS
################################################################################

#
# Whether to enable the profiler (source version)
#
ifndef APPLICATION_PROFILE_SOURCE
  APPLICATION_PROFILE_SOURCE = false
endif


#
# Whether to enable the profiler (build version)
#
ifndef APPLICATION_PROFILE_BUILD
  APPLICATION_PROFILE_BUILD = false
endif






################################################################################
# ADDITIONAL CONFIGURATION
################################################################################

#
# Additional class paths and URIs.
# These should be comma separated.
# The generator option will be automatically added
#
ifndef APPLICATION_ADDITIONAL_CLASS_PATH
  APPLICATION_ADDITIONAL_CLASS_PATH =
endif

ifndef APPLICATION_ADDITIONAL_CLASS_URI
  APPLICATION_ADDITIONAL_CLASS_URI =
endif

#
# Additional options to pass to the generator call of the source version.
# e.g. "--script-output-encoding=ISO-8859-1"
#
ifndef APPLICATION_ADDITIONAL_SOURCE_OPTIONS
  APPLICATION_ADDITIONAL_SOURCE_OPTIONS =
endif

#
# Additional options to pass to the generator call of the build version.
# e.g. "--script-output-encoding=ISO-8859-1"
#
ifndef APPLICATION_ADDITIONAL_BUILD_OPTIONS
  APPLICATION_ADDITIONAL_BUILD_OPTIONS =
endif

#
# Additional params to pass to the xgettext call in exec-*-translation.
# e.g. "--sort-by-file" or "--no-location --sort-output"
#
ifndef APPLICATION_ADDITIONAL_XGETTEXT_PARAMS
  APPLICATION_ADDITIONAL_XGETTEXT_PARAMS = --sort-by-file --add-comments=TRANSLATION
endif







################################################################################
# INCLUDE EXTERNAL MAKEFILES
################################################################################

include $(QOOXDOO_PATH)/frontend/framework/tool/make/compute.mk
include ./my-impl.mk
