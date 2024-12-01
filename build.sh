# arm
# eval "$(/opt/homebrew/bin/brew shellenv)"

# # intel
# eval "$(/usr/local/bin/brew shellenv)"

pyinstaller --optimize 2 --onefile --add-data "data:./data" --add-data "bg.gif:." --disable-windowed-traceback --add-data "icon.icns:." --windowed --icon=icon.icns background.py --noconfirm