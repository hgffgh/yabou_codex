# ORBITAL DOMINION（仮）データ定義書

## 1. 文書情報

| 項目 | 内容 |
| --- | --- |
| 文書版 | 0.1 |
| 対象 | Godot Resource、ランタイム状態、セーブデータ |
| 関連文書 | `GAME_SPECIFICATION.md`および各詳細仕様書 |
| 実装前提 | Godot 4／GDScript |

## 2. 設計方針

### 2.1 データの分類

| 分類 | 内容 | 保存形式 |
| --- | --- | --- |
| マスターデータ | 機体、武器、パイロット、技術、勢力、エリアなど不変の定義 | Godot `Resource`（`.tres`） |
| キャンペーン状態 | 所有機体、部隊、領地、研究、生産、外交など周回中に変化する値 | ランタイムクラス＋セーブ辞書 |
| プロフィール状態 | 図鑑、恒久アンロック、実績、設定 | キャンペーンと独立したセーブ |
| 一時戦闘状態 | 戦場位置、行動ゲージ、制圧ゲージなど | メモリのみ。戦闘中セーブなし |

### 2.2 ID規則

- すべてのマスターデータは一意な`StringName id`を持つ。
- IDは半角小文字の`snake_case`とする。
- 表示名、翻訳文、画像ファイル名をIDとして使用しない。
- セーブデータはResource参照ではなくIDを保存する。
- IDは公開後に変更しない。廃止時は移行テーブルを用意する。

例：

```text
faction: earth_union
unit: eu_vanguard_mk1
weapon: beam_rifle_standard
pilot: eu_akira_sen
tech: eu_mobile_frame_t2
region: earth_orbit_01
event: eu_main_003
```

### 2.3 数値型・丸め

- HP、EN、能力値、費用、ターン数は`int`を基本とする。
- 割合と内部時間は`float`を使用する。
- ダメージ・修理・EXPは最終結果で仕様どおり四捨五入または切り上げする。
- UI表示用の丸め値をゲーム内部へ書き戻さない。

## 3. 共通列挙値

実装では文字列の直書きを避け、enumまたは定数へ集約する。

### 3.1 勢力・戦略

```gdscript
enum Difficulty { EASY, NORMAL, HARD }
enum FactionControl { PLAYER, AI }
enum RelationBand { NEMESIS, HOSTILE, NEUTRAL, FRIENDLY, CLOSE }
enum TreatyType { NONE, CEASEFIRE, NON_AGGRESSION }
enum StrategicPhase { START, STRATEGY, COMBAT, END }
enum RegionScale { SMALL, MEDIUM, LARGE }
enum FacilityType {
    ECONOMY,
    LARGE_ECONOMY,
    RESOURCE,
    LARGE_RESOURCE,
    RESEARCH,
    PRODUCTION,
    LARGE_PRODUCTION
}
```

### 3.2 機体・戦闘

```gdscript
enum UnitSize { LIGHT, STANDARD, HEAVY }
enum UnitRole { ATTACK, DEFENSE, LONG_RANGE, RECON, SUPPORT }
enum EnvironmentType { GROUND, SPACE, MOON }
enum EnvironmentAptitude { PROFICIENT, STANDARD, POOR }
enum WeaponClass { LIGHT, STANDARD, HEAVY, STRATEGIC }
enum DamageAttribute { BALLISTIC, BEAM, MELEE }
enum RangeClass { MELEE, SHORT, MEDIUM, LONG, STRATEGIC }
enum RowType { FRONT, REAR }
enum BattlePolicy { BALANCED, OFFENSIVE, DEFENSIVE, SUPPORT, RETREAT }
enum TerrainEffect { NORMAL, DIFFICULT, COVER, HAZARDOUS, IMPASSABLE }
enum TargetRule {
    FRONT,
    LOW_HP,
    HIGH_HP,
    LOW_ARMOR,
    HIGH_ARMOR,
    HIGH_SPEED,
    SUPPORT,
    RANDOM
}
enum SupportTargetRule {
    LOW_HP_RATIO,
    HIGH_HP_LOSS,
    LOW_EN_RATIO,
    HIGH_EN_CONSUMPTION,
    FRONT,
    REAR,
    LEADER,
    ROLE,
    SELF_EXCLUDED,
    SELF_INCLUDED
}
enum TargetPattern {
    SINGLE,
    FRONT_ROW,
    REAR_ROW,
    LEFT_COLUMN,
    CENTER,
    RIGHT_COLUMN,
    ALL_ENEMIES,
    ALL_ALLIES
}
enum ActionType { ATTACK, REPAIR, EN_TRANSFER, DEFEND }
enum UnitCondition { ACTIVE, REPAIRING, DESTROYED_RECOVERED }
```

### 3.3 情報・イベント

```gdscript
enum IntelState { UNKNOWN, CONFIRMED }
enum EventImportance { MAIN, SUB }
enum EventEffectType {
    FUNDS,
    MATERIALS,
    TECH_CANDIDATE,
    RESEARCH_MODIFIER,
    PILOT_JOIN,
    PILOT_LEAVE,
    PILOT_INJURE,
    UNIT_GAIN,
    UNIT_LOSE,
    RELATION,
    TREATY,
    ENEMY_REINFORCEMENT,
    EVENT_FLAG
}
```

## 4. キャンペーン設定 `CampaignConfig`

### 4.1 マスターフィールド

