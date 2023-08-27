project('breakpadwrapper', 'cpp')

dir_base = meson.current_source_dir()

cc = meson.get_compiler('cpp')
lib_common = cc.find_library('libcommon', dirs: join_paths(dir_base, '../crashpad/crashpad/out/Default/obj/handler'))
lib_client_common = cc.find_library('libcommon', dirs: join_paths(dir_base, '../crashpad/crashpad/out/Default/obj/client'))
lib_client = cc.find_library('libclient', dirs: join_paths(dir_base, '../crashpad/crashpad/out/Default/obj/client'))
lib_util = cc.find_library('libutil', dirs: join_paths(dir_base, '../crashpad/crashpad/out/Default/obj/util'))
lib_base = cc.find_library('libbase', dirs: join_paths(dir_base, '../crashpad/crashpad/out/Default/obj/third_party/mini_chromium/mini_chromium/base'))

incdir = include_directories([ '../crashpad/crashpad/',
    '../crashpad/crashpad/third_party/mini_chromium/mini_chromium/',
    '../crashpad/crashpad/out/Default/gen/'])

files = ['crashpad.cpp']

lib = static_library(
    'crashpad_wrapper', 
    files, 
    include_directories: [incdir, '.'], 
    dependencies: [lib_common, lib_client_common, lib_client, lib_util, lib_base])

crashpad_wrapper = declare_dependency(link_with: lib, include_directories: '.')
meson.override_dependency('crashpad_wrapper', crashpad_wrapper)