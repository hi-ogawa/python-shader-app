import argparse
import json
import sys
import requests

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

#
# Scrape Shadertoy's data using https://www.browserless.io/
# (NOTE: as of today (2020/02/04), this services allows 50 requrests per day for free.)
# (NOTE: this is not used since clearly scrape_v2 is much simpler)
#
# cf.
# - https://www.shadertoy.com/js/pgWatch.js?v=79
# - https://docs.browserless.io/docs/function.html
# - https://github.com/puppeteer/puppeteer/blob/master/docs/api.md
#
def scrape(id):
  req_url = 'https://chrome.browserless.io/function'
  req_json_payload = {
    "code": """
      module.exports = async ({ page, context: { url } }) => {
        await page.goto(url);
        await page.waitFor(() => !!window.gRes);
        const data = await page.evaluate(() => ({
          info:   window.gShaderToy.mInfo,
          passes: window.gShaderToy.mEffect.mPasses.map(pass => pass.mSource),
        }));
        return { data, type: 'application/json' };
      };
    """,
    "context": {
      "url": f"https://www.shadertoy.com/view/{id}"
    }
  }
  resp = requests.post(req_url, json=req_json_payload)
  if not resp.status_code == requests.codes.ok:
    print(f"[scrape] Error\n{resp.text}", file=sys.stderr)
    return

  return json.loads(resp.text)

#
# ShaderToy's unofficial/internal API endpoint
# (NOTE: as of today (2020/02/04), it works as long as you set any same origin 'Referer' in header)
#
def scrape_v2(id):
  req_args = dict(
    url     = 'https://www.shadertoy.com/shadertoy',
    headers = { 'Referer': 'https://www.shadertoy.com' },
    data    = { 's': json.dumps({ 'shaders': [id] }) }
  )
  resp = requests.post(**req_args)
  if not resp.status_code == requests.codes.ok:
    print(f"[scrape_v2] Error\n{resp.text}", file=sys.stderr)
    return None

  return json.loads(resp.text)


def download(id, key):
  url = f"https://www.shadertoy.com/api/v1/shaders/{id}"
  url_with_key = f"{url}?key={key}"
  print(f"[download] {url_with_key}", file=sys.stderr)

  resp = requests.get(url_with_key)

  fallback_to_scrape = False
  shader_info = None  # dict
  shader_passes = []  # [str]

  if not resp.status_code == requests.codes.ok:
    print(f"[download] HTTP error\n{resp.text}", file=sys.stderr)
    fallback_to_scrape = True
  else:
    resp_json = json.loads(resp.text)
    if resp_json.get('Error'):
      print(f"[download] API error\n{resp_json}", file=sys.stderr)
      fallback_to_scrape = True
    else:
      assert resp_json['Shader'] and \
             resp_json['Shader']['info'] and \
             resp_json['Shader']['renderpass']
      shader_info   = resp_json['Shader']['info']
      shader_passes = [
          data['code'] for data in resp_json['Shader']['renderpass']]

  if fallback_to_scrape:
    print(f"[download] Fallback to scrape_v2", file=sys.stderr)
    resp_json = scrape_v2(id)
    if resp_json:
      assert resp_json[0] and \
             resp_json[0]['info'] and \
             resp_json[0]['renderpass']
      shader_info   = resp_json[0]['info']
      shader_passes = [
          data['code'] for data in resp_json[0]['renderpass']]

  if not shader_info:
    print(f"[download] download unsucceeded", file=sys.stderr)
    return

  # Emit info
  header = TEMPLATE_HEADER.format(
      url=f"https://www.shadertoy.com/view/{id}",
      info=json.dumps(shader_info, indent=2))
  print(header)

  # Emit renderpass
  for i, code in enumerate(shader_passes):
    print(TEMPLATE_RENDERPASS.format(i=i, code=code))

  print(f"[download] download succeeded", file=sys.stderr)


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
