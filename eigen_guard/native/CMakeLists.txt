# EigenGuard Native Engine
# C++ hisoblash yadrosi - CMake konfiguratsiyasi
cmake_minimum_required(VERSION 3.14)
project(eigenguard_engine LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# ============================================================
# Asosiy kutubxona (shared library)
# ============================================================
add_library(eigenguard_engine SHARED
    src/spline_processor.cpp
    src/optical_flow.cpp
    src/kalman_filter.cpp
    src/fft_processor.cpp
    src/approximation_processor.cpp
    src/ffi_bridge.cpp
)

target_include_directories(eigenguard_engine PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}/include
)

# Windows uchun DLL eksport
if(WIN32)
    target_compile_definitions(eigenguard_engine PRIVATE EIGENGUARD_BUILDING_DLL)
endif()

# ============================================================
# Test executable (ixtiyoriy)
# cmake -DBUILD_TESTS=ON orqali yoqiladi
# ============================================================
option(BUILD_TESTS "Build test executable" OFF)

if(BUILD_TESTS)
    add_executable(eigenguard_test
        tests/test_spline.cpp
        src/spline_processor.cpp
    )

    target_include_directories(eigenguard_test PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/include
    )

    target_compile_features(eigenguard_test PUBLIC cxx_std_17)

    # Test ni ishga tushirish uchun CTest qo'shish
    enable_testing()
    add_test(NAME SplineTest COMMAND eigenguard_test)
endif()
