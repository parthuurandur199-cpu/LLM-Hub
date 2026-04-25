cmake_minimum_required(VERSION 3.22.1)
project("llmhub_mnn")

# Tell the compiler where GitHub dropped our MNN headers
include_directories(${CMAKE_CURRENT_SOURCE_DIR}/include)

# We will create this bridge file in Phase 3
# add_library(mnn_bridge SHARED mnn_bridge.cpp)
