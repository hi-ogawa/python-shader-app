#!/bin/bash

function Main() {
  mkdir -p shaders/images
  for FILE in shaders/example*.glsl; do
    BASENAME=$(basename "${FILE}" .glsl)
    PNG_FILE="shaders/images/${BASENAME}.png"
    python shader_app.py "${FILE}" --width 400 --height 300 --offscreen "${PNG_FILE}"
  done
}

Main "${@}"
