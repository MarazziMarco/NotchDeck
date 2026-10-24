import math, os, sys
OUT = sys.argv[1]
COLORS = {"notchdeck": ("#FFA64D", "#F0541E"), "arcus": ("#A58BFF", "#5A3CF0"),
          "launchpad": ("#46DDD6", "#1688B0"), "facekey": ("#4BDB8C", "#11935A")}
FILL, DIM = "#FFFFFF", "rgba(255,255,255,.62)"

def seg(cx, cy, ro, ri, a0, a1):
    p = lambda R, a: (cx + R * math.cos(math.radians(a)), cy + R * math.sin(math.radians(a)))
    (x0, y0), (x1, y1), (x2, y2), (x3, y3) = p(ro, a0), p(ro, a1), p(ri, a1), p(ri, a0)
    return f"M{x0:.1f} {y0:.1f}A{ro} {ro} 0 0 1 {x1:.1f} {y1:.1f}L{x2:.1f} {y2:.1f}A{ri} {ri} 0 0 0 {x3:.1f} {y3:.1f}Z"

def glyph(app):
    f, d = FILL, DIM
    if app == "notchdeck":
        return f'''<rect x="232" y="296" width="560" height="430" rx="78" fill="none" stroke="{d}" stroke-width="34"/>
<path d="M402 296 h220 v34 a40 40 0 0 1 -40 40 h-140 a40 40 0 0 1 -40 -40z" fill="{d}"/>
<rect x="337" y="404" width="350" height="128" rx="64" fill="{f}"/>
<rect x="377" y="566" width="270" height="34" rx="17" fill="{d}" opacity=".8"/>
<rect x="417" y="626" width="190" height="34" rx="17" fill="{d}" opacity=".55"/>'''
    if app == "arcus":
        s = ""
        for i in range(6):
            a0 = -90 + i * 60 + 5
            s += f'<path d="{seg(512, 520, 262, 142, a0, a0 + 50)}" fill="{f if i == 0 else d}" opacity="{1 if i == 0 else .75}"/>\n'
        return s + f'<circle cx="512" cy="520" r="66" fill="{f}"/>'
    if app == "launchpad":
        s = f'<rect x="262" y="262" width="300" height="300" rx="64" fill="{f}"/>\n'
        for x, y, h in [(602, 262, 110), (602, 412, 150), (262, 602, 160), (412, 602, 160), (602, 602, 160)]:
            s += f'<rect x="{x}" y="{y}" width="160" height="{h}" rx="40" fill="{d}"/>\n'
        return s
    if app == "facekey":
        k = f'stroke="{d}" stroke-width="34" stroke-linecap="round" fill="none"'
        return f'''<path d="M262 382 v-60 a60 60 0 0 1 60 -60 h60" {k}/><path d="M642 262 h60 a60 60 0 0 1 60 60 v60" {k}/>
<path d="M762 642 v60 a60 60 0 0 1 -60 60 h-60" {k}/><path d="M382 762 h-60 a60 60 0 0 1 -60 -60 v-60" {k}/>
<path d="M372 452 a20 20 0 0 1 20 -20 h50 v28 a24 24 0 0 0 24 24 h92 a24 24 0 0 0 24 -24 v-28 h50 a20 20 0 0 1 20 20 v196 a52 52 0 0 1 -52 52 h-176 a52 52 0 0 1 -52 -52z" fill="{f}"/>
<circle cx="512" cy="560" r="34" fill="{COLORS['facekey'][1]}"/><rect x="497" y="578" width="30" height="62" rx="15" fill="{COLORS['facekey'][1]}"/>'''

def icon(app):
    c0, c1 = COLORS[app]
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
<!-- Suite icon, direction B ("famiglia a colori"): shared tile, light and glyph style; one hue per app. -->
<defs>
<linearGradient id="bg" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="{c0}"/><stop offset="1" stop-color="{c1}"/></linearGradient>
<filter id="tile" x="-10%" y="-10%" width="120%" height="125%"><feDropShadow dx="0" dy="14" stdDeviation="18" flood-color="#000" flood-opacity=".35"/></filter>
<filter id="glyph" x="-20%" y="-20%" width="140%" height="140%"><feDropShadow dx="0" dy="10" stdDeviation="14" flood-color="#000" flood-opacity=".25"/></filter>
</defs>
<rect x="100" y="100" width="824" height="824" rx="185" fill="url(#bg)" filter="url(#tile)"/>
<rect x="101.5" y="101.5" width="821" height="821" rx="184" fill="none" stroke="rgba(255,255,255,.16)" stroke-width="3"/>
<g filter="url(#glyph)">
{glyph(app)}
</g>
</svg>
'''

os.makedirs(OUT, exist_ok=True)
for app in COLORS:
    open(os.path.join(OUT, f"{app}.svg"), "w").write(icon(app))
print("ok")
