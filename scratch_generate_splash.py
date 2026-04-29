from PIL import Image, ImageDraw, ImageFont

width, height = 1080, 1920
image = Image.new("RGB", (width, height), "#1a1a1a")
draw = ImageDraw.Draw(image)

text = "ABYSS"

# Try to use an elegant serif font
font_paths = [
    "C:/Windows/Fonts/georgiab.ttf",  # Georgia Bold
    "C:/Windows/Fonts/timesbd.ttf",   # Times New Roman Bold
    "C:/Windows/Fonts/arialbd.ttf"    # Fallback to Arial Bold
]

font = None
for path in font_paths:
    try:
        font = ImageFont.truetype(path, 180)
        break
    except IOError:
        continue

if font is None:
    font = ImageFont.load_default()

# Get text bounding box
bbox = draw.textbbox((0, 0), text, font=font)
text_width = bbox[2] - bbox[0]
text_height = bbox[3] - bbox[1]

# Center text
x = (width - text_width) / 2
y = (height - text_height) / 2 - 50 # slightly above absolute center often looks better visually

# Draw text with faint glow effect
glow_color = (255, 255, 255, 50)
text_color = (255, 255, 255, 255)

# Faint glow (draw text slightly offset multiple times)
glow_radius = 4
for dx in range(-glow_radius, glow_radius + 1):
    for dy in range(-glow_radius, glow_radius + 1):
        if dx == 0 and dy == 0:
            continue
        # Use a secondary image with alpha for the glow if we wanted perfect blur, 
        # but simple offset drawing works for a subtle faint glow
        draw.text((x + dx, y + dy), text, font=font, fill=(100, 100, 100))

# Draw main text
draw.text((x, y), text, font=font, fill=(255, 255, 255))

image.save("assets/abyss_splash.png")
print("Saved assets/abyss_splash.png")
