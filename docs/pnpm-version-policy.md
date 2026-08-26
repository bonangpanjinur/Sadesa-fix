# Panduan Penggunaan Versi pnpm

## Tujuan

Repository ini menggunakan **satu versi pnpm yang konsisten** untuk development lokal, CI, dan deployment. Konsistensi ini mencegah konflik lockfile, perbedaan dependency resolution, dan kegagalan `pnpm/action-setup` di GitHub Actions.

## Versi resmi repository

Versi pnpm yang wajib digunakan saat ini adalah:

```text
pnpm 9.15.9
```

Sumber utama deklarasi versi berada di `package.json`:

```json
{
  "packageManager": "pnpm@9.15.9"
}
```

Semua workflow GitHub Actions yang memakai `pnpm/action-setup` juga harus menggunakan `version: 9.15.9`.

## Aturan wajib

Anggota tim wajib menggunakan pnpm, bukan npm atau yarn, untuk memasang dependency dan menjalankan script repository. Jangan mengubah `packageManager` atau `pnpm-lock.yaml` ke versi lain tanpa persetujuan maintainer.

Jika menambahkan setup pnpm ke workflow baru, gunakan konfigurasi berikut:

```yaml
- name: Setup pnpm
  uses: pnpm/action-setup@v4
  with:
    version: 9.15.9
```

Jangan menulis versi yang berbeda, seperti `version: 10`, ketika `package.json` masih menetapkan `pnpm@9.15.9`. Konflik tersebut akan membuat GitHub Actions gagal pada tahap setup pnpm.

## Setup lokal

Aktifkan dan gunakan versi yang disetujui sebelum memasang dependency:

```bash
corepack enable
corepack prepare pnpm@9.15.9 --activate
pnpm --version
pnpm install --frozen-lockfile
```

Perintah `pnpm --version` harus menghasilkan `9.15.9`.

## Menjalankan validasi

Sebelum membuka pull request, jalankan validator versi:

```bash
pnpm validate:package-manager
```

Validator memeriksa `package.json`, seluruh file workflow di `.github/workflows`, dan metadata `pnpm-lock.yaml`. Pull request akan gagal jika terdapat setup pnpm tanpa versi, versi yang berbeda, atau format `packageManager` yang tidak exact.

Selain itu, jalankan pemeriksaan standar:

```bash
pnpm install --frozen-lockfile
pnpm lint
pnpm test
pnpm build
```

Gunakan `--frozen-lockfile` pada CI agar dependency tidak mengubah lockfile secara otomatis.

## Perubahan dependency

Setelah mengubah dependency, gunakan pnpm 9.15.9 untuk memperbarui lockfile. Periksa perubahan sebelum commit:

```bash
pnpm install
pnpm validate:package-manager
git diff -- pnpm-lock.yaml package.json
```

Commit `package.json` dan `pnpm-lock.yaml` secara bersamaan apabila keduanya berubah. Jangan menghapus atau mengganti lockfile dengan hasil instalasi dari npm, yarn, atau versi pnpm lain.

## Checklist pull request

Sebelum meminta review, pastikan hal-hal berikut terpenuhi:

| Pemeriksaan | Hasil yang diharapkan |
|---|---|
| `pnpm --version` | `9.15.9` |
| `package.json` | `"packageManager": "pnpm@9.15.9"` |
| Workflow GitHub Actions | Semua `pnpm/action-setup` memakai `9.15.9` |
| Lockfile | Tidak dibuat ulang oleh pnpm versi lain |
| Validator | `pnpm validate:package-manager` berhasil |
| Install CI | Menggunakan `pnpm install --frozen-lockfile` |

> Jika memang diperlukan upgrade pnpm, lakukan sebagai perubahan terencana: perbarui `packageManager`, regenerasi lockfile menggunakan versi baru, sesuaikan seluruh workflow, jalankan lint/test/build, lalu minta review maintainer sebelum merge.
