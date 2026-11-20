#!/usr/bin/env python3
# tap.py <ui.xml> <regex> — tap center of first node whose text/desc matches
import re, subprocess, sys
import xml.etree.ElementTree as ET

xmlf, pat = sys.argv[1], sys.argv[2]
root = ET.parse(xmlf).getroot()
rx = re.compile(pat, re.I)
for n in root.iter('node'):
    blob = ' '.join(filter(None, [n.get('text'), n.get('content-desc')]))
    b = n.get('bounds') or ''
    m = re.match(r'\[(-?\d+),(-?\d+)\]\[(-?\d+),(-?\d+)\]', b)
    if blob and rx.search(blob) and m:
        x = (int(m.group(1)) + int(m.group(3))) // 2
        y = (int(m.group(2)) + int(m.group(4))) // 2
        print('TAP %r -> %d,%d' % (blob, x, y))
        subprocess.run(['adb', 'shell', 'input', 'tap', str(x), str(y)], check=False)
        sys.exit(0)
print('NOTFOUND %s' % pat)
sys.exit(1)
