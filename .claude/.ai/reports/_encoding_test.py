import sys
samples = [
    "InfusiÃn Tila Hacendado",
    "Agua de soda con sifÃn La Casa",
    "DentÃfrico 3 action Deliplus",
    "Gel de baÃo marino y cedro Deliplus piel normal",
    "InfusiÃn CÃrcuma Hacendado con manzana y canela",
]

def try_combo(s, src, dst, errors='strict'):
    try:
        return s.encode(src, errors=errors).decode(dst, errors=errors)
    except Exception as e:
        return None

combos = [
    ('latin-1', 'utf-8'),
    ('cp1252', 'utf-8'),
    ('utf-8', 'latin-1'),
    ('utf-8', 'cp1252'),
]

for s in samples:
    line = f"ORIG: {s}\n"
    sys.stdout.buffer.write(line.encode('utf-8'))
    for src, dst in combos:
        t = try_combo(s, src, dst)
        if t and t != s:
            line = f"  {src}->{dst}: {t}\n"
            sys.stdout.buffer.write(line.encode('utf-8'))
    # Try ftfy if available
    try:
        import ftfy
        t = ftfy.fix_text(s)
        if t != s:
            line = f"  ftfy: {t}\n"
            sys.stdout.buffer.write(line.encode('utf-8'))
    except ImportError:
        pass
    sys.stdout.buffer.write(b"\n")

# Analyze byte structure of one mojibake char
print("=== BYTE ANALYSIS ===")
s = samples[0]  # "InfusiÃn Tila Hacendado"
for i, ch in enumerate(s):
    if ord(ch) > 127:
        print(f"  pos {i}: char={ch!r} codepoint={hex(ord(ch))}")

# Check ftfy availability
try:
    import ftfy
    print(f"\nftfy version: {ftfy.__version__}")
except ImportError:
    print("\nftfy NOT INSTALLED")
