"""Copy the compiled MoonBit browser entry beside the static local page."""
from pathlib import Path
import shutil
root=Path(__file__).resolve().parents[1]
source=root/'_build/js/debug/build/web/core/core.js'
assert source.exists(), 'Run moon build --target js first'
shutil.copyfile(source,root/'web/moonstdf.js')
print('Open web/index.html locally; no server or upload required')
