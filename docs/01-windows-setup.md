# Подробная установка под Windows

> Эта инструкция дополняет `README.md` и описывает типичные проблемы,
> с которыми сталкиваются Windows-юзеры при поднятии Docker + n8n.

## 1. Включаем виртуализацию

Docker Desktop требует виртуализации:

- В BIOS/UEFI: включи `Intel VT-x` / `AMD-V` (обычно уже включено на современных машинах).
- В Windows проверь, что включены компоненты:

  ```powershell
  Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -All
  Enable-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform
  Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux
  ```

  После включения — перезагрузка.

## 2. Ставим WSL 2

```powershell
wsl --install
wsl --set-default-version 2
```

## 3. Docker Desktop

После установки в **Settings → Resources → WSL integration** включи интеграцию
с твоим дистрибутивом. В **Settings → General** убедись, что включено
«Use the WSL 2 based engine».

## 4. Проверка

```powershell
docker --version
docker compose version
docker run --rm hello-world
```

## 5. Частые ошибки

### `port is already allocated`

У тебя что-то уже слушает 5432 / 5678. Меняй порты в `.env`:

```env
POSTGRES_PORT=5433
N8N_PORT=15678
```

### `n8n` не стартует, в логах `EACCES`

На Windows + WSL иногда права на тома слетают. Решение:

```powershell
docker compose down
docker volume rm automind_n8n_data
docker compose up -d
```

(Удалит данные n8n — для свежего стенда не страшно. Если уже есть workflow —
сначала экспортируй их в `backups/`.)

### Telegram не приходит в n8n

1. Проверь, что workflow **Active** (тумблер в правом верхнем углу).
2. Проверь, что `WEBHOOK_URL` соответствует туннелю.
3. Проверь зарегистрированный вебхук:

   ```powershell
   $Token = "..."
   Invoke-RestMethod "https://api.telegram.org/bot$Token/getWebhookInfo"
   ```

   Если `url` пустой или указывает на старый домен — пересохрани workflow или
   принудительно установи:

   ```powershell
   $Url = "https://your-tunnel.trycloudflare.com/webhook/automind-booking-bot"
   Invoke-RestMethod -Method Post "https://api.telegram.org/bot$Token/setWebhook?url=$Url"
   ```
