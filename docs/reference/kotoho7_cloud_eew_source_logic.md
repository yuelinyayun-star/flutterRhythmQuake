# kotoho7 Scratch cloud / EEW / `円の中トリガ` source logic

Source inspected:

- `.dart_tool/external_refs/scratch-realtime-earthquake-viewer-page/docs/assets/project.json`
- target: `受信と検出`

This note is about the Scratch source logic, not live cloud values.

## 1. Cloud variable declarations

The Stage declares these cloud variables:

```text
☁ url
☁ c2h
☁ c2b0
☁ c2b1
☁ c2b2
☁ c2b3
☁ c2b4
☁ c2b5
☁ c2b6
☁ c2b7
☁ c2u
☁ open link
☁ eval
```

Packager cloud hosts/IDs are loaded from:

```text
https://gist.githubusercontent.com/kotoho7/039aaef1782ef4a7db80f8876c5bef5f/raw/srev-csi.json
```

Current CSI content:

```json
{
  "hosts": [
    "wss://clouddata-srev.kothn.net",
    "wss://clouddata.turbowarp.org",
    "wss://clouddata.turbowarp.xyz"
  ],
  "ids": [
    "kotoho7.github.io/srev",
    "kotoho7.github.io/srev/2"
  ]
}
```

## 2. `クラウド変数更新したら`

This is the top-level receive/update procedure.

### Sync / packet-valid gate

If `☁ c2h` is long enough:

```text
if len(☁ c2h) > 256:
  accept
```

Otherwise it requires the first character of every body packet to match, and
also match `letter(45, ☁ c2h)`:

```text
head = letter(1, ☁ c2b0)
if head == letter(1, ☁ c2b1)
 and head == letter(1, ☁ c2b2)
 and head == letter(1, ☁ c2b3)
 and head == letter(1, ☁ c2b4)
 and head == letter(1, ☁ c2b5)
 and head == letter(1, ☁ c2b6)
 and head == letter(1, ☁ c2b7)
 and head == letter(45, ☁ c2h):
   accept
```

### Header routing

When accepted, it extracts:

```text
cloud time / receive id = ☁ c2h[1..10]

#r:最新クラウド変数[2] = ☁ c2h[11..50]
#r:最新クラウド変数[5] = ☁ c2h[51..256]
#受信バージョン          = ☁ c2h[43..44]
```

`#受信バージョン` is read from absolute `☁ c2h[43..44]`, so it is inside the
same 40-character header span copied to `#r[2]`, not after it.

The exact Scratch call is:

```text
雲変化(カウント3, ☁ c2h[11..50], 2, compare-by-content, "")
雲変化(カウント3, ☁ c2h[51..256], 5, compare-by-content, "")
```

### Body routing

For long `c2h`, it calls `雲変化チェック` directly:

```text
雲変化チェック(☁ c2b0, 3, no content compare)
雲変化チェック(☁ c2b1, 4, no content compare)
雲変化チェック(☁ c2b2, 6, content compare)
雲変化チェック(☁ c2b4, 8, no content compare)
雲変化チェック(☁ c2b5, 7, content compare)
雲変化チェック(☁ c2b6, 9, content compare)
```

For the shorter combined-body route, it concatenates `c2b0..c2b7[2..256]`
into `多目的2`, then routes by `letter(50, ☁ c2h)`:

```text
letter(50, ☁ c2h) == 0 -> #r[3]
letter(50, ☁ c2h) == 1 -> #r[4]
letter(50, ☁ c2h) == 2 -> #r[6]
letter(50, ☁ c2h) == 4 -> #r[8]
letter(50, ☁ c2h) == 5 -> #r[7]
letter(50, ☁ c2h) == 6 -> #r[9]
```

## 3. `雲変化` and `雲変化チェック`

`雲変化` is the central list write:

```text
if 内容比較 and ("a" + 内容) == ("a" + #r:最新クラウド変数[番号]):
  stop this script

if #リプレイモード == 0:
  @前回ループ = 0
  #r:最新クラウド変数[番号] = 内容
  #r:更新済み[番号] = 1
  #r:更新済み[10 + 番号] = 識別番号 + 2000s
```

`雲変化チェック` validates the raw body packet envelope:

```text
if 雲[14..20] == "6244032":
  packet_time = 雲[1..10]
  packet_id   = 雲[11..13]
  content     = 雲[21..len(雲)]

  if #r:更新済み[10 + 番号] != packet_id + packet_time:
    雲変化(packet_time, content, 番号, 内容比較あり, packet_id)
```

