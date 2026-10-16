# home-power

Home energy storage: a Marstek Venus E 3.0 battery, and a menu bar app that reads it over the
Local API: [mac/](mac/README.md) (HomePower).

This README is a field reference for the device: docs, first start, app, indicators, error codes,
blackout use, videos, and API links.

**Device:** Marstek Venus E 3.0 (Gen 3), official model **MST-BIE5-2500**, LiFePO4 51.2 V / 100 Ah, 5.12 kWh.
Sold in Ukraine as "Зарядна станція Marstek Venus-E V3 51.2V 5.12kWh".

⚠️ marks facts from user forums or reviews, not confirmed by official docs.

---

## 0. Must know

1. **The BACKUP socket works during a blackout only if "Backup Power" is enabled in the app.** While it is off, the socket is off too.
2. **BACKUP is an output.** Plug loads into it. Never connect it to the house wiring, except through a properly installed ATS / changeover switch. If GRID and BACKUP are both connected to the mains, the breaker trips or the unit is damaged.
3. **A generator goes into the GRID input only**, never into BACKUP.
4. When the grid goes down, the GRID port disconnects (anti-islanding, EN50549-1). Power comes **only from the BACKUP socket**.
5. **No cold start.** If the SOC drops to the DoD cutoff during a blackout, the socket turns off and will not come back by itself. Charge from the grid or a generator above ~12% to restore it.

## 1. Documentation