| フィールド | 型 | 必須 | 初期値 | 説明・制約 |
| --- | --- | --- | --- | --- |
| `id` | `StringName` | ○ | `main_campaign` | 設定ID |
| `turn_cap` | `int` | ○ | `100` | 期限。1以上 |
| `standard_clear_turn` | `int` | ○ | `50` | 標準クリア目標 |
| `faction_turn_order` | `Array[StringName]` | ○ | — | プレイヤー選択後にプレイヤーを先頭へ並べる元順序 |
| `tech_nodes_per_run` | `int` | ○ | `30` | 周回ツリー目標件数 |
| `tech_tier_count` | `int` | ○ | `5` | Tier数 |
| `tech_costs` | `Array[int]` | ○ | `[1000,2000,3000,5000,8000]` | index 0がTier 1 |
| `tech_turns` | `Array[int]` | ○ | `[1,2,3,4,5]` | Tier別研究期間 |
| `manual_save_slots` | `int` | ○ | `10` | 手動スロット数 |
| `autosave_slots` | `int` | ○ | `3` | オートスロット数 |
| `battle_time_limit_sec` | `float` | ○ | `300.0` | 戦場時間上限 |
| `battle_round_sec` | `float` | ○ | `30.0` | 自動戦闘1ラウンド |
| `reengage_wait_sec` | `float` | ○ | `5.0` | 再行動待ち |
| `retreat_prepare_sec` | `float` | ○ | `10.0` | 撤退準備 |
| `capture_gauge_max` | `float` | ○ | `100.0` | 制圧完了値 |
| `capture_rate_per_unit` | `float` | ○ | `1.0` | 1機毎秒 |
| `capture_recovery_rate` | `float` | ○ | `2.0` | 非制圧時の毎秒回復 |
| `capture_enemy_unit_pct` | `float` | ○ | `0.10` | 敵撃破機の鹵獲率 |
| `exp_meta_step_pct` | `float` | ○ | `0.05` | 実績1件のEXP補正 |
| `exp_meta_max_pct` | `float` | ○ | `0.50` | 恒久EXP補正上限 |

### 4.2 検証

- `tech_costs.size() == tech_turns.size() == tech_tier_count`
- `standard_clear_turn <= turn_cap`
- 時間・ゲージ・速度は0より大きい。
- 鹵獲率と割合値は0.0〜1.0。

## 5. 難易度定義 `DifficultyDef`

| フィールド | 型 | Easy | Normal | Hard | 説明 |
| --- | --- | ---: | ---: | ---: | --- |
| `id` | `StringName` | `easy` | `normal` | `hard` | 一意ID |
| `enemy_income_multiplier` | `float` | `0.50` | `1.00` | `1.50` | 資金・物資収入 |
| `enemy_hp_multiplier` | `float` | `0.75` | `1.00` | `1.25` | 最大・現在HP |
| `enemy_firepower_multiplier` | `float` | `0.75` | `1.00` | `1.25` | 機体火力 |
| `enemy_accuracy_add` | `int` | `-15` | `0` | `15` | 命中加算% |
| `enemy_evasion_add` | `int` | `-15` | `0` | `15` | 回避加算% |
| `ai_profile_id` | `StringName` | `easy` | `normal` | `hard` | AI思考定義 |

## 6. 勢力定義 `FactionDef`

### 6.1 マスターフィールド

| フィールド | 型 | 必須 | 説明・制約 |
| --- | --- | --- | --- |
| `id` | `StringName` | ○ | 勢力ID |
| `display_name_key` | `StringName` | ○ | 翻訳キー |
| `description_key` | `StringName` | ○ | 勢力説明 |
| `color` | `Color` | ○ | 基本色。識別は色だけに依存しない |
| `emblem` | `Texture2D` | ○ | 紋章 |
| `border_pattern` | `Texture2D` | ○ | 領域境界模様 |
| `starting_capital_region_id` | `StringName` | ○ | 本拠地エリア |
| `starting_funds` | `int` | ○ | 0以上 |
| `starting_materials` | `int` | ○ | 0以上 |
| `starting_relation` | `int` | ○ | 原則−50 |
| `base_tech_ids` | `Array[StringName]` | ○ | 必ず配置する基礎技術 |
| `tech_candidate_pool_ids` | `Array[StringName]` | ○ | 初期抽選候補 |
| `starting_pilot_ids` | `Array[StringName]` | ○ | 初期固有パイロット |
| `starting_unit_loadout` | `Array[Dictionary]` | ○ | エリア・機体・パイロット・部隊構成 |
| `ai_behavior_id` | `StringName` | ○ | 勢力固有AI傾向 |
| `main_event_ids` | `Array[StringName]` | ○ | 主要イベント |
| `sub_event_pool_ids` | `Array[StringName]` | ○ | 補助イベント候補 |

### 6.2 ランタイム `FactionState`

| フィールド | 型 | 説明 |
| --- | --- | --- |
| `faction_id` | `StringName` | `FactionDef.id` |
| `control_type` | `FactionControl` | PLAYER／AI |
| `funds` | `int` | 現在資金。負数不可 |
| `materials` | `int` | 現在物資。負数不可 |
| `eliminated` | `bool` | 本拠地喪失後true |
| `current_research` | `ResearchState` | 未研究時null相当 |
| `researched_tech_ids` | `Array[StringName]` | 当該周回の研究済み |
| `generated_tech_node_ids` | `Array[StringName]` | 周回生成ツリー |
| `gifted_tech_node_ids` | `Array[StringName]` | 外交追加候補 |
| `relation_states` | `Dictionary` | 相手勢力ID→`RelationState` |
| `unit_instance_ids` | `Array[StringName]` | 所有機体個体 |
| `squad_ids` | `Array[StringName]` | 所有部隊 |
| `owned_region_ids` | `Array[StringName]` | 再構築可能なキャッシュ |
| `event_flags` | `Dictionary` | イベント条件フラグ |
| `pending_event_ids` | `Array[StringName]` | 次ターン再生待ち |

## 7. エリア定義 `RegionDef`

### 7.1 マスターフィールド

| フィールド | 型 | 必須 | 説明・制約 |
| --- | --- | --- | --- |
| `id` | `StringName` | ○ | エリアID |
| `display_name_key` | `StringName` | ○ | 翻訳キー |
| `map_position` | `Vector2` | ○ | 戦略マップ位置 |
| `neighbor_ids` | `Array[StringName]` | ○ | 双方向接続 |
| `environment` | `EnvironmentType` | ○ | 地上・宇宙・月面 |
| `scale` | `RegionScale` | ○ | 小・中・大 |
| `base_funds_income` | `int` | ○ | 小300／中600／大1200 |
| `base_materials_income` | `int` | ○ | 小100／中250／大500 |
| `facility_ids` | `Array[StringName]` | ○ | 固定施設インスタンス |
| `battle_map_id` | `StringName` | ○ | 使用戦闘マップ |
| `starting_owner_faction_id` | `StringName` | — | 中立は空ID |
| `is_capital` | `bool` | ○ | 本拠地判定 |
| `capital_faction_id` | `StringName` | — | 本来の本拠地所有者 |

### 7.2 ランタイム `RegionState`

