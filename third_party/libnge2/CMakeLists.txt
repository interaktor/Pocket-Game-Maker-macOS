cmake_minimum_required(VERSION 2.8.5 FATAL_ERROR)

# Search in the directorys for additional CMake modules.
set(CMAKE_MODULE_PATH
  "${CMAKE_SOURCE_DIR}/CMake"
  "${CMAKE_SOURCE_DIR}/CMake/Utils"
  "${CMAKE_SOURCE_DIR}/CMake/Packages"
)
set(CMAKE_TEMPLATE_PATH "${CMAKE_SOURCE_DIR}/CMake/Templates")

if(NOT BUILD_FOR)
  set(BUILD_FOR Normal CACHE STRING
	"Choose the os of build, options are:
     Normal PSP Android."
	 FORCE)
endif()

if(${BUILD_FOR} STREQUAL PSP)
  set(CMAKE_TOOLCHAIN_FILE "${CMAKE_SOURCE_DIR}/CMake/Utils/psp.toolchain.cmake")
elseif(${BUILD_FOR} STREQUAL Android)
  if(NOT ANDROID_ABI)
	set(ANDROID_ABI armeabi)
  endif()
  set(CMAKE_TOOLCHAIN_FILE "${CMAKE_SOURCE_DIR}/CMake/Utils/android.toolchain.cmake")
endif()

option(BUILD_SAMPLES "Whether build samples" ON)
option(BUILD_SHARED "Whether build shared library" OFF)

# Set the project name.
project(NGE2)
set(NGE2_SRCS)
set(NGE2_LIBS)
set(NGE2_VERSION 2.1)

include(Common)
if(ANDROID)
  include(AndroidCommon)
endif()
include(SetupDepends)

# Put libraries into `lib'.
if(NOT WIN32)
  if(ANDROID)
	set_output_root(${CMAKE_BINARY_DIR}/Android)
  else()
	set(LIBRARY_OUTPUT_PATH ${CMAKE_BINARY_DIR}/lib)
  endif()
endif()

if(LINUX)
  set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -fPIC")
  set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -fPIC")
endif()

if(ANDROID)
  set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -pedantic")
  set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -pedantic")
endif()

set(NGE2_BUILD_TYPE ${CMAKE_BUILD_TYPE} CACHE INTERNAL
  "Real variable for build." FORCE)

if(${NGE2_BUILD_TYPE} STREQUAL "Debug")
  set(NGE_IS_DEBUG 1)
endif()

# Search for C header files in these directories.
include_directories(${CMAKE_SOURCE_DIR}/include)
include_directories(${CMAKE_BINARY_DIR}/include)

# PGM-Mac: src/charsets/*.h include their siblings as "charsets/xxx.h",
# so src/ itself has to be on the include path.
include_directories(${CMAKE_SOURCE_DIR}/src)

# common src files
list(APPEND NGE2_SRCS
  src/nge_bmp.c
  src/nge_charsets.c
  src/nge_debug_log.c
  src/nge_font.c
  src/nge_font_freetype.c
  src/nge_font_hzk.c
  src/nge_font_nfont.c
  src/nge_image.c
  src/nge_image_effect.c
  src/nge_image_ext.c
  src/nge_input.c
  src/nge_io_dir.c
  src/nge_io_file.c
  src/nge_jpg.c
  src/nge.c
  src/nge_misc.c
  src/nge_png.c
  src/nge_rbtree.c
  src/nge_rle.c
  src/nge_sys_compatible.c
  src/nge_tex_cache.c
  src/nge_tga.c
  src/nge_timer.c
  src/nge_app.c
  src/nge_app_cpp.cpp
  src/nge_ref_handle.c
  src/nge_package.c
  )

if(NOT APPLE)
  # nge_package_zip.c needs minizip's unzip.h. PGM uses its own pack
  # format (see include/helper/package.h), so macOS skips this module.
  list(APPEND NGE2_SRCS
\tsrc/nge_package_zip.c
\t)
endif()
#----=={ PGM-Mac: macOS (NGE_MAC) backend }==----
if(APPLE)
  enable_language(OBJC)
  list(APPEND NGE2_SRCS
	src/mac/nge_mac_window.m
	)
  # Apple deprecated OpenGL in 10.14 but it still works; silence the noise.
  add_definitions(-DGL_SILENCE_DEPRECATION)
  find_library(COCOA_LIBRARY Cocoa REQUIRED)
  find_library(OPENGL_FRAMEWORK OpenGL REQUIRED)
  find_library(AVFOUNDATION_FRAMEWORK AVFoundation REQUIRED)
  list(APPEND NGE2_LIBS ${COCOA_LIBRARY} ${OPENGL_FRAMEWORK} ${AVFOUNDATION_FRAMEWORK})
  # nge_mac_window.m is written in manual-retain-release style.
  set_source_files_properties(src/mac/nge_mac_window.m PROPERTIES
	COMPILE_FLAGS "-fno-objc-arc")
endif()

list(APPEND NGE2_LIBS ${NGE2_DEP_LIBS} ${UNZIP_LIBRARIES})

if(NOT ANDROID)
  list(APPEND NGE2_SRCS
	src/nge_gif_animation.c
	src/nge_gif_show.c
	)
