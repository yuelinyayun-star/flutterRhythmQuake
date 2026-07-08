# Scratch/TurboWarp HYP algorithm extraction

This is a generated, review-oriented extraction of the reference Scratch/TurboWarp source-estimation blocks. It is not production code.

- Source project: `.dart_tool/external_refs/scratch-realtime-earthquake-viewer-page/docs/assets/project.json`
- Source target/sprite: `受信と検出`
- Encoding: UTF-8

## Procedure map

| Procedure | Arguments | Calls |
|---|---|---|
| `HYP:震源検出 %s %s` | 検出id, 4-3オフセット | `HYP:誤差レベル比較繰り返し %s %s %s %b %b %s %s` |
| `HYP:誤差レベル計算 %s %s %s %s %s %s` | 経度X, 緯度Y, 深さ, 対象id, おふせ, 4-3offset | `JMA2001距離近似: %s %s %b %b`<br>`緯度経度で距離km(多目的0) xy1 %s %s xy2 %s %s` |
| `HYP:誤差レベル比較 %s %s %s %b %b %s` | id, 水平移動, 深さ移動, 緯度経度移動あり, 深さ時刻移動あり, 4-3offset | `HYP:誤差レベル計算 %s %s %s %s %s %s` |
| `HYP:誤差レベル比較繰り返し %s %s %s %b %b %s %s` | id, 水平移動, 深さ移動, 緯度経度移動あり, 深さ時間移動あり, 4-3offset, 制限 | `HYP:誤差レベル比較 %s %s %s %b %b %s` |
| `JMA2001距離近似: %s %s %b %b` | 経過時間or距離, 深さ, P波, 走時計算 |  |
| `epi最大距離(多目的1)or仮震央(カウント3id) %b %s` | 仮震央, 対象id | `緯度経度で距離km(多目的0) xy1 %s %s xy2 %s %s` |
| `検出id1_全点へ適用` |  | `検出id2_各点の許可idと推定用をセット %s %s %s %s`<br>`検出id_グリッド別idと存在idをセット %s %s %s`<br>`検出id_同一震源統合 %s %s %b`<br>`検出id_消えたidに対応する検出無効化` |
| `検出id2_各点の許可idと推定用をセット %s %s %s %s` | 番号, 変化速度, 現在状態, 7点スタート | `検出id3_点にIDを登録 %s %b`<br>`検出id_点の推定用をリセット %s` |
| `検出id3_点にIDを登録 %s %b` | 点番号, 再上昇 | `検出id4_点に適用するべきIDを検索 %s %b`<br>`検出id_新規id追加 %s %b`<br>`検出id_点の推定用をリセット %s`<br>`検出id適用数カウント追加 %s %b %s` |
| `検出id4_点に適用するべきIDを検索 %s %b` | 点番号, 再上昇 | `検出id4-1_適用id最短7から候補選択 %s %s %s`<br>`検出id4-2_適用id震源から候補選択 %s %s %s %s %s %s`<br>`検出id_周囲gridの最新ID検索 %s %s %s %s`<br>`緯度経度で距離km(多目的0) xy1 %s %s xy2 %s %s` |
| `検出id4-1_適用id最短7から候補選択 %s %s %s` | 7点オフセット, 推定用オフセット, 点番号 | `検出id4-1_適用id最短7から候補選択 %s %s %s` |
| `検出id4-2_適用id震源から候補選択 %s %s %s %s %s %s` | 点番号, x, y, 深さ, 発生時刻, 4-3オフセット | `JMA2001距離近似: %s %s %b %b`<br>`検出id4-2_適用id震源から候補選択 %s %s %s %s %s %s`<br>`緯度経度で距離km(多目的0) xy1 %s %s xy2 %s %s` |
| `検出id適用数カウント追加 %s %b %s` | 番号, 距離セット, 変更数 | `推定用tenPS時間計算(多目的0,2使用) %s %s`<br>`検出id_点の推定用をリセット %s`<br>`検出id距離計算 %s %s` |
| `推定用tenPS時間計算(多目的0,2使用) %s %s` | 番号, id | `JMA2001距離近似: %s %s %b %b`<br>`緯度経度で距離km(多目的0) xy1 %s %s xy2 %s %s` |
| `検出id_推定PS時間id別再計算 %s` | id | `推定用tenPS時間計算(多目的0,2使用) %s %s` |
| `検出id_グリッド別idと存在idをセット %s %s %s` | 番号, id, 含まれるオフセット | `検出id_グリッド別idと存在idをセット %s %s %s` |
| `検出id_周囲gridの最新ID検索 %s %s %s %s` | 番号, 初期, 指定id, 最大範囲012 | `検出id_周囲gridの最新ID検索 %s %s %s %s` |
| `検出id_消えたidに対応する検出無効化` |  |  |
| `検出id_点の推定用をリセット %s` | 番号 | `検出id適用数カウント追加 %s %b %s` |
| `検出id_同一震源統合 %s %s %b` | id1, id2, 実行 | `検出id_同一震源統合 %s %s %b`<br>`緯度経度で距離km(多目的0) xy1 %s %s xy2 %s %s` |
| `検出id_新規id追加 %s %b` | 番号, 再上昇 |  |
| `検出id距離計算 %s %s` | 番号, 4-3おふせ |  |
| `点-震源 距離計算 %s %s %s` | 番号, x, y | `緯度経度で距離km(多目的0) xy1 %s %s xy2 %s %s` |
| `緯度経度で距離km(多目的0) xy1 %s %s xy2 %s %s` | x1, y1, x2, y2 |  |
| `距離の震度 %s %s %s %s` | 距離, M, 深さ, 増幅 |  |

## Pseudo-code blocks

### `HYP:震源検出 %s %s`

- Definition block: `bhn`
- Prototype block: `*r`
- Arguments: `検出id, 4-3オフセット`

```text
o(: control_if_else | inputs[CONDITION=bho:data_itemoflist]
  SUBSTACK:
    *s: data_setvariableto | fields[VARIABLE=@hyp:最初検知時刻] | inputs[VALUE=bhq:data_itemoflist]
    *t: control_if | inputs[CONDITION=bhs:operator_lt]
      SUBSTACK:
        bht: data_setvariableto | fields[VARIABLE=@hyp:計算フェーズ] | inputs[VALUE='start']
        *u: data_setvariableto | fields[VARIABLE=@hyp:検知点数] | inputs[VALUE=bhv:data_itemoflist]
        *v: data_setvariableto | fields[VARIABLE=@hyp:許可最大深さ] | inputs[VALUE=bhx:operator_round]
        *w: data_setvariableto | fields[VARIABLE=@hyp:許可最大距離] | inputs[VALUE=bhG:operator_round]
        cg: control_if_else | inputs[CONDITION=*C:operator_or]
          SUBSTACK:
            *D: data_setvariableto | fields[VARIABLE=@hyp:仮の震源 経度X] | inputs[VALUE=bhU:operator_divide]
            *F: data_setvariableto | fields[VARIABLE=@hyp:仮の震源 緯度Y] | inputs[VALUE=bh#:operator_divide]
            bh!: data_setvariableto | fields[VARIABLE=@hyp:仮の震源 深さ] | inputs[VALUE='10']
            bh,: data_setvariableto | fields[VARIABLE=@hyp:仮の震源 発生時刻] | inputs[VALUE=deV:operator_subtract]
          SUBSTACK2:
            *E: data_setvariableto | fields[VARIABLE=@hyp:仮の震源 経度X] | inputs[VALUE=bh-:data_itemoflist]
            *G: data_setvariableto | fields[VARIABLE=@hyp:仮の震源 緯度Y] | inputs[VALUE=bh::data_itemoflist]
            *H: data_setvariableto | fields[VARIABLE=@hyp:仮の震源 深さ] | inputs[VALUE=bh@:data_itemoflist]
            bh?: data_setvariableto | fields[VARIABLE=@hyp:仮の震源 発生時刻] | inputs[VALUE=bh^:data_itemoflist]
        *B: data_setvariableto | fields[VARIABLE=@hyp:最小誤差レベル] | inputs[VALUE=de!:operator_divide]
        bh{: data_setvariableto | fields[VARIABLE=@hyp:1フレーム休みカウント] | inputs[VALUE='0']
        o): control_if | inputs[CONDITION=bh}:operator_lt]
          SUBSTACK:
            bh~: data_setvariableto | fields[VARIABLE=@hyp:計算フェーズ] | inputs[VALUE='start-h2']
            ch: HYP:誤差レベル比較繰り返し %s %s %s %b %b %s %s | inputs[iig=!xPR}H^$*b]`$Scc=$検出id, yaMHA8bi?A2,cmiEKqOq='0.5', B!OA/D:-OXxO0Wx5~#1o='', #wqDaaP@qXfj4+odj%`~=de(:operator_not, k`JVzfgikuY,]3Pg{U}r=$4-3オフセット, /WQbmWfY6ngB}e;F43[G=bic:operator_subtract]
        bh|: data_setvariableto | fields[VARIABLE=@hyp:計算フェーズ] | inputs[VALUE='start-h10']
        ap: HYP:誤差レベル比較繰り返し %s %s %s %b %b %s %s | inputs[iig=!xPR}H^$*b]`$Scc=$検出id, yaMHA8bi?A2,cmiEKqOq='0.1', B!OA/D:-OXxO0Wx5~#1o='', #wqDaaP@qXfj4+odj%`~=de-:operator_not, k`JVzfgikuY,]3Pg{U}r=$4-3オフセット, /WQbmWfY6ngB}e;F43[G=bil:operator_subtract]
        bik: data_setvariableto | fields[VARIABLE=@hyp:計算フェーズ] | inputs[VALUE='start-h10-v50']
        aq: HYP:誤差レベル比較繰り返し %s %s %s %b %b %s %s | inputs[iig=!xPR}H^$*b]`$Scc=$検出id, yaMHA8bi?A2,cmiEKqOq='0.1', B!OA/D:-OXxO0Wx5~#1o='50', #wqDaaP@qXfj4+odj%`~=de=:operator_not, ysxEN}Y1#V0-N!pe1=h:=de?:operator_not, k`JVzfgikuY,]3Pg{U}r=$4-3オフセット, /WQbmWfY6ngB}e;F43[G='100']
        bit: data_setvariableto | fields[VARIABLE=@hyp:計算フェーズ] | inputs[VALUE='start-h10-v10']
        ar: HYP:誤差レベル比較繰り返し %s %s %s %b %b %s %s | inputs[iig=!xPR}H^$*b]`$Scc=$検出id, yaMHA8bi?A2,cmiEKqOq='0.1', B!OA/D:-OXxO0Wx5~#1o='10', #wqDaaP@qXfj4+odj%`~=de]:operator_not, ysxEN}Y1#V0-N!pe1=h:=de^:operator_not, k`JVzfgikuY,]3Pg{U}r=$4-3オフセット, /WQbmWfY6ngB}e;F43[G='100']
        biu: data_setvariableto | fields[VARIABLE=@hyp:計算フェーズ] | inputs[VALUE='start-h60']
        as: HYP:誤差レベル比較繰り返し %s %s %s %b %b %s %s | inputs[iig=!xPR}H^$*b]`$Scc=$検出id, yaMHA8bi?A2,cmiEKqOq=de{:operator_divide, B!OA/D:-OXxO0Wx5~#1o='', #wqDaaP@qXfj4+odj%`~=de|:operator_not, k`JVzfgikuY,]3Pg{U}r=$4-3オフセット, /WQbmWfY6ngB}e;F43[G='10']
        biv: data_setvariableto | fields[VARIABLE=@hyp:計算フェーズ] | inputs[VALUE='end1']
        *K: data_setvariableto | fields[VARIABLE=多目的1] | inputs[VALUE=biw:operator_multiply]
        *L: data_setvariableto | fields[VARIABLE=多目的2] | inputs[VALUE=biy:operator_multiply]
        *M: control_if | inputs[CONDITION=*N:operator_or]
          SUBSTACK:
            o*: data_replaceitemoflist | fields[LIST=4-3 検出id別情報] | inputs[INDEX=dfd:operator_add, ITEM=biF:operator_join]
            ci: control_if_else | inputs[CONDITION=*P:operator_and]
              SUBSTACK:
                biI: data_replaceitemoflist | fields[LIST=4-3 検出id別情報] | inputs[INDEX=dfh:operator_add, ITEM='250']
              SUBSTACK2:
                *Q: data_replaceitemoflist | fields[LIST=4-3 検出id別情報] | inputs[INDEX=dfi:operator_add, ITEM='@hyp:最小誤差レベル']
                *R: control_if | inputs[CONDITION=biL:operator_lt]
                  SUBSTACK:
                    biM: data_replaceitemoflist | fields[LIST=4-3 検出id別情報] | inputs[INDEX=dfk:operator_add, ITEM='@hyp:最小誤差レベル']
            *O: data_replaceitemoflist | fields[LIST=4-3 検出id別情報] | inputs[INDEX=dfl:operator_add, ITEM='@hyp:震源候補 最初検知-震央距離']
            o+: data_replaceitemoflist | fields[LIST=4-4 検出id震源要素] | inputs[INDEX=dfm:operator_add, ITEM=biO:operator_divide]
            o,: data_replaceitemoflist | fields[LIST=4-4 検出id震源要素] | inputs[INDEX=dfo:operator_add, ITEM=biQ:operator_divide]
            o-: data_replaceitemoflist | fields[LIST=4-4 検出id震源要素] | inputs[INDEX=dfq:operator_add, ITEM=dfr:operator_round]
            o.: data_replaceitemoflist | fields[LIST=4-4 検出id震源要素] | inputs[INDEX=dfs:operator_add, ITEM=dft:operator_round]
            *S: data_replaceitemoflist | fields[LIST=4-3 検出id別情報] | inputs[INDEX=dfu:operator_add, ITEM=dfv:data_itemoflist]
deG: data_setvariableto | fields[VARIABLE=@hyp計算中] | inputs[VALUE='']
```

