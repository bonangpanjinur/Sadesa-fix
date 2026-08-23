# Security API Smoke Test

Skrip `scripts/security-api-smoke.sh` menguji Supabase Edge Functions secara aman terhadap project staging. Skrip tidak memerlukan service-role key dan tidak pernah mencetak nilai token.

## Prerequisites

Set URL project staging, publishable/anon key, dan origin frontend yang memang terdaftar pada `ALLOWED_ORIGINS` function:

```sh
export SUPABASE_TEST_URL="https://your-staging-project.supabase.co"
export SUPABASE_TEST_ANON_KEY="your-staging-anon-key"
export SECURITY_TEST_ALLOWED_ORIGIN="https://staging.example.com"
```

Untuk menguji jalur authenticated dengan token test berumur pendek:

```sh
export SECURITY_TEST_ACCESS_TOKEN="<staging-user-access-token>"
```

Jangan gunakan service-role key, token production, atau credential payment provider. Target yang tidak mengandung `staging`, `stage`, `test`, `localhost`, atau `127.0.0.1` ditolak secara default.

## Run

```sh
pnpm test:security-api
```

Skrip menjalankan preflight CORS dari allowed origin dan invalid origin, request unauthenticated, request dengan token invalid, method guard, dan payload validation. Jika `SECURITY_TEST_ACCESS_TOKEN` disediakan, skrip juga menguji request authenticated dengan payload kosong yang aman.

Rate limiting diuji dengan request `POST {}` yang tidak terautentikasi ke `assign-courier`. Secara default tidak adanya HTTP 429 dicatat sebagai warning karena rate limiting dapat berada pada gateway/provider. Untuk menjadikan rate limiting sebagai hard failure:

```sh
export SECURITY_TEST_REQUIRE_RATE_LIMIT=1
export SECURITY_TEST_REQUESTS=50
pnpm test:security-api
```

Target rate-limit dapat diubah dengan `SECURITY_TEST_RATE_LIMIT_FUNCTION`. Function list dapat diubah dengan `SECURITY_TEST_FUNCTIONS`, misalnya:

```sh
export SECURITY_TEST_FUNCTIONS="assign-courier send-push-notification"
```

## Expected behavior

Allowed preflight harus mengembalikan origin yang sama dan `Vary: Origin`. Disallowed origin tidak boleh direfleksikan. Request tanpa token dan token invalid harus mengembalikan 401 atau 403. Endpoint yang tidak menerima method tertentu harus mengembalikan 405. Rate limiting yang aktif harus pada akhirnya mengembalikan 429.

## Important limitations

Skrip ini adalah smoke test HTTP, bukan pengganti integration test RLS. Ia tidak membuktikan isolasi tenant, authorization database, webhook signature provider, atau ketepatan migration. Jalankan terhadap project staging terpisah dan tambahkan skenario RLS/concurrency melalui `scripts/run-rls-staging.sh`.
