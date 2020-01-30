import argparse
import os
from PySide2 import QtWidgets, QtGui
from .app import setup_misc, OffscreenRenderer
from .utils import setup_interrupt_handler, setup_qt_message_handler, preprocess_include


def process_batch(files, width, height, out_dir, format):
  setup_misc()
  app = QtWidgets.QApplication()
  renderer = OffscreenRenderer(width, height)
  for file in files:
    basename_wo_ext = os.path.splitext(os.path.basename(file))[0]
    out_file = os.path.join(out_dir, f"{basename_wo_ext}.{format}")
    print(f"[process_batch] (input) {file} (output) {out_file}")
    renderer.render(file)
    renderer.fbo.toImage().save(out_file)


def main():
  parser = argparse.ArgumentParser(description='ShaderApp (batch offscreen mode)')
  parser.add_argument('files', type=str, nargs='*',         help='shader files')
  parser.add_argument('--width',  type=int, default=500,    help='resolution width')
  parser.add_argument('--height', type=int, default=400,    help='resolution height')
  parser.add_argument('--out-dir', type=str, required=True, help='output directory')
  parser.add_argument('--format', type=str, default='png',  help='image file format')
  args = parser.parse_args()
  process_batch(**args.__dict__)


if __name__ == '__main__':
  main()
