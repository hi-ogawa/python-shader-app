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
// - name: {name}
// - inputs: {inputs}
//

{code}
"""

BUFFER_NAME_MAP = dict(
    buffer00='Buffer A', buffer01='Buffer B', buffer02='Buffer C', buffer03='Buffer D')


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


def emit_shader_pass(i, shader_pass): # (int, dict) -> str
  code = shader_pass['code']
  name = shader_pass['name']
  #
  # NOTE: Reverse engineering "input" (i.e. iChannel, Buffer A/B/C/D etc...)
  # - 'filepath' (e.g. '/media/previz/buffer00.png') indicates Buffer A/B/C/D
  # - 'channel' indicates associated iChennel<N> in the render pass.
  # - For now this only handles Buffer A/B/C/D (so, e.g. static texture is not handled yet.)
  #
  # TODO:
  # - for multipass shader to be directly executable in our shader app, we need to
  #   - emit "Common" at the top of the source
  #   - emit "mainImage" as e.g. "mainImage1(..., sampler2D iChannel0, ...)"
  #   - emit yaml config with framebuffer samplers
  #     - internal_format GL_RGBA32F and double_buffering false
  #
  for inp in shader_pass['inputs']:
    if not inp['channel'] in [0, 1, 2, 3]:
      print(f"[download:warning] shader pass ({name}) : input channel {inp['channel']} found")
    if not inp['filepath'][14:22] in ['buffer00', 'buffer01', 'buffer02', 'buffer03']:
      print(f"[download:warning] shader pass ({name}) : input filepath {inp['filepath']} found")
  inputs = sorted(shader_pass['inputs'], key=lambda inp: inp['channel'])
  input_names = [BUFFER_NAME_MAP.get(inp['filepath'][14:22], 'Unknown') for inp in inputs]
  result = TEMPLATE_RENDERPASS.format(
      i=i, code=code, name=name, inputs=input_names)
  return result


def download(id, out_dir):
  import json, re, os

  print(f"[download] downloading (Shader ID: {id})")
  resp = scrape(id)
  if resp == []:
    return print(f"[download] Shader not found")

  assert resp and \
         resp[0]['info'] and \
         resp[0]['renderpass']
  shader_info   = resp[0]['info']       # dict
  shader_passes = resp[0]['renderpass'] # [dict]

  result = ''
  view_url = f"https://www.shadertoy.com/view/{id}"
  result += TEMPLATE_HEADER.format(view_url=view_url, info=json.dumps(shader_info, indent=2))
  for i, shader_pass in enumerate(shader_passes):
    result += emit_shader_pass(i, shader_pass)

  name = shader_info['name']
  simple_name = re.sub('[^0-9a-z]', '_', name.lower())
  filename = f"{simple_name}__{id}.glsl"

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