| Document | Link |
|---|---|
| User manual (V3, multilingual: indicators, error codes, installation) | [PDF](https://cdn.shopify.com/s/files/1/0746/1575/0952/files/43A212010001_BIE5_01_140mmx210mm_120g_80g_VENUS-E_3.0_2025.05.08.29_compressed.pdf) |
| User manual, Ukrainian translation (hosted by a UA retailer, 30 MB) | [PDF](https://shop.bachu-vse.online/wp-content/uploads/2026/02/Venus-E-3.0_UA.pdf) |
| App manual, Venus E 3.0 (v1.6.53, 2025-12) | [PDF](https://eu.hamedata.com/ems/resource/agreement/app/venus/Venus_E3.pdf) |
| Product presentation (EU) | [PDF](https://cdn.shopify.com/s/files/1/0746/1575/0952/files/MARSTEK_VENUS_E_3.0_PPT_EU_EN.pdf) |
| Datasheet (distributor) | [PDF](https://cdn.shopify.com/s/files/1/0609/9481/4140/files/Marstek-Venus-E-3-0-Balkonkraftwerk-Speicher-Datenblatt.pdf) |
| Official pages | [Download Center](https://marstekenergy.com/pages/download-center) · [Product](https://marstekenergy.com/products/marstek-venus-e-gen-3) · [FAQ](https://marstekenergy.com/pages/faqs) · [Warranty](https://marstekenergy.com/pages/warranty) |
| Best community knowledge (DE) | [photovoltaikforum: Venus topic index](https://www.photovoltaikforum.com/thread/263629-inhaltsverzeichnis-und-themen%C3%BCbersicht-zum-marstek-venus-c-e-ac-speicher-5-12-kw/) · [Backup socket wiki](https://www.photovoltaikforum.com/wissen/entry/121-notstromsteckdose/) · [Firmware thread](https://www.photovoltaikforum.com/thread/252576-venus-e-c-aktuelle-firmware-probleme-%C3%A4nderungen-erfahrungen/) |
| In-depth reviews | [smartzone.de](https://www.smartzone.de/marstek-venus-e-3-0-im-test-speicher-fuer-balkonkraftwerke-und-mehr/) · [techtest.org](https://techtest.org/marstek-venus-e-gen-3-0-test-ac-batteriespeicher-mit-512-kwh-im-test-1000e-fuer-512-kwh/) · [homeandsmart.de](https://www.homeandsmart.de/marstek-venus-e-3-0-speicher-test) |

## 2. Specs

| | |
|---|---|
| Capacity | 5.12 kWh. Usable ~4.5–4.9 kWh (DoD 90%) |
| Grid charge | up to 2500 W, full charge < 3 h |
| Grid feed-in | 800 W by default, 2500 W switchable in the app |
| BACKUP (EPS) | Schuko socket, 2.5 kVA continuous, 3.5 kVA peak for 10 s. Switchover ~15 ms (20 ms with SmartBox) |
| PV input | none, AC-coupled only |
| Connectivity | Wi-Fi, Bluetooth, LAN (RJ45), RS485 (RJ45) |
| Enclosure | IP65, fanless, < 30 dB, 60 kg, 480×153×624 mm |
| Temperature | −20…+55 °C operating. No separate charge/discharge limits in official docs |
| Grid | 230 V (187–253 V), 50 Hz |
| Idle draw | 5–10 W. Switched off: ~1% SOC loss per day |
| Efficiency | round-trip ~83–85% (measured) |
| Cycles | > 6000 @ 25 °C |
| Expansion | up to 3 units per phase; 9 units / 46.08 kWh on 3 phases with SmartBox. BACKUP outputs must never be interconnected |
| Warranty | 10 years from activation; register in the app with a receipt |

⚠️ No official Marstek distributor found in Ukraine. Get the warranty terms from the seller in writing.

## 3. First start

1. Mount strictly upright, on the floor or a wall (brackets included). Clearances: **≥200 mm top, ≥150 mm sides, ≥20 mm from the wall**. Nothing flammable nearby.
2. Open the left cover. Underneath: **RS485**, **LAN** ports and the **ON/OFF button**.
3. Plug the round connector of the AC cable into **GRID**, the plug into a wall socket. The socket's circuit must have its own breaker.
4. Press the button. The unit is ready to pair with the app.
5. In the app: add the device over Bluetooth → connect Wi-Fi → update firmware → enable **Backup Power** → choose a mode.
6. Register the warranty in the app (Warranty section).

The AC cable is not replaceable: per the manual, a damaged cable means the unit must be replaced.

## 4. App and Wi-Fi

- **App:** **MARSTEK** (by Hamedata) — Google Play, [App Store](https://apps.apple.com/app/id6459365638), [APK](https://eu.hamedata.com/ems/apk/marstek/index.html).
- **Sign-up:** first pick the server in the top-right corner of the login screen. For Ukraine use **Europe**. Always log in to the same server you registered on.
- **Adding the device:** "+ Add Device" → BT scan → name it → pick Wi-Fi and enter the password. Keep Bluetooth connected for the whole setup.
- **Android:** without location enabled and granted to the app, the device is not found over BT.
- **Wi-Fi:** ⚠️ **2.4 GHz only** (forum reports; module Quectel FC41D). If unstable:
  - use a dedicated 2.4 GHz SSID with a fixed channel;
  - avoid mesh roaming;
  - check "Wi-Fi Signal History" in the app;
  - best fix — use a **LAN cable**.

  Signal −50…−60 dBm is good, below −70 dBm expect problems. Errors 5C2–5C4 mean weak Wi-Fi.
- **Firmware:** red dot in settings → Upgrade. **Main firmware updates over Bluetooth only** — keep the phone close.
  - ⚠️ Versions 146/147: reports of settings resets and reboots with LAN connected.
  - 150 fixed Local API over Ethernet, 151 improved Modbus TCP stability. Changelog: [marstek-firmware-archiv](https://github.com/sphings79/marstek-firmware-archiv).
  - ⚠️ Updates are not pushed to every unit: the app may say "up to date" while newer firmware exists. Email support@marstekenergy.com with the serial number and ask them to unlock the latest firmware for it; it then shows up in the app (reply within ~24 h to a few days). Each component takes ~30 min; keep the phone next to the unit.
  - Latest known for V3 (2026-09): Control/EMS **151**, BMS **115**, Micro **119**.
  - ⚠️ Before leaving 148, read [Running without the cloud](#running-without-the-cloud): 150+ resets or reboots when the cloud is unreachable, as it often is during a blackout.
- **Useful settings:**
  - Backup Power;
  - Grid Power 800/2500 W;
  - **DoD 30–88%** (88% means discharge down to 12% SOC). The app labels the rest "Backup Reserve": grid-side discharge (Self-Consumption, AI, Manual, API) stops there. ⚠️ Whether BACKUP may dip into the reserve during an outage is unclear — forum reports conflict. For backup-only use set 88%, for daily cycling leave 20–30% as an outage reserve;
  - Local API;
  - sharing (view-only or control);
  - factory reset (with or without clearing statistics).

  **Do not enable Bluetooth Lock:** during a blackout without internet, BT is the only way to control the unit.

## 5. Modes

- **Self-Consumption** — needs a meter: Marstek CT002/CT003, Shelly Pro 3EM, Shelly EM Gen3 or Pro EM-50. The battery covers house consumption. Sub-modes: single phase / three-phase total. Reaction 2–3 s.
  - Shelly needs "RPC over UDP" enabled and must be on the same network.
  - ⚠️ Plain Shelly 3EM (not Pro) does not work.
- **AI Mode** — charging on spot prices (Nord Pool, Tibber, Octopus). **Useless in Ukraine.**
- **Manual** — schedule: time, power 30–800/2500 W, weekdays. **Main mode for blackouts**: charge while the grid is up, don't discharge into the house, keep the battery full.
- **Passive** — API only: set power and a countdown.
- **UPS** — in the app this is the Backup Power toggle. In the API it is a separate `UPS` mode.

## 6. Indicators and button

Panel left to right: **WARN · GRID · BACKUP · BATTERY · CT · WIFI · BT**. LEDs are white, WARN is red.

| LED | Meaning |
|---|---|
| BATTERY | off — powered off; on — powered on; bar runs **→** — charging; **←** — discharging |
| WARN | off — normal; **solid red — fault** (⚠️ blinking for 1–2 min after restart is normal) |
| GRID / BACKUP | on — GRID / BACKUP socket active |
| CT | on — meter connected |
| WIFI / BT | on — connected (BT lights only during an active session) |

Button:
- Official: short press toggles on/off.
- ⚠️ Hold **>10 s** — reboot.
- ⚠️ Hard reset: hold 10 s, switch off, unplug from the grid for **15 min or more**.
- Wi-Fi cannot be reset with the button; reconfigure it in the app over BT.

## 7. Error codes (from the manual)

| Code | Meaning / action |
|---|---|
| 400 / 530 / 558 | overheating — check ventilation |
| **559** | too cold |
| 401, 402, 410–430 | internal error — wait 30 s, restart |
| **405** | BACKUP overload — reduce load |
| 431 | no BMS communication (often deep discharge) — connect to grid within 5 min |
| 432 / 433 | battery overvoltage / overcurrent — contact support |
| 434, 560 | battery low — connect to grid |
| 440–448 | grid issues (voltage, frequency, fluctuation, DCI/DCV) — wait for the grid to stabilize |
| 5C0 | Bluetooth error |
| 5C1 | OTA update failed — retry |
| 5C2–5C4 | weak Wi-Fi |
| 5C8–5CB | network error |
| 5D2 | no meter (CT) communication |

⚠️ Common V3 field issues: stuck in standby or bypass; SOC suddenly drops to 0% with BMS unresponsive (431) — warranty replacement.

## 8. Operation

- **Placement:** a heated room is best. IP65 allows outdoor use, but LiFePO4 handles charging in frost poorly, and there is no heater.
- **Heat:** after 2 h at 2.5 kW the front reaches 35–37 °C, the rear heatsink up to 50 °C. Normal.
- **Minimum SOC:** don't go below 15%. Avoid sitting at 100% in heat for long.
- ⚠️ **SOC calibration:** do a full cycle periodically — discharge to cutoff, charge to 100%. This also balances cells. Hanging at 99% is normal.
- **Storage:** charged and switched off with the button. Inspect and dust once a year.

## 9. Blackouts, ATS, generator

- Relay switchover in ~15 ms — this is **not an online UPS**. Keep PCs/NAS on their own small UPS. Fridge, boiler, pump, router run fine in tests.
- **Bypass while the grid is up:** with Backup Power enabled, the BACKUP socket is a relay pass-through — loads get grid power directly, the inverter and battery are not used (app shows "Bypass"; Modbus 35100 = 6). The battery only spends its 5–10 W standby draw.
  - Bypass does not stop **Self-Consumption** from cycling the battery: the meter sees BACKUP loads as house consumption, and the battery discharges to cover it. To keep the battery untouched, use Manual with no discharge slots.
  - No official bypass current limit — keep BACKUP loads within its 2.5 kVA / 10.9 A rating.
  - ⚠️ The GRID plug carries charging (up to 2.5 kW) **plus** bypassed BACKUP loads. Up to ~5 kW (~22 A) through one Schuko socket exceeds a 16 A circuit: cap the charge power in Manual or keep BACKUP loads low while charging.
- In Self-Consumption the battery may already be empty when the outage starts. Hence: Manual charging or a high DoD cutoff. **DoD can be changed over BT without internet.**
- **Generator:** inverter type only, stable 50 Hz and 187–253 V, otherwise errors 440–446. Limit charge power in Manual to fit the generator: the unit draws up to 2.5 kW plus whatever is on BACKUP. ⚠️ One user could set manual charging from a generator only over Wi-Fi, not BT.
- **Solar:** a grid-tied inverter shuts down during a blackout. A micro-inverter plugged into BACKUP can charge the battery in island mode. With the grid present, that inverter feeds the house via bypass instead of the battery.
- **Meters for Ukraine:** Shelly Pro 3EM or CT002 clamps. P1, HomeWizard and EcoTracker target EU meters.
- **CT002 is a meter, not a switch.** DIN-rail box with an antenna, voltage inputs N/L1/L2/L3 and CT clamp jacks. It only measures grid power for Self-Consumption; it carries no load and does no backup switching.
- **Whole-apartment backup** (one feed for the whole apartment, switched to battery on outage) — two options, both by an electrician in the distribution board:
  - **Marstek SmartBox** (DB63S single-phase / DB63T three-phase): official whole-house backup, switchover within 20 ms, 1–3 Venus per phase; three-phase needs at least 3 Venus (one per phase).
  - **Generic ATS / changeover switch:** grid → apartment normally, Venus BACKUP → apartment on outage. The socket feeding Venus GRID must be on the grid side of the ATS, otherwise BACKUP ends up feeding GRID.
  - Either way, during an outage the whole apartment shares **one Venus = 2.5 kW** (3.5 kVA for 10 s). Kettle + oven + boiler at once → error 405.

## 10. Videos

All links verified.

**First start, app, Wi-Fi (UA):**
- [Як налаштувати MARSTEK VENUS E GEN 3.0 — Marstek Ukraine (official)](https://www.youtube.com/watch?v=GiQHWHLOkjs) — 3 min, start here
- [Підключення, налаштування застосунку та тест — TRINITI-SB](https://www.youtube.com/watch?v=7CgXUoh_OX4) — indicators, modes, schedule, backup test
- [Як розпочати роботу з Marstek — Dnipro-M](https://www.youtube.com/watch?v=9rBBpWtgABU) — chapters on lost Wi-Fi, BT not found, generator charging

**Modes, UPS (UA):**
- [Детальний огляд Venus E 3.0 — Твій Дім](https://www.youtube.com/watch?v=PggvUGhqucg) — UPS, two-zone meter, modes
- [Як Marstek живить всю квартиру — Kostenko Family](https://www.youtube.com/watch?v=yb9xfGox-bE)
- [Все про MARSTEK Venus E, або те чого не показують блогери — BootUse UA](https://www.youtube.com/watch?v=kzwtMhauvO4) — 25 min: load tests, bypass, RS485, Home Assistant

**ATS and distribution board (UA):**
- [Підключення через АВР до щитка — Іван Матевощук](https://www.youtube.com/watch?v=KVxCnWrPz_4)

**Deep dive (UA):**
- [Що в середині? Огляд та тест — GreenPowerTalk](https://www.youtube.com/watch?v=S1eorcCzOq4) — 33 min: teardown, efficiency, Local API, solar
- [Я підключив Marstek до Telegram через API — Kostenko Family](https://www.youtube.com/watch?v=Q6OPBypuvmI) — relevant for this project

**Reviews (UA):**
- [Огляд UA](https://www.youtube.com/watch?v=66e-uiRpgB8)
- [Marstek Ukraine — review](https://www.youtube.com/watch?v=iZR1pNrr4tQ)
- [Andro-news](https://www.youtube.com/watch?v=MZkgLCwQNLc)

**RU:**
- [Обзор от ИТшника — Андрій Нікішаєв](https://www.youtube.com/watch?v=XhsKXBjHVw4)
- Viktor-Ard: [part 1](https://www.youtube.com/watch?v=nONDibVYpU8), [part 2 — per-phase compensation](https://www.youtube.com/watch?v=qfmAxqjDQH4), [+ micro-inverter and panels](https://www.youtube.com/watch?v=EnmrV2FTkFo)
- [ZBS — тянет всю квартиру](https://www.youtube.com/watch?v=VZ6VfcOYeA4)

**EN/DE:**
- [Official installation guide](https://www.youtube.com/watch?v=Rrnmk98oC5o)
- [Firmware update in the app](https://www.youtube.com/watch?v=UuP8fJtHoUs)
- [Blackout test (DE)](https://www.youtube.com/watch?v=1RrO5hPRTWo)
- [Local control without cloud in Home Assistant (DE, 48 min)](https://www.youtube.com/watch?v=bFsq0se9hMI)

## 11. API

### Official Local API (Open API)

[PDF Rev 3.1](https://eu.hamedata.com/ems/resource/agreement/MarstekDeviceOpenApi.pdf) · [markdown copy](https://github.com/taurgis/has-marstek-local-api/blob/main/docs/marstek_device_openapi.MD)

- Transport: JSON-RPC style over **UDP, port 30000** (configurable in the app). Discovery: broadcast `Marstek.GetDevice` to `255.255.255.255:30000`.
- **Disabled by default.** Enable in the app (Settings → Local API) or over BT with [marstek-venus-monitor](https://rweijnen.github.io/marstek-venus-monitor/latest/). ⚠️ Firmware resets on 144–148 can switch it off again; a client should report "no answer" as "Local API probably off".
- V3 identifies itself as `VenusE 3.0` / `VNSE3-0`. `wifi_mac` in `GetDevice` is the **access point's BSSID**, not the unit's; identify the unit by `ble_mac`.
- Methods: `Marstek.GetDevice`, `Wifi.GetStatus`, `BLE.GetStatus`, `Bat.GetStatus`, `ES.GetStatus`, `ES.GetMode`, `ES.SetMode` (Auto / AI / Manual / Passive / UPS), `EM.GetStatus`. `PV.GetStatus` is not available on Venus E (`-32601 Method not found`). SYS methods (`DOD.SET`, `Led.Ctrl`, `Ble.Adv`, `Set.Ver`, `Reset.Factory`) need firmware ≥150; `DOD.SET` has no read-back.
- Gotchas:
  - bind **source port 30000** (SO_REUSEADDR); some firmware replies only there;
  - one request at a time; the firmware ignores requests for **~2 s after a reply** (0 of 23 answered within 1 s, 13 of 13 after 2 s);
  - over Wi-Fi ~7% of requests time out, in bursts. Resend reads at 0.5, 2.5 and 5 s; send mode writes once;
  - Local API runs over Wi-Fi or LAN, not both; LAN wins;
  - units differ between firmware versions (Wh vs kWh, temperature ×10). ⚠️ Some firmware resets on `Bat.GetStatus` ([taurgis #14](https://github.com/taurgis/has-marstek-local-api)); don't poll it often;
  - Manual: one slot per `SetMode` call; a slot that already covers the current time is often not acknowledged.

**Our unit (checked 2026-10-14):** firmware 148, on Wi-Fi at −40 dBm. Unicast works from port 30000 and from an ephemeral port; all read methods answered on the first try. The ~2 s quiet window is device-wide: a request right after another client's reply is dropped too. Broadcast discovery over Wi-Fi needs resends: right after a burst of requests, only the copy sent at 2.5 s was answered, near the 5 s mark. On 148, `ES.GetStatus` returns `total_*_energy` as 0 and has no `bat_power`; `Bat.GetStatus` works (temperature in °C, capacity in Wh).

Manual slot and UPS (`week_set` bit 0 = Monday, `time_num` 0–9):

```json
{"id":1,"method":"ES.SetMode","params":{"id":0,"config":{"mode":"Manual","manual_cfg":{"time_num":0,"start_time":"08:30","end_time":"20:30","week_set":127,"power":800,"enable":1}}}}
{"id":1,"method":"ES.SetMode","params":{"id":0,"config":{"mode":"UPS","ups_cfg":{"enable":1}}}}
← {"id":1,"src":"…","result":{"id":0,"set_result":true}}
```

```json
→ {"id":1,"method":"ES.GetStatus","params":{"id":0}}
← {"id":1,"src":"VenusE-24215edb178f","result":{"id":0,"bat_soc":98,"bat_cap":5120,"pv_power":0,
   "ongrid_power":100,"offgrid_power":0,"total_pv_energy":0,"total_grid_output_energy":2548,
   "total_grid_input_energy":3273,"total_load_energy":0}}
```

```json
{"id":1,"method":"ES.SetMode","params":{"id":0,"config":{"mode":"Passive","passive_cfg":{"power":100,"cd_time":300}}}}
```

⚠️ Passive `power` sign: negative = charge, positive = discharge (not stated in the PDF).

### Modbus

- **TCP:** port 502, **LAN only** (not Wi-Fi), firmware ≥144, unit ID 1, a single session at a time.
- **RTU:** RS485 RJ45, 115200 8N1, ID 1, via a gateway (Elfin EW11, Waveshare) or ESP32.
- Writing 42xxx registers requires `42000 = 0x55AA` first; `0x55BB` disables RS485 control mode.
- **Gen 2 register maps do not apply to V3.** V3 maps:
  - [ViperRNMC/marstek_venus_modbus](https://github.com/ViperRNMC/marstek_venus_modbus) (`registers/e_v3.yaml`)
  - [evcc docs](https://docs.evcc.io/en/meters/marstek-venus-e-gen-3-0.md) · [evcc template](https://github.com/evcc-io/evcc/blob/master/templates/definition/meter/marstek-venus-e.yaml)
  - [schauveau/modbus-marstek-venus3](https://github.com/schauveau/modbus-marstek-venus3)
  - [sphings79/marstek-modbus-suite](https://github.com/sphings79/marstek-modbus-suite)

Key V3 registers:

| Purpose | Register |
|---|---|
| SOC | 34002 (u16 ×0.1 %) |
| Battery power | 30001 (i16 W) |
| AC power | 30006 (i16 W) |
| Battery voltage / current | 30100 (×0.01 V) / 30101 (×0.1 A) |
| Total charge / discharge | 33000 / 33002 (u32 ×0.01 kWh) |
| Inverter state | 35100 (0 sleep, 1 standby, 2 charge, 3 discharge, 4 backup, 5 OTA, 6 bypass) |
| Firmware EMS / VMS / BMS | 30200 / 30202 / 30204 |
| RS485 control mode | 42000 |
| Force (0 none, 1 charge, 2 discharge) | 42010 |
| Force charge / discharge power | 42020 / 42021 |
| Work mode (0 manual, 1 anti-feed, 2 trade/AI) | 43000 |
| Max charge / discharge power | 44002 / 44003 |
| Backup | 41200 |

### Cloud (unofficial)

- Login: `https://eu.hamedata.com/app/Solar/v2_get_device.php?mailbox=<email>&pwd=<md5(password)>` → `token`.
- Data: `https://eu.hamedata.com/ems/api/v1/getDeviceList?mailbox=..&token=..`
- Cloud MQTT bridge to a local broker: [tomquist/hame-relay](https://github.com/tomquist/hame-relay) · decoder: [tomquist/hm2mqtt](https://github.com/tomquist/hm2mqtt)
- HA cloud integration: [DoctaShizzle/marstek_cloud](https://github.com/DoctaShizzle/marstek_cloud)

### Integrations

- **Home Assistant:**
  - official: [MarstekEnergy/ha_marstek](https://github.com/MarstekEnergy/ha_marstek) (sensors only, 30 s polling). Its licence allows HA use only. The library [aiomarstek](https://github.com/MarstekEnergy/aiomarstek) is MIT, read-only and alpha.
  - most active, best protocol research (firmware notes, unit profiles, retry policy): [taurgis/has-marstek-local-api](https://github.com/taurgis/has-marstek-local-api)
  - with Passive mode and schedules: [jaapp/ha-marstek-local-api](https://github.com/jaapp/ha-marstek-local-api). No licence, no commits since 2025-11.
- **Standalone:**
  - Go library + CLI, Prometheus exporter, MCP: [loafoe/go-marstek](https://github.com/loafoe/go-marstek) (Apache-2.0)
  - Python CLI: [pangamut/marstek-cli](https://github.com/pangamut/marstek-cli) (MIT)
  - macOS menu bar, Ukrainian UI, tested on fw 148: [kotov228/marstek-mac-widget](https://github.com/kotov228/marstek-mac-widget) (MIT)
  - Telegram bot with outage alerts derived from grid power and SOC trend: [pashaoleynik97/marstek-tg-bot](https://github.com/pashaoleynik97/marstek-tg-bot) (Kotlin, Venus A)
- **Others:** [evcc](https://docs.evcc.io/en/meters/marstek-venus-e-gen-3-0.md) · [Homey](https://homey.app/en-us/app/com.niewold.marstek/) · [openHAB](https://community.openhab.org/t/marstek-energy-battery-binding-5-0-0-0-6-0-0-0/167938) · [ioBroker](https://github.com/Slugger2k/ioBroker.marstek-venus) · [Node-RED](https://github.com/gitcodebob/marstek-venus-rs485-node-red)
- **Meter emulation (CT002/CT003, Shelly):** [tomquist/AstraMeter](https://github.com/tomquist/AstraMeter) · [sdeigm/uni-meter](https://github.com/sdeigm/uni-meter). CT protocol notes: [rweijnen/marstek-venus-e-firmware-notes](https://github.com/rweijnen/marstek-venus-e-firmware-notes).
- **BLE:** [jaapp/ha-marstek-ble](https://github.com/jaapp/ha-marstek-ble) · [sphings79/marstek-ble-control](https://github.com/sphings79/marstek-ble-control)

### Running without the cloud

⚠️ Since firmware 150, if cloud telemetry upload fails, the battery resets its network chip: every 15 min on Wi-Fi, every 30 min on LAN. This breaks Modbus TCP and HA. On 151, decompiled code shows a reboot after ~4 h 25 min without the cloud, which **cuts the output, BACKUP included** (not measured yet). During a blackout the internet is often down too, so **stay on 148** until this is confirmed or fixed. Workaround: [sphings79/Marstek-offline-endpoint](https://github.com/sphings79/Marstek-offline-endpoint).