| フィールド | 型 | 説明 |
| --- | --- | --- |
| `region_id` | `StringName` | マスターID |
| `owner_faction_id` | `StringName` | 現所有者 |
| `squad_ids_by_faction` | `Dictionary` | 勢力ID→部隊ID配列 |
| `pending_move_squad_ids` | `Array[StringName]` | 戦略フェイズ移動予定 |
| `production_queues` | `Dictionary` | 施設ID→`ProductionQueueState` |
| `supply_connected_by_faction` | `Dictionary` | 補給線計算キャッシュ |
| `battle_pending` | `bool` | 戦闘フェイズ対象 |

## 8. 施設定義 `FacilityDef`／`FacilityInstanceDef`

### 8.1 `FacilityDef`

| フィールド | 型 | 説明 |
| --- | --- | --- |
| `id` | `StringName` | 種別ID |
| `display_name_key` | `StringName` | 表示名 |
| `facility_type` | `FacilityType` | 施設種別 |
| `funds_income` | `int` | 経済300／大型600、それ以外0 |
| `materials_income` | `int` | 資源200／大型400、それ以外0 |
| `production_power` | `int` | 生産100／大型200、それ以外0 |
| `research_discount_pct` | `float` | 研究施設0.05、それ以外0 |

### 8.2 `FacilityInstanceDef`

| フィールド | 型 | 説明 |
| --- | --- | --- |
| `id` | `StringName` | エリア内で一意 |
| `facility_def_id` | `StringName` | 種別参照 |
| `region_id` | `StringName` | 配置先 |

施設は建設・破壊せず、エリア所有権と同時に移転する。

## 9. 機体定義 `UnitDef`

### 9.1 マスターフィールド

| フィールド | 型 | 必須 | 説明・制約 |
| --- | --- | --- | --- |
| `id` | `StringName` | ○ | 機体ID |
| `display_name_key` | `StringName` | ○ | 翻訳キー |
| `description_key` | `StringName` | ○ | 説明 |
| `faction_origin_id` | `StringName` | ○ | 生産元勢力 |
| `size` | `UnitSize` | ○ | 軽量・標準・重量 |
| `role` | `UnitRole` | ○ | 5役から1つ |
| `icon` | `Texture2D` | ○ | UIアイコン |
| `model_scene` | `PackedScene` | ○ | 3DモデルScene |
| `vignette_sprite` | `Texture2D` | — | 詳細・演出用 |
| `max_hp` | `int` | ○ | 軽800〜1600／標1500〜3000／重3000〜6000目安 |
| `max_en` | `int` | ○ | 200〜500目安 |
| `firepower` | `int` | ○ | 支援50〜100／汎用100〜200／攻撃200〜400目安 |
| `armor` | `int` | ○ | 軽25〜100／標100〜300／重300〜700目安 |
| `speed` | `int` | ○ | 50〜200目安 |
| `evasion` | `int` | ○ | 軽20〜40／標10〜25／重0〜10目安 |
| `ground_aptitude` | `EnvironmentAptitude` | ○ | 地上適性 |
| `space_aptitude` | `EnvironmentAptitude` | ○ | 宇宙適性 |
| `moon_aptitude` | `EnvironmentAptitude` | ○ | 月面適性 |
| `ballistic_damage_multiplier` | `float` | ○ | 0.50／0.75／1.00／1.25／1.50 |
| `beam_damage_multiplier` | `float` | ○ | 同上 |
| `melee_damage_multiplier` | `float` | ○ | 同上 |
| `weapon_ids` | `Array[StringName]` | ○ | 固定優先順位順 |
| `support_skill_ids` | `Array[StringName]` | — | 固定優先順位順 |
| `sensor_range_m` | `float` | ○ | 通常150／偵察300 |
| `sensor_ignores_obstacles` | `bool` | ○ | 偵察機true |
| `capture_allowed` | `bool` | ○ | 通常true、物語機はfalse可 |
| `power_adjustment` | `float` | ○ | 原則1.00 |
| `tech_id` | `StringName` | ○ | 生産解放技術 |

### 9.1.1 `model_scene` アセット仕様

`model_scene`はGodotのglTF 2.0（`.glb`）をインポートした`PackedScene`を想定する。実装側（`scenes/battle/battle_prototype_view.gd`の`_build_squad_visuals`）は現状これを一切参照せず、`icon`/`vignette_sprite`を貼った`Sprite3D`ビルボードのみで代替している。全ユニットの`model_scene`は空の`Node3D`一つだけの`scenes/units/placeholder_unit_model.tscn`を指しており、本番モデルへの差し替え待ち。以下は差し替え時にモデル制作側・実装側の双方が合わせるべき規約。

**座標・スケール規約**（現行ビルボードの数値と整合させる）：
- モデル原点は接地面（両足中心、`y=0`）。前方は`-Z`。
- `size == STANDARD`基準で全高はおよそ80〜90ユニット相当（現行実装のHPバーが`y=82〜84`、スプライト中心が`y=42`）。`LIGHT`は0.8倍、`HEAVY`は1.35倍の見た目になるよう、サイズ別に別モデルを用意するか、単一モデルを`UnitDef.size`に応じて一様スケールする前提で作る。
- ルートモーションは持たない。位置は`BattleRuntimeState`が毎フレーム`Node3D.position`へ直接反映するため、アニメーション内でルートを移動させない。

**アニメーションクリップ**（モデルSceneに`AnimationPlayer`を1つ含め、コード側は`play(<クリップ名>)`で再生する想定）：

| クリップ名 | ループ | 用途 |
| --- | --- | --- |
| `idle` | ○ | 待機（デフォルト状態） |
| `move` | ○ | 移動中 |
| `attack` | — | 射撃・格闘の1ショット |
| `hit` | — | 被弾リアクション |
| `destroyed` | — | 撃破演出。最終フレームで静止 |

**マテリアル**：陣営色（自軍寄り＝水色、敵軍寄り＝赤）は現行の`Sprite3D.modulate`と同じくランタイムで乗算着色する前提を維持する。鹵獲により`owner_faction_id`が変わり得るため、テクスチャへ陣営色を焼き込まない。ベースカラーは彩度を抑えたグレー〜白系とし、乗算着色で破綻しないようにする。

**ポリゴン/テクスチャ予算**：1体あたり三角形2,000〜5,000程度、テクスチャ1024×1024以下、マテリアル数は理想的に1つ（1部隊最大5体が同時表示されるため描画負荷を抑える）。

