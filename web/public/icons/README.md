# PWA Icons

Place the following PNG files here before deploying:

| File | Size | Notes |
|------|------|-------|
| `icon-192.png` | 192×192 | Android home screen, PWA |
| `icon-512.png` | 512×512 | Splash screen, app store |
| `icon-180.png` | 180×180 | Apple Touch Icon |

Design notes:
- Background: #059669 (Tailwind emerald-600)
- Foreground: white letter "ل" (Urdu lam) in Noto Nastaliq Urdu
- Use maskable safe zone (80% inner circle) for `purpose: "maskable"`
- Export from Figma / Canva / any editor as PNG with transparency

Quick placeholder (generates a green square with "L"):
```bash
# macOS / Linux (requires ImageMagick)
convert -size 512x512 xc:#059669 -font DejaVu-Sans-Bold -pointsize 300 \
  -fill white -gravity Center -annotate 0 "L" icon-512.png
convert icon-512.png -resize 192x192 icon-192.png
convert icon-512.png -resize 180x180 icon-180.png
```