### `HYP:誤差レベル計算 %s %s %s %s %s %s`

- Definition block: `ayd`
- Prototype block: `O`
- Arguments: `経度X, 緯度Y, 深さ, 対象id, おふせ, 4-3offset`

```text
gT: control_if | inputs[CONDITION=GF:operator_or]
  SUBSTACK:
    cF=: control_stop | fields[STOP_OPTION=this script]
gU: control_if | inputs[CONDITION=GH:operator_or]
  SUBSTACK:
    cF]: control_stop | fields[STOP_OPTION=this script]
{: 緯度経度で距離km(多目的0) xy1 %s %s xy2 %s %s | inputs[]{P@NqNQS3.9ZW^L7/Id=$経度X, v4!`%fK.fAl-7,*LjmoN=$緯度Y, PD=h#Y$/m@?PDZm(Qn:L=ayl:data_itemoflist, ;:CHeDp67!I+0u0Hv{UC=aym:data_itemoflist]
gV: control_if | inputs[CONDITION=cGb:operator_lt]
  SUBSTACK:
    cGc: control_stop | fields[STOP_OPTION=this script]
ayr: data_deletealloflist | fields[LIST=@hyp:時間差リスト未着]
ays: data_deletealloflist | fields[LIST=@hyp:重みリスト]
ayt: data_deletealloflist | fields[LIST=@hyp:時間差リスト]
ayu: data_setvariableto | fields[VARIABLE=@hyp:時間差の合計] | inputs[VALUE='0']
a): control_if_else | inputs[CONDITION=cGd:operator_lt]
  SUBSTACK:
    cGe: data_setvariableto | fields[VARIABLE=@hyp:最初検出点の震央距離] | inputs[VALUE='50']
  SUBSTACK2:
    cGf: data_setvariableto | fields[VARIABLE=@hyp:最初検出点の震央距離] | inputs[VALUE='多目的0']
GK: data_setvariableto | fields[VARIABLE=@hyp:計算用経過時刻] | inputs[VALUE=ayv:operator_subtract]
gW: JMA2001距離近似: %s %s %b %b | inputs[)mGAodyW$Qxr28i|bA^^='@hyp:計算用経過時刻', TeevruD^wB$OTE*kFu!]=$深さ, .Mvwp@L}y=pm:g13O%*m=cGi:operator_not]
ayw: data_replaceitemoflist | fields[LIST=@hyp:誤差レベル用PS半径&時間] | inputs[INDEX='1', ITEM='tjma3:波震央距離']
gX: control_if | inputs[CONDITION=GM:operator_lt]
  SUBSTACK:
    ayx: data_replaceitemoflist | fields[LIST=@hyp:誤差レベル用PS半径&時間] | inputs[INDEX='1', ITEM=ayC:operator_add]
GL: JMA2001距離近似: %s %s %b %b | inputs[)mGAodyW$Qxr28i|bA^^='@hyp:計算用経過時刻', TeevruD^wB$OTE*kFu!]=$深さ]
ayG: data_replaceitemoflist | fields[LIST=@hyp:誤差レベル用PS半径&時間] | inputs[INDEX='2', ITEM='tjma3:波震央距離']
gY: control_if | inputs[CONDITION=GN:operator_lt]
  SUBSTACK:
    ayI: data_replaceitemoflist | fields[LIST=@hyp:誤差レベル用PS半径&時間] | inputs[INDEX='2', ITEM=ayN:operator_add]
