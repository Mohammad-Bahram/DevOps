# Kafka Secure Cluster – DevOps Deployment

# استقرار کلاستر امن Kafka

---

## 1. Overview | معرفی پروژه

**English**

This project provides a secure Kafka cluster deployment using Docker Compose and Kafka KRaft mode. It consists of two Kafka brokers and uses TLS encryption and SASL authentication to secure communication.

**فارسی**

این پروژه امکان استقرار یک کلاستر امن Kafka را با استفاده از Docker Compose و حالت KRaft فراهم می‌کند. کلاستر شامل دو Broker است و برای ایمن‌سازی ارتباطات از رمزنگاری TLS و احراز هویت SASL استفاده می‌کند.

---

## 2. Architecture | معماری

**English**

The cluster consists of two Kafka brokers:

- `kafka-1`
- `kafka-2`

Kafka KRaft is used for metadata management without requiring an external ZooKeeper service.

**فارسی**

این کلاستر از دو Broker تشکیل شده است:

- `kafka-1`
- `kafka-2`

برای مدیریت متادیتا از حالت KRaft استفاده می‌شود؛ بنابراین نیازی به سرویس خارجی ZooKeeper نیست.

---

## 3. Prerequisites | پیش‌نیازها

**English**

Make sure the following tools are installed:

- Docker
- Docker Compose V2
- OpenSSL
- Java Keytool

**فارسی**

قبل از راه‌اندازی پروژه، از نصب ابزارهای زیر اطمینان حاصل کنید:

- Docker
- Docker Compose نسخه ۲
- OpenSSL
- Java Keytool

Check the installed versions:

```bash
docker --version
docker compose version
openssl version
keytool -help
```

---

## 4. Configuration | تنظیمات

**English**

Create the environment configuration file from the provided example:

```bash
cp .env.example .env
```

Configure the required environment variables in `.env`.

**فارسی**

ابتدا با استفاده از فایل نمونه، فایل تنظیمات محیطی را ایجاد کنید:

```bash
cp .env.example .env
```

سپس متغیرهای محیطی موردنیاز را در فایل `.env` مقداردهی کنید.

**Important | نکته مهم**

Do not commit `.env` to the Git repository.

فایل `.env` نباید در مخزن Git ثبت شود.

---

## 5. Certificate Generation | تولید Certificateها

**English**

Run the certificate generation script:

```bash
./scripts/generate-certs.sh
```

The script generates or validates the CA, broker certificates, PKCS12 keystores, truststores, password files, and JAAS configurations.

Existing valid artifacts are reused. Incomplete or invalid security artifacts cause the script to stop instead of being automatically overwritten.

**فارسی**

برای تولید Certificateها و تنظیمات امنیتی، اسکریپت زیر را اجرا کنید:

```bash
./scripts/generate-certs.sh
```

این اسکریپت وظیفه تولید یا اعتبارسنجی CA، Certificateهای Brokerها، Keystoreها، Truststoreها، فایل‌های رمز عبور و تنظیمات JAAS را بر عهده دارد.

فایل‌های امنیتی معتبر موجود مجدداً استفاده می‌شوند. در صورت ناقص یا نامعتبر بودن فایل‌ها، اسکریپت متوقف می‌شود و آن‌ها را به‌صورت خودکار بازنویسی نمی‌کند.

---

## 6. Starting the Cluster | راه‌اندازی کلاستر

**English**

After successful certificate generation, start the Kafka services:

**فارسی**

پس از تولید موفق Certificateها، سرویس‌های Kafka را اجرا کنید:

```bash
docker compose up -d
```

Check container status | بررسی وضعیت Containerها:

```bash
docker compose ps
```

View logs | مشاهده گزارش سرویس‌ها:

```bash
docker compose logs -f
```

---

## 7. Security Notes | نکات امنیتی

**English**

- Never commit `.env` files.
- Never commit private keys.
- Keep keystores, truststores, passwords, and JAAS files out of Git.
- Store the CA private key securely.
- Do not regenerate the CA while existing certificates depend on it.

**فارسی**

- فایل‌های `.env` را در Git ثبت نکنید.
- کلیدهای خصوصی را در مخزن قرار ندهید.
- Keystore، Truststore، رمزهای عبور و فایل‌های JAAS را خارج از Git نگه دارید.
- کلید خصوصی CA را در محل امن نگهداری کنید.
- تا زمانی که Certificateهای موجود به CA فعلی وابسته هستند، آن را مجدداً تولید نکنید.
