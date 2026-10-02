# SaDesa POS Print Bridge

Print Bridge adalah service lokal di komputer kasir. PWA mengirim byte ESC/POS ke `127.0.0.1:18181`, lalu bridge meneruskannya ke printer thermal tanpa dialog browser. Ini adalah jalur utama untuk mode **non-browser**: PWA tetap memakai engine browser, tetapi pekerjaan cetak diproses oleh service lokal dan driver OS.

Jika Print Bridge atau printer native tidak tersedia, POS tidak menghilangkan struk. Receipt disimpan di print outbox IndexedDB/local storage dan PWA membuka fallback print sheet untuk `window.print()`. Pada mode fallback, kasir memilih printer thermal dari dialog sistem/browser; status ini tetap terpisah dari status sinkronisasi transaksi.

## Rekomendasi pilihan perangkat

| Jalur | Rekomendasi | Catatan |
|---|---|---|
| **LAN/WiFi + bridge** | **Paling disarankan** | Printer dan komputer kasir berada di jaringan yang sama; tidak bergantung pada Web Serial browser. |
| USB + bridge | Disarankan untuk printer USB | Bridge memakai `serialport`; lebih stabil daripada mencoba USB printer class langsung dari browser. |
| USB langsung dari browser | Hanya untuk perangkat yang benar-benar menyediakan USB-serial/CDC | Banyak printer thermal USB bukan serial sehingga tidak muncul di Web Serial. |
| Bluetooth langsung dari browser | Tidak disarankan untuk operasional utama | Web Bluetooth tidak mendukung Bluetooth Classic/SPP dan profil BLE tiap printer berbeda. |

## Setup Windows satu kali

1. Pastikan Node.js 22 atau lebih baru terpasang.
2. Buka PowerShell di root repository.
3. Jalankan:

```powershell
powershell -ExecutionPolicy Bypass -File .\print-bridge\scripts\install-windows.ps1
```

Script tersebut akan memasang dependency, membuat `print-bridge/data/config.json` dari template, dan memasang auto-start saat Windows login.

4. Edit `print-bridge/data/config.json`.
5. Jalankan bridge pertama kali dengan `npm --prefix print-bridge start`, lalu lakukan **Test Print** dari POS.

## Setup macOS satu kali

1. Pastikan Node.js 22 atau lebih baru terpasang.
2. Buka Terminal di root repository.
3. Jalankan:

```bash
chmod +x print-bridge/scripts/install-macos.sh
./print-bridge/scripts/install-macos.sh
```

Installer memasang dependency, membuat konfigurasi awal, dan mendaftarkan LaunchAgent `id.sadesa.pos-print-bridge` agar bridge otomatis berjalan saat user login. Konfigurasi berada di `print-bridge/data/config.json`; log berada di `print-bridge/data/logs/`.

Untuk menghentikan service sementara:

```bash
launchctl bootout "gui/$(id -u)" "$HOME/Library/LaunchAgents/id.sadesa.pos-print-bridge.plist"
```

## Setup Linux satu kali

1. Pastikan Node.js 22 atau lebih baru terpasang.
2. Buka Terminal di root repository.
3. Jalankan:

```bash
chmod +x print-bridge/scripts/install-linux.sh
./print-bridge/scripts/install-linux.sh
```

Installer memasang dependency, membuat konfigurasi awal, dan mendaftarkan systemd user service `sadesa-pos-print-bridge.service`. Status dan log dapat dilihat dengan:

```bash
systemctl --user status sadesa-pos-print-bridge.service
journalctl --user -u sadesa-pos-print-bridge.service -f
```

Jika distro tidak menjalankan systemd user session, installer tetap membuat unit file dan menampilkan perintah aktivasi manual.

Untuk printer LAN, konfigurasi minimal:

```json
{
  "printers": [{
    "id": "kasir-lan",
    "name": "Printer Thermal LAN",
    "type": "tcp",
    "host": "192.168.1.100",
    "port": 9100,
    "isDefault": true
  }]
}
```

Untuk printer USB yang dikenali sebagai serial:

```json
{
  "printers": [{
    "id": "kasir-usb",
    "name": "Printer Thermal USB",
    "type": "serial",
    "path": "COM3",
    "baudRate": 9600,
    "isDefault": true
  }]
}
```

> `COM3` hanya contoh. Lihat nama port sebenarnya di Device Manager. Tidak semua printer USB dapat dipakai sebagai serial; untuk printer seperti itu gunakan LAN atau driver/print server OS.

## Pengujian dari POS

1. Pastikan browser membuka aplikasi SaDesa melalui HTTPS.
2. Buka **POS → Pengaturan → Printer**.
3. Pilih **WiFi/LAN melalui Print Bridge** atau **USB melalui Print Bridge** untuk cetak tanpa dialog browser. USB/Bluetooth direct hanya digunakan jika browser dan perangkat mendukung Web Serial/Web Bluetooth.
4. Simpan pengaturan dan tekan **Test Print**.
5. Jika gagal, cek `http://127.0.0.1:18181/health`. Respons yang benar memiliki `ok: true`.

Untuk LAN, IP printer dan port pada halaman POS harus sama dengan entry `type: "tcp"` pada bridge. Port raw printing yang umum adalah `9100`.

## Operasional dan keamanan

Bridge hanya bind ke `127.0.0.1` secara default dan tidak boleh diekspos ke internet. CORS dibatasi ke `https://www.sadesa.id`, `https://sadesa.id`, dan `http://localhost:5173` secara default. Untuk staging atau domain lain, set daftar origin secara eksplisit sebelum menjalankan service, misalnya:

```bash
ALLOWED_ORIGIN="https://staging.example.id,http://localhost:5173" npm --prefix print-bridge start
```

Jangan memakai `ALLOWED_ORIGIN=*` pada komputer kasir produksi karena website lain dapat mengirim perintah cetak ke localhost.

Job disimpan lokal dengan `jobId` sebagai idempotency key. Job `queued` atau `printing` dipulihkan saat bridge restart. Job `failed` dapat dikirim ulang dari tombol retry; karena bridge mungkin kehilangan acknowledgement setelah printer sudah menerima data, retry manual dapat menghasilkan cetak ganda dan harus dilakukan setelah kasir memeriksa printer. PWA juga menyimpan antrean receipt ketika printer belum tersedia.

Endpoint yang tersedia:

- `GET /health` — status service.
- `GET /printers` — daftar printer dari konfigurasi lokal.
- `POST /jobs` — menerima byte ESC/POS dalam Base64.
- `GET /jobs/:jobId` — status job cetak.

Status bridge atau job **bukan bukti tinta/kertas benar-benar keluar** pada semua model printer. Test print fisik tetap wajib dilakukan saat onboarding.

## Batasan yang masih perlu diuji secara fisik

Sebelum pilot, uji minimal satu printer nyata untuk setiap kombinasi model, OS, dan koneksi. Fokus uji: struk 58/80 mm, karakter Indonesia, QR, pemutusan listrik saat job, retry, dan status printer kehabisan kertas. Untuk deployment multi-kasir, setiap komputer kasir perlu menjalankan bridge lokalnya sendiri atau memakai print server terdedikasi.
