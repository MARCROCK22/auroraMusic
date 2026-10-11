cmake_minimum_required(VERSION 3.20)
project(aurora_so_loud_pcm_regression LANGUAGES CXX)

if(NOT DEFINED SOLOUD_ROOT)
  message(FATAL_ERROR "SOLOUD_ROOT must point to pinned flutter_soloud's src/soloud")
endif()

file(GLOB SOLOUD_CORE CONFIGURE_DEPENDS "${SOLOUD_ROOT}/src/core/*.cpp")
file(GLOB SOLOUD_FILTERS CONFIGURE_DEPENDS "${SOLOUD_ROOT}/src/filter/*.cpp")
add_library(soloud STATIC
  ${SOLOUD_CORE}
  ${SOLOUD_FILTERS}
  "${SOLOUD_ROOT}/src/audiosource/wav/soloud_wav.cpp"
  "${SOLOUD_ROOT}/src/audiosource/wav/stb_vorbis.c"
  "${SOLOUD_ROOT}/src/audiosource/wav/dr_impl.cpp"
  "${SOLOUD_ROOT}/src/backend/null/soloud_null.cpp"
  "${SOLOUD_ROOT}/../audiobuffer/mp3_stream_decoder.cpp"
)
target_include_directories(soloud PUBLIC "${SOLOUD_ROOT}/include")
target_include_directories(soloud PRIVATE "${SOLOUD_ROOT}/src")
target_include_directories(soloud PRIVATE "${SOLOUD_ROOT}/..")
target_compile_definitions(soloud PRIVATE WITH_NULL)
target_compile_features(soloud PUBLIC cxx_std_17)
set_source_files_properties(
  "${SOLOUD_ROOT}/src/audiosource/wav/dr_impl.cpp"
  "${SOLOUD_ROOT}/src/audiosource/wav/stb_vorbis.c"
  PROPERTIES LANGUAGE CXX
)

add_executable(audio_pcm_regression audio_pcm_regression.cpp)
target_link_libraries(audio_pcm_regression PRIVATE soloud)
