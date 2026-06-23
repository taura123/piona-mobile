# PIONA Mobile

Aplikasi mobile untuk scanner barcode boarding pass penumpang bandara (petugas gate). Tema korporat biru & putih (InJourney Airports style).

## Persyaratan

- [Flutter SDK](https://docs.flutter.dev/get-started/install) (channel stable)
- Android Studio (opsional, untuk editor dan emulator)
- Perangkat Android terhubung via USB (untuk run di device)

## Menjalankan di Android Studio & Perangkat via USB

1. **Buka project di Android Studio**
   - File → Open → pilih folder `pionaku`
   - Tunggu hingga Gradle sync dan indexing selesai

2. **Install dependency Flutter**
   - Buka terminal di Android Studio (atau CMD/PowerShell di folder project)
   - Jalankan:
     ```bash
     flutter pub get
     ```
   - Jika belum, pastikan Flutter sudah di-PATH dan jalankan `flutter doctor`

3. **Hubungkan perangkat Android via USB**
   - Aktifkan **Developer options** dan **USB debugging** di perangkat
   - Sambungkan kabel USB; di perangkat pilih **Allow USB debugging** jika diminta
   - Cek device terdeteksi: `flutter devices`

4. **Jalankan aplikasi**
   - Di Android Studio: pilih device di toolbar, lalu klik **Run** (▶)
   - Atau dari terminal:
     ```bash
     flutter run
     ```

## Struktur Navigasi & Fitur

- **Login** – ID petugas & password + pemilihan bandara dan checkpoint (scan point).
- **Home** – KPI dan insight yang ter-hydrate dari data scan (polling periodik dari backend).
- **Scan** – Kamera + deteksi barcode, parsing IATA BCBP, hasil scan (valid/invalid/partial), dan publish ke Passenger List.
- **Manual Entry** – Draft otomatis untuk hasil scan partial, serta input manual/unggah/ambil foto untuk bantu decode.
- **Passenger List & Reports** – Daftar scan + filter, serta ekspor laporan (Excel/PDF/share).

## Tema

- Primary: biru korporat `#0066B3`
- Background: putih/abu sangat terang
- Valid: hijau; Invalid: merah
- Tombol dan area sentuh dibuat besar (thumb-friendly)

## Langkah Pengembangan Berikutnya

- Hardening produksi: HTTPS + konfigurasi base URL via `--dart-define=PIONA_API_BASE_URL=...`.
- Integrasi validasi boarding pass server-side (bukan hanya parse format BCBP).
- Refresh token / expiry policy dan UX offline/retry yang lebih kaya bila diperlukan.
- iOS: saat ini repo ini Android-first (folder `ios/` belum ada). Jika butuh iOS, scaffold proyek iOS dan set izin kamera/Info.plist.
