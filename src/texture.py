import argparse
import json
import sys
import requests
import os
import re


# texture_type : 'texture' or 'cubemap'
def shadertoy_scrape_info(texture_type):
  assert texture_type in ['texture', 'cubemap']
  req_args = dict(
    url     = 'https://www.shadertoy.com/shadertoy',
    headers = { 'Referer': 'https://www.shadertoy.com' },
    data    = { 'mga': '1', 'type': texture_type }
  )
  resp = requests.post(**req_args)
  if not resp.status_code == requests.codes.ok:
    raise RuntimeError(f"[texture.scrape] Error: {resp.text}")

  return json.loads(resp.text)


def shadertoy_download_all(out_dir):
  def download(texture_type, name, url_path):
    ext = os.path.splitext(url_path)[-1]
    local_path = os.path.join(out_dir, texture_type + '_' + re.sub('[^0-9a-z]', '_', name.lower()) + ext)
    print(f"[shadertoy_download_all] downloading '{name}' to '{local_path}'")
    resp = requests.get(f"https://www.shadertoy.com/{url_path}")
    with open(local_path, 'wb') as f:
      f.write(resp.content)

  #
  # Texture
  #
  texture_info = shadertoy_scrape_info('texture')
  with open(os.path.join(out_dir, 'texture.json'), 'w') as f:
    f.write(json.dumps(texture_info, indent=2))

  for name, url_path in zip(texture_info['name'], texture_info['filepath']):
    download('texture', name, url_path)

  #
  # Cubemap
  #
  cubemap_info = shadertoy_scrape_info('cubemap')
  with open(os.path.join(out_dir, 'cubemap.json'), 'w') as f:
    f.write(json.dumps(cubemap_info, indent=2))

  for name, url_path in zip(cubemap_info['name'], cubemap_info['filepath']):
    download('cubemap', name, url_path)
