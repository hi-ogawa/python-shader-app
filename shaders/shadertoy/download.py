TEMPLATE_HEADER = """\
//
// {view_url}
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

#
# ShaderToy's unofficial/internal API endpoint
# (NOTE: as of today (2020/02/04), it works as long as you set any same origin 'Referer' in header)
#
def scrape(id):
  import json, requests
  req_args = dict(
    url     = 'https://www.shadertoy.com/shadertoy',
    headers = { 'Referer': 'https://www.shadertoy.com' },
    data    = { 's': json.dumps({ 'shaders': [id] }) }
  )
  resp = requests.post(**req_args)
  if not resp.status_code == requests.codes.ok:
    raise RuntimeError(f"[scrape] Error\n{resp.text}")

  return json.loads(resp.text)


def download(id, out_dir):
  import json, re, os

  print(f"[download] downloading (Shader ID: {id})")
  resp = scrape(id)
  if resp == []:
    return print(f"[download] Shader not found")

  assert resp and \
         resp[0]['info'] and \
         resp[0]['renderpass']
  shader_info   = resp[0]['info']                                  # dict
  shader_passes = [data['code'] for data in resp[0]['renderpass']] # [str]

  result = ''
  view_url = f"https://www.shadertoy.com/view/{id}"
  result += TEMPLATE_HEADER.format(view_url=view_url, info=json.dumps(shader_info, indent=2))
  for i, code in enumerate(shader_passes):
    result += TEMPLATE_RENDERPASS.format(i=i, code=code)

  name = shader_info['name']
  simple_name = re.sub('[^0-9a-z]', '_', name.lower())
  filename = f"{id}_{simple_name}.glsl"

  with open(os.path.join(out_dir, filename), 'w') as f:
    f.write(result)

  print(f"[download] download succeeded ({name} (by {shader_info['username']}))")


if __name__ == '__main__':
  import argparse
  parser = argparse.ArgumentParser(description='Shader downloader')
  parser.add_argument('id', type=str, help='Shader ID or URL')
  parser.add_argument('--out-dir', type=str)
  args = parser.parse_args()
  if args.id.startswith('https://www.shadertoy.com/view'):
    args.id = args.id.split('/')[-1]
  download(**args.__dict__)
