TEMPLATE_HEADER = f"""
//
// AUTO GENERATED
//
""".strip()
TEMPLATE_FONT = "SDF_FONT({name},{commands})"
TEMPLATE_LINE = "SDF_FONT_LINE({x0}, {y0}, {x1}, {y1})"
TEMPLATE_ARC  = "SDF_FONT_ARC ({cx}, {cy}, {r}, {t0}, {t1})"
TEMPLATE_FONT_LIST_NAMES = "#define FONT_LIST_NAMES(_){names}"
TEMPLATE_FONT_NUM_NAMES = "#define FONT_NUM_NAMES {num}"


def main():
  from sys import stdin
  from types import SimpleNamespace
  import re

  result = ''
  result += TEMPLATE_HEADER
  result += '\n\n'

  # Parse line by line
  state = SimpleNamespace(codepoint=None, commands=[], codepoints=[])
  for line in stdin.read().splitlines():
    # Look for start <g id="...">
    if state.codepoint is None:
      if m := re.match("<g id=\"(.*?)\"", line.strip()):
        name = m.group(1)
        if name[0] != '_':
          state.codepoint = name

    else:
      # Read children of <g ...>
      if m := re.match("<path d=\"(.*?)\"", line.strip()):
        tokens = m.group(1).split()

        # LINE command e.g. <path d="M 0 2  L 0 0"/>
        if tokens[0] == 'M' and tokens[3] == 'L':
          data = dict(
              x0=tokens[1],
              y0=tokens[2],
              x1=tokens[4],
              y1=tokens[5])
          state.commands += [TEMPLATE_LINE.format(**data)]

        # ARC command from comment e.g. <!-- arc 1 1  1  0.5 0.25 -->
        if tokens[0] == 'M' and tokens[3] == 'A':
          m = re.search("<!-- arc (.*) -->", line.strip())
          assert m, f"'arc' comment not found: {line}"
          comment_tokens = [float(_) for _ in m.group(1).split()]
          data = dict(
              cx=comment_tokens[0],
              cy=comment_tokens[1],
              r =comment_tokens[2],
              t0=comment_tokens[3],
              t1=comment_tokens[4])
          state.commands += [TEMPLATE_ARC.format(**data)]


      # Get out of <g ....> and emit data
      if re.match("</g>", line.strip()):
        data = dict(
            name=state.codepoint,
            commands='\n  ' +  '\n  '.join(state.commands))
        result += TEMPLATE_FONT.format(**data)
        result += '\n\n'
        state.codepoints += [state.codepoint]
        state.codepoint = None
        state.commands = []

  # Finally emit some statistics
  names = ''.join([f" \\\n  _({name})" for name in state.codepoints])
  result += TEMPLATE_FONT_LIST_NAMES.format(names=names)
  result += '\n\n'
  result += TEMPLATE_FONT_NUM_NAMES.format(num=len(state.codepoints))
  print(result)

if __name__ == '__main__':
  main()
