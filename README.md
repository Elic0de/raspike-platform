# raspike-platform

Raspberry Pi 起動時に ET ロボコン用のローカルサービスを安定起動しつつ、学校 Wi-Fi 認証やアップデート処理をロボット操作系から切り離して管理するための platform リポジトリです。

## 設計方針

- `raspike-bridge.service` と `raspike-web.service` はローカルサービスとして systemd で常駐起動します。
- bridge / web-ui は学校 Wi-Fi 認証に依存しません。認証に失敗してもロボット操作系は起動できます。
- USB デバイス名の固定は udev が担当し、実機デバイスは `/dev/raspike-real` として扱います。
- libraspike-art が作る `/etc/udev/rules.d/99-serial.rules` は platform 管理版へ置き換え、元ファイルは uninstall で復元できるようバックアップします。
- 学校 Wi-Fi の SSID 検知と認証起動だけを NetworkManager dispatcher が担当します。
- `raspike-network-auth.service` と `raspike-update.service` は oneshot で、通常は enable しません。
- `update.sh` は bridge / web の更新だけを担当し、既存 web をバックアップしてから差し替えます。

## 配置先

```text
/opt/raspike
├── apps/
│   ├── bridge/
│   └── web/
├── config/
│   ├── raspike.env
│   └── wifi-auth.env
├── scripts/
│   ├── school-auth.sh
│   └── update.sh
└── logs/
```

## Install

Raspberry Pi 上で実行します。

ワンライナーで実行する場合:

```bash
curl -fsSL https://raw.githubusercontent.com/Elic0de/raspike-platform/main/scripts/install.sh | sudo bash
```

branch/tag や取得元を変える場合:

```bash
curl -fsSL https://raw.githubusercontent.com/Elic0de/raspike-platform/main/scripts/install.sh \
  | sudo env RASPIKE_PLATFORM_REF=main bash
```

repo を clone 済みの場合:

```bash
sudo ./installer/install.sh
```

必要に応じて取得元を環境変数で上書きできます。

```bash
sudo BRIDGE_REPO_URL=https://github.com/Elic0de/raspike-bridge-ps5.git \
  BRIDGE_REF=main \
  WEB_RELEASE_REPO=Elic0de/raspike-web-control-v3 \
  WEB_RELEASE_ASSET=dist.zip \
  ./installer/install.sh
```

install 後、bridge/web だけが enable されます。

```bash
sudo systemctl start raspike-bridge.service raspike-web.service
```

## Update

```bash
sudo /opt/raspike/scripts/update.sh
```

または systemd service として実行します。

```bash
sudo systemctl start raspike-update.service
```

`BRIDGE_REF`、`WEB_RELEASE_REPO`、`WEB_RELEASE_ASSET` は `/opt/raspike/config/raspike.env` で変更できます。web は差し替え前に `/opt/raspike/apps/web.backup.YYYYmmddHHMMSS` へバックアップされます。

web release の `dist.zip` には、Vite の静的成果物 `dist/` に加えて `server.mjs` を同梱してください。platform は展開後に `/opt/raspike/apps/web/server.mjs` を systemd で起動します。
`raspike-web.service` は `/opt/raspike/scripts/run-web.sh` 経由で起動し、`node`、`nodejs`、または `RASPIKE_NODE_BIN` を探します。Node.js が無い環境では install 時に `apt-get install -y nodejs` を試します。

## Uninstall

service、dispatcher、udev rule だけを削除します。

```bash
sudo ./installer/uninstall.sh
```

`/opt/raspike` も削除する場合は確認付きで実行します。

```bash
sudo ./installer/uninstall.sh --remove-data
```

## 設定ファイル

- `/opt/raspike/config/raspike.env`: systemd service 共通設定、bridge/web/update の既定値。
- `/opt/raspike/config/wifi-auth.env`: 学校 Wi-Fi 認証情報。`600` 権限を想定し、パスワードは script に直書きしません。
- `/opt/raspike/backups/udev/99-serial.rules.original`: install 前に存在した `/etc/udev/rules.d/99-serial.rules` のバックアップ。
- `packages/config/wifi-auth.example.env`: `wifi-auth.env` のテンプレート。

## systemd Services

- `raspike-bridge.service`: bridge と PS5 controller を起動します。`/dev/raspike-real` を一定時間待ち、見つからない場合は正常終了して再起動ループを避けます。
- bridge は `User=raspike` のまま `/dev/USB_SPIKE` を PTY symlink として作るため、`CAP_DAC_OVERRIDE` を付与しています。`/dev/USB_SPIKE` は udev では作りません。
- `raspike-web.service`: ローカル web-ui を起動します。
- `raspike-network-auth.service`: 学校 Wi-Fi 認証用の oneshot service です。dispatcher から必要時のみ起動します。
- `raspike-update.service`: bridge/web 更新用の oneshot service です。手動実行、または認証成功後の任意起動に使います。

## Network Auth

NetworkManager dispatcher は `wlan0` が `up` になった時だけ動きます。`iwgetid -r wlan0` で取得した SSID が `SCHOOL_WIFI_SSID` と一致する場合のみ `raspike-network-auth.service` を起動します。

認証情報を設定します。

```bash
sudo cp packages/config/wifi-auth.example.env /opt/raspike/config/wifi-auth.env
sudo chown raspike:raspike /opt/raspike/config/wifi-auth.env
sudo chmod 600 /opt/raspike/config/wifi-auth.env
sudo editor /opt/raspike/config/wifi-auth.env
```

## Troubleshooting

service 状態確認:

```bash
systemctl status raspike-bridge.service
systemctl status raspike-web.service
systemctl status raspike-network-auth.service
systemctl status raspike-update.service
```

journalctl の見方:

```bash
journalctl -u raspike-bridge.service -f
journalctl -u raspike-web.service -f
journalctl -u raspike-network-auth.service -n 100
```

`raspike-web.service` で `/usr/bin/env: 'node': No such file or directory` が出る場合:

```bash
command -v node
command -v nodejs
sudo command -v node || true
sudo command -v nodejs || true
sudo apt-get update
sudo apt-get install -y nodejs
sudo systemctl restart raspike-web.service
```

通常ユーザーの nvm で入れた Node.js は、`sudo` や systemd の PATH から見えないことがあります。systemd で安定運用する場合は apt の `nodejs` を入れるか、`/opt/raspike/config/raspike.env` に `RASPIKE_NODE_BIN=/path/to/node` を設定してください。

SSID 確認:

```bash
iwgetid -r wlan0
nmcli device status
```

udev デバイス確認:

```bash
ls -l /dev/raspike-real
ls -l /dev/USB_SPIKE
udevadm info -a -n /dev/ttyACM0
```

`/dev/USB_SPIKE` が実機 ttyACM ではなく bridge の PTY を指していることを確認してください。実機 SPIKE Hub は `/dev/raspike-real` として扱います。

network-auth 単体実行:

```bash
sudo -u raspike /opt/raspike/scripts/school-auth.sh
sudo systemctl start raspike-network-auth.service
```

udev rule を変更した場合:

```bash
sudo udevadm control --reload-rules
sudo udevadm trigger
```