ayH: data_setvariableto | fields[VARIABLE=カウント1] | inputs[VALUE='0']
ayR: data_setvariableto | fields[VARIABLE=@hyp:Sカウント] | inputs[VALUE='0']
gZ: control_repeat | inputs[TIMES=cGq:data_lengthoflist]
  SUBSTACK:
    |: 緯度経度で距離km(多目的0) xy1 %s %s xy2 %s %s | inputs[]{P@NqNQS3.9ZW^L7/Id=$経度X, v4!`%fK.fAl-7,*LjmoN=$緯度Y, PD=h#Y$/m@?PDZm(Qn:L=ayS:operator_add, ;:CHeDp67!I+0u0Hv{UC=ayT:operator_add]
    g!: control_if | inputs[CONDITION=GP:operator_or]
      SUBSTACK:
        GQ: data_setvariableto | fields[VARIABLE=カウント2] | inputs[VALUE=ay+:operator_add]
        GR: control_repeat_until | inputs[CONDITION=ay,:operator_equals]
          SUBSTACK:
            GS: data_setvariableto | fields[VARIABLE=多目的1] | inputs[VALUE=cGA:data_itemoflist]
            GT: data_setvariableto | fields[VARIABLE=多目的2] | inputs[VALUE=ay-:operator_multiply]
            a*: control_if_else | inputs[CONDITION=GU:operator_equals]
              SUBSTACK:
                }: 緯度経度で距離km(多目的0) xy1 %s %s xy2 %s %s | inputs[]{P@NqNQS3.9ZW^L7/Id=$経度X, v4!`%fK.fAl-7,*LjmoN=$緯度Y, PD=h#Y$/m@?PDZm(Qn:L=cGH:data_itemoflist, ;:CHeDp67!I+0u0Hv{UC=cGI:data_itemoflist]
                ay/: data_setvariableto | fields[VARIABLE=@hyp:震央距離] | inputs[VALUE='多目的0']
                ~: JMA2001距離近似: %s %s %b %b | inputs[)mGAodyW$Qxr28i|bA^^=ay::operator_mathop, TeevruD^wB$OTE*kFu!]=$深さ, .Mvwp@L}y=pm:g13O%*m=ay;:operator_not, a-hp9v4l7{(gt*_Fd~:p=cGK:operator_not]
                GW: data_addtolist | fields[LIST=@hyp:時間差リスト] | inputs[ITEM=ay?:operator_subtract]
                G#: data_changevariableby | fields[VARIABLE=@hyp:時間差の合計] | inputs[VALUE=cGS:data_itemoflist]
                g#: control_if | inputs[CONDITION=cGT:operator_lt]
                  SUBSTACK:
                    cGU: data_setvariableto | fields[VARIABLE=@hyp:震央距離] | inputs[VALUE='50']
                g%: control_if | inputs[CONDITION=ay[:data_itemoflist]
                  SUBSTACK:
                    cGV: data_changevariableby | fields[VARIABLE=@hyp:Sカウント] | inputs[VALUE='1']
                G%: data_addtolist | fields[LIST=@hyp:重みリスト] | inputs[ITEM=cGY:operator_divide]
                cGX: data_changevariableby | fields[VARIABLE=@hyp:1フレーム休みカウント] | inputs[VALUE='1']
              SUBSTACK2:
                GV: control_if | inputs[CONDITION=G(:operator_or]
                  SUBSTACK:
                    aa: 緯度経度で距離km(多目的0) xy1 %s %s xy2 %s %s | inputs[]{P@NqNQS3.9ZW^L7/Id=cG#:data_itemoflist, v4!`%fK.fAl-7,*LjmoN=cG%:data_itemoflist, PD=h#Y$/m@?PDZm(Qn:L=$経度X, ;:CHeDp67!I+0u0Hv{UC=$緯度Y]
                    azk: data_setvariableto | fields[VARIABLE=@hyp:震央距離] | inputs[VALUE='多目的0']
                    g(: control_if | inputs[CONDITION=G):operator_or]
                      SUBSTACK:
                        ab: JMA2001距離近似: %s %s %b %b | inputs[)mGAodyW$Qxr28i|bA^^=azp:operator_mathop, TeevruD^wB$OTE*kFu!]=$深さ, .Mvwp@L}y=pm:g13O%*m=cG;:operator_not, a-hp9v4l7{(gt*_Fd~:p=cG=:operator_not]
                        cG/: data_addtolist | fields[LIST=@hyp:時間差リスト未着] | inputs[ITEM='tjma:波震源距離or波走時']
                    cG*: data_changevariableby | fields[VARIABLE=@hyp:1フレーム休みカウント] | inputs[VALUE='1']
            cGC: data_changevariableby | fields[VARIABLE=カウント2] | inputs[VALUE='1']
    cGv: data_changevariableby | fields[VARIABLE=カウント1] | inputs[VALUE='1']
GO: data_setvariableto | fields[VARIABLE=@hyp:差の平均] | inputs[VALUE=azr:operator_divide]
azq: data_setvariableto | fields[VARIABLE=@hyp:2乗誤差の合計] | inputs[VALUE='0']
azs: data_setvariableto | fields[VARIABLE=@hyp:合計カウント] | inputs[VALUE='0']
azt: data_setvariableto | fields[VARIABLE=@hyp:時間差の合計] | inputs[VALUE='0']
azu: data_setvariableto | fields[VARIABLE=カウント1] | inputs[VALUE='1']
g): control_repeat | inputs[TIMES=cG^:data_lengthoflist]
  SUBSTACK:
    G.: data_changevariableby | fields[VARIABLE=@hyp:2乗誤差の合計] | inputs[VALUE=G::operator_multiply]
    G/: data_changevariableby | fields[VARIABLE=@hyp:合計カウント] | inputs[VALUE=cG}:data_itemoflist]
    cG|: data_changevariableby | fields[VARIABLE=カウント1] | inputs[VALUE='1']
g*: control_if | inputs[CONDITION=azx:operator_lt]
  SUBSTACK:
    azy: data_setvariableto | fields[VARIABLE=カウント1] | inputs[VALUE='1']
    G?: control_repeat | inputs[TIMES=cHa:data_lengthoflist]
      SUBSTACK:
        g+: control_if | inputs[CONDITION=G@:operator_lt]
          SUBSTACK:
            cHc: data_changevariableby | fields[VARIABLE=@hyp:2乗誤差の合計] | inputs[VALUE='1']
        cHb: data_changevariableby | fields[VARIABLE=カウント1] | inputs[VALUE='1']
G=: data_setvariableto | fields[VARIABLE=@hyp:Sカウント] | inputs[VALUE=azA:operator_subtract]
g,: control_if | inputs[CONDITION=cHh:operator_lt]
  SUBSTACK:
    cHi: data_setvariableto | fields[VARIABLE=@hyp:Sカウント] | inputs[VALUE='0.25']
G]: data_setvariableto | fields[VARIABLE=@hyp:誤差レベル] | inputs[VALUE=azB:operator_multiply]
G^: control_if | inputs[CONDITION=cHn:operator_lt]
  SUBSTACK:
    azH: data_setvariableto | fields[VARIABLE=@hyp:最小誤差レベル] | inputs[VALUE='@hyp:誤差レベル']
    G|: data_setvariableto | fields[VARIABLE=@hyp:震源候補 経度X] | inputs[VALUE=$経度X]
    G}: data_setvariableto | fields[VARIABLE=@hyp:震源候補 緯度Y] | inputs[VALUE=$緯度Y]
    G~: data_setvariableto | fields[VARIABLE=@hyp:震源候補 深さ] | inputs[VALUE=$深さ]
    azI: data_setvariableto | fields[VARIABLE=@hyp:震源候補 発生時刻] | inputs[VALUE='@hyp:差の平均']
    azJ: data_setvariableto | fields[VARIABLE=@hyp:震源候補 最初検知-震央距離] | inputs[VALUE='@hyp:最初検出点の震央距離']
    Ha: control_if | inputs[CONDITION=azK:sensing_keypressed]
      SUBSTACK:
        g-: data_replaceitemoflist | fields[LIST=4-4 検出id震源要素] | inputs[INDEX=azL:operator_add, ITEM=azM:operator_divide]
        g.: data_replaceitemoflist | fields[LIST=4-4 検出id震源要素] | inputs[INDEX=azR:operator_add, ITEM=azS:operator_divide]
        g/: data_replaceitemoflist | fields[LIST=4-4 検出id震源要素] | inputs[INDEX=azX:operator_add, ITEM=azY:operator_round]
        Hb: data_replaceitemoflist | fields[LIST=4-4 検出id震源要素] | inputs[INDEX=az#:operator_add, ITEM=az%:operator_subtract]
```

### `HYP:誤差レベル比較 %s %s %s %b %b %s`

- Definition block: `ax;`
- Prototype block: `N`
- Arguments: `id, 水平移動, 深さ移動, 緯度経度移動あり, 深さ時刻移動あり, 4-3offset`

```text
gQ: control_if | inputs[CONDITION=cFF:operator_equals]
  SUBSTACK:
    cFG: control_stop | fields[STOP_OPTION=this script]
ax=: data_setvariableto | fields[VARIABLE=@hyp:震源候補 経度X] | inputs[VALUE='b']
gR: control_if | inputs[CONDITION=$緯度経度移動あり]
  SUBSTACK:
    aX: HYP:誤差レベル計算 %s %s %s %s %s %s | inputs[#~gg70ioPS|D54HBd?9A=ax@:operator_add, CBTc)gODI#nB}u?=Q7ru='@hyp:仮の震源 緯度Y', ?7NGADwVs=yB7DCA[YoD='@hyp:仮の震源 深さ', =2#U*f^WnXlh_P1oFg5G=$id, WDWsMX0w$a/nnh:r^goo='2', o]Lc!}A`0$LvPl}SHUm^=$4-3offset]
    ax?: 1フレーム休み判断
    aY: HYP:誤差レベル計算 %s %s %s %s %s %s | inputs[#~gg70ioPS|D54HBd?9A=ax]:operator_subtract, CBTc)gODI#nB}u?=Q7ru='@hyp:仮の震源 緯度Y', ?7NGADwVs=yB7DCA[YoD='@hyp:仮の震源 深さ', =2#U*f^WnXlh_P1oFg5G=$id, WDWsMX0w$a/nnh:r^goo='3', o]Lc!}A`0$LvPl}SHUm^=$4-3offset]
    ax[: 1フレーム休み判断
    aZ: HYP:誤差レベル計算 %s %s %s %s %s %s | inputs[#~gg70ioPS|D54HBd?9A='@hyp:仮の震源 経度X', CBTc)gODI#nB}u?=Q7ru=ax_:operator_add, ?7NGADwVs=yB7DCA[YoD='@hyp:仮の震源 深さ', =2#U*f^WnXlh_P1oFg5G=$id, WDWsMX0w$a/nnh:r^goo='4', o]Lc!}A`0$LvPl}SHUm^=$4-3offset]
    ax^: 1フレーム休み判断
    a!: HYP:誤差レベル計算 %s %s %s %s %s %s | inputs[#~gg70ioPS|D54HBd?9A='@hyp:仮の震源 経度X', CBTc)gODI#nB}u?=Q7ru=ax`:operator_subtract, ?7NGADwVs=yB7DCA[YoD='@hyp:仮の震源 深さ', =2#U*f^WnXlh_P1oFg5G=$id, WDWsMX0w$a/nnh:r^goo='5', o]Lc!}A`0$LvPl}SHUm^=$4-3offset]
    cFR: 1フレーム休み判断
gS: control_if | inputs[CONDITION=$深さ時刻移動あり]
  SUBSTACK:
    a%: HYP:誤差レベル計算 %s %s %s %s %s %s | inputs[#~gg70ioPS|D54HBd?9A='@hyp:仮の震源 経度X', CBTc)gODI#nB}u?=Q7ru='@hyp:仮の震源 緯度Y', ?7NGADwVs=yB7DCA[YoD=ax|:operator_add, =2#U*f^WnXlh_P1oFg5G=$id, WDWsMX0w$a/nnh:r^goo='6', o]Lc!}A`0$LvPl}SHUm^=$4-3offset]
    ax{: 1フレーム休み判断
    a(: HYP:誤差レベル計算 %s %s %s %s %s %s | inputs[#~gg70ioPS|D54HBd?9A='@hyp:仮の震源 経度X', CBTc)gODI#nB}u?=Q7ru='@hyp:仮の震源 緯度Y', ?7NGADwVs=yB7DCA[YoD=ax}:operator_subtract, =2#U*f^WnXlh_P1oFg5G=$id, WDWsMX0w$a/nnh:r^goo='7', o]Lc!}A`0$LvPl}SHUm^=$4-3offset]
    cFZ: 1フレーム休み判断
a#: control_if_else | inputs[CONDITION=cF):operator_equals]
  SUBSTACK:
    ax~: data_setvariableto | fields[VARIABLE=@hyp:震源候補 経度X] | inputs[VALUE='e']
    cF*: control_stop | fields[STOP_OPTION=this script]
  SUBSTACK2:
    aya: data_setvariableto | fields[VARIABLE=@hyp:仮の震源 経度X] | inputs[VALUE='@hyp:震源候補 経度X']
    ayb: data_setvariableto | fields[VARIABLE=@hyp:仮の震源 緯度Y] | inputs[VALUE='@hyp:震源候補 緯度Y']
    ayc: data_setvariableto | fields[VARIABLE=@hyp:仮の震源 深さ] | inputs[VALUE='@hyp:震源候補 深さ']
    cF+: data_setvariableto | fields[VARIABLE=@hyp:仮の震源 発生時刻] | inputs[VALUE='@hyp:震源候補 発生時刻']
cF(: data_changevariableby | fields[VARIABLE=@hyp:計算回数] | inputs[VALUE='1']
```

### `HYP:誤差レベル比較繰り返し %s %s %s %b %b %s %s`

- Definition block: `ax,`
- Prototype block: `t`
- Arguments: `id, 水平移動, 深さ移動, 緯度経度移動あり, 深さ時間移動あり, 4-3offset, 制限`

```text
ax-: data_setvariableto | fields[VARIABLE=@hyp:計算回数] | inputs[VALUE='0']
ax.: data_setvariableto | fields[VARIABLE=@hyp:震源候補 経度X] | inputs[VALUE='']
ax/: data_setvariableto | fields[VARIABLE=@hyp:震源候補 発生時刻] | inputs[VALUE='@hyp:仮の震源 発生時刻']
GD: control_repeat_until | inputs[CONDITION=ax::operator_lt]
  SUBSTACK:
    u: HYP:誤差レベル比較 %s %s %s %b %b %s | inputs[TTbV70~UcbC*;5p4e8Mu=$id, :OrtRsJ[R[Q{FUQca)Xe=$水平移動, I96^.n3orAdO.{8jGA0!=$深さ移動, dZbOqisxy+GuE.JXpBhU=$緯度経度移動あり, %kJnd=j0;JA^36=16M7D=$深さ時間移動あり, S|iQMET!T%UTa7}dY|f^=$4-3offset]
    v: HYP:誤差レベル比較 %s %s %s %b %b %s | inputs[TTbV70~UcbC*;5p4e8Mu=$id, :OrtRsJ[R[Q{FUQca)Xe=$水平移動, I96^.n3orAdO.{8jGA0!=$深さ移動, dZbOqisxy+GuE.JXpBhU=$緯度経度移動あり, %kJnd=j0;JA^36=16M7D=$深さ時間移動あり, S|iQMET!T%UTa7}dY|f^=$4-3offset]
    w: HYP:誤差レベル比較 %s %s %s %b %b %s | inputs[TTbV70~UcbC*;5p4e8Mu=$id, :OrtRsJ[R[Q{FUQca)Xe=$水平移動, I96^.n3orAdO.{8jGA0!=$深さ移動, dZbOqisxy+GuE.JXpBhU=$緯度経度移動あり, %kJnd=j0;JA^36=16M7D=$深さ時間移動あり, S|iQMET!T%UTa7}dY|f^=$4-3offset]
    x: HYP:誤差レベル比較 %s %s %s %b %b %s | inputs[TTbV70~UcbC*;5p4e8Mu=$id, :OrtRsJ[R[Q{FUQca)Xe=$水平移動, I96^.n3orAdO.{8jGA0!=$深さ移動, dZbOqisxy+GuE.JXpBhU=$緯度経度移動あり, %kJnd=j0;JA^36=16M7D=$深さ時間移動あり, S|iQMET!T%UTa7}dY|f^=$4-3offset]
    y: HYP:誤差レベル比較 %s %s %s %b %b %s | inputs[TTbV70~UcbC*;5p4e8Mu=$id, :OrtRsJ[R[Q{FUQca)Xe=$水平移動, I96^.n3orAdO.{8jGA0!=$深さ移動, dZbOqisxy+GuE.JXpBhU=$緯度経度移動あり, %kJnd=j0;JA^36=16M7D=$深さ時間移動あり, S|iQMET!T%UTa7}dY|f^=$4-3offset]
    z: HYP:誤差レベル比較 %s %s %s %b %b %s | inputs[TTbV70~UcbC*;5p4e8Mu=$id, :OrtRsJ[R[Q{FUQca)Xe=$水平移動, I96^.n3orAdO.{8jGA0!=$深さ移動, dZbOqisxy+GuE.JXpBhU=$緯度経度移動あり, %kJnd=j0;JA^36=16M7D=$深さ時間移動あり, S|iQMET!T%UTa7}dY|f^=$4-3offset]
    GE: control_if | inputs[CONDITION=cFx:operator_equals]
      SUBSTACK:
        cFy: control_stop | fields[STOP_OPTION=this script]
```

### `JMA2001距離近似: %s %s %b %b`

- Definition block: `aFc`
- Prototype block: `a=`
- Arguments: `経過時間or距離, 深さ, P波, 走時計算`

```text
aFd: data_setvariableto | fields[VARIABLE=tjma:波震源距離or波走時] | inputs[VALUE='0']
aFe: data_setvariableto | fields[VARIABLE=tjma3:波震央距離] | inputs[VALUE='1']
Jh: control_repeat | inputs[TIMES='6']
  SUBSTACK:
    Ji: data_changevariableby | fields[VARIABLE=tjma:波震源距離or波走時] | inputs[VALUE=Jj:operator_multiply]
    cK*: data_changevariableby | fields[VARIABLE=tjma3:波震央距離] | inputs[VALUE='1']
aFf: data_setvariableto | fields[VARIABLE=tjma3:波震央距離] | inputs[VALUE=aFs:operator_multiply]
```

### `epi最大距離(多目的1)or仮震央(カウント3id) %b %s`

- Definition block: `bgZ`
- Prototype block: `*g`
- Arguments: `仮震央, 対象id`

```text
bg!: data_setvariableto | fields[VARIABLE=多目的0] | inputs[VALUE='0']
bg#: data_setvariableto | fields[VARIABLE=多目的1] | inputs[VALUE='0']
bg%: data_setvariableto | fields[VARIABLE=多目的2] | inputs[VALUE='0']
bg(: data_setvariableto | fields[VARIABLE=カウント1] | inputs[VALUE='0']
oV: control_repeat | inputs[TIMES=dd|:data_lengthoflist]
  SUBSTACK:
    oW: control_if | inputs[CONDITION=bg):operator_lt]
      SUBSTACK:
        *i: data_setvariableto | fields[VARIABLE=カウント2] | inputs[VALUE=bg,:operator_add]
        *j: control_repeat_until | inputs[CONDITION=bg-:operator_equals]
          SUBSTACK:
            oX: control_if | inputs[CONDITION=*k:operator_and]
              SUBSTACK:
                oY: control_if_else | inputs[CONDITION=$仮震央]
                  SUBSTACK:
                    *m: data_changevariableby | fields[VARIABLE=多目的1] | inputs[VALUE=bg@:data_itemoflist]
                    *n: data_changevariableby | fields[VARIABLE=多目的2] | inputs[VALUE=bg[:data_itemoflist]
                    dei: data_changevariableby | fields[VARIABLE=多目的0] | inputs[VALUE='1']
                  SUBSTACK2:
                    ao: 緯度経度で距離km(多目的0) xy1 %s %s xy2 %s %s | inputs[]{P@NqNQS3.9ZW^L7/Id=bg]:data_itemoflist, v4!`%fK.fAl-7,*LjmoN=bg^:data_itemoflist, PD=h#Y$/m@?PDZm(Qn:L=bg_:data_itemoflist, ;:CHeDp67!I+0u0Hv{UC=bg`:data_itemoflist]
                    *o: control_if | inputs[CONDITION=deo:operator_lt]
                      SUBSTACK:
                        dep: data_setvariableto | fields[VARIABLE=多目的1] | inputs[VALUE='多目的0']
            dec: data_changevariableby | fields[VARIABLE=カウント2] | inputs[VALUE='1']
    dd}: data_changevariableby | fields[VARIABLE=カウント1] | inputs[VALUE='1']
*h: control_if | inputs[CONDITION=$仮震央]
  SUBSTACK:
    oZ: data_replaceitemoflist | fields[LIST=4-3 検出id別情報] | inputs[INDEX=der:operator_add, ITEM=bg}:operator_join]
    o!: data_replaceitemoflist | fields[LIST=4-3 検出id別情報] | inputs[INDEX=det:operator_add, ITEM=deu:operator_divide]
    o#: data_replaceitemoflist | fields[LIST=4-4 検出id震源要素] | inputs[INDEX=bhb:operator_add, ITEM=bhc:operator_divide]
    o%: data_replaceitemoflist | fields[LIST=4-4 検出id震源要素] | inputs[INDEX=bhf:operator_add, ITEM=bhg:operator_divide]
    *p: data_replaceitemoflist | fields[LIST=4-4 検出id震源要素] | inputs[INDEX=bhj:operator_add, ITEM='10']
    *q: data_replaceitemoflist | fields[LIST=4-4 検出id震源要素] | inputs[INDEX=bhk:operator_add, ITEM=bhl:data_itemoflist]
```

### `検出id1_全点へ適用`

- Definition block: `a:L`
- Prototype block: `c:^`

```text
a:M: 検出id_同一震源統合 %s %s %b | inputs[On5xt865tWb$iO8!5zf.='', $!w^k/.]?`6=PXKQ)=+]='']
a:N: data_setvariableto | fields[VARIABLE=カウント1] | inputs[VALUE='1']
lQ: control_repeat | inputs[TIMES=c:_:data_lengthoflist]
  SUBSTACK:
    b): 検出id2_各点の許可idと推定用をセット %s %s %s %s | inputs[6bY9_vNM1*Sw%)sF0@`M='カウント1', YsZCuRmv~1a+)p2_Km+G=c:{:data_itemoflist, (T_@/TnfQyf:1xJe4am-=c:|:data_itemoflist, ~W=K~5;dvO1/*#k~Yj=@=a:P:operator_add]
    c:`: data_changevariableby | fields[VARIABLE=カウント1] | inputs[VALUE='1']
a:O: 検出id_グリッド別idと存在idをセット %s %s %s | inputs[D}h{Gh9?O|ep-4cj.O.6='', n(;^X2btKi2:X4t3.|OL='', eO8rY@:@x=0na2Rm)XqM='']
a:R: 検出id_消えたidに対応する検出無効化
a:S: data_setvariableto | fields[VARIABLE=カウント1] | inputs[VALUE='1']
lR: control_repeat | inputs[TIMES=c:~:data_lengthoflist]
  SUBSTACK:
    lS: control_if | inputs[CONDITION=a:U:operator_lt]
      SUBSTACK:
        Xu: control_if | inputs[CONDITION=Xv:operator_or]
          SUBSTACK:
            Xw: data_replaceitemoflist | fields[LIST=grid:検出id] | inputs[INDEX=c;e:data_itemoflist, ITEM='']
            a:(: data_replaceitemoflist | fields[LIST=grid:検出id時間] | inputs[INDEX=c;f:data_itemoflist, ITEM='0']
    lT: 検出id海岸補助 %s %s | inputs[P@rlK(*{6vgWDo/X,KJT=c;g:data_itemoflist, }{e98y2gf9kY`~EcWYSs=a:):operator_add]
    lU: 検出id海岸補助 %s %s | inputs[P@rlK(*{6vgWDo/X,KJT=c;i:data_itemoflist, }{e98y2gf9kY`~EcWYSs=a:*:operator_subtract]
    lV: 検出id海岸補助 %s %s | inputs[P@rlK(*{6vgWDo/X,KJT=c;k:data_itemoflist, }{e98y2gf9kY`~EcWYSs=a:+:operator_add]
    lW: 検出id海岸補助 %s %s | inputs[P@rlK(*{6vgWDo/X,KJT=c;n:data_itemoflist, }{e98y2gf9kY`~EcWYSs=a:,:operator_subtract]
    c;m: data_changevariableby | fields[VARIABLE=カウント1] | inputs[VALUE='1']
a:T: data_setvariableto | fields[VARIABLE=カウント1] | inputs[VALUE='0']
a:-: data_setvariableto | fields[VARIABLE=カウント2] | inputs[VALUE='1']
lX: control_repeat | inputs[TIMES=c;p:data_lengthoflist]
  SUBSTACK:
    lY: control_if | inputs[CONDITION=a:/:operator_not]
      SUBSTACK:
        c;q: data_changevariableby | fields[VARIABLE=カウント2] | inputs[VALUE='1']
    lZ: control_if | inputs[CONDITION=a:?:operator_not]
      SUBSTACK:
        Xy: data_setvariableto | fields[VARIABLE=多目的0] | inputs[VALUE=a:^:operator_multiply]
        Xz: control_if | inputs[CONDITION=XA:operator_or]
          SUBSTACK:
            XB: control_if | inputs[CONDITION=XD:operator_lt]
              SUBSTACK:
                XE: control_if | inputs[CONDITION=XF:operator_and]
                  SUBSTACK:
                    l!: data_replaceitemoflist | fields[LIST=4-3 検出id別情報] | inputs[INDEX=c;F:operator_add, ITEM=a;s:data_itemoflist]
                    l#: control_if_else | inputs[CONDITION=a;v:operator_equals]
                      SUBSTACK:
                        XJ: 震度上昇効果音 %s %s %s | inputs[Lu1nilfTMT@Z4/*MCo++='-4', m|AmLW7j4(fMJ-riJH;w=a;x:data_itemoflist, JKoD%0yMPZI92t{{%e@,=c;I:operator_add]
                      SUBSTACK2:
                        l%: 震度上昇効果音 %s %s %s | inputs[Lu1nilfTMT@Z4/*MCo++=a;y:data_itemoflist, m|AmLW7j4(fMJ-riJH;w=a;z:data_itemoflist, JKoD%0yMPZI92t{{%e@,=c;K:operator_add]
    c;s: data_changevariableby | fields[VARIABLE=カウント1] | inputs[VALUE='1']
a:.: data_replaceitemoflist | fields[LIST=@1 hyp:震源計算] | inputs[INDEX='15', ITEM='カウント2']
a;A: data_setvariableto | fields[VARIABLE=カウント1] | inputs[VALUE='0']
XK: control_repeat_until | inputs[CONDITION=XL:operator_lt]
  SUBSTACK:
    l(: control_if | inputs[CONDITION=a;C:data_itemoflist]
      SUBSTACK:
        XM: control_if | inputs[CONDITION=a;E:operator_lt]
          SUBSTACK:
            XN: data_replaceitemoflist | fields[LIST=4-3 検出id別情報] | inputs[INDEX=a;H:operator_add, ITEM=c;S:operator_equals]
    c;P: data_changevariableby | fields[VARIABLE=カウント1] | inputs[VALUE='1']
```

### `検出id2_各点の許可idと推定用をセット %s %s %s %s`

- Definition block: `a-!`
- Prototype block: `bY`
- Arguments: `番号, 変化速度, 現在状態, 7点スタート`

```text
bX: control_if_else | inputs[CONDITION=a-#:operator_lt]
  SUBSTACK:
    bZ: control_if_else | inputs[CONDITION=a-(:operator_lt]
      SUBSTACK:
        WM: control_if | inputs[CONDITION=a-::operator_equals]
          SUBSTACK:
            WQ: data_replaceitemoflist | fields[LIST=ten:推定用] | inputs[INDEX=a-[:operator_add, ITEM=c/U:data_itemoflist]
      SUBSTACK2:
        WN: control_if | inputs[CONDITION=a-_:operator_not]
          SUBSTACK:
            a-`: data_replaceitemoflist | fields[LIST=ten:推定用] | inputs[INDEX=a.b:operator_add, ITEM='']
    lD: control_if_else | inputs[CONDITION=WR:operator_and]
      SUBSTACK:
        a.e: data_setvariableto | fields[VARIABLE=多目的0] | inputs[VALUE='0']
        a.m: data_setvariableto | fields[VARIABLE=多目的1] | inputs[VALUE='0']
        b#: control_if_else | inputs[CONDITION=a.n:operator_lt]
          SUBSTACK:
            lE: control_if_else | inputs[CONDITION=a.o:operator_lt]
              SUBSTACK:
                WU: data_setvariableto | fields[VARIABLE=カウント2] | inputs[VALUE=a.q:operator_add]
                a.p: control_repeat | inputs[TIMES='7']
                  SUBSTACK:
                    WV: data_changevariableby | fields[VARIABLE=多目的0] | inputs[VALUE=a.r:operator_equals]
                    lF: control_if | inputs[CONDITION=a.t:operator_lt]
                      SUBSTACK:
                        a.u: data_changevariableby | fields[VARIABLE=多目的1] | inputs[VALUE=a.z:data_itemoflist]
                    c/*: data_changevariableby | fields[VARIABLE=カウント2] | inputs[VALUE='2']
              SUBSTACK2:
                c/#: data_setvariableto | fields[VARIABLE=多目的0] | inputs[VALUE='1']
          SUBSTACK2:
            WT: control_if | inputs[CONDITION=a.D:operator_equals]
              SUBSTACK:
                c/-: data_setvariableto | fields[VARIABLE=多目的0] | inputs[VALUE='1']
        WS: control_if | inputs[CONDITION=c//:operator_lt]
          SUBSTACK:
            b%: control_if_else | inputs[CONDITION=a.F:operator_equals]
              SUBSTACK:
                lG: control_if_else | inputs[CONDITION=WW:operator_and]
                  SUBSTACK:
                    WX: data_replaceitemoflist | fields[LIST=ten:推定用] | inputs[INDEX=a.M:operator_add, ITEM='多目的1']
                    WY: data_replaceitemoflist | fields[LIST=ten:推定用] | inputs[INDEX=a.P:operator_add, ITEM=c/@:data_itemoflist]
                  SUBSTACK2:
                    lI: data_replaceitemoflist | fields[LIST=ten:推定用] | inputs[INDEX=a.S:operator_add, ITEM=c/]:data_itemoflist]
                    WZ: data_replaceitemoflist | fields[LIST=ten:推定用] | inputs[INDEX=a.V:operator_add, ITEM=c/_:data_itemoflist]
              SUBSTACK2:
                lH: data_replaceitemoflist | fields[LIST=ten:推定用] | inputs[INDEX=a.Y:operator_add, ITEM=a.Z:data_itemoflist]
                W!: data_replaceitemoflist | fields[LIST=ten:推定用] | inputs[INDEX=a.*:operator_add, ITEM=a.+:data_itemoflist]
            a.E: 検出id3_点にIDを登録 %s %b | inputs[PK6Ipg/`h0KI=,OV@(/m=$番号]
      SUBSTACK2:
        b!: control_if_else | inputs[CONDITION=W%:operator_and]
          SUBSTACK:
            W(: data_setvariableto | fields[VARIABLE=カウント2] | inputs[VALUE=a.@:operator_add]
            a.?: data_setvariableto | fields[VARIABLE=多目的0] | inputs[VALUE='0']
            a.[: data_setvariableto | fields[VARIABLE=多目的1] | inputs[VALUE='0']
            W*: control_repeat | inputs[TIMES='7']
              SUBSTACK:
                lJ: control_if | inputs[CONDITION=W,:operator_and]
                  SUBSTACK:
                    a.]: data_changevariableby | fields[VARIABLE=多目的0] | inputs[VALUE='10000000']
                    W/: control_if | inputs[CONDITION=a.~:operator_equals]
                      SUBSTACK:
                        c:i: data_changevariableby | fields[VARIABLE=多目的0] | inputs[VALUE='20000']
                lK: control_if_else | inputs[CONDITION=W;:operator_and]
                  SUBSTACK:
                    W=: data_changevariableby | fields[VARIABLE=多目的0] | inputs[VALUE=a/f:operator_add]
                    W?: control_if | inputs[CONDITION=W@:operator_lt]
                      SUBSTACK:
                        a/h: data_setvariableto | fields[VARIABLE=多目的0] | inputs[VALUE=c:p:operator_divide]
                W:: data_changevariableby | fields[VARIABLE=多目的1] | inputs[VALUE=a/q:data_itemoflist]
                c:q: data_changevariableby | fields[VARIABLE=カウント2] | inputs[VALUE='2']
            W+: data_setvariableto | fields[VARIABLE=多目的1] | inputs[VALUE=c:s:operator_divide]
            W[: data_setvariableto | fields[VARIABLE=多目的1] | inputs[VALUE=W]:operator_multiply]
            lL: control_if_else | inputs[CONDITION=W^:operator_or]
              SUBSTACK:
                lM: control_if_else | inputs[CONDITION=c:z:operator_lt]
                  SUBSTACK:
                    lN: 点許可状態更新 %s %s %s %b | inputs[;[?.?JT(]5(f^/tV4Zu*=$番号, #S%)!7,AqB`GM~6J?v=u='5', )o*TMC[I6Rt,C(kphQ7I='再び震度加速', btp_G:Ff8nQ9.^CI0kFU=c:B:operator_not]
                    b(: control_if_else | inputs[CONDITION=a/A:operator_equals]
                      SUBSTACK:
                        lO: data_replaceitemoflist | fields[LIST=ten:推定用] | inputs[INDEX=a/F:operator_add, ITEM=c:D:data_itemoflist]
                        W~: data_replaceitemoflist | fields[LIST=ten:推定用] | inputs[INDEX=a/I:operator_add, ITEM=c:F:data_itemoflist]
                      SUBSTACK2:
                        lP: data_replaceitemoflist | fields[LIST=ten:推定用] | inputs[INDEX=a/L:operator_add, ITEM=a/M:data_itemoflist]
                        Xa: data_replaceitemoflist | fields[LIST=ten:推定用] | inputs[INDEX=a/S:operator_add, ITEM=a/T:data_itemoflist]
                    W}: 検出id3_点にIDを登録 %s %b | inputs[PK6Ipg/`h0KI=,OV@(/m=$番号, ftG|FNjqfiOB_,6TPnDY=c:M:operator_not]
                  SUBSTACK2:
                    W|: 点許可状態更新 %s %s %s %b | inputs[;[?.?JT(]5(f^/tV4Zu*=$番号, #S%)!7,AqB`GM~6J?v=u='6', )o*TMC[I6Rt,C(kphQ7I='再び震度加速用待機', btp_G:Ff8nQ9.^CI0kFU=c:O:operator_not]
              SUBSTACK2:
                W_: control_if | inputs[CONDITION=a/Z:operator_equals]
                  SUBSTACK:
                    Xb: data_replaceitemoflist | fields[LIST=ten:推定用] | inputs[INDEX=a/!:operator_add, ITEM=c:Q:data_itemoflist]
          SUBSTACK2:
            W): control_if | inputs[CONDITION=Xc:operator_or]
              SUBSTACK:
                a/(: 検出id_点の推定用をリセット %s | inputs[M0:kdR4x)(?|bUO1K:U7=$番号]
        W#: control_if | inputs[CONDITION=a/~:operator_equals]
          SUBSTACK:
            Xl: data_setvariableto | fields[VARIABLE=多目的1] | inputs[VALUE=Xn:operator_subtract]
            Xm: control_if | inputs[CONDITION=Xo:operator_and]
              SUBSTACK:
                a:e: 点許可状態更新 %s %s %s %b | inputs[;[?.?JT(]5(f^/tV4Zu*=$番号, #S%)!7,AqB`GM~6J?v=u='6', )o*TMC[I6Rt,C(kphQ7I='震度上昇無し40秒']
  SUBSTACK2:
    WL: control_if | inputs[CONDITION=a:m:operator_not]
      SUBSTACK:
        a:n: 検出id_点の推定用をリセット %s | inputs[M0:kdR4x)(?|bUO1K:U7=$番号]
WK: control_if | inputs[CONDITION=a:t:operator_not]
  SUBSTACK:
    Xq: control_if | inputs[CONDITION=Xr:operator_or]
      SUBSTACK:
        Xs: 検出id_点の推定用をリセット %s | inputs[M0:kdR4x)(?|bUO1K:U7=$番号]
        Xt: control_if | inputs[CONDITION=a:J:operator_equals]
          SUBSTACK:
            a:K: 点許可状態更新 %s %s %s %b | inputs[;[?.?JT(]5(f^/tV4Zu*=$番号, #S%)!7,AqB`GM~6J?v=u='6', )o*TMC[I6Rt,C(kphQ7I='無効からの震度上昇無し50秒']
```

### `検出id3_点にIDを登録 %s %b`

- Definition block: `a;I`
- Prototype block: `XO`
- Arguments: `点番号, 再上昇`

```text
l): control_if | inputs[CONDITION=a;J:operator_not]
  SUBSTACK:
    XP: 検出id適用数カウント追加 %s %b %s | inputs[y:F|`*?l]NVyF1!(6L;x=$点番号, bl6#g!fJU0hl:`G)=qG1=c;Y:operator_not, xOeHlykhk^(q[zTZkw0P='-1']
b*: control_if_else | inputs[CONDITION=XQ:operator_and]
  SUBSTACK:
    a;P: data_setvariableto | fields[VARIABLE=カウント2] | inputs[VALUE=a;S:operator_divide]
  SUBSTACK2:
    XR: 検出id4_点に適用するべきIDを検索 %s %b | inputs[ZoBco^R=l[T]v6Hn.D?8=$点番号, 1NcshkJJEu|y[k]u~TLr=$再上昇]
b+: control_if_else | inputs[CONDITION=c;):operator_lt]
  SUBSTACK:
    a;T: data_replaceitemoflist | fields[LIST=ten:推定用] | inputs[INDEX=a;U:operator_add, ITEM='カウント2']
  SUBSTACK2:
    l+: control_if_else | inputs[CONDITION=a;X:operator_not]
      SUBSTACK:
        l,: control_if | inputs[CONDITION=a;Y:sensing_keypressed]
          SUBSTACK:
            XT: ​​log​​ %s | inputs[arg0=$点番号]
            c;-: ​​breakpoint​​
        l-: 検出id_新規id追加 %s %b | inputs[8}Uc7Rl1OpRWlCRVbMb==$点番号, =TMeg-`7/.TfhuqxQG/9=$再上昇]
        XU: data_replaceitemoflist | fields[LIST=ten:推定用] | inputs[INDEX=a;Z:operator_add, ITEM=a;!:operator_divide]
      SUBSTACK2:
        XS: 検出id_点の推定用をリセット %s | inputs[M0:kdR4x)(?|bUO1K:U7=$点番号]
        c;?: control_stop | fields[STOP_OPTION=this script]
l*: data_replaceitemoflist | fields[LIST=grid:検出id] | inputs[INDEX=a;(:data_itemoflist, ITEM=a;):data_itemoflist]
l.: data_replaceitemoflist | fields[LIST=grid:検出id時間] | inputs[INDEX=a;-:data_itemoflist, ITEM=c;^:data_itemoflist]
XV: 検出id適用数カウント追加 %s %b %s | inputs[y:F|`*?l]NVyF1!(6L;x=$点番号, bl6#g!fJU0hl:`G)=qG1=c;{:operator_not, xOeHlykhk^(q[zTZkw0P='1']
```

### `検出id4_点に適用するべきIDを検索 %s %b`

- Definition block: `a[q`
- Prototype block: `YT`
- Arguments: `点番号, 再上昇`

```text
a[r: data_setvariableto | fields[VARIABLE=カウント2] | inputs[VALUE='0']
mi: control_if | inputs[CONDITION=a[s:sensing_keypressed]
  SUBSTACK:
    a[t: ​​log​​ %s | inputs[arg0=a[u:operator_join]
mj: 検出id4-1_適用id最短7から候補選択 %s %s %s | inputs[e?]MV)aiq)H!+v}W(z2T=a[w:operator_add, -s%yx:?g2k%lD(Pq34(U='', J`|iYKx:W/?(ACxZiz(w=$点番号]
mk: control_if | inputs[CONDITION=a[z:operator_not]
  SUBSTACK:
    YU: control_if | inputs[CONDITION=a[A:sensing_keypressed]
      SUBSTACK:
        a[B: ​​log​​ %s | inputs[arg0=c@f:operator_join]
ml: control_if | inputs[CONDITION=c@g:operator_equals]
  SUBSTACK:
    YV: control_if | inputs[CONDITION=YW:operator_and]
      SUBSTACK:
        ah: 緯度経度で距離km(多目的0) xy1 %s %s xy2 %s %s | inputs[]{P@NqNQS3.9ZW^L7/Id=a[M:data_itemoflist, v4!`%fK.fAl-7,*LjmoN=a[N:data_itemoflist, PD=h#Y$/m@?PDZm(Qn:L=a[O:data_itemoflist, ;:CHeDp67!I+0u0Hv{UC=a[P:data_itemoflist]
        Y#: control_if | inputs[CONDITION=c@r:operator_lt]
          SUBSTACK:
            Y%: data_setvariableto | fields[VARIABLE=カウント2] | inputs[VALUE=a[U:operator_divide]
            mn: control_if | inputs[CONDITION=a[V:sensing_keypressed]
              SUBSTACK:
                a[W: ​​log​​ %s | inputs[arg0=c@v:operator_join]
            c@t: control_stop | fields[STOP_OPTION=this script]
mm: control_if | inputs[CONDITION=Y(:operator_and]
  SUBSTACK:
    mp: control_if | inputs[CONDITION=a[Y:sensing_keypressed]
      SUBSTACK:
        a[Z: ​​log​​ %s | inputs[arg0=a[!:data_itemoflist]
    Y): control_if | inputs[CONDITION=Y*:operator_and]
      SUBSTACK:
        Y+: data_setvariableto | fields[VARIABLE=カウント2] | inputs[VALUE=a[-:data_itemoflist]
        mq: control_if | inputs[CONDITION=a[/:sensing_keypressed]
          SUBSTACK:
            Y-: ​​log​​ %s | inputs[arg0=a[;:data_itemoflist]
            a[:: ​​log​​ %s | inputs[arg0=c@H:operator_join]
        c@E: control_stop | fields[STOP_OPTION=this script]
mo: control_if | inputs[CONDITION=c@I:operator_equals]
  SUBSTACK:
    a[?: 検出id4-2_適用id震源から候補選択 %s %s %s %s %s %s | inputs[SfsPQ05=H3bXdT?LdvL+=$点番号, gWBY16E2o.0z[=BXRz/;='', [NPkP|/Bht[PEYIpV}`x='', ZKLp$9%HhQC{5(gP%9X,='', zJNWwKY*VB-8R8bu4i(O='', ekw[WZS`jw4;NwLv|jj6='']
mr: control_if | inputs[CONDITION=c@K:operator_equals]
  SUBSTACK:
    a[@: data_setvariableto | fields[VARIABLE=カウント3] | inputs[VALUE='-9']
    Y.: 周囲9grid最大震度or上昇(多目的0,1) %s %s | inputs[FB4`R.nq]SrcY1W8?Si2=a[[:data_itemoflist, X9.gM58+(q~bPs{p}@Dg='']
    Y/: control_if | inputs[CONDITION=Y::operator_or]
      SUBSTACK:
        a[]: data_setvariableto | fields[VARIABLE=カウント2] | inputs[VALUE='0']
        mt: control_if | inputs[CONDITION=a]g:sensing_keypressed]
          SUBSTACK:
            a]h: ​​log​​ %s | inputs[arg0=c@S:operator_join]
        c@Q: control_stop | fields[STOP_OPTION=this script]
ms: control_if | inputs[CONDITION=c@T:operator_equals]
  SUBSTACK:
    Y@: control_if | inputs[CONDITION=Y[:operator_or]
      SUBSTACK:
        a]i: data_setvariableto | fields[VARIABLE=多目的1] | inputs[VALUE='0']
        Y]: 検出id_周囲gridの最新ID検索 %s %s %s %s | inputs[WQ69[qI~Q^Ey(5+.Mg7a='', :wWYlkm51n#O8Cy{2d/i=a]q:data_itemoflist, fwA,l^1vh~)m0v5tUi1a='', BKrpGB%L1xi5A+m*-Xkq='']
        Y^: control_if | inputs[CONDITION=a]r:operator_not]
          SUBSTACK:
            ai: 緯度経度で距離km(多目的0) xy1 %s %s xy2 %s %s | inputs[]{P@NqNQS3.9ZW^L7/Id=a]s:data_itemoflist, v4!`%fK.fAl-7,*LjmoN=a]t:data_itemoflist, PD=h#Y$/m@?PDZm(Qn:L=a]u:data_itemoflist, ;:CHeDp67!I+0u0Hv{UC=a]v:data_itemoflist]
            Y_: control_if | inputs[CONDITION=a]A:operator_lt]
              SUBSTACK:
                a]B: data_setvariableto | fields[VARIABLE=カウント2] | inputs[VALUE='多目的1']
                Y`: control_if | inputs[CONDITION=a]G:sensing_keypressed]
                  SUBSTACK:
                    mu: control_if | inputs[CONDITION=c@):operator_equals]
                      SUBSTACK:
                        c@*: ​​breakpoint​​
                    a]H: ​​log​​ %s | inputs[arg0=c@+:operator_join]
Y?: control_if | inputs[CONDITION=c@,:operator_equals]
  SUBSTACK:
    Y{: control_if | inputs[CONDITION=a]I:operator_lt]
      SUBSTACK:
        c@-: data_setvariableto | fields[VARIABLE=カウント2] | inputs[VALUE='-1']
```

### `検出id4-1_適用id最短7から候補選択 %s %s %s`

- Definition block: `bj,`
- Prototype block: `pn`
- Arguments: `7点オフセット, 推定用オフセット, 点番号`

```text
pm: control_if_else | inputs[CONDITION=bj-:operator_equals]
  SUBSTACK:
    bj.: data_setvariableto | fields[VARIABLE=多目的1] | inputs[VALUE='10']
    bj/: data_setvariableto | fields[VARIABLE=カウント3] | inputs[VALUE='0']
    +o: control_repeat_until | inputs[CONDITION=+p:operator_or]
      SUBSTACK:
        ck: 検出id4-1_適用id最短7から候補選択 %s %s %s | inputs[e?]MV)aiq)H!+v}W(z2T=$7点オフセット, -s%yx:?g2k%lD(Pq34(U=bj@:operator_multiply, J`|iYKx:W/?(ACxZiz(w=$点番号]
        dg@: data_changevariableby | fields[VARIABLE=カウント3] | inputs[VALUE='2']
  SUBSTACK2:
    +n: control_if | inputs[CONDITION=+q:operator_and]
      SUBSTACK:
        +r: data_setvariableto | fields[VARIABLE=多目的0] | inputs[VALUE=bkg:operator_mathop]
        +t: control_if | inputs[CONDITION=dg~:operator_lt]
          SUBSTACK:
            +v: data_setvariableto | fields[VARIABLE=カウント2] | inputs[VALUE=bkn:operator_add]
            dha: data_setvariableto | fields[VARIABLE=多目的1] | inputs[VALUE='多目的0']
```

### `検出id4-2_適用id震源から候補選択 %s %s %s %s %s %s`

- Definition block: `bkq`
- Prototype block: `P`
- Arguments: `点番号, x, y, 深さ, 発生時刻, 4-3オフセット`

```text
po: control_if_else | inputs[CONDITION=bkr:operator_equals]
  SUBSTACK:
    +w: data_setvariableto | fields[VARIABLE=多目的1] | inputs[VALUE=dhj:operator_divide]
    +x: data_setvariableto | fields[VARIABLE=カウント3] | inputs[VALUE=bks:operator_divide]
    +y: control_repeat | inputs[TIMES=bkt:operator_divide]
      SUBSTACK:
        +z: data_setvariableto | fields[VARIABLE=多目的0] | inputs[VALUE=bku:operator_multiply]
        pp: control_if | inputs[CONDITION=bkv:data_itemoflist]
          SUBSTACK:
            pq: control_if_else | inputs[CONDITION=+A:operator_and]
              SUBSTACK:
                +B: data_setvariableto | fields[VARIABLE=多目的0] | inputs[VALUE=bkE:operator_multiply]
                pr: control_if | inputs[CONDITION=bkF:sensing_keypressed]
                  SUBSTACK:
                    bkG: ​​log​​ %s | inputs[arg0=+F:operator_join]
                Q: 検出id4-2_適用id震源から候補選択 %s %s %s %s %s %s | inputs[SfsPQ05=H3bXdT?LdvL+=$点番号, gWBY16E2o.0z[=BXRz/;=bkI:data_itemoflist, [NPkP|/Bht[PEYIpV}`x=bkJ:data_itemoflist, ZKLp$9%HhQC{5(gP%9X,=bkK:data_itemoflist, zJNWwKY*VB-8R8bu4i(O=bkL:data_itemoflist, ekw[WZS`jw4;NwLv|jj6=dhy:operator_multiply]
              SUBSTACK2:
                +C: control_if | inputs[CONDITION=bkM:operator_lt]
                  SUBSTACK:
                    +G: data_setvariableto | fields[VARIABLE=多目的0] | inputs[VALUE=bkO:data_itemoflist]
                    ps: control_if | inputs[CONDITION=bkP:sensing_keypressed]
                      SUBSTACK:
                        bkQ: ​​log​​ %s | inputs[arg0=+H:operator_join]
                    cl: 検出id4-2_適用id震源から候補選択 %s %s %s %s %s %s | inputs[SfsPQ05=H3bXdT?LdvL+=$点番号, gWBY16E2o.0z[=BXRz/;=dhJ:data_itemoflist, [NPkP|/Bht[PEYIpV}`x=dhK:data_itemoflist, ZKLp$9%HhQC{5(gP%9X,='10', zJNWwKY*VB-8R8bu4i(O=bkS:operator_subtract, ekw[WZS`jw4;NwLv|jj6='多目的0']
        dhn: data_changevariableby | fields[VARIABLE=カウント3] | inputs[VALUE='-1']
  SUBSTACK2:
    av: 緯度経度で距離km(多目的0) xy1 %s %s xy2 %s %s | inputs[]{P@NqNQS3.9ZW^L7/Id=bkW:data_itemoflist, v4!`%fK.fAl-7,*LjmoN=bkX:data_itemoflist, PD=h#Y$/m@?PDZm(Qn:L=$x, ;:CHeDp67!I+0u0Hv{UC=$y]
    pt: control_if | inputs[CONDITION=+I:operator_and]
      SUBSTACK:
        dhQ: control_stop | fields[STOP_OPTION=this script]
    aw: JMA2001距離近似: %s %s %b %b | inputs[)mGAodyW$Qxr28i|bA^^=bk;:operator_mathop, TeevruD^wB$OTE*kFu!]=$深さ, .Mvwp@L}y=pm:g13O%*m=dhZ:operator_not, a-hp9v4l7{(gt*_Fd~:p=dh!:operator_not]
    +O: data_setvariableto | fields[VARIABLE=多目的2] | inputs[VALUE=bk=:operator_add]
    pu: control_if | inputs[CONDITION=bk?:sensing_keypressed]
      SUBSTACK:
        bk@: ​​log​​ %s | inputs[arg0=bk[:operator_join]
    pv: control_if | inputs[CONDITION=+R:operator_lt]
      SUBSTACK:
        cm: JMA2001距離近似: %s %s %b %b | inputs[)mGAodyW$Qxr28i|bA^^=blf:operator_mathop, TeevruD^wB$OTE*kFu!]=$深さ, a-hp9v4l7{(gt*_Fd~:p=dh/:operator_not]
        px: control_if | inputs[CONDITION=blg:sensing_keypressed]
          SUBSTACK:
            blh: ​​log​​ %s | inputs[arg0=bli:operator_join]
        +U: control_if | inputs[CONDITION=+Y:operator_or]
          SUBSTACK:
            dh_: control_stop | fields[STOP_OPTION=this script]
    pw: control_if | inputs[CONDITION=blI:sensing_keypressed]
      SUBSTACK:
        blJ: ​​log​​ %s | inputs[arg0=blK:operator_join]
    +%: control_if | inputs[CONDITION=blR:operator_lt]
      SUBSTACK:
        py: control_if | inputs[CONDITION=blZ:sensing_keypressed]
          SUBSTACK:
            bl!: ​​log​​ %s | inputs[arg0=dih:operator_join]
        blY: data_setvariableto | fields[VARIABLE=カウント2] | inputs[VALUE='カウント3']
        bl#: data_setvariableto | fields[VARIABLE=多目的1] | inputs[VALUE=bl%:operator_mathop]
```

### `検出id適用数カウント追加 %s %b %s`

- Definition block: `a;.`
- Prototype block: `l/`
- Arguments: `番号, 距離セット, 変更数`

```text
XW: data_setvariableto | fields[VARIABLE=カウント3] | inputs[VALUE=a;/:operator_multiply]
l:: control_if_else | inputs[CONDITION=a;[:data_itemoflist]
  SUBSTACK:
    l;: data_replaceitemoflist | fields[LIST=4-3 検出id別情報] | inputs[INDEX=c=c:operator_add, ITEM=XZ:operator_add]
    XY: control_if | inputs[CONDITION=$距離セット]
      SUBSTACK:
        l=: 推定用tenPS時間計算(多目的0,2使用) %s %s | inputs[=K;P8qcRFIPj?hma3imV=$番号, :*7KND/I:]v=#|F`A0PK=a;_:data_itemoflist]
        a;^: 検出id距離計算 %s %s | inputs[rAF)lvBWa*x?S:/i*+ss=$番号, ]GcXz8r37D=Oy+^q_DPj='カウント3']
  SUBSTACK2:
    XX: control_if | inputs[CONDITION=a;}:operator_lt]
      SUBSTACK:
        a;~: 検出id_点の推定用をリセット %s | inputs[M0:kdR4x)(?|bUO1K:U7=$番号]
```

### `推定用tenPS時間計算(多目的0,2使用) %s %s`

- Definition block: `a=*`
- Prototype block: `X|`
- Arguments: `番号, id`

```text
X{: data_setvariableto | fields[VARIABLE=多目的2] | inputs[VALUE=a=+:operator_multiply]
l{: control_if_else | inputs[CONDITION=X}:operator_or]
  SUBSTACK:
    X~: data_replaceitemoflist | fields[LIST=ten:推定用] | inputs[INDEX=a=?:operator_add, ITEM='']
    a==: data_replaceitemoflist | fields[LIST=ten:推定用] | inputs[INDEX=a=]:operator_add, ITEM='']
  SUBSTACK2:
    ag: 緯度経度で距離km(多目的0) xy1 %s %s xy2 %s %s | inputs[]{P@NqNQS3.9ZW^L7/Id=a=`:data_itemoflist, v4!`%fK.fAl-7,*LjmoN=a={:data_itemoflist, PD=h#Y$/m@?PDZm(Qn:L=a=|:data_itemoflist, ;:CHeDp67!I+0u0Hv{UC=a=}:data_itemoflist]
    Ya: data_setvariableto | fields[VARIABLE=多目的0] | inputs[VALUE=a?b:operator_mathop]
    b.: JMA2001距離近似: %s %s %b %b | inputs[)mGAodyW$Qxr28i|bA^^='多目的0', TeevruD^wB$OTE*kFu!]=a?g:data_itemoflist, .Mvwp@L}y=pm:g13O%*m=c=^:operator_not, a-hp9v4l7{(gt*_Fd~:p=c=_:operator_not]
    l|: data_replaceitemoflist | fields[LIST=ten:推定用] | inputs[INDEX=a?i:operator_add, ITEM=a?j:operator_add]
    l}: JMA2001距離近似: %s %s %b %b | inputs[)mGAodyW$Qxr28i|bA^^='多目的0', TeevruD^wB$OTE*kFu!]=a?o:data_itemoflist, a-hp9v4l7{(gt*_Fd~:p=c=}:operator_not]
    l~: data_replaceitemoflist | fields[LIST=ten:推定用] | inputs[INDEX=a?q:operator_add, ITEM=a?r:operator_add]
    Yd: data_replaceitemoflist | fields[LIST=ten:推定用] | inputs[INDEX=a?w:operator_add, ITEM=Ye:operator_lt]
```

### `検出id_推定PS時間id別再計算 %s`

- Definition block: `a?R`
- Prototype block: `a?T`
- Arguments: `id`

```text
a?S: data_setvariableto | fields[VARIABLE=カウント1] | inputs[VALUE='0']
Yh: control_repeat | inputs[TIMES=c?i:data_lengthoflist]
  SUBSTACK:
    ma: control_if | inputs[CONDITION=a?U:operator_lt]
      SUBSTACK:
        Yi: data_setvariableto | fields[VARIABLE=カウント2] | inputs[VALUE=a?X:operator_add]
        Yj: control_repeat_until | inputs[CONDITION=a?Y:operator_equals]
          SUBSTACK:
            mb: control_if | inputs[CONDITION=Yk:operator_equals]
              SUBSTACK:
                Yl: 推定用tenPS時間計算(多目的0,2使用) %s %s | inputs[=K;P8qcRFIPj?hma3imV=c?q:data_itemoflist, :*7KND/I:]v=#|F`A0PK=$id]
            c?n: data_changevariableby | fields[VARIABLE=カウント2] | inputs[VALUE='1']
    c?j: data_changevariableby | fields[VARIABLE=カウント1] | inputs[VALUE='1']
```

### `検出id_グリッド別idと存在idをセット %s %s %s`

- Definition block: `bgc`
- Prototype block: `oN`
- Arguments: `番号, id, 含まれるオフセット`

```text
oM: control_if_else | inputs[CONDITION=bgd:operator_equals]
  SUBSTACK:
    bge: data_deletealloflist | fields[LIST=@1 grid存在id]
    bgf: data_setvariableto | fields[VARIABLE=カウント1] | inputs[VALUE='1']
    )^: control_repeat | inputs[TIMES=ddO:data_lengthoflist]
      SUBSTACK:
        oO: control_if | inputs[CONDITION=bgg:operator_lt]
          SUBSTACK:
            oP: 検出id_グリッド別idと存在idをセット %s %s %s | inputs[D}h{Gh9?O|ep-4cj.O.6=ddR:data_itemoflist, n(;^X2btKi2:X4t3.|OL=bgi:data_itemoflist, eO8rY@:@x=0na2Rm)XqM=bgj:operator_add]
        ddP: data_changevariableby | fields[VARIABLE=カウント1] | inputs[VALUE='1']
  SUBSTACK2:
    )]: data_setvariableto | fields[VARIABLE=多目的1] | inputs[VALUE=bgl:data_itemoflist]
    )_: data_replaceitemoflist | fields[LIST=grid:検出id] | inputs[INDEX=$番号, ITEM='']
    )`: data_setvariableto | fields[VARIABLE=カウント2] | inputs[VALUE=$含まれるオフセット]
    ){: control_repeat_until | inputs[CONDITION=bgm:operator_equals]
      SUBSTACK:
        )|: data_setvariableto | fields[VARIABLE=多目的0] | inputs[VALUE=bgn:operator_multiply]
        oQ: control_if | inputs[CONDITION=bgp:operator_equals]
          SUBSTACK:
            )}: data_replaceitemoflist | fields[LIST=grid:検出id] | inputs[INDEX=$番号, ITEM='多目的1']
            oR: control_if | inputs[CONDITION=bgr:operator_not]
              SUBSTACK:
                bgs: data_addtolist | fields[LIST=@1 grid存在id] | inputs[ITEM=bgu:data_itemoflist]
            dd%: control_stop | fields[STOP_OPTION=this script]
        ddZ: data_changevariableby | fields[VARIABLE=カウント2] | inputs[VALUE='1']
```

### `検出id_周囲gridの最新ID検索 %s %s %s %s`

- Definition block: `a{@`
- Prototype block: `b@`
- Arguments: `番号, 初期, 指定id, 最大範囲012`

```text
m[: control_if_else | inputs[CONDITION=a{[:operator_equals]
  SUBSTACK:
    a{]: data_setvariableto | fields[VARIABLE=多目的0] | inputs[VALUE='0']
    m]: 検出id_周囲gridの最新ID検索 %s %s %s %s | inputs[WQ69[qI~Q^Ey(5+.Mg7a=a{^:operator_add, :wWYlkm51n#O8Cy{2d/i='', fwA,l^1vh~)m0v5tUi1a=$指定id, BKrpGB%L1xi5A+m*-Xkq='']
    m^: 検出id_周囲gridの最新ID検索 %s %s %s %s | inputs[WQ69[qI~Q^Ey(5+.Mg7a=a{_:operator_add, :wWYlkm51n#O8Cy{2d/i='', fwA,l^1vh~)m0v5tUi1a=$指定id, BKrpGB%L1xi5A+m*-Xkq='']
    m_: 検出id_周囲gridの最新ID検索 %s %s %s %s | inputs[WQ69[qI~Q^Ey(5+.Mg7a=a{`:operator_subtract, :wWYlkm51n#O8Cy{2d/i='', fwA,l^1vh~)m0v5tUi1a=$指定id, BKrpGB%L1xi5A+m*-Xkq='']
    m`: 検出id_周囲gridの最新ID検索 %s %s %s %s | inputs[WQ69[qI~Q^Ey(5+.Mg7a=a{{:operator_subtract, :wWYlkm51n#O8Cy{2d/i='', fwA,l^1vh~)m0v5tUi1a=$指定id, BKrpGB%L1xi5A+m*-Xkq='']
    m{: 検出id_周囲gridの最新ID検索 %s %s %s %s | inputs[WQ69[qI~Q^Ey(5+.Mg7a=a{|:operator_subtract, :wWYlkm51n#O8Cy{2d/i='', fwA,l^1vh~)m0v5tUi1a=$指定id, BKrpGB%L1xi5A+m*-Xkq='']
    m|: 検出id_周囲gridの最新ID検索 %s %s %s %s | inputs[WQ69[qI~Q^Ey(5+.Mg7a=a{}:operator_add, :wWYlkm51n#O8Cy{2d/i='', fwA,l^1vh~)m0v5tUi1a=$指定id, BKrpGB%L1xi5A+m*-Xkq='']
    m}: 検出id_周囲gridの最新ID検索 %s %s %s %s | inputs[WQ69[qI~Q^Ey(5+.Mg7a=a{~:operator_subtract, :wWYlkm51n#O8Cy{2d/i='', fwA,l^1vh~)m0v5tUi1a=$指定id, BKrpGB%L1xi5A+m*-Xkq='']
    m~: 検出id_周囲gridの最新ID検索 %s %s %s %s | inputs[WQ69[qI~Q^Ey(5+.Mg7a=a|a:operator_add, :wWYlkm51n#O8Cy{2d/i='', fwA,l^1vh~)m0v5tUi1a=$指定id, BKrpGB%L1xi5A+m*-Xkq='']
    #d: 検出id_周囲gridの最新ID検索 %s %s %s %s | inputs[WQ69[qI~Q^Ey(5+.Mg7a=$初期, :wWYlkm51n#O8Cy{2d/i='', fwA,l^1vh~)m0v5tUi1a=$指定id, BKrpGB%L1xi5A+m*-Xkq='']
  SUBSTACK2:
    #c: control_if | inputs[CONDITION=a|b:operator_not]
      SUBSTACK:
        #e: control_if | inputs[CONDITION=#f:operator_or]
          SUBSTACK:
            #g: control_if | inputs[CONDITION=a|g:operator_lt]
              SUBSTACK:
                #i: data_setvariableto | fields[VARIABLE=多目的1] | inputs[VALUE=a|k:data_itemoflist]
                a|j: data_setvariableto | fields[VARIABLE=多目的0] | inputs[VALUE=a|l:operator_subtract]
```

### `検出id_消えたidに対応する検出無効化`

- Definition block: `bl-`
- Prototype block: `dik`

```text
pz: control_if_else | inputs[CONDITION=bl.:operator_equals]
  SUBSTACK:
    bl/: data_deletealloflist | fields[LIST=4-3 検出id別情報]
    dim: data_deletealloflist | fields[LIST=4-4 検出id震源要素]
  SUBSTACK2:
    bl:: data_setvariableto | fields[VARIABLE=カウント1] | inputs[VALUE='0']
    +,: control_repeat_until | inputs[CONDITION=+-:operator_lt]
      SUBSTACK:
        cn: control_if_else | inputs[CONDITION=bl=:data_listcontainsitem]
          SUBSTACK:
            co: control_if_else | inputs[CONDITION=bl?:operator_lt]
              SUBSTACK:
                bl@: data_setvariableto | fields[VARIABLE=カウント2] | inputs[VALUE=bl^:operator_multiply]
              SUBSTACK2:
                dir: data_setvariableto | fields[VARIABLE=カウント2] | inputs[VALUE='400']
            pA: control_if | inputs[CONDITION=+/:operator_lt]
              SUBSTACK:
                +:: data_replaceitemoflist | fields[LIST=4-3 検出id別情報] | inputs[INDEX=bmc:operator_add, ITEM=bmd:operator_add]
            cp: control_if_else | inputs[CONDITION=+;:operator_lt]
              SUBSTACK:
                +=: data_replaceitemoflist | fields[LIST=4-3 検出id別情報] | inputs[INDEX=bmi:operator_add, ITEM=diA:operator_equals]
              SUBSTACK2:
                +?: data_replaceitemoflist | fields[LIST=4-3 検出id別情報] | inputs[INDEX=bmj:operator_add, ITEM=bmk:data_itemoflist]
            pB: control_if | inputs[CONDITION=bmm:operator_lt]
              SUBSTACK:
                +[: control_if | inputs[CONDITION=bmp:operator_lt]
                  SUBSTACK:
                    +^: data_replaceitemoflist | fields[LIST=4-3 検出id別情報] | inputs[INDEX=bms:operator_add, ITEM=diH:operator_equals]
            +@: control_if | inputs[CONDITION=+_:operator_and]
              SUBSTACK:
                +`: control_if | inputs[CONDITION=bmC:operator_lt]
                  SUBSTACK:
                    +|: control_if | inputs[CONDITION=bmF:operator_lt]
                      SUBSTACK:
                        +}: data_replaceitemoflist | fields[LIST=4-3 検出id別情報] | inputs[INDEX=bmI:operator_add, ITEM=diP:operator_equals]
          SUBSTACK2:
            +.: control_if | inputs[CONDITION=bmJ:operator_lt]
              SUBSTACK:
                ,a: control_if | inputs[CONDITION=diT:operator_equals]
                ,c: data_replaceitemoflist | fields[LIST=4-3 検出id別情報] | inputs[INDEX=bmM:operator_add, ITEM=diU:operator_equals]
        dip: data_changevariableby | fields[VARIABLE=カウント1] | inputs[VALUE='1']
```

### `検出id_点の推定用をリセット %s`

- Definition block: `a?(`
- Prototype block: `a?)`
- Arguments: `番号`

```text
Ym: data_replaceitemoflist | fields[LIST=ten:推定用] | inputs[INDEX=a?*:operator_add, ITEM='']
Yn: data_replaceitemoflist | fields[LIST=ten:推定用] | inputs[INDEX=a?-:operator_add, ITEM='']
Yo: 検出id適用数カウント追加 %s %b %s | inputs[y:F|`*?l]NVyF1!(6L;x=$番号, xOeHlykhk^(q[zTZkw0P='-1']
Yp: data_replaceitemoflist | fields[LIST=ten:推定用] | inputs[INDEX=a?::operator_add, ITEM='']
Yq: data_replaceitemoflist | fields[LIST=ten:推定用] | inputs[INDEX=a??:operator_add, ITEM='']
Yr: data_replaceitemoflist | fields[LIST=ten:推定用] | inputs[INDEX=a?]:operator_add, ITEM='']
Ys: data_replaceitemoflist | fields[LIST=ten:推定用] | inputs[INDEX=a?{:operator_add, ITEM='']
a?`: data_replaceitemoflist | fields[LIST=ten:推定用] | inputs[INDEX=a?~:operator_add, ITEM='']
```

### `検出id_同一震源統合 %s %s %b`

- Definition block: `bi?`
- Prototype block: `o=`
- Arguments: `id1, id2, 実行`

```text
o;: control_if | inputs[CONDITION=$実行]
  SUBSTACK:
    bi@: data_setvariableto | fields[VARIABLE=カウント1] | inputs[VALUE='0']
    o@: control_repeat_until | inputs[CONDITION=*+:operator_lt]
      SUBSTACK:
        o[: control_if | inputs[CONDITION=*,:operator_equals]
          SUBSTACK:
            *-: data_replaceitemoflist | fields[LIST=ten:推定用] | inputs[INDEX=df+:operator_add, ITEM=$id2]
        df(: data_changevariableby | fields[VARIABLE=カウント1] | inputs[VALUE='10']
    **: data_setvariableto | fields[VARIABLE=カウント1] | inputs[VALUE=bi]:operator_multiply]
    *.: data_setvariableto | fields[VARIABLE=カウント2] | inputs[VALUE=bi_:operator_multiply]
    o]: control_if | inputs[CONDITION=*/:operator_gt]
      SUBSTACK:
        o_: data_replaceitemoflist | fields[LIST=4-3 検出id別情報] | inputs[INDEX=df;:operator_add, ITEM=bi}:data_itemoflist]
        o`: data_replaceitemoflist | fields[LIST=4-3 検出id別情報] | inputs[INDEX=df?:operator_add, ITEM=bi~:data_itemoflist]
        o{: data_replaceitemoflist | fields[LIST=4-3 検出id別情報] | inputs[INDEX=df[:operator_add, ITEM=bja:data_itemoflist]
        o|: data_replaceitemoflist | fields[LIST=4-3 検出id別情報] | inputs[INDEX=df^:operator_add, ITEM=bjb:data_itemoflist]
        o}: data_replaceitemoflist | fields[LIST=4-3 検出id別情報] | inputs[INDEX=df`:operator_add, ITEM=bjc:data_itemoflist]
        o~: data_replaceitemoflist | fields[LIST=4-3 検出id別情報] | inputs[INDEX=df|:operator_add, ITEM=bjd:data_itemoflist]
        *:: data_replaceitemoflist | fields[LIST=4-3 検出id別情報] | inputs[INDEX=df~:operator_add, ITEM=bje:data_itemoflist]
    o^: control_if | inputs[CONDITION=*;:operator_gt]
      SUBSTACK:
        pb: data_replaceitemoflist | fields[LIST=4-3 検出id別情報] | inputs[INDEX=dgd:operator_add, ITEM=bjh:data_itemoflist]
        pc: data_replaceitemoflist | fields[LIST=4-3 検出id別情報] | inputs[INDEX=dgf:operator_add, ITEM=bji:data_itemoflist]
        *=: data_replaceitemoflist | fields[LIST=4-3 検出id別情報] | inputs[INDEX=dgh:operator_add, ITEM=bjj:data_itemoflist]
    pa: control_if | inputs[CONDITION=*?:operator_gt]
      SUBSTACK:
        pe: data_replaceitemoflist | fields[LIST=4-3 検出id別情報] | inputs[INDEX=dgl:operator_add, ITEM=bjm:data_itemoflist]
        *@: data_replaceitemoflist | fields[LIST=4-3 検出id別情報] | inputs[INDEX=dgn:operator_add, ITEM=bjn:data_itemoflist]
    pd: control_if | inputs[CONDITION=*[:operator_lt]
      SUBSTACK:
        *]: data_replaceitemoflist | fields[LIST=4-3 検出id別情報] | inputs[INDEX=dgr:operator_add, ITEM=bjq:data_itemoflist]
    pf: control_if | inputs[CONDITION=*^:operator_lt]
      SUBSTACK:
        *_: data_replaceitemoflist | fields[LIST=4-3 検出id別情報] | inputs[INDEX=dgv:operator_add, ITEM=bjt:data_itemoflist]
    pg: data_replaceitemoflist | fields[LIST=4-3 検出id別情報] | inputs[INDEX=dgy:operator_add, ITEM=dgz:operator_and]
    dgx: control_stop | fields[STOP_OPTION=this script]
o?: control_if | inputs[CONDITION=bju:operator_equals]
  SUBSTACK:
    bjv: data_setvariableto | fields[VARIABLE=カウント1] | inputs[VALUE='0']
    ph: control_repeat_until | inputs[CONDITION=*{:operator_lt]
      SUBSTACK:
        *|: data_setvariableto | fields[VARIABLE=カウント2] | inputs[VALUE=dgE:operator_add]
        pi: control_repeat_until | inputs[CONDITION=*}:operator_lt]
          SUBSTACK:
            pj: control_if | inputs[CONDITION=bjw:operator_not]
              SUBSTACK:
                *~: control_if | inputs[CONDITION=+a:operator_and]
                  SUBSTACK:
                    +b: control_if | inputs[CONDITION=bjD:operator_lt]
                      SUBSTACK:
                        +e: 検出id_同一震源統合 %s %s %b | inputs[On5xt865tWb$iO8!5zf.=bjH:operator_add, $!w^k/.]?`6=PXKQ)=+]=bjI:operator_add]
            dgI: data_changevariableby | fields[VARIABLE=カウント2] | inputs[VALUE='20']
        dgF: data_changevariableby | fields[VARIABLE=カウント1] | inputs[VALUE='20']
    dgB: control_stop | fields[STOP_OPTION=this script]
*`: data_setvariableto | fields[VARIABLE=カウント1] | inputs[VALUE=bjJ:operator_multiply]
+g: data_setvariableto | fields[VARIABLE=カウント2] | inputs[VALUE=bjL:operator_multiply]
au: 緯度経度で距離km(多目的0) xy1 %s %s xy2 %s %s | inputs[]{P@NqNQS3.9ZW^L7/Id=bjN:data_itemoflist, v4!`%fK.fAl-7,*LjmoN=bjO:data_itemoflist, PD=h#Y$/m@?PDZm(Qn:L=bjP:data_itemoflist, ;:CHeDp67!I+0u0Hv{UC=bjQ:data_itemoflist]
+h: data_setvariableto | fields[VARIABLE=多目的1] | inputs[VALUE=bjR:operator_divide]
pk: control_if | inputs[CONDITION=bjW:operator_lt]
  SUBSTACK:
    +k: control_if | inputs[CONDITION=+l:operator_lt]
      SUBSTACK:
        pl: 検出id_同一震源統合 %s %s %b | inputs[On5xt865tWb$iO8!5zf.=$id1, $!w^k/.]?`6=PXKQ)=+]=$id2, .,6A_~@+BK%~)K9;~Z4U=dg+:operator_not]
+j: data_setvariableto | fields[VARIABLE=カウント1] | inputs[VALUE=bj(:operator_multiply]
bj%: data_setvariableto | fields[VARIABLE=カウント2] | inputs[VALUE=bj*:operator_multiply]
```

### `検出id_新規id追加 %s %b`

- Definition block: `a@l`
- Prototype block: `Yu`
- Arguments: `番号, 再上昇`

```text
Yt: data_addtolist | fields[LIST=4-3 検出id別情報] | inputs[ITEM=$番号]
Yv: data_addtolist | fields[LIST=4-3 検出id別情報] | inputs[ITEM=c?I:operator_not]
Yw: data_addtolist | fields[LIST=4-3 検出id別情報] | inputs[ITEM=c?J:data_itemoflist]
a@m: data_addtolist | fields[LIST=4-3 検出id別情報] | inputs[ITEM='1']
a@n: data_addtolist | fields[LIST=4-3 検出id別情報] | inputs[ITEM='']
a@o: data_addtolist | fields[LIST=4-3 検出id別情報] | inputs[ITEM='-3']
a@p: data_addtolist | fields[LIST=4-3 検出id別情報] | inputs[ITEM='-3']
Yx: data_addtolist | fields[LIST=4-3 検出id別情報] | inputs[ITEM=a@q:operator_join]
b/: control_if_else | inputs[CONDITION=a@t:operator_lt]
  SUBSTACK:
    a@u: data_addtolist | fields[LIST=4-3 検出id別情報] | inputs[ITEM=a@A:operator_add]
  SUBSTACK2:
    a@v: data_addtolist | fields[LIST=4-3 検出id別情報] | inputs[ITEM=a@B:operator_add]
a@s: data_addtolist | fields[LIST=4-3 検出id別情報] | inputs[ITEM='']
Yy: data_addtolist | fields[LIST=4-3 検出id別情報] | inputs[ITEM=c?O:operator_divide]
a@C: data_addtolist | fields[LIST=4-3 検出id別情報] | inputs[ITEM='']
a@D: data_addtolist | fields[LIST=4-3 検出id別情報] | inputs[ITEM='']
a@E: data_addtolist | fields[LIST=4-3 検出id別情報] | inputs[ITEM='']
a@F: data_addtolist | fields[LIST=4-3 検出id別情報] | inputs[ITEM='']
a@G: data_addtolist | fields[LIST=4-3 検出id別情報] | inputs[ITEM='']
a@H: data_addtolist | fields[LIST=4-3 検出id別情報] | inputs[ITEM='']
a@I: data_addtolist | fields[LIST=4-3 検出id別情報] | inputs[ITEM='']
Yz: data_addtolist | fields[LIST=4-3 検出id別情報] | inputs[ITEM=c?P:operator_divide]
a@J: data_addtolist | fields[LIST=4-3 検出id別情報] | inputs[ITEM='']
YA: control_repeat | inputs[TIMES='10']
  SUBSTACK:
    c?Q: data_addtolist | fields[LIST=4-4 検出id震源要素] | inputs[ITEM='']
md: control_if | inputs[CONDITION=a@K:operator_equals]
  SUBSTACK:
    a@L: data_setvariableto | fields[VARIABLE=カウント3] | inputs[VALUE='1']
    YC: control_repeat | inputs[TIMES=c?S:data_lengthoflist]
      SUBSTACK:
        me: control_if | inputs[CONDITION=a@O:operator_not]
          SUBSTACK:
            YD: control_if | inputs[CONDITION=YE:operator_and]
              SUBSTACK:
                mf: data_replaceitemoflist | fields[LIST=grid:検出id] | inputs[INDEX=c?Z:data_itemoflist, ITEM=a@(:operator_divide]
                YH: data_replaceitemoflist | fields[LIST=grid:検出id時間] | inputs[INDEX=c?#:data_itemoflist, ITEM=a@):operator_add]
        c?T: data_changevariableby | fields[VARIABLE=カウント3] | inputs[VALUE='1']
YB: control_if | inputs[CONDITION=a@*:operator_lt]
  SUBSTACK:
    YI: control_if | inputs[CONDITION=c?):operator_equals]
      SUBSTACK:
        YJ: data_replaceitemoflist | fields[LIST=4-3 検出id別情報] | inputs[INDEX=c?*:data_lengthoflist, ITEM=a@+:operator_add]
```

### `検出id距離計算 %s %s`

- Definition block: `a@-`
- Prototype block: `YL`
- Arguments: `番号, 4-3おふせ`

```text
YK: data_setvariableto | fields[VARIABLE=多目的0] | inputs[VALUE=a@.:operator_multiply]
mg: data_replaceitemoflist | fields[LIST=ten:推定用] | inputs[INDEX=a@?:operator_add, ITEM=c?::operator_multiply]
YN: data_setvariableto | fields[VARIABLE=多目的0] | inputs[VALUE=a@]:operator_multiply]
mh: data_replaceitemoflist | fields[LIST=ten:推定用] | inputs[INDEX=a@|:operator_add, ITEM=a@}:operator_mathop]
YP: control_if | inputs[CONDITION=YR:operator_lt]
  SUBSTACK:
    YS: data_replaceitemoflist | fields[LIST=4-3 検出id別情報] | inputs[INDEX=a[l:operator_add, ITEM=a[m:data_itemoflist]
```

### `点-震源 距離計算 %s %s %s`

- Definition block: `a%E`
- Prototype block: `kB`
- Arguments: `番号, x, y`

```text
T#: control_if | inputs[CONDITION=a%F:operator_not]
  SUBSTACK:
    kC: control_if | inputs[CONDITION=c)S:data_itemoflist]
      SUBSTACK:
        a%I: data_setvariableto | fields[VARIABLE=カウント2] | inputs[VALUE='0']
        T%: control_repeat | inputs[TIMES=c)T:data_lengthoflist]
          SUBSTACK:
            ad: 緯度経度で距離km(多目的0) xy1 %s %s xy2 %s %s | inputs[]{P@NqNQS3.9ZW^L7/Id=$x, v4!`%fK.fAl-7,*LjmoN=$y, PD=h#Y$/m@?PDZm(Qn:L=a%J:data_itemoflist, ;:CHeDp67!I+0u0Hv{UC=a%K:data_itemoflist]
            T(: data_replaceitemoflist | fields[LIST=ten c:震源距離] | inputs[INDEX=T):operator_add, ITEM='多目的0']
            c)Y: data_changevariableby | fields[VARIABLE=カウント2] | inputs[VALUE='1']
    a%H: data_setvariableto | fields[VARIABLE=カウント2] | inputs[VALUE='1']
    T*: control_repeat | inputs[TIMES='6']
      SUBSTACK:
        T+: data_replaceitemoflist | fields[LIST=1-1カメラ用近傍点] | inputs[INDEX=a%M:operator_add, ITEM='99999']
        c)#: data_changevariableby | fields[VARIABLE=カウント2] | inputs[VALUE='1']
    a%L: data_setvariableto | fields[VARIABLE=カウント2] | inputs[VALUE='1']
    T,: control_repeat | inputs[TIMES='188']
      SUBSTACK:
        T-: data_setvariableto | fields[VARIABLE=多目的0] | inputs[VALUE=a%Q:data_itemoflist]
        ae: 緯度経度で距離km(多目的0) xy1 %s %s xy2 %s %s | inputs[]{P@NqNQS3.9ZW^L7/Id=$x, v4!`%fK.fAl-7,*LjmoN=$y, PD=h#Y$/m@?PDZm(Qn:L=a%T:operator_add, ;:CHeDp67!I+0u0Hv{UC=T/:operator_add]
        T.: data_replaceitemoflist | fields[LIST=map:EEW震源距離] | inputs[INDEX=T::operator_add, ITEM='多目的0']
        kD: control_if | inputs[CONDITION=a%#:operator_equals]
          SUBSTACK:
            a%%: カメラ用近傍点 %s %s %s | inputs[Ew@?Qy$P^J]jMqse]c6n=a%(:operator_multiply, )`UU+u|AuZI8/ArNXD?5='カウント2', Rxf_PJ/=U6n8tvp4Cq_g='多目的0']
        c):: data_changevariableby | fields[VARIABLE=カウント2] | inputs[VALUE='1']
    a%P: data_setvariableto | fields[VARIABLE=カウント2] | inputs[VALUE='1']
    T;: control_repeat | inputs[TIMES=c)?:data_lengthoflist]
      SUBSTACK:
        af: 緯度経度で距離km(多目的0) xy1 %s %s xy2 %s %s | inputs[]{P@NqNQS3.9ZW^L7/Id=$x, v4!`%fK.fAl-7,*LjmoN=$y, PD=h#Y$/m@?PDZm(Qn:L=a%*:operator_add, ;:CHeDp67!I+0u0Hv{UC=a%+:operator_add]
        T=: data_replaceitemoflist | fields[LIST=grid連番:距離] | inputs[INDEX=T?:operator_add, ITEM='多目的0']
        c)_: data_changevariableby | fields[VARIABLE=カウント2] | inputs[VALUE='1']
```

### `緯度経度で距離km(多目的0) xy1 %s %s xy2 %s %s`

- Definition block: `aQJ`
- Prototype block: `bo`
- Arguments: `x1, y1, x2, y2`

```text
aQK: data_setvariableto | fields[VARIABLE=多目的0] | inputs[VALUE=aQL:operator_multiply]
```

### `距離の震度 %s %s %s %s`

- Definition block: `aT)`
- Prototype block: `by`
- Arguments: `距離, M, 深さ, 増幅`

```text
P.: data_setvariableto | fields[VARIABLE=多目的0] | inputs[VALUE=P/:operator_subtract]
jo: control_if | inputs[CONDITION=cXI:operator_lt]
  SUBSTACK:
    cXJ: data_setvariableto | fields[VARIABLE=多目的0] | inputs[VALUE='3']
aT:: data_setvariableto | fields[VARIABLE=距離の震度] | inputs[VALUE=aT;:operator_add]
```

