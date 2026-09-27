// Run with: node tools/audit_ka_vector_basemap.cjs <topojson-client directory>
const fs = require('fs');
const crypto = require('crypto');
const topo = require(require('path').resolve(process.argv[2]));
for (const name of ['medium.global.modified.topo.json', 'jp.pref.topo.json', 'cn.province.topo.json']) {
  const path = `assets/maps/ka/${name}`;
  const bytes = fs.readFileSync(path);
  const data = JSON.parse(bytes);
  const features = topo.feature(data, data.objects.region).features;
  const canonical = [];
  let rings = 0, points = 0;
  for (const feature of features) {
    const polygons = feature.geometry.type === 'Polygon' ? [feature.geometry.coordinates] : feature.geometry.coordinates;
    for (const polygon of polygons) {
      canonical.push([feature.properties.name, polygon.map(ring => {
        rings++; points += ring.length;
        return ring.map(([x, y]) => [x.toFixed(9), y.toFixed(9)]);
      })]);
    }
  }
  const hash = value => crypto.createHash('sha256').update(value).digest('hex');
  console.log(JSON.stringify({name, bytes:bytes.length, sha256:hash(bytes),
    polygons:canonical.length, rings, points, arcs:data.arcs.length,
    canonicalSha256:hash(JSON.stringify(canonical))}));
}
