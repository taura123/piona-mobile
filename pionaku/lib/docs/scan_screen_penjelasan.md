# Penjelasan: Halaman Scan Normal/Transit (Tanpa Mengubah Kode)

## 1. Tabrakan tombol dan tulisan (overflow)

**Yang terjadi saat ini:**
- Di **header** (kotak putih "Boarding Pass Scan") ada satu baris (`Row`) yang berisi:
  - Titik hijau + teks status "READY Ready to scan"
  - Lalu di kanan: tombol **Focus**, tombol **ganti kamera**, dan kontrol **zoom** (tombol −, teks "0.0x", tombol +).
- Semua elemen itu diletakkan dalam satu baris dengan `Spacer()` di tengah. Di layar sempit (atau font besar), lebar total konten melebihi lebar layar sehingga terjadi **overflow** (konten “meluber” ke kanan).
- Flutter dalam **mode debug** lalu menggambar peringatan visual di area yang overflow.

**Kesimpulan:** Tabrakan bukan karena dua tombol yang saling tindih secara desain, melainkan **satu baris yang terlalu penuh** sehingga layout-nya overflow. Perbaikannya: mengatur ulang header (misalnya status dan kontrol dipisah ke dua baris, atau kontrol zoom tidak pakai baris yang sama) agar tidak ada yang meluber.

---

## 2. Kotak hitam kuning dan tulisan “OVERFLOWED”

**Apa itu:**
- Kotak **hitam‑kuning bergaris** dan tulisan seperti **"RIGHT OVERFLOWED BY 42 PIXELS"** adalah **overflow indicator** bawaan Flutter.
- Ini **bukan bagian dari desain aplikasi** dan **bukan fitur** untuk user. Fungsinya untuk **developer**: menandai bahwa ada widget yang melewati batas layout (overflow).
- Di **release build** (build untuk production) indikator ini **tidak ditampilkan**. Yang Anda lihat hanya muncul saat menjalankan aplikasi dalam **mode debug**.

**Apakah punya fungsi?**  
Tidak ada fungsi untuk user. Ini murni alat bantu debugging.

**Cara “menghapus”-nya:**  
Tidak perlu “menghapus” widget khusus. Setelah **layout diperbaiki** (misalnya baris header tidak lagi overflow), Flutter tidak lagi menggambar indikator ini, sehingga kotak hitam kuning dan tulisan overflow akan hilang dengan sendirinya.

---

## 3. Zoom in/out saat ini vs keinginan (pinch-to-zoom)

**Yang berjalan saat ini:**
- Zoom hanya bisa diubah lewat **tombol +** dan **−** di header.
- Tombol tersebut memanggil `_controller.setZoomScale(_zoomLevel)` dan state `_zoomLevel` diubah (naik/turun dengan langkah 0.25, dibatasi 1.0–4.0).

**Keinginan Anda:**
- Zoom in/out **langsung di area kotak kamera** dengan **gerakan mencubit (pinch)**.
- Jadi zoom diatur oleh gesture pinch di atas area preview kamera, bukan oleh tombol +/−.

**Implikasi:**  
Perlu menambahkan **GestureDetector** (atau widget gesture lain) dengan **ScaleStart/ScaleUpdate/ScaleEnd** di area kamera, lalu mengubah `_zoomLevel` dan memanggil `_controller.setZoomScale(...)` sesuai scale gesture. Tombol zoom +/− bisa **dihapus** dari UI agar tidak tabrakan dan sesuai keinginan (zoom hanya lewat pinch).

---

## 4. Tombol “Send Last Capture” → “Scan Manual”

**Yang berjalan saat ini:**
- Label tombol: **"Send Last Capture"**.
- Saat diklik:
  - Jika **sudah ada** hasil scan sebelumnya (`_lastResult` tidak null): modal hasil scan ditampilkan lagi.
  - Jika **belum ada** hasil scan: muncul Snackbar “Belum ada hasil scan. Arahkan kamera ke barcode.”

**Keinginan Anda:**
- Nama tombol diubah menjadi **"Scan Manual"**.
- Fungsinya: **memicu proses scan saat diklik**, sebagai **mitigasi** ketika scanner **tidak otomatis** membaca barcode yang sudah diarahkan ke kamera (user bisa “paksa” baca sekali dengan tap).

**Implikasi:**  
- **Label** cukup diubah dari "Send Last Capture" ke "Scan Manual".
- **Perilaku:** idealnya tombol ini memicu “satu kali baca barcode” dari frame kamera saat ini. Di package `mobile_scanner`, tidak ada API langsung “capture frame saat ini lalu decode”. Yang ada misalnya stream barcode (otomatis) dan `analyzeImage(path)` untuk file gambar. Opsi yang bisa dilakukan:
  - Tetap memakai hasil terakhir: jika sudah pernah dapat barcode, “Scan Manual” menampilkan lagi hasil itu (sama seperti sekarang, hanya label dan maksudnya yang dijelaskan sebagai “scan manual”).
  - Atau: saat “Scan Manual” diklik, scanner di-**restart** sebentar (stop lalu start) agar mesin deteksi “membaca ulang” frame; atau tampilkan pesan yang mengarahkan user untuk mengarahkan barcode ke kotak dan memanfaatkan deteksi otomatis.  
Implementasi detail bisa disesuaikan dengan API yang tersedia (misalnya jika nanti ada dukungan capture frame), tetapi nama dan maksud tombol sudah mengarah ke “scan manual” sebagai fallback saat otomatis tidak jalan.

---

## Ringkasan

| Topik | Keadaan saat ini | Yang akan dilakukan (setelah ubah kode) |
|-------|-------------------|----------------------------------------|
| Tabrakan / overflow | Satu baris di header terlalu penuh → overflow → tombol/tulisan “bertabrakan” | Header dirapikan (mis. status dan kontrol dipisah baris / ukuran), agar tidak overflow. |
| Kotak hitam kuning | Overflow indicator Flutter (debug), bukan fitur aplikasi | Hilang dengan sendirinya setelah overflow diperbaiki; tidak ada widget “kotak kuning” yang perlu dihapus di kode. |
| Zoom | Hanya lewat tombol + dan − | Tombol +/− dihapus; zoom hanya lewat **pinch-to-zoom** di area kotak kamera. |
| Send Last Capture | Nama dan perilaku saat ini seperti di atas | Diubah menjadi **"Scan Manual"**; perilaku diarahkan untuk mitigasi saat scan otomatis tidak jalan (tetap pakai hasil terakhir atau trigger baca ulang sesuai API). |

Setelah Anda setuju, langkah berikutnya adalah mengubah kode: rapikan layout header, hilangkan overflow, tambah pinch-to-zoom di kamera, hapus tombol zoom +/−, dan ganti "Send Last Capture" menjadi "Scan Manual" dengan penyesuaian perilaku di atas.
