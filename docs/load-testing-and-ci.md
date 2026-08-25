# Load Testing and CI Security Gate

## Load/stress test staging

`scripts/load-test-staging.sh` menjalankan burst request paralel ke endpoint Edge Function kritikal: Xendit webhook, notification worker, subscription worker, dan admin-create-user. Test default memakai 60 request per endpoint, concurrency 10, dan timeout 10 detik. Hasilnya menampilkan distribusi HTTP status, average/max latency, transport failures, dan elapsed time.

Jalankan hanya terhadap staging:

```bash
LOAD_TEST_BASE_URL="https://<staging-project>.supabase.co" \
LOAD_TEST_CONFIRM_STAGING=YES_I_CONFIRM_STAGING \
LOAD_TEST_REQUESTS=60 \
LOAD_TEST_CONCURRENCY=10 \
./scripts/load-test-staging.sh
```

Test ini sengaja mengirim payload kosong tanpa credential. Tujuannya memeriksa throughput, timeout, CORS/method/auth rejection, dan transport behavior; test ini tidak membuktikan transaksi payment sukses. Untuk load test authenticated, gunakan fixture staging khusus dan rate yang disetujui provider. Jangan menjalankan test ke production atau provider live.

Agar URL Railway staging yang tidak mengandung kata `staging` dapat diuji secara eksplisit, operator harus menyetel `ALLOW_EXPLICIT_STAGING_HOST=1` setelah melakukan verifikasi manual bahwa target benar-benar staging.

## GitHub Actions

Workflow `.github/workflows/production-readiness.yml` berjalan pada pull request ke `main`, push ke `main`, dan manual dispatch. Dua job wajib berjalan pada setiap PR:

| Job | Checks |
|---|---|
| `static-security-and-migrations` | Migration filename/destructive SQL preflight, RLS static audit, dependency audit high/critical, tracked secret scan, shell syntax check |
| `application-quality` | TypeScript, ESLint, unit test, production build |
| `staging-integration` | Manual only; staging environment, Supabase CLI, migration apply, P0 integration suite, API security smoke test |

Job staging hanya aktif jika repository variable `RUN_STAGING_INTEGRATION=true` dan dijalankan pada GitHub Environment `staging`. Required secrets:

```text
SUPABASE_STAGING_PROJECT_REF
SUPABASE_ACCESS_TOKEN
SUPABASE_STAGING_URL
SUPABASE_STAGING_ANON_KEY
SUPABASE_STAGING_ALLOWED_ORIGIN
```

Secret tidak boleh diletakkan pada repository variables biasa atau dikirim melalui pull request dari fork. Aktifkan required reviewers pada environment `staging` dan batasi deploy production pada protected branch/tag.

## Branch protection recommendation

Set `main` sebagai protected branch. Wajibkan pull request, minimal satu reviewer, status checks `Security and migration checks` dan `Application quality`, conversation resolution, serta larangan force-push/delete branch. Staging integration dapat dijadikan required sebelum release tag atau sebelum workflow production, tetapi tidak boleh otomatis memakai production secret pada pull request.

## Interpreting results

HTTP 401/403 pada unauthenticated load test dapat menjadi hasil yang diharapkan untuk endpoint protected. Investigasi dilakukan jika endpoint mengembalikan 2xx untuk payload kosong tanpa auth, transport failure meningkat, latency melewati SLO yang disepakati, 5xx meningkat, atau worker queue menunjukkan duplicate/dead-letter abnormal. Hasil load test wajib disimpan bersama commit SHA, target environment, timestamp, request count, concurrency, dan provider test fixture.
