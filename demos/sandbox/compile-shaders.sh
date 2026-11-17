#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/src/shaders"

glslangValidator -V --target-env vulkan1.0 -o shader.vert.spv shader.vert
glslangValidator -V --target-env vulkan1.0 -o shader.frag.spv shader.frag
