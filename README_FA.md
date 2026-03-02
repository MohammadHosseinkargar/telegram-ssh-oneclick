# telegram-ssh-oneclick

`telegram-ssh-oneclick` یک ربات مدیریت SSH از طریق تلگرام است که با نصب‌کننده یک‌مرحله‌ای برای Debian و Ubuntu ارائه می‌شود.

## معرفی پروژه

این پروژه یک بات تلگرام اجرا می‌کند که می‌تواند به سرورهای ثبت‌شده متصل شود و دستورهای SSH را اجرا کند. نصب‌کننده، وابستگی‌ها، فایل تنظیمات، کاربر سرویس و سرویس اجرایی را آماده می‌کند.

## نصب سریع

```bash
curl -fsSL https://raw.githubusercontent.com/MohammadHosseinkargar/telegram-ssh-oneclick/main/scripts/quick-install.sh | sudo bash
```

این دستور مخزن را در `/opt/telegram-ssh-oneclick` همگام می‌کند، `install.sh` را اجرا می‌کند، تنظیمات را می‌گیرد و سرویس را بالا می‌آورد.

## قابلیت‌ها

- نصب تعاملی و بازپیکربندی امن
- پشتیبانی از اجرای غیرتعاملی با متغیر محیطی
- امکان اجرا با `systemd` یا `pm2`
- نگهداری لیست سرورها در `servers.json`
- ساخت فایل `.env` با دسترسی محدود

## پیکربندی (`.env`)

فایل تنظیمات در مسیر `/opt/telegram-ssh-oneclick/.env` ایجاد می‌شود.

متغیرهای پشتیبانی‌شده:

- `BOT_TOKEN` (الزامی)
- `CHAT_ID` (الزامی)
- `OWNER_IDS` (الزامی، لیست عددی با کاما)
- `PATH_PRIVATEKEY` (اختیاری)
- `SERVERS_FILE` (اختیاری، پیش‌فرض `/opt/telegram-ssh-oneclick/servers.json`)
- `PROCESS_MANAGER` (`systemd` یا `pm2`)
- `RECONFIGURE` (`true` یا `1`)

نمونه اجرای غیرتعاملی:

```bash
sudo BOT_TOKEN='123456:ABCDEF...' \
CHAT_ID='123456789' \
OWNER_IDS='123456789,987654321' \
PATH_PRIVATEKEY='/home/ubuntu/.ssh/id_rsa' \
SERVERS_FILE='/opt/telegram-ssh-oneclick/servers.json' \
PROCESS_MANAGER='systemd' \
RECONFIGURE='true' \
bash /opt/telegram-ssh-oneclick/install.sh
```

## استفاده از systemd

نام سرویس: `telegram-ssh-oneclick`

```bash
sudo systemctl status telegram-ssh-oneclick
sudo systemctl restart telegram-ssh-oneclick
sudo systemctl enable telegram-ssh-oneclick
```

## لاگ و عیب‌یابی

لاگ systemd:

```bash
journalctl -u telegram-ssh-oneclick -f
```

لاگ در حالت PM2:

```bash
sudo su -s /bin/bash -c 'pm2 ls' telegram-ssh-oneclick
sudo su -s /bin/bash -c 'pm2 logs telegram-ssh-oneclick' telegram-ssh-oneclick
```

چک‌لیست سریع:

- مقادیر `.env` را بررسی کنید.
- دسترسی خواندن کلید خصوصی برای کاربر سرویس را بررسی کنید.
- صحت ساختار `servers.json` را بررسی کنید.
- در صورت نیاز نصب‌کننده را دوباره اجرا کنید:

```bash
sudo bash /opt/telegram-ssh-oneclick/install.sh
```
