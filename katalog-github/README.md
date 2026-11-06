# Katalog Digital

Katalog interaktif seperti buku sungguhan. Seluruh website adalah **satu file: `index.html`**.

- Beranda pengunjung: `https://USERNAME.github.io/NAMA-REPO/`
- Dashboard admin (tombol **Masuk admin** ada di paling bawah beranda): `.../?admin`
- Link baca katalog: `.../?c=alamat-katalog`

## Bagian 1 — Unggah ke GitHub Pages

1. Buat repository baru di GitHub (Public), misalnya `katalog`.
2. Klik **Add file → Upload files**, lalu seret semua isi folder ini (`index.html`, `.nojekyll`, `README.md`, folder `supabase`) dan klik **Commit changes**.
3. Buka **Settings → Pages**. Pada *Build and deployment* pilih **Deploy from a branch**, branch **main**, folder **/ (root)**, lalu **Save**.
4. Tunggu 1–2 menit. Alamat website muncul di halaman yang sama.

> Sampai di sini website sudah bisa dibuka, tetapi masih **mode lokal**: data admin hanya tersimpan di browser Anda sendiri, pengunjung tidak melihat katalognya. Lanjutkan Bagian 2.

## Bagian 2 — Hubungkan database agar katalog tampil untuk semua orang (gratis)

1. Daftar di <https://supabase.com> → **New project**.
2. Buka **SQL Editor → New query**, tempel isi `supabase/schema.sql`, klik **Run**.
3. Buka **Authentication → Users → Add user**, buat email + password admin.
4. Di SQL Editor jalankan (ganti emailnya):
   ```sql
   insert into public.admins (user_id)
   select id from auth.users where email = 'EMAIL-ANDA@contoh.com';
   ```
5. Buka **Project Settings → API**, salin **Project URL** dan **anon public key**.
6. Buka `index.html` di GitHub (ikon pensil), cari bagian `KONFIGURASI` di dekat atas file, lalu isi:
   ```js
   SUPABASE_URL: "https://xxxx.supabase.co",
   SUPABASE_ANON_KEY: "eyJ...",
   ```
   Sekalian ubah `SITE_NAME`, `SITE_TAGLINE`, dan `CONTACT_LINE`. Klik **Commit changes**.
7. Buka `.../?admin`, masuk dengan akun tadi, unggah halaman, lalu **Terbitkan**.

Kunci *anon public* memang aman ditaruh di website publik. Yang menjaga data adalah aturan keamanan (RLS) di `schema.sql`: hanya akun admin yang bisa mengubah isi katalog.

## Catatan
- Jangan pernah menaruh *service_role key* di file ini.
- Sampul belakang: jika tidak diunggah, buku membuat sampul belakang otomatis.
- Mengubah file memerlukan commit baru; GitHub Pages memperbarui otomatis dalam beberapa menit.
