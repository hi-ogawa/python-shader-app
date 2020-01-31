import argparse
import json
import urllib.request

TEMPLATE = """
//
// RenderPass {i}
//

{code}
"""

def download(id, key):
  url = f"https://www.shadertoy.com/api/v1/shaders/{id}?key={key}"
  with urllib.request.urlopen(url) as f:
    response = json.load(f)
  for i, renderpass in enumerate(response['Shader']['renderpass']):
    print(TEMPLATE.format(i=i, code=renderpass['code']))


def main():
  parser = argparse.ArgumentParser(description='Shadertoy downloader')
  parser.add_argument('id', type=str, help='Shader ID')
  parser.add_argument('--key',  type=str, required=True, help='API Key')
  args = parser.parse_args()
  download(**args.__dict__)


if __name__ == '__main__':
  main()
