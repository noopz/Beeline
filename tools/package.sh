#!/usr/bin/env bash
# The release zip: the addon (without its tests) and the built-in plans, nothing else (no planner, no companion).
# usage: tools/package.sh [version]   -> dist/Beeline-<version>.zip   (version default: the TOC's)
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
VER="${1:-$(sed -n 's/^## Version: *//p' addon/Beeline/Beeline.toc | tr -d '\r')}"
rm -rf dist && mkdir -p dist/pkg
node tools/gen-news.js >/dev/null # the in-game what's new, from CHANGELOG.md
cp -r addon/Beeline dist/pkg/
rm -rf dist/pkg/Beeline/tests
# your own plan (the companion writes it) is never shipped
rm -f dist/pkg/Beeline/Route.lua
# ...nor listed in the TOC: the game warns "Error loading Beeline/Route.lua" on every load for a file that an
# addon-site install never has (the built-in plan is used then). The companion's own install (tools/install.sh) keeps the line
T=dist/pkg/Beeline/Beeline.toc; grep -v '^Route[.]lua' "$T" > "$T.new" && mv "$T.new" "$T"
if grep -q '^Route.lua' dist/pkg/Beeline/Beeline.toc; then echo "package: Route.lua still in the TOC"; exit 1; fi
sed -i "s/^## Version: .*/## Version: $VER/" dist/pkg/Beeline/Beeline.toc
# the built-in plans as two addons, one per faction (tools/bundle-plans.js): 51 one-per-plan addons filled the addon list
node tools/bundle-plans.js dist/pkg >/dev/null || { echo "package: bundling the plans failed"; exit 1; }
# every built-in plan nests under Beeline in the game's addon list (## Group), or 51 entries fill it
missing=$(grep -L '^## Group: Beeline' dist/pkg/Beeline_Plans_*/*.toc 2>/dev/null); if [ -n "$missing" ]; then echo "package: built-in plans without ## Group: $missing"; exit 1; fi
# the licenses (NOTICE says which is which): the addon is CC BY-NC-SA with a few GPL quest-data files; each built-in
# plan is all quest data, so GPL
cp LICENSE dist/pkg/Beeline/LICENSE
cp LICENSES/GPL-3.0.txt dist/pkg/Beeline/LICENSE-GPL-3.0.txt
cp NOTICE dist/pkg/Beeline/NOTICE
# the old saves (Beeline was ForeverRoute until 2.0): an empty addon by the old name, so Beeline can read them once
# (Migrate.lua). It takes the old ForeverRoute folder's place - an app update or unzipping over it
cp -r addon/ForeverRoute dist/pkg/
grep -q "^## X-Beeline-Stub: 1" dist/pkg/ForeverRoute/ForeverRoute.toc || { echo "package: addon/ForeverRoute is not the empty one"; exit 1; }
[ "$(ls dist/pkg/ForeverRoute | xargs)" = "Bindings.xml Core.lua ForeverRoute.toc" ] || { echo "package: addon/ForeverRoute has more than its TOC, Core.lua and Bindings.xml"; exit 1; }
for d in dist/pkg/Beeline_Plans_*/; do cp LICENSES/GPL-3.0.txt "$d/LICENSE-GPL-3.0.txt"; cp NOTICE "$d/NOTICE"; done
# the outdoor zones' walk maps for the map line: one load-on-demand addon per continent (tools/navgrid.js); their
# hostile-spawn layer is from the quest data, so GPL as well
nav=0
for d in addon/Beeline_Nav*/; do
  n=$(basename "$d"); cp -r "$d" dist/pkg/; nav=$((nav + 1))
  sed -i "s/^## Version: .*/## Version: $VER/" "dist/pkg/$n/$n.toc"
  grep -q '^## LoadOnDemand: 1' "dist/pkg/$n/$n.toc" || { echo "package: $n is not load-on-demand"; exit 1; }
  cp LICENSES/GPL-3.0.txt "dist/pkg/$n/LICENSE-GPL-3.0.txt"; cp NOTICE "dist/pkg/$n/NOTICE"
done
[ "$nav" -eq 2 ] || { echo "package: expected the two walk-map addons (Beeline_NavEK, Beeline_NavKalimdor), found $nav"; exit 1; }
# the Detailed map line's navigation meshes (an option, off by default): one load-on-demand addon per continent with the
# zones that pass the audit (tools/navmesh.js ship); baked from the walk maps alone, so CC BY-NC-SA like the addon
mesh=0
for d in addon/Beeline_Mesh*/; do
  n=$(basename "$d"); cp -r "$d" dist/pkg/; mesh=$((mesh + 1))
  sed -i "s/^## Version: .*/## Version: $VER/" "dist/pkg/$n/$n.toc"
  grep -q '^## LoadOnDemand: 1' "dist/pkg/$n/$n.toc" || { echo "package: $n is not load-on-demand"; exit 1; }
  grep -q '^## Dependencies: Beeline' "dist/pkg/$n/$n.toc" || { echo "package: $n does not depend on Beeline"; exit 1; }
  cp LICENSE "dist/pkg/$n/LICENSE"; cp NOTICE "dist/pkg/$n/NOTICE"
done
[ "$mesh" -eq 2 ] || { echo "package: expected the two mesh addons (Beeline_MeshEK, Beeline_MeshKalimdor), found $mesh"; exit 1; }
if command -v zip >/dev/null; then (cd dist/pkg && zip -qr "../Beeline-$VER.zip" .)
else powershell -NoProfile -Command "Compress-Archive -Path 'dist/pkg/*' -DestinationPath 'dist/Beeline-$VER.zip'"; fi
echo "dist/Beeline-$VER.zip: $(ls dist/pkg | wc -l) addon folders"