### 9.2 サイズ別生産値

| サイズ | 資金 | 物資 | 必要生産値 |
| --- | ---: | ---: | ---: |
| LIGHT | 300 | 200 | 100 |
| STANDARD | 600 | 400 | 200 |
| HEAVY | 1200 | 800 | 400 |

これらは`UnitDef`へ重複保存せず、共通バランス定義から取得する。例外機だけ上書き値を許可する場合は、`-1`を「共通値使用」とする。

### 9.3 ランタイム `UnitInstanceState`

| フィールド | 型 | 説明・制約 |
| --- | --- | --- |
| `instance_id` | `StringName` | UUID相当。一意 |
| `unit_def_id` | `StringName` | 機体マスター参照 |
| `owner_faction_id` | `StringName` | 現所有勢力 |
| `origin_faction_id` | `StringName` | 有償返還先。所有変更でも維持 |
| `current_hp` | `int` | 0〜難易度補正後最大HP |
| `current_en` | `int` | 0〜最大EN |
| `pilot_id` | `StringName` | 固有パイロット。一般兵は空ID |
| `squad_id` | `StringName` | 所属部隊 |
| `slot_index` | `int` | 未配属時は-1。部隊配属時は0〜4 |
| `condition` | `UnitCondition` | 稼働・修理・回収大破 |
| `repair_turns_remaining` | `int` | 修理中のみ1以上 |
| `movement_used` | `bool` | 分割統合後も維持する移動済み |
| `captured` | `bool` | 鹵獲由来か |

一般兵は個別データを作成せず、`pilot_id == &""`を一般兵搭乗として扱う。

## 10. 武器定義 `WeaponDef`

| フィールド | 型 | 必須 | 説明・制約 |
| --- | --- | --- | --- |
| `id` | `StringName` | ○ | 武器ID |
| `display_name_key` | `StringName` | ○ | 翻訳キー |
| `weapon_class` | `WeaponClass` | ○ | 軽・標準・重・戦略級 |
| `damage_attribute` | `DamageAttribute` | ○ | 実弾・ビーム・格闘 |
| `action_type` | `ActionType` | ○ | 原則ATTACK |
| `total_power` | `int` | ○ | 軽150〜300／標300〜600／重600〜1200目安 |
| `hit_count` | `int` | ○ | 1〜10 |
| `penetration` | `int` | ○ | 軽0〜100／標100〜300／重300〜700目安 |
| `base_accuracy_pct` | `int` | ○ | 軽85〜95／標75〜90／重60〜80目安 |
| `base_critical_pct` | `int` | ○ | 軽10〜20／標5〜15／重0〜10目安 |
| `en_cost` | `int` | ○ | 軽10〜30／標30〜70／重80〜150目安 |
| `post_action_delay_sec` | `float` | ○ | 軽0〜1／標2〜3／重4〜6目安 |
| `min_range_m` | `float` | ○ | 原則0 |
| `max_range_m` | `float` | ○ | 近0〜20／短20〜60／中60〜150／長150〜300 |
| `target_rule` | `TargetRule` | ○ | 対象優先 |
| `target_pattern` | `TargetPattern` | ○ | 単体・行・列・全体 |
| `can_target_front` | `bool` | ○ | 前衛可否 |
| `can_target_rear` | `bool` | ○ | 後衛可否 |
| `ignores_cover` | `bool` | ○ | 格闘はtrue |
| `is_giftable` | `bool` | ○ | 技術贈与との整合用 |

1ヒット威力は`float(total_power) / hit_count`で算出し、マスターへ重複保存しない。

## 11. 支援スキル定義 `SupportSkillDef`

| フィールド | 型 | 必須 | 説明 |
| --- | --- | --- | --- |
| `id` | `StringName` | ○ | スキルID |
| `display_name_key` | `StringName` | ○ | 表示名 |
| `action_type` | `ActionType` | ○ | REPAIR／EN_TRANSFER |
| `priority` | `int` | ○ | 小さいほど優先 |
| `trigger_resource` | `StringName` | ○ | `hp_pct`または`en_pct` |
| `trigger_threshold_pct` | `float` | ○ | 0.0〜1.0 |
| `target_rule` | `SupportTargetRule` | ○ | HP・EN・配置・役割による固定規則 |
| `target_pattern` | `TargetPattern` | ○ | 単体／味方全体 |
| `fixed_repair` | `int` | — | 修理固定値 |
| `max_hp_repair_pct` | `float` | — | 最大HP割合 |
| `transfer_en` | `int` | — | 等量EN移送量 |
| `en_cost` | `int` | ○ | 修理は固定、移送は移送量と同値 |
| `post_action_delay_sec` | `float` | ○ | 0以上 |
| `can_target_self` | `bool` | ○ | 自分を含むか |

## 12. パイロット定義 `PilotDef`

### 12.1 マスターフィールド

| フィールド | 型 | 必須 | 説明・制約 |
| --- | --- | --- | --- |
| `id` | `StringName` | ○ | 固有パイロットID |
| `display_name_key` | `StringName` | ○ | 表示名 |
| `description_key` | `StringName` | ○ | 人物説明 |
| `faction_id` | `StringName` | ○ | 初期所属 |
| `portrait` | `Texture2D` | ○ | 2D立ち絵 |
| `initial_level` | `int` | ○ | 1〜50 |
| `initial_shooting` | `int` | ○ | 0〜200 |
| `initial_melee` | `int` | ○ | 0〜200 |
| `initial_defense` | `int` | ○ | 0〜200 |
| `initial_reaction` | `int` | ○ | 0〜200 |
| `initial_command` | `int` | ○ | 0〜200 |
| `growth_shooting` | `int` | ○ | 0〜3／Lv |
| `growth_melee` | `int` | ○ | 0〜3／Lv |
| `growth_defense` | `int` | ○ | 0〜3／Lv |
| `growth_reaction` | `int` | ○ | 0〜3／Lv |
| `growth_command` | `int` | ○ | 0〜3／Lv |
| `skill_ids` | `Array[StringName]` | ○ | 最大5、Lv1／10／20／30／40順 |
| `preferred_unit_ids` | `Array[StringName]` | — | 得意機体 |
| `poor_unit_ids` | `Array[StringName]` | — | 苦手機体 |
| `exclusive_unit_ids` | `Array[StringName]` | — | 専用機 |
| `relationship_tags` | `Array[StringName]` | — | イベント条件用 |

