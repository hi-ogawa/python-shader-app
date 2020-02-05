Download all hdr files from http://www.pauldebevec.com/Probes/

```
curl -H 'user-agent:' http://www.pauldebevec.com/Probes/  \
| python -c 'import sys, re; print(*set(re.findall(r"HREF=\"(.*\.hdr)\"", sys.stdin.read())))'  \
| xargs -d ' ' -I@  wget -P . http://www.pauldebevec.com/Probes/@
```
