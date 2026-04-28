# Named Cloudflare Tunnel со своим доменом

Quick tunnel (`cloudflared tunnel --url http://localhost:5678`) хорош для
разработки, но URL меняется каждый рестарт. Для продакшена нужен **named tunnel**
со стабильным доменом.

## Предусловия

- У тебя есть домен, делегированный на Cloudflare (NS Cloudflare).
- Установлен `cloudflared.exe` (см. `README.md`).

## Шаги

### 1. Логин

```powershell
.\cloudflared.exe tunnel login
```

Откроется браузер — авторизуй домен. После этого появится файл
`%USERPROFILE%\.cloudflared\cert.pem`.

### 2. Создаём туннель

```powershell
.\cloudflared.exe tunnel create automind
```

Запиши `Tunnel ID` (UUID) — он будет нужен. Cloudflare также создаст файл
`%USERPROFILE%\.cloudflared\<UUID>.json` с приватным ключом.

### 3. Конфиг

Создай файл `%USERPROFILE%\.cloudflared\config.yml`:

```yaml
tunnel: automind
credentials-file: C:\Users\<TWOJ_USER>\.cloudflared\<UUID>.json

ingress:
  - hostname: automind.example.com
    service: http://localhost:5678
  - service: http_status:404
```

### 4. DNS

```powershell
.\cloudflared.exe tunnel route dns automind automind.example.com
```

### 5. Запуск

```powershell
.\cloudflared.exe tunnel run automind
```

В `.env` пропиши:

```env
WEBHOOK_URL=https://automind.example.com
```

И перезапусти n8n:

```powershell
docker compose up -d --force-recreate n8n
```

### 6. (Опционально) Запуск как Windows-сервис

```powershell
.\cloudflared.exe service install
```

Теперь туннель поднимается автоматически при старте Windows.

## Альтернатива: cloudflared в docker

В `docker-compose.yml` есть закомментированный сервис `cloudflared`. Чтобы
использовать его:

1. В Cloudflare Zero Trust dashboard создай туннель и скопируй **token**.
2. В `.env` добавь `CF_TUNNEL_TOKEN=...`.
3. Раскомментируй блок `cloudflared:` в `docker-compose.yml`.
4. `docker compose up -d cloudflared`.
