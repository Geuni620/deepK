#!/usr/bin/env python3
"""Offline coverage and placeholder checks for the app's explicitly localized UI."""
import json
from pathlib import Path
import re

root = Path(__file__).resolve().parent.parent
catalog = json.loads((root / 'DeepK/Localizable.xcstrings').read_text())
strings = catalog['strings']
locales = ('ko', 'en', 'ja', 'zh-Hant')
assert catalog['sourceLanguage'] == 'ko'
for key, entry in strings.items():
    placeholders = sorted(re.findall(r'%\d+\$@', key))
    for locale in locales:
        unit = entry['localizations'][locale]['stringUnit']
        assert unit['value'].strip(), (key, locale, 'empty translation')
        assert sorted(re.findall(r'%\d+\$@', unit['value'])) == placeholders, (key, locale, 'placeholder mismatch')

used = set()
pattern = re.compile(r'DK(?:Localized|Format)\(("(?:[^"\\\n]|\\.)*")')
for source in (root / 'DeepK').rglob('*.swift'):
    for line in source.read_text().splitlines():
        if line.lstrip().startswith('//'):
            continue
        for match in pattern.finditer(line):
            key = json.loads(match[1])
            assert key in strings, (source.relative_to(root), key, 'missing catalog key')
            used.add(key)
print(f'Localization coverage passed: {len(used)} referenced keys; {len(strings)} entries; {len(locales)} locales; placeholders preserved')
