"""Attribute linked bytes (alloc sections only) in an lld map to their source library; also report .eh_frame share."""
import re, sys, collections
def cat(path):
    for key, name in [('Models50Loop.', 'Models50Loop (generated classes, forEach)'), ('Models50.', 'Models50 (generated classes)'),
                      ('Codable50D.', 'Codable50D (Decodable-only structs)'), ('Codable50.', 'Codable50 (Codable structs)'),
                      ('CYYJSON', 'CYYJSON (yyjson C)'), ('YYLite.', 'YYLite (Swift core)')]:
        if key in path: return name
    if 'FoundationICU' in path: return 'ICU'
    if 'Foundation' in path: return 'Foundation (in OS on iOS)'
    if 'libswift' in path: return 'Swift runtime/stdlib (in OS on iOS)'
    if 'libc++' in path or 'libunwind' in path: return 'C++ runtime'
    if '-p.build' in path or 'main' in path: return 'main'
    return 'libc/other'
ln = re.compile(r'^\s*[0-9a-f]+\s+[0-9a-f]+\s+([0-9a-f]+)\s+\d+\s{9}(\S.*):\(([^)]*)\)\s*$')
osec = re.compile(r'^\s*[0-9a-f]+\s+[0-9a-f]+\s+[0-9a-f]+\s+\d+ (\S+)\s*$')
out = collections.Counter(); eh = collections.Counter(); skip = False
for line in open(sys.argv[1]):
    o = osec.match(line)
    if o:
        skip = o.group(1).startswith(('.debug', '.comment', '.symtab', '.strtab', '.shstrtab', '.bss', '.tbss')); continue
    if skip: continue
    m = ln.match(line)
    if m and not m.group(3).startswith(('.bss', '.tbss')):
        c = cat(m.group(2)); n = int(m.group(1), 16); out[c] += n
        if m.group(3).startswith('.eh_frame'): eh[c] += n
for k, v in sorted(out.items(), key=lambda x: -x[1]):
    if 'OS on iOS' in k or k in ('libc/other', 'C++ runtime', 'ICU'): continue
    print(f"{v:>10}  {k}   (eh_frame {eh[k]}, without {v - eh[k]})")
