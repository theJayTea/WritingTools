#!/usr/bin/bash
set -euo pipefail

# We generate .pot files from all python scripts...
xgettext --language=Python --keyword=_ WritingToolApp.py -o pot_files/WritingToolApp.pot
for file in ui/*.py; do
  output="${file#ui/}"
  output="${output%.py}.pot"
  xgettext --language=Python --keyword=_ "$file" -o "pot_files/$output"
done

# ... merge them into a single .pot file...
msgcat pot_files/*.pot -o pot_files/merged.pot

# ... and update the .po files with the new strings.
for locale in locales/*; do
  echo -n "Updating $locale translation files"
  msgmerge --update "$locale/LC_MESSAGES/messages.po" pot_files/merged.pot
  echo -n "Compiling $locale translation files............"
  msgfmt -o "$locale/LC_MESSAGES/messages.mo" "$locale/LC_MESSAGES/messages.po"
  echo " done."
done