### 12.2 ランタイム `PilotState`

| フィールド | 型 | 説明 |
| --- | --- | --- |
| `pilot_id` | `StringName` | マスターID |
| `owner_faction_id` | `StringName` | 現所属 |
| `level` | `int` | 1〜50 |
| `current_exp` | `int` | 次レベル用EXP |
| `injury_turns_remaining` | `int` | 撃破時3。0で出撃可 |
| `assigned_unit_instance_id` | `StringName` | 未配属は空ID |
| `available` | `bool` | 離脱イベントを含む可否 |
| `joined` | `bool` | 加入済み |

基礎能力は初期値と成長値から再計算可能なため、セーブへ冗長保存しない。

### 12.3 EXPテーブル

| 現在Lv | 次Lv必要EXP |
| ---: | ---: |
| 1〜10 | 250 |
| 11〜20 | 500 |
| 21〜30 | 750 |
| 31〜40 | 1000 |
| 41〜49 | 1500 |

## 13. パイロットスキル定義 `PilotSkillDef`

| フィールド | 型 | 説明 |
| --- | --- | --- |
| `id` | `StringName` | スキルID |
| `display_name_key` | `StringName` | 表示名 |
| `description_key` | `StringName` | 効果説明 |
| `unlock_level` | `int` | 1／10／20／30／40 |
| `leader_only` | `bool` | 部隊長時限定 |
| `condition_type` | `StringName` | always／hp_pct／en_pct／environmentなど |
| `condition_value` | `float` | 条件閾値 |
| `modifiers` | `Dictionary` | firepower、accuracy、evasion、armor、critical等 |
| `action_skill_id` | `StringName` | 能動支援追加時のみ |

状態異常関連の効果は禁止する。

## 14. 部隊状態 `SquadState`

部隊はマスターを持たないランタイム個体とする。

| フィールド | 型 | 説明・制約 |
| --- | --- | --- |
| `squad_id` | `StringName` | 一意ID |
| `display_name` | `String` | 自動生成名。将来編集可 |
| `owner_faction_id` | `StringName` | 所有勢力 |
| `region_id` | `StringName` | 現戦略エリア |
| `unit_instance_ids` | `Array[StringName]` | 最大5 |
| `slot_unit_ids` | `Array[StringName]` | size 5。0〜2前衛、3〜4後衛。空は空ID |
| `leader_pilot_id` | `StringName` | 部隊長。一般兵なら空ID |
| `battle_policy` | `BattlePolicy` | 5方針 |
| `movement_used` | `bool` | 当該勢力ターンの移動済み |
| `move_origin_region_id` | `StringName` | 撤退先 |
| `planned_destination_region_id` | `StringName` | 戦略フェイズ移動先 |
| `intel_revision` | `int` | 編成変更毎に加算。敵記録無効化用 |

### 14.1 機体個体・部隊IDの生成

- 機体個体IDは`unit_<連番>`、部隊IDは`squad_<連番>`の形式で生成する。
- 生成時は保存済みの`next_unit_serial`または`next_squad_serial`を使用し、生成後に対応する値を1加算する。
- 連番はキャンペーン乱数から分離し、機体個体や部隊を削除しても再利用しない。
- セーブのロード後も保存された次回連番から生成を再開し、既存IDと衝突させない。

### 14.2 検証

- 機体数1〜5。0機になった部隊は削除する。
- すべての機体の所有勢力・地域・`squad_id`が一致する。
- 固有パイロット重複配置禁止。
- 部隊長は部隊内機体の搭乗者、または一般兵でなければならない。
- 統合時は`movement_used`をOR結合する。

## 15. 技術定義 `TechDef`

| フィールド | 型 | 必須 | 説明・制約 |
| --- | --- | --- | --- |
| `id` | `StringName` | ○ | 技術ID |
| `display_name_key` | `StringName` | ○ | 表示名 |
| `description_key` | `StringName` | ○ | 説明 |
| `origin_faction_id` | `StringName` | ○ | 元勢力 |
| `tier` | `int` | ○ | 1〜5 |
| `category` | `StringName` | ○ | unit／support／facility等 |
| `unlocks_unit_ids` | `Array[StringName]` | — | 解放機体 |
| `unlocks_skill_ids` | `Array[StringName]` | — | 解放支援等 |
| `candidate_tags` | `Array[StringName]` | — | ランダム抽選・系統用 |
| `mandatory_base_tech` | `bool` | ○ | 勢力基礎技術か |
| `giftable` | `bool` | ○ | 技術贈与可能か |
| `capture_unlockable` | `bool` | ○ | 鹵獲解析対象か |
| `encyclopedia_unlockable` | `bool` | ○ | 恒久候補登録可否 |

費用・期間は技術個別に持たず、Tier別`CampaignConfig`から取得する。

### 15.1 周回ノード `GeneratedTechNodeState`

| フィールド | 型 | 説明 |
| --- | --- | --- |
| `node_id` | `StringName` | 周回内一意 |
| `tech_id` | `StringName` | 技術参照 |
| `tier` | `int` | 技術Tier |
| `prerequisite_node_ids` | `Array[StringName]` | 直前Tierの1〜2ノード |
| `gifted` | `bool` | 外交追加ノードか |
| `researched` | `bool` | 研究済み |

### 15.2 研究状態 `ResearchState`

| フィールド | 型 | 説明 |
| --- | --- | --- |
| `node_id` | `StringName` | 研究対象 |
| `funds_paid` | `int` | 開始時支払額 |
| `turns_remaining` | `int` | 1以上 |
| `started_turn` | `int` | 監査・表示用 |

研究開始後はキャンセル・停止・切り替え不可。

## 16. 生産状態

### 16.1 `ProductionQueueState`

| フィールド | 型 | 説明 |
| --- | --- | --- |
| `facility_instance_id` | `StringName` | 生産施設 |
| `job_ids` | `Array[StringName]` | 登録順 |

### 16.2 `ProductionJobState`

