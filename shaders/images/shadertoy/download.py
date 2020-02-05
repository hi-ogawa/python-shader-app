import json, re, os, subprocess

command = """
curl 'https://www.shadertoy.com/shadertoy' \
  -H 'Referer: https://www.shadertoy.com' \
  -d mga=1 -d type=texture
"""
proc = subprocess.run(command, capture_output=True, check=True, shell=True)
texture_info = json.loads(proc.stdout)

with open('texture.json', 'w') as f:
  f.write(json.dumps(texture_info, indent=2))

for name, url_path in zip(texture_info['name'], texture_info['filepath']):
  ext = os.path.splitext(url_path)[-1]
  simple_name = re.sub('[^0-9a-z]', '_', name.lower())
  url = "https://www.shadertoy.com/" + url_path
  command = f"wget -O {simple_name + ext} {url}"
  subprocess.run(command, check=True, shell=True)