This is why raw `☁ c2b2` is not directly equivalent to `#r[2]` or `0EEW`.
It is first envelope-checked and routed to one of the `#r` slots.

## 4. `EEW %s %s`

`EEW(内容, おふせ)` parses a cloud content string into `0EEW` and
`0-2EEW追加情報`.

Confirmed writes:

```text
0EEW[おふせ + 1]  = letter(1, 内容) mod 2
0EEW[おふせ + 2]  = floor(letter(1, 内容) / 2) mod 2
0EEW[おふせ + 3]  = id/report number from 内容[27..29] or "l"
0EEW[おふせ + 4]  = 内容[2..4]
0EEW[おふせ + 5]  = 内容[5..14] (+2 under one flag)
0EEW[おふせ + 6]  = 内容[15..17] / 10 + 86      # longitude-like
0EEW[おふせ + 7]  = 内容[18..20] / 10           # latitude-like
0EEW[おふせ + 8]  = 内容[21..23], or "n" if 999 # depth
0EEW[おふせ + 9]  = 内容[24] + "." + 内容[25], or "n" if 99 # M
0EEW[おふせ + 10] = 内容[26], or "h" under one flag
0EEW[おふせ + 14] = #r:最新クラウド変数[1]
```

Extra info:

```text
0-2EEW追加情報[おふせ + 6]
  = flags from 内容[31], 内容[32], 内容[36..38]

0-2EEW追加情報[おふせ + 9]
  = letter(36, 内容) mod 5, or blank
```

Important: this means M and depth are not inferred from the GIF stations in
this procedure. They are read from the EEW content string.

## 5. `円の中か判定(多目的0)`

This helper only checks whether a point lies inside any active EEW circle
radius. It loops 10 EEW slots:

```text
多目的0 = 0
slot = 0
repeat 10:
  if 0EEW[slot * 14 + 1] > 0:
    if ten c:震源距離[(番号 - 1) * 10 + slot + 1]
       < 0EEW[slot * 14 + 12 + s波] + おふせ:
      多目的0 = 1
      stop this script
  slot += 1
```

This helper is circle-membership only. The actual `円の中トリガ` permission
promotion is inside `単独トリガ`.

## 6. `単独トリガ ...` -> `円の中トリガ`

`円の中トリガ` is not a standalone algorithm. It is one branch inside
`単独トリガ 状態 ...`.

The branch is entered only when:

```text
現在状態 == 3
しきい値 < 4
(
  (点数 == 1 and 震度 >= -0.5)
  or
  (now - ten c:揺れ検出トリガー時間[番号] < 10 and 震度 >= 0.5)
)
EEW全体で発表中？ == 1
```

Then it loops the 10 EEW slots:

```text
slot = 0
repeat 10:
  if 0EEW[slot * 14 + 8] < 150
     and 0-1EEW発表中[slot + 1] > 0:

    stationDistance =
      ten c:震源距離[(番号 - 1) * 10 + slot + 1]

    if stationDistance >= 200:
      距離の震度(
        stationDistance,
        0EEW[slot * 14 + 9], # M
        0EEW[slot * 14 + 8], # depth
        1
      )

    if 距離の震度 > -0.5 or stationDistance < 200:
      if 0EEW[slot * 14 + 13] - 100 < stationDistance:
        if 0-2EEW追加情報[slot * 14 + 3] * 0EEW[slot * 14 + 13]
             < stationDistance
           and stationDistance < 0EEW[slot * 14 + 12] * 0.8:

          点許可状態更新(番号, 5, "円の中トリガ", false)
          stop this script

  slot += 1
```

So this branch uses:

- active EEW global state: `EEW全体で発表中？`
- active slot state: `0-1EEW発表中`
- EEW source slots: `0EEW`
- EEW extra radius/flag slots: `0-2EEW追加情報`
- per-station distance-to-EEW-source cache: `ten c:震源距離`
- predicted intensity helper: `距離の震度`

It does not use the current HYP source estimate as the EEW circle source.

## 7. Implementation implication for our reproduction

For replay packages that only contain NIED GIF station frames, this branch
cannot be faithfully activated unless the replay also contains the equivalent
EEW state:

```text
0EEW
0-1EEW発表中
0-2EEW追加情報
ten c:震源距離
EEW全体で発表中？
```

Using final catalog truth or our current HYP output to synthesize these fields
would not be a reproduction of the Scratch source logic.

Important correction: the downloaded cloud variables do not directly contain
all of these fields.

The generation chain in the Scratch source is:

```text
☁ c2h / ☁ c2b*
  -> クラウド変数更新したら
  -> 雲変化 / 雲変化チェック
  -> #r:最新クラウド変数
  -> EEW %s %s
       writes the basic 0EEW slot:
       active, report id, origin/announcement time,
       lon, lat, depth, magnitude, max/intensity-like field
  -> EEW情報の処理
       writes runtime-derived state:
       EEW全体で発表中？
       0EEW +11 elapsed seconds
       0EEW +12 P-wave epicentral circle radius
       0EEW +13 S-wave epicentral circle radius
       0-1EEW発表中
       0-2EEW追加情報 +2/+3/+4
       ten c:震源距離
```

`0EEW +12/+13` are generated by two calls to:

```text
JMA2001距離近似: 経過時間or距離, 深さ, P波, 走時計算
```

For the EEW circle radii, `走時計算` is false.  The procedure reads the
Scratch list:

```text
d JMA2001走時表近似式
```

This list has 1704 coefficients, split by depth bucket, P/S, and forward vs
inverse mode.  It is not a constant P/S velocity shortcut.

`ten c:震源距離` is generated by:

```text
点-震源 距離計算 %s %s %s
```

When an EEW source changes, Scratch stores a key in `@1 点震源距離用`, then
recomputes each station's distance to that EEW source with:

```text
緯度経度で距離km(多目的0)
  = acos(
      sin(y1) * sin(y2)
      + cos(y1) * cos(y2) * cos(x1 - x2)
    ) * 111.31949
```

Therefore, the faithful local replay path must either replay these Scratch
steps or call the local JS reference that now does so.  Merely saving cloud
variables is necessary but not sufficient for `円の中トリガ`.

## 8. Local JS reference engine

The cloud / EEW / circle-trigger logic is now kept as a local JavaScript
reference instead of being hand-translated directly into Dart:

```text
tools/kotoho7_cloud_eew_logic.js
tools/kotoho7_cloud_eew_bridge.js
tools/kotoho7_cloud_eew_logic_test.js
test/kotoho7_js_eew_bridge_test.dart
```

Intent:

- JavaScript remains the authority for this Scratch/TurboWarp branch.
- Dart only passes the current station context and Scratch-equivalent metadata
  to the JS bridge.
- The JS reference now includes the generation side of `EEW情報の処理` for the
  circle-trigger inputs: it loads `d JMA2001走時表近似式` from the downloaded
  Scratch `project.json`, computes the P/S radii, updates active flags, and can
  compute station-to-EEW-source distances from station coordinates.
- The source estimator enables this path only when
  `request.metadata["kotoho7_use_js_eew_bridge"] == true`.
- Without the flag or without `0EEW` / `0-1EEW発表中` /
  `0-2EEW追加情報` metadata, the estimator keeps the existing inactive
  diagnostic behavior.

Required metadata for the bridge:

```text
kotoho7_use_js_eew_bridge = true
kotoho7_eew_slots
kotoho7_eew_active_flags
kotoho7_eew_extra_info
kotoho7_eew_global_active
```

The bridge also exposes the generation command:

```json
{
  "command": "processEewInformation",
  "metadata": { "...": "state returned by parseEewContent/updateCloud" },
  "nowSeconds": 1020,
  "stations": [
    { "stationIndex1": 123, "latitude": 39.5, "longitude": 131.8 }
  ]
}
```

That command returns updated `kotoho7_eew_slots`,
`kotoho7_eew_active_flags`, `kotoho7_eew_extra_info`, and
`kotoho7_eew_global_active`.

Optional:

```text
kotoho7_js_eew_bridge_script_path
```

If omitted, Dart uses:

```text
tools/kotoho7_cloud_eew_bridge.js
```

The current Dart integration only calls the JS bridge for the same narrow
Scratch branch:

```text
previousState == 3
単独トリガ early gate
EEW circle conditions
```

When JS promotes the station, Dart records:

```text
scratch_permission_circle_eew_trigger_js
```

This keeps the risky EEW-circle logic in JS while preserving the rest of the
current kotoho7 state machine.