| フィールド | 型 | 説明 |
| --- | --- | --- |
| `job_id` | `StringName` | 一意ID |
| `unit_def_id` | `StringName` | 生産機体 |
| `production_required` | `int` | 登録時スナップショット |
| `production_accumulated` | `int` | 現在進捗 |
| `funds_paid` | `int` | 先払い額 |
| `materials_paid` | `int` | 先払い額 |
| `registered_turn` | `int` | 表示用 |

生産ジョブIDは`production_job_<8桁連番>`で生成する。次回連番は
`next_production_job_serial`として保存し、キャンペーン乱数から分離する。
完了・施設喪失で削除したIDは再利用しない。

- キャンセル・一時停止不可。
- キュー並べ替え可能。
- 施設喪失時はキューと全Jobを削除する。
- 完成時は一般兵搭乗の1機部隊を生成する。

## 17. 修理状態 `RepairJobState`

| フィールド | 型 | 説明 |
| --- | --- | --- |
| `unit_instance_id` | `StringName` | 修理対象 |
| `region_id` | `StringName` | 修理場所 |
| `damage_ratio_at_start` | `float` | 開始時損傷率 |
| `target_hp` | `int` | 原則最大HP |
| `funds_paid` | `int` | `ceil(生産資金×損傷率×0.25)` |
| `materials_paid` | `int` | 同物資式 |
| `turns_remaining` | `int` | `max(1, ceil(基本生産ターン×損傷率))` |
| `paused_by_supply` | `bool` | 補給線遮断中 |

キャンセル・返金不可。同時修理数上限なし。

## 18. 外交状態

### 18.1 `RelationState`

| フィールド | 型 | 説明 |
| --- | --- | --- |
| `other_faction_id` | `StringName` | 相手勢力 |
| `friendship` | `int` | −100〜100、初期−50 |
| `treaty_type` | `TreatyType` | 現条約 |
| `treaty_turns_remaining` | `int` | 0以上 |
| `proposal_cooldown_turns` | `int` | 失敗後5 |
| `gift_cooldown_turns` | `int` | 資源・技術共通5 |
| `intel_purchase_cooldown_turns` | `int` | 5 |
| `violation_penalty_turns` | `int` | 破棄後10 |
| `violation_success_penalty_pct` | `int` | 通常−10 |
| `gifted_tech_ids` | `Array[StringName]` | 重複贈与防止 |

関係は対称値を原則とする。片側更新時に相手側も同一トランザクションで更新する。

### 18.2 外交履歴 `DiplomacyLogEntry`

| フィールド | 型 | 説明 |
| --- | --- | --- |
| `turn` | `int` | 発生週 |
| `actor_faction_id` | `StringName` | 実行者 |
| `target_faction_id` | `StringName` | 対象 |
| `action_type` | `StringName` | ceasefire／gift／intel等 |
| `payload` | `Dictionary` | 金額・期間・技術ID等 |
| `success` | `bool` | 成否 |

## 19. 戦闘マップ定義 `BattleMapDef`

| フィールド | 型 | 必須 | 説明 |
| --- | --- | --- | --- |
| `id` | `StringName` | ○ | マップID |
| `scene` | `PackedScene` | ○ | 3D戦場Scene |
| `environment` | `EnvironmentType` | ○ | 適性判定 |
| `world_size_m` | `Vector2` | ○ | 標準1000×1000 |
| `attacker_spawn_transform` | `Transform3D` | ○ | 攻撃側配置基準 |
| `defender_spawn_transform` | `Transform3D` | ○ | 防御側配置基準 |
| `attacker_hq_id` | `StringName` | ○ | 攻撃側本拠点 |
| `defender_hq_id` | `StringName` | ○ | 防御側本拠点 |
| `control_point_ids` | `Array[StringName]` | — | 補助拠点 |
| `terrain_zone_ids` | `Array[StringName]` | — | 地形効果領域 |
| `navigation_region_path` | `NodePath` | ○ | 自由移動Nav |

### 19.1 拠点 `BattleControlPointDef`

| フィールド | 型 | 説明 |
| --- | --- | --- |
| `id` | `StringName` | マップ内一意 |
| `is_headquarters` | `bool` | 本拠点か |
| `position` | `Vector3` | 中心位置 |
| `capture_radius_m` | `float` | 0より大きい |
| `sensor_radius_m` | `float` | 400 |
| `hp_recovery_pct_per_sec` | `float` | 0.01 |
| `en_recovery_pct_per_sec` | `float` | 0.02 |

### 19.2 地形領域 `TerrainZoneDef`

| フィールド | 型 | 説明 |
| --- | --- | --- |
| `id` | `StringName` | マップ内一意 |
| `effect` | `TerrainEffect` | 5種類 |
| `area_node_path` | `NodePath` | Area3D等 |
| `move_multiplier` | `float` | 困難0.8、通常1.0 |
| `evasion_add` | `int` | 遮蔽15、それ以外0 |
| `hazard_hp_pct_per_sec` | `float` | 高危険0.01 |
| `blocks_sensor_los` | `bool` | 大型障害物判定 |

## 20. 一時戦闘状態

戦闘中セーブを行わないため、以下はセーブ対象外。ただし自動解決と手動指揮で同じデータ構造・計算を使用する。

### 20.1 `BattleState`

| フィールド | 型 | 説明 |
| --- | --- | --- |
| `battle_id` | `StringName` | 一時ID |
| `region_id` | `StringName` | 戦略エリア |
| `attacker_faction_id` | `StringName` | 侵攻側 |
| `defender_faction_id` | `StringName` | 防御側 |
| `elapsed_world_sec` | `float` | 0〜300 |
| `time_scale` | `float` | 0／1／2／4 |
| `attacker_squad_ids` | `Array[StringName]` | 上限なし |
| `defender_squad_ids` | `Array[StringName]` | 上限なし |
| `control_point_states` | `Dictionary` | 拠点ID→状態 |
| `rng_state` | `int` | 再現用 |
| `result` | `BattleResultState` | 未決着時null相当 |

### 20.2 `BattleSquadState`

| フィールド | 型 | 説明 |
| --- | --- | --- |
| `squad_id` | `StringName` | 戦略部隊参照 |
| `world_position` | `Vector3` | 部隊中心 |
| `destination` | `Vector3` | 現移動先 |
| `policy` | `BattlePolicy` | 現方針 |
| `sensor_range_m` | `float` | 生存機最大値 |
| `reengage_wait_sec` | `float` | 0〜5 |
| `retreat_prepare_sec` | `float` | 0〜10 |
| `retreat_requested` | `bool` | 撤退中か |
| `last_battle_time_sec` | `float` | 拠点回復5秒停止用 |
| `intel_revision` | `int` | 敵情報照合 |

