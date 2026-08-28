# SaDesa POS Print Bridge

Print Bridge adalah service lokal yang menerima job ESC/POS dari PWA melalui loopback dan mengirimkannya ke printer thermal tanpa popup atau dialog browser.

## Menjalankan

```bash
cd print-bridge
cp data/config.example.json data/config.json
# Edit data/config.json sesuai printer
npm install
npm start
```

Service berjalan di `http://127.0.0.1:18181`.

## Konfigurasi printer

Printer LAN memakai `type: "tcp"`, `host`, dan `port` raw printing yang umumnya `9100`. Printer USB tahap awal memakai `type: "serial"`, `path` seperti `COM3` di Windows atau `/dev/ttyUSB0` di Linux, serta `baudRate`.

## Endpoint

`GET /health` mengembalikan status service. `GET /printers` mengembalikan daftar printer dari `data/config.json`. `POST /jobs` menerima envelope job dengan `jobId`, `saleId`, `saleNumber`, `outletId`, `createdAt`, `copies`, `printerId`, dan `data` berupa byte ESC/POS dalam Base64. `GET /jobs/:jobId` membaca status job.

Bridge menyimpan job secara lokal dan menggunakan `jobId` sebagai idempotency key. Submit ulang job dengan ID yang sama tidak mencetak ulang secara otomatis.

## Catatan keamanan

Bridge hanya bind ke `127.0.0.1` secara default. Jangan expose port ini ke internet atau jaringan publik. Pada fase hardening, tambahkan token pairing, allowlist origin, installer signed, dan service auto-start.
