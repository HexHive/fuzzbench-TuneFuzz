# Copyright 2020 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

ARG parent_image
FROM $parent_image

# Install llvm 12 and gcc 10
RUN apt-get update && \
    apt-get install -y wget libstdc++-5-dev libexpat1-dev && \
    apt-get install -y apt-utils apt-transport-https ca-certificates

# Download afl++
RUN git clone https://github.com/AFLplusplus/AFLplusplus.git /afl && \
    cd /afl && \
    git checkout 5dd35f5281afec0955c08fe9f99e3c83222b7764 && \
    sed -i 's|^#define CMPLOG_SOLVE|// #define CMPLOG_SOLVE|' include/config.h
    
# Build without Python support as we don't need it.
# Set AFL_NO_X86 to skip flaky tests.
RUN cd /afl && unset CFLAGS && unset CXXFLAGS && export AFL_NO_X86=1 && \
    CC=clang PYTHON_INCLUDE=/ make && make install && \
    make -C utils/aflpp_driver && \
    cp utils/aflpp_driver/libAFLDriver.a / && \
    cp -va `llvm-config --libdir`/libc++* /afl/
