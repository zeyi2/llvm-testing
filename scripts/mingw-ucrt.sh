#!/usr/bin/env bash
set -euo pipefail
mkdir -p logs
case "$1" in
configure)
  clang++ --version | tee logs/compiler.txt
  pacman -Q > logs/packages.txt
  cmake -S llvm-project/llvm -B build -G Ninja \
    -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++ \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_EXPORT_COMPILE_COMMANDS=ON \
    '-DLLVM_ENABLE_PROJECTS=clang;clang-tools-extra' -DLLVM_TARGETS_TO_BUILD=X86 \
    -DLLVM_ENABLE_ASSERTIONS=ON -DLLVM_INCLUDE_BENCHMARKS=OFF \
    -DLLVM_ENABLE_LLD=ON -DLLVM_PARALLEL_LINK_JOBS=1 \
    -DLLVM_BUILD_LLVM_DYLIB_VIS=ON -DLLVM_BUILD_LLVM_DYLIB=ON \
    -DLLVM_LINK_LLVM_DYLIB=ON -DCLANG_LINK_CLANG_DYLIB=ON \
    -DLLVM_ENABLE_PLUGINS=ON -DCLANG_PLUGIN_SUPPORT=ON \
    2>&1 | tee logs/configure.txt
  printf '#include "llvm/Support/Compiler.h"\n' > logs/abi.cpp
  clang++ -E -dM -DLLVM_EXPORTS -Ibuild/include -Illvm-project/llvm/include \
    logs/abi.cpp > logs/abi-macros.txt
  grep -E '^#define (LLVM_ABI |__MINGW32__ |__MINGW64__ )' logs/abi-macros.txt
  ;;
support)
  ninja -C build -n LLVMSupport > logs/support-dry-run.txt
  ninja -C build -j3 -v LLVMSupport 2>&1 | tee logs/support.txt
  ;;
plugin)
  ninja -C build -n clang clang-tidy clangTidyPlugin FileCheck > logs/plugin-dry-run.txt
  ninja -C build -j3 clang clang-tidy clangTidyPlugin FileCheck 2>&1 | tee logs/plugin.txt
  ;;
test)
  export PATH="$PWD/build/bin:$PATH"
  python build/bin/llvm-lit -v --xunit-xml-output logs/tests.xml \
    llvm-project/clang-tools-extra/test/clang-tidy/infrastructure/clang-plugin.cpp \
    llvm-project/clang-tools-extra/test/clang-tidy/infrastructure/clang-plugin-analyzer.cpp \
    2>&1 | tee logs/tests.txt
  # Unsupported must not be mistaken for successful plugin execution.
  python -c 'import xml.etree.ElementTree as E; r=E.parse("logs/tests.xml"); t=r.findall(".//testcase"); assert len(t)==2 and all(x.find("skipped") is None for x in t)'
  ;;
esac