### 20.3 `BattleUnitState`

| フィールド | 型 | 説明 |
| --- | --- | --- |
| `unit_instance_id` | `StringName` | 戦略個体参照 |
| `initial_hp` | `int` | 戦闘開始時HP。戦略状態へ途中経過を漏らさないため保持 |
| `initial_en` | `int` | 戦闘開始時EN |
| `current_hp` | `int` | 戦闘中HP。結果適用時だけ戦略個体へ反映 |
| `current_en` | `int` | 戦闘中EN。結果適用時だけ戦略個体へ反映 |
| `action_gauge` | `float` | 0〜100 |
| `post_action_delay_sec` | `float` | 0以上 |
| `defending` | `bool` | 装甲＋20・回避＋10 |
| `destroyed_this_battle` | `bool` | HP0 |
| `exp_earned` | `int` | 戦闘後反映 |

### 20.4 `BattleControlPointState`

| フィールド | 型 | 説明 |
| --- | --- | --- |
| `control_point_id` | `StringName` | 定義参照 |
| `owner_faction_id` | `StringName` | 現所有者 |
| `capture_progress` | `float` | 0〜100 |
| `capturing_faction_id` | `StringName` | 現制圧勢力 |

### 20.5 `BattleResultState`

| フィールド | 型 | 説明 |
| --- | --- | --- |
| `winner_faction_id` | `StringName` | 勝者 |
| `loser_faction_id` | `StringName` | 敗者 |
| `reason` | `StringName` | hq_capture／annihilation／retreat／timeout |
| `elapsed_world_sec` | `float` | 戦場時間 |
| `destroyed_unit_ids` | `Array[StringName]` | 撃破個体 |
| `recovered_unit_ids` | `Array[StringName]` | 勝者自軍回収 |
| `captured_unit_ids` | `Array[StringName]` | 敵撃破機10% |
| `lost_unit_ids` | `Array[StringName]` | 完全喪失 |
| `injured_pilot_ids` | `Array[StringName]` | 固有のみ |
| `pilot_exp` | `Dictionary` | pilot ID→EXP |

## 21. 敵情報状態 `IntelRecordState`

| フィールド | 型 | 説明 |
| --- | --- | --- |
| `observer_faction_id` | `StringName` | 情報所有勢力 |
| `target_squad_id` | `StringName` | 対象部隊 |
| `intel_state` | `IntelState` | 未確認／確認済み |
| `target_revision` | `int` | 編成変更検知 |
| `last_known_region_id` | `StringName` | 戦略位置 |
| `last_known_battle_position` | `Vector3` | 戦場最終位置 |
| `last_seen_turn` | `int` | 最終週 |
| `last_seen_world_sec` | `float` | 戦闘内最終時刻 |
| `unit_snapshot` | `Array[Dictionary]` | 機体、配置、パイロット、HP・EN |
| `revealed_until_world_sec` | `float` | 発砲公開終了時刻 |

`target_revision`が現在部隊の`intel_revision`と異なる場合、記録を破棄して未確認へ戻す。

## 22. イベント定義 `EventDef`

| フィールド | 型 | 必須 | 説明 |
| --- | --- | --- | --- |
| `id` | `StringName` | ○ | イベントID |
| `faction_id` | `StringName` | ○ | 対象勢力 |
| `importance` | `EventImportance` | ○ | MAIN／SUB |
| `priority` | `int` | ○ | 同種内順序。最終tieはID |
| `title_key` | `StringName` | ○ | タイトル |
| `condition_tree` | `Dictionary` | ○ | AND／OR／NOT対応条件 |
| `exclusive_group_id` | `StringName` | — | 排他イベント群 |
| `once_per_profile` | `bool` | ○ | 通常false |
| `once_per_campaign` | `bool` | ○ | 通常true |
| `scene_background` | `Texture2D` | — | 主要イベント |
| `dialogue_entries` | `Array[Dictionary]` | — | 話者、立ち絵、本文キー |
| `choice_entries` | `Array[Dictionary]` | — | 選択肢と効果ID |
| `default_effect_ids` | `Array[StringName]` | — | 選択なし効果 |
| `followup_event_ids` | `Array[StringName]` | — | 後続候補 |

イベント条件は実行コードをResourceへ保存せず、許可された条件タイプと値のデータとして表現する。

## 23. 実績定義 `AchievementDef`

| フィールド | 型 | 説明 |
| --- | --- | --- |
| `id` | `StringName` | 実績ID |
| `display_name_key` | `StringName` | 仮名称含む |
| `description_key` | `StringName` | 条件説明 |
| `condition_type` | `StringName` | faction_clear／difficulty_clear等 |
| `condition_payload` | `Dictionary` | 勢力ID、回数、難易度等 |
| `exp_bonus_pct` | `float` | 0.05 |
| `steam_achievement_id` | `StringName` | 任意 |

10件のID案：

```text
clear_earth_union
clear_space_alliance
clear_independent_corporate
clear_normal
clear_hard
clear_within_50_turns
research_three_tier5
capture_ten_units
three_treaties_in_run
manual_flawless_victory
```

## 24. プロフィール状態 `ProfileState`

| フィールド | 型 | 説明 |
| --- | --- | --- |
| `profile_version` | `int` | 移行用 |
| `encyclopedia_unit_ids` | `Array[StringName]` | 発見機体 |
| `encyclopedia_weapon_ids` | `Array[StringName]` | 発見武器 |
| `encyclopedia_pilot_ids` | `Array[StringName]` | 発見人物 |
| `unlocked_tech_candidate_ids` | `Array[StringName]` | 次周抽選候補 |
| `achievement_ids` | `Array[StringName]` | 達成済み |
| `permanent_exp_bonus_pct` | `float` | 実績から再計算可能。最大0.50 |
| `viewed_event_ids` | `Array[StringName]` | 既読・回想 |
| `settings` | `SettingsState` | 共通設定 |

`permanent_exp_bonus_pct`は実績配列から起動時に再計算し、破損・不整合を検証する。

## 25. 設定状態 `SettingsState`

