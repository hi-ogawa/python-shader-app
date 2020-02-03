import argparse
import json
import urllib.request
import sys

TEMPLATE_HEADER = """\
//
// {url}
//

/*
{info}
*/
"""

TEMPLATE_RENDERPASS = """
//
// RenderPass {i}
//

{code}
"""

def download(id, key):
  url = f"https://www.shadertoy.com/api/v1/shaders/{id}"
  url_with_key = f"{url}?key={key}"
  print(f"[download] {url_with_key}", file=sys.stderr)

  with urllib.request.urlopen(url_with_key) as f:
    response = json.load(f)

  if response.get('Error'):
    print(f"[download] API Error\n{response}", file=sys.stderr)
    return

  assert response['Shader'] and \
         response['Shader']['info'] and \
         response['Shader']['renderpass']

  # Emit info
  info = response['Shader']['info']
  print(TEMPLATE_HEADER.format(url=url, info=json.dumps(info, indent=2)))

  # Emit renderpass
  renderpasses = response['Shader']['renderpass']
  for i, renderpass in enumerate(renderpasses):
    print(TEMPLATE_RENDERPASS.format(i=i, code=renderpass['code']))


def main():
  parser = argparse.ArgumentParser(description='Shadertoy downloader')
  parser.add_argument('id', type=str, help='Shader ID or URL')
  parser.add_argument('--key',  type=str, required=True, help='API Key')
  args = parser.parse_args()
  if args.id.startswith('https://www.shadertoy.com/view'):
    args.id = args.id.split('/')[-1]
  download(**args.__dict__)


if __name__ == '__main__':
  main()
