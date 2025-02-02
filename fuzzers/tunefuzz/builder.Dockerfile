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

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Etc/UTC

RUN apt-get update && \
    apt-get install -y \
        build-essential \
        python3-dev \
        python3-setuptools \
        automake \
        cmake \
        git \
        flex \
        bison \
        libglib2.0-dev \
        libpixman-1-dev \
        cargo \
        libgtk-3-dev \
        # for QEMU mode
        ninja-build \
        gcc-$(gcc --version|head -n1|sed 's/\..*//'|sed 's/.* //')-plugin-dev \
        libstdc++-$(gcc --version|head -n1|sed 's/\..*//'|sed 's/.* //')-dev

RUN apt install -y git gcc g++ make cmake wget \
        libgmp-dev libmpfr-dev texinfo bison python3

RUN apt-get install -y libboost-all-dev libjsoncpp-dev libgraphviz-dev \
    pkg-config libglib2.0-dev findutils

RUN apt install -y lsb-release wget software-properties-common python3-pip

# these two packages are automatically installed, libpcap will consider libnl
# installed and try to link with libnl-genl-3-dev, which is not installed.
# Simply remove these packages
RUN apt remove libnl-3-200 libnl-3-dev -y

RUN pip3 install networkx pydot

RUN git clone https://github.com/kdsjZh/Fishpp /FishFuzz && \
    cd /FishFuzz && \
    git checkout be113d6a9d27c0b574d083f2d827d1e6c551435d || \
    true

# build clang-12 with gold plugin
RUN mkdir -p /build && \
    git clone \
        https://github.com/llvm/llvm-project /llvm && \
    git clone \
        --depth 1 \
        --branch binutils-2_40-branch \
        git://sourceware.org/git/binutils-gdb.git /llvm/binutils && \
    cd /llvm/ && git checkout bf7f8d6fa6f460bf0a16ffec319cd71592216bf4 && \
    git apply /FishFuzz/fish_mode/llvm_patch/llvm-15.0/llvm-15-asan.diff && \
    cp /FishFuzz/fish_mode/llvm_patch/llvm-15.0/FishFuzzAddressSanitizer.cpp llvm/lib/Transforms/Instrumentation/ && \
    mkdir /llvm/binutils/build && cd /llvm/binutils/build && \
        CFLAGS="" CXXFLAGS="" CC=gcc CXX=g++ \
        ../configure --enable-gold --enable-plugins --disable-werror && \
        make all-gold -j$(nproc) && \
    cd /llvm/ && mkdir build && cd build &&\
    CFLAGS="" CXXFLAGS="" CC=gcc CXX=g++ \
    cmake -DCMAKE_BUILD_TYPE=Release \
          -DLLVM_BINUTILS_INCDIR=/llvm/binutils/include \
          -DLLVM_ENABLE_PROJECTS="compiler-rt;clang" \
          -DLLVM_ENABLE_RUNTIMES="libcxx;libcxxabi" ../llvm && \
    make -j$(nproc) && \
    cp /llvm/build/lib/LLVMgold.so //usr/lib/bfd-plugins/ && \
    cp /llvm/build/lib/libLTO.so //usr/lib/bfd-plugins/


ENV LLVM_CONFIG=llvm-config

# make sure our modified clang-12 is called before clang-15, which is in /usr/local/bin
ENV PATH="/llvm/build/bin:${PATH}"
ENV LD_LIBRARY_PATH="/llvm/build/lib/x86_64-unknown-linux-gnu/"


# Build without Python support as we don't need it.
# Set AFL_NO_X86 to skip flaky tests.
RUN cd /FishFuzz/ && \
    unset CFLAGS CXXFLAGS CC CXX && \
    git checkout 40947508037b874020c8dd1251359fecaab04b9d src/afl-fuzz-bitmap.c && \
    export AFL_NO_X86=1 && \
    make clean && \
    PYTHON_INCLUDE=/ make && \
    # make -C dyncfg && \
    chmod +x fish_mode/distance/*.py && \
    make install

RUN wget https://raw.githubusercontent.com/llvm/llvm-project/5feb80e748924606531ba28c97fe65145c65372e/compiler-rt/lib/fuzzer/afl/afl_driver.cpp -O /FishFuzz/afl_driver.cpp && \
    clang++ -stdlib=libc++ -std=c++11 -O2 -c /FishFuzz/afl_driver.cpp -o /FishFuzz/afl_driver.o && \
    ar r /libAFLDriver.a /FishFuzz/afl_driver.o /FishFuzz/afl-compiler-rt.o
