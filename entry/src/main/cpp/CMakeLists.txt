# StarFlowOhos native build (T041 / plan D11):
# llama.cpp vendored under ./llama.cpp, built as shared libs for the
# HarmonyOS NDK toolchain; llamacpp_bridge exposes the NAPI module.
cmake_minimum_required(VERSION 3.5)
project(starflow_native)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# --- llama.cpp build options (cross-compile friendly) ---
set(GGML_NATIVE OFF CACHE BOOL "" FORCE)
set(GGML_OPENMP OFF CACHE BOOL "" FORCE)
set(GGML_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(GGML_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(BUILD_SHARED_LIBS ON CACHE BOOL "" FORCE)
set(LLAMA_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_TOOLS OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_SERVER OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_COMMON OFF CACHE BOOL "" FORCE)
set(LLAMA_CURL OFF CACHE BOOL "" FORCE)

add_subdirectory(llama.cpp)

# --- NAPI bridge: produces libllamacpp.so (import name "libllamacpp.so") ---
add_library(llamacpp SHARED llamacpp_bridge.cpp)

target_include_directories(llamacpp PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/llama.cpp/include
    ${CMAKE_CURRENT_SOURCE_DIR}/llama.cpp/ggml/include)

find_library(ace-lib ace_ndk.z)
find_library(ace_napi-lib ace_napi.z)

target_link_libraries(llamacpp PUBLIC
    llama
    ggml
    ${ace-lib}
    ${ace_napi-lib})