endif()

if(PSP)
  include_directories(${CMAKE_SOURCE_DIR}/include/psp)
  list(APPEND NGE2_SRCS
	src/psp/nge_graphics.c
	src/psp/vram.c
	)
else()
  list(APPEND NGE2_SRCS
	src/nge_graphics.c
	)
endif()

# depends
include_directories(coolaudio)
add_subdirectory(coolaudio)
if(WIN32)
  list(APPEND NGE2_LIBS ${COOLAUDIO_LIBRARY})
else()
  LIST(APPEND NGE2_LIBS coolaudio)
endif()
if(COOLAUDIO_LIBS)
  list(APPEND NGE2_LIBS ${COOLAUDIO_LIBS})
endif()

if(COMPILER_GCC)
  set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -fexceptions")
endif()

if(NGE_IS_DEBUG)
  option(USE_STDOUT_DEBUG "debug logs use stdout." on)
  if(USE_STDOUT_DEBUG)
	add_definitions(-D_DEBUG_STDOUT)
  endif()
endif()

if(PSP)
  list(APPEND NGE2_LIBS psppower pspgum pspgu psprtc)
endif()

if(WIN32)
  list(APPEND NGE2_LIBS ${SDLMAIN_LIBRARY})
elseif(ANDROID)
  list(APPEND NGE2_LIBS log GLESv1_CM)
else()
  if(APPLE)
	# macOS: libSystem provides libc and clang links libc++ itself;
	# there is no libg on Apple platforms.
  else()
	list(APPEND NGE2_LIBS g)
	if(NOT PSP)
	  list(APPEND NGE2_LIBS c) # psp contains newlib's libc
	endif()
	list(APPEND NGE2_LIBS stdc++)
  endif()
endif()

if(PSP)
  add_pspsdk_libs(NGE2_LIBS)
endif()

if(ANDROID)
  include(CopyFile)
  function(copy_nge_android_java_files target dir)
	set(fromfile "${CMAKE_SOURCE_DIR}/src/android/NGE2.java")
	set(tofile "${dir}/src/org/libnge/nge2/NGE2.java")
	copy_file("NGE2.java for ${nm}" ${fromfile} ${tofile})
	add_custom_target(${target}_nge_java DEPENDS "NGE2.java for ${nm}")
	add_dependencies(${target} ${target}_nge_java)
  endfunction()
  set(NGE_ANDROID_JNI_FILE ${CMAKE_SOURCE_DIR}/src/android/nge_jni.cpp)
endif()

# addons
macro(add_addon_srcs subdir)
  set(_next "")
  set(_need_subdir true)

  foreach(s ${ARGN})
	if(${s} STREQUAL "HAS_SUBDIR_IN_INCLUDE")
	  include_directories(${CMAKE_SOURCE_DIR}/include/${subdir})
	elseif(${s} STREQUAL "INCLUDE_THIS_DIR")
	  include_directories(${subdir})
	elseif(${s} STREQUAL "SRC_NO_SUBDIR")
	  set(_need_subdir false)
	elseif(${s} STREQUAL "SRCS")
	  set(_next "SRC")
	elseif(${s} STREQUAL "LIBS")
	  set(_next "LIB")
	elseif(${s} STREQUAL "INCLUDES")
	  set(_next "INC")
	else()
	  if(${_next} STREQUAL "SRC")
		if(_need_subdir)
		  list(APPEND NGE2_SRCS ${subdir}/${s})
		else()
		  list(APPEND NGE2_SRCS ${s})
		endif()
	  elseif(${_next} STREQUAL "LIB")
		list(APPEND NGE2_LIBS ${s})
	  elseif(${_next} STREQUAL "INC")
		include_directories(${s})
	  endif()
	endif()
  endforeach()
endmacro()

macro(add_addon subdir)
  include(${subdir}/CMakeLists.txt)
endmacro()

# mmgr
if(NGE_IS_DEBUG)
  option(USE_MMGR "Useful for debug." off)
  if(USE_MMGR)
	add_definitions(-DMMGR)
	add_addon(mmgr)
  endif()
endif()

# hge particle system
add_addon(hge)

# helpers
add_addon(helper)

if(PSP)
  add_addon(dirent)
  add_addon(movie)
  add_addon(net)
endif()

if(BUILD_SHARED)
  add_our_library(nge2 SHARED ${NGE2_SRCS})
else()
  add_definitions(-DNGE_LIBTYPE_STATIC)
  add_our_library(nge2 STATIC ${NGE2_SRCS})
endif()

if(WIN32)
  set_target_properties(nge2 PROPERTIES COMPILE_DEFINITIONS "NGE2_EXPORTS")
endif()

if(WIN32 OR UNIX OR PSP)
  add_our_library(nge2_main STATIC src/nge_main.c)
endif()

if(MSVC)
#  if(NGE_IS_DEBUG)
#	msvc_force_link_runtime(nge2 MDd)
#  else()
	msvc_force_link_runtime(nge2 MD)
#  endif()
endif()

install(TARGETS nge2 DESTINATION lib)
install(DIRECTORY include DESTINATION ${CMAKE_INSTALL_PREFIX})

if(BUILD_SAMPLES)
  add_subdirectory(samples)
endif()
