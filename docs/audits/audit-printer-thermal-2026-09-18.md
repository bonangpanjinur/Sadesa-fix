# Audit Kesiapan Printer Thermal POS — 18 September 2026

## Kesimpulan

Aplikasi POS berbasis PWA tetap dapat mencetak ke printer thermal, tetapi browser bukan tempat yang ideal untuk mengelola seluruh variasi driver USB, Bluetooth Classic, dan jaringan printer. Jalur operasional yang paling mudah dan stabil untuk SaDesa adalah **PWA → Print Bridge lokal → printer thermal**.

Repository sudah memiliki kontrak receipt, antrean lokal, idempotency berdasarkan `jobId`, generator ESC/POS, serta bridge lokal yang mendukung TCP raw printing dan serial. Dengan demikian, masalah utama bukan pada format struk, melainkan pada setup service lokal dan variasi protokol perangkat.

## Temuan teknis

| Area | Status | Dampak |
|---|---|---|
| Generator ESC/POS | Siap untuk receipt teks, total, QR, dan cut | Perlu uji fisik per model printer |
| Print Bridge TCP | Tersedia pada `127.0.0.1:18181` | Jalur terbaik untuk printer LAN/WiFi |
| Print Bridge serial | Tersedia melalui optional dependency `serialport` | Cocok untuk USB yang tampil sebagai COM/serial |
| Web Serial langsung | Tersedia tetapi terbatas | Banyak printer USB thermal memakai USB printer class, bukan serial |
| Web Bluetooth langsung | Tersedia untuk profil BLE tertentu | Tidak cocok sebagai default karena Bluetooth Classic/SPP tidak didukung |
| Browser print fallback | Tersedia | Bergantung pada dialog OS dan layout driver, bukan raw ESC/POS |
| Retry/outbox | Tersedia | Job disimpan lokal dan memakai `jobId` idempotent |
| Setup Windows | Sebelumnya manual | Installer kini memasang dependency, membuat config, dan auto-start |

## Jalur yang direkomendasikan

Untuk merchant, gunakan printer thermal **LAN/WiFi dengan raw TCP port 9100** bila model tersedia. Komputer kasir menjalankan Print Bridge lokal. POS hanya perlu dikonfigurasi ke mode WiFi/LAN dan IP printer; browser tidak perlu berbicara langsung ke printer.

Jika printer hanya USB, gunakan Print Bridge dengan konfigurasi `type: "serial"` setelah memastikan perangkat muncul sebagai COM port. Jika perangkat tidak muncul sebagai COM port, jangan memaksa Web Serial; gunakan driver OS, print server, atau printer LAN.

## Alur troubleshooting

1. Buka `http://127.0.0.1:18181/health` pada komputer kasir.
2. Pastikan respons mengandung `ok: true`.
3. Periksa `http://127.0.0.1:18181/printers` dan pastikan ada satu printer `isDefault: true`.
4. Cocokkan IP dan port di POS dengan `config.json` bridge.
5. Jalankan **Test Print** dari menu POS.
6. Jika job `failed`, periksa pesan error pada status job dan log terminal bridge.
7. Jika bridge sehat tetapi printer tidak merespons, masalah berada pada IP/port, driver serial, kabel, atau mode ESC/POS printer.

## Kriteria penerimaan sebelum pilot

Uji dengan printer fisik yang akan dipakai merchant: cetak receipt 58 mm dan 80 mm, nama produk panjang, karakter Bahasa Indonesia, QR, dua salinan, retry setelah bridge dimatikan, dan pemulihan setelah listrik/USB dicabut. Verifikasi bahwa transaksi tidak dibuat ulang ketika cetak gagal dan bahwa antrean dapat dicetak ulang setelah koneksi kembali.
