#!/usr/bin/env python3

import re
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as f:
    s = f.read()

if "web_file_manager" in s:
    sys.exit(0)

item = '''
\t\t\t\t<listitem name="Web File Manager">
\t\t\t\t\t<icon res="rwa"/>
\t\t\t\t\t<action function="page">web_file_manager</action>
\t\t\t\t</listitem>
'''

m = re.search(r'[ \t]*<listitem name="Remote Web Access">.*?</listitem>\n', s, re.S)
if not m:
    m = re.search(
        r'[ \t]*<listitem[^>]*>\s*<icon[^>]*/>\s*'
        r'<action function="page">remote_web_access_settings</action>\s*</listitem>\n',
        s, re.S)
if not m:
    sys.exit(1)

s = s[:m.end()] + item + s[m.end():]

page = '''
\t\t<!-- TWRP Web File Manager (microhttpd) -->
\t\t<page name="web_file_manager">
\t\t\t<template name="base"/>

\t\t\t<text style="text_ab_title">
\t\t\t\t<placement x="%col1_x_indent%" y="%ab_bc_y%"/>
\t\t\t\t<text>Web File Manager</text>
\t\t\t</text>

\t\t\t<text style="text_body2_hl">
\t\t\t\t<placement x="%gl_text_x%" y="%row2_1_y%"/>
\t\t\t\t<text>Start the server, then open http://&lt;phone-IP&gt;:8080/ in your browser.</text>
\t\t\t</text>

\t\t\t<listbox style="group_list">
\t\t\t\t<placement x="0" y="%row2_3a_y%" w="%screen_w%" h="600"/>

\t\t\t\t<listitem name="Start Web File Manager">
\t\t\t\t\t<icon res="rwa"/>
\t\t\t\t\t<action function="cmd">setprop ctl.start microhttpd</action>
\t\t\t\t\t<action function="page">web_file_manager</action>
\t\t\t\t</listitem>

\t\t\t\t<listitem name="Stop Web File Manager">
\t\t\t\t\t<icon res="rwa"/>
\t\t\t\t\t<action function="cmd">setprop ctl.stop microhttpd</action>
\t\t\t\t\t<action function="page">web_file_manager</action>
\t\t\t\t</listitem>
\t\t\t</listbox>

\t\t\t<template name="gestures"/>

\t\t\t<action>
\t\t\t\t<touch key="home"/>
\t\t\t\t<action function="page">main</action>
\t\t\t</action>

\t\t\t<action>
\t\t\t\t<touch key="back"/>
\t\t\t\t<action function="page">wlan</action>
\t\t\t</action>
\t\t</page>
'''

if "\t</pages>" not in s:
    sys.exit(1)

s = s.replace("\t</pages>", page + "\n\t</pages>", 1)

with open(path, "w", encoding="utf-8") as f:
    f.write(s)