| フィールド | 型 | 説明 |
| --- | --- | --- |
| `window_mode` | `int` | window／borderless／exclusive fullscreen |
| `resolution` | `Vector2i` | ウィンドウ・排他用 |
| `monitor_index` | `int` | 表示先 |
| `ui_scale` | `StringName` | small／standard／large |
| `master_volume` | `float` | 0.0〜1.0 |
| `bgm_volume` | `float` | 0.0〜1.0 |
| `sfx_volume` | `float` | 0.0〜1.0 |
| `effect_reduction` | `bool` | 点滅軽減 |
| `camera_shake` | `bool` | 揺れ |
| `cinematic_camera` | `bool` | 初期true |
| `battle_speed` | `float` | 1／2／4。戦闘開始時1へ戻す |
| `round_animation_speed` | `float` | 1／2／0（skip） |
| `last_input_type` | `StringName` | keyboard_mouse／gamepad |

キー・ボタン割り当ては固定のため保存しない。

## 26. キャンペーンセーブ `CampaignSaveData`

### 26.1 ルートフィールド

| フィールド | 型 | 説明 |
| --- | --- | --- |
| `save_version` | `int` | 移行用 |
| `save_id` | `String` | スロットID |
| `saved_at_unix` | `int` | 保存日時 |
| `play_time_sec` | `int` | プレイ時間 |
| `difficulty_id` | `StringName` | 途中変更不可 |
| `player_faction_id` | `StringName` | 選択勢力 |
| `week_number` | `int` | 1〜100 |
| `active_faction_index` | `int` | 固定順序の位置 |
| `phase` | `StrategicPhase` | 手動保存はSTRATEGYのみ |
| `rng_state` | `int` | キャンペーン乱数 |
| `next_unit_serial` | `int` | 次に生成する機体個体IDの連番。乱数と分離し、削除後も再利用しない |
| `next_squad_serial` | `int` | 次に生成する部隊IDの連番。乱数と分離し、削除後も再利用しない |
| `next_production_job_serial` | `int` | 次に生成する生産ジョブIDの連番。乱数と分離し、削除後も再利用しない |
| `faction_states` | `Array[Dictionary]` | 各勢力 |
| `region_states` | `Array[Dictionary]` | 全エリア |
| `unit_states` | `Array[Dictionary]` | 全機体個体 |
| `squad_states` | `Array[Dictionary]` | 全部隊 |
| `pilot_states` | `Array[Dictionary]` | 固有パイロット |
| `production_jobs` | `Array[Dictionary]` | 生産 |
| `repair_jobs` | `Array[Dictionary]` | 修理 |
| `intel_records` | `Array[Dictionary]` | 勢力別情報 |
| `diplomacy_log` | `Array[Dictionary]` | 外交履歴 |
| `campaign_event_history` | `Array[StringName]` | 発生済み |

### 26.2 保存前検証

- すべての参照IDがマスターまたは同セーブ内個体に存在する。
- 機体個体は必ず1つの部隊だけに属する。
- 固有パイロットは最大1機にだけ配置される。
- エリア所有権と勢力の所有エリアキャッシュが一致する。
- 資金・物資・HP・EN・残りターンが負数でない。
- 手動保存時の`phase == STRATEGY`。
- 戦闘一時状態を保存しない。

## 27. マスターデータ配置案

```text
res://data/
  campaign/
  difficulties/
  factions/
  regions/
  facilities/
  battle_maps/
  units/
  weapons/
  support_skills/
  pilots/
  pilot_skills/
  techs/
  events/
  achievements/
```

`GameState`は各ディレクトリを走査し、`id -> Resource`の辞書へロードする。ディレクトリ名とResourceクラスの対応を固定し、異なる型が混入した場合は起動時エラーにする。

## 28. 既存実装からの移行対応

| 現在 | 新定義 | 対応 |
| --- | --- | --- |
| `FactionDef.starting_resources` | `starting_funds`＋`starting_materials` | 1資源を分離 |
| `Faction.resources` | `FactionState.funds/materials` | ランタイム再設計 |
| `UnitType` | `UnitDef`＋`WeaponDef` | 能力・固定武装・適性を分離 |
| `UnitStack.units[type_id] = count` | `SquadState`＋`UnitInstanceState` | 個体HP・EN・パイロット対応 |
| `TechDef.cost` | Tier別`CampaignConfig.tech_costs` | 個別費用を廃止 |
| `Faction.tech_tier` | 生成技術ノード＋研究済みID | 単純開発レベルを廃止 |
| `RegionDef.resource_yield` | 資金・物資基礎収入＋固定施設 | 二資源化 |
| `Region.pending_production` | 施設別キュー＋生産値 | 並列タイマーを廃止 |
| `CombatResolver` | RTS戦闘＋30秒ラウンド解決 | 簡易比率戦闘を置換 |
| `TurnManager`一括進行 | 勢力別戦略・戦闘フェイズ | 固定勢力順に再設計 |

既存`.tres`は新Resourceクラスへ一括変換せず、IDを維持しながら新マスターを作成する。旧フィールドは移行完了後に削除する。

## 29. 起動時データ検証

開発ビルドでは起動時に以下を検査し、エラー一覧を表示する。

1. IDの空・重複・命名規則違反
2. 存在しない参照ID
3. 勢力本拠地とエリア所有者の不整合
4. エリア隣接の非対称
5. 技術Tier範囲・前提生成不能
6. 武器ヒット数1〜10、命中率・クリティカル率範囲
7. 機体の武器・技術・勢力参照
8. パイロット能力0〜200、成長0〜3、スキル最大5
9. 固定施設値と種別の矛盾
10. 戦闘マップの本拠点・Nav・Spawn不足
11. イベント条件・効果タイプの未対応値
12. 実績10件とEXP補正合計0.50

## 30. 実装優先順位

1. 共通enum・IDレジストリ・検証器
2. `CampaignConfig`、`FactionDef/State`、`RegionDef/State`
3. `UnitDef`、`WeaponDef`、`UnitInstanceState`、`SquadState`
4. `PilotDef/State`、一般兵判定
5. `TechDef`、生成ノード、研究状態
6. 施設、生産キュー、修理ジョブ、補給線
7. 戦闘マップ定義、一時戦闘状態、戦闘結果
8. 外交、敵情報、イベント
9. プロフィール、実績、設定、セーブ移行
