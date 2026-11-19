# Gera o logo do Qolly: docs/logo.png (512, para o CurseForge) e Media/Logo.tga (64, ícone
# na lista de addons). Uso: python tools/make_logo.py docs/logo.png Media/Logo.tga
import sys
from PIL import Image, ImageDraw, ImageFont, ImageFilter, ImageChops

out_png, out_tga = sys.argv[1], sys.argv[2]
S = 1024
R = 190  # raio dos cantos


def rounded_mask(size, inset, radius):
    m = Image.new("L", (size, size), 0)
    ImageDraw.Draw(m).rounded_rectangle((inset, inset, size - 1 - inset, size - 1 - inset), radius, fill=255)
    return m


def vertical_gradient(size, top, bottom):
    g = Image.new("RGB", (1, size))
    for y in range(size):
        t = y / (size - 1)
        g.putpixel((0, y), tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3)))
    return g.resize((size, size))


def radial(size, inner, outer, cx=0.5, cy=0.4):
    img = Image.new("RGB", (size, size))
    px = img.load()
    maxd = (size * 0.75) ** 2
    for y in range(size):
        for x in range(size):
            d = min(1.0, ((x - size * cx) ** 2 + (y - size * cy) ** 2) / maxd)
            px[x, y] = tuple(int(inner[i] + (outer[i] - inner[i]) * d) for i in range(3))
    return img


logo = Image.new("RGBA", (S, S), (0, 0, 0, 0))

# Moldura dourada (degradê de cima para baixo) e fundo azul-escuro radial por dentro.
gold = vertical_gradient(S, (255, 226, 130), (150, 100, 25)).convert("RGBA")
logo.paste(gold, (0, 0), rounded_mask(S, 0, R))
dark_edge = Image.new("RGBA", (S, S), (40, 26, 6, 255))
logo.paste(dark_edge, (0, 0), rounded_mask(S, 44, R - 40))
bg = radial(S, (32, 70, 110), (6, 14, 28)).convert("RGBA")
logo.paste(bg, (0, 0), rounded_mask(S, 56, R - 50))

# Brilho suave atrás das letras.
glow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
ImageDraw.Draw(glow).ellipse((210, 230, 814, 800), fill=(90, 190, 255, 90))
glow = glow.filter(ImageFilter.GaussianBlur(90))
logo = Image.alpha_composite(logo, glow)

# "Qy": letras com degradê azul, contorno escuro e sombra.
font = ImageFont.truetype("C:/Windows/Fonts/georgiab.ttf", 560)
text = "Qy"
probe = ImageDraw.Draw(Image.new("L", (S, S)))
box = probe.textbbox((0, 0), text, font=font)
w, h = box[2] - box[0], box[3] - box[1]
x = (S - w) / 2 - box[0]
y = (S - h) / 2 - box[1] - 10

mask = Image.new("L", (S, S), 0)
ImageDraw.Draw(mask).text((x, y), text, font=font, fill=255)

shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
shadow.putalpha(mask.filter(ImageFilter.MaxFilter(25)).filter(ImageFilter.GaussianBlur(14)).point(lambda v: v * 0.85))
shadow = ImageChops.offset(shadow, 0, 16)
logo = Image.alpha_composite(logo, shadow)

outline = Image.new("RGBA", (S, S), (8, 22, 40, 255))
outline.putalpha(mask.filter(ImageFilter.MaxFilter(19)))
logo = Image.alpha_composite(logo, outline)

fill = vertical_gradient(S, (215, 245, 255), (40, 150, 225)).convert("RGBA")
fill.putalpha(mask)
logo = Image.alpha_composite(logo, fill)

# Reflexo na metade de cima das letras.
shine = Image.new("RGBA", (S, S), (255, 255, 255, 0))
band = Image.new("L", (S, S), 0)
ImageDraw.Draw(band).rectangle((0, 0, S, int(y + box[1] + h * 0.42)), fill=70)
shine.putalpha(ImageChops.multiply(band, mask))
logo = Image.alpha_composite(logo, shine)

logo.resize((512, 512), Image.LANCZOS).save(out_png)
logo.resize((64, 64), Image.LANCZOS).save(out_tga)
print("ok")
