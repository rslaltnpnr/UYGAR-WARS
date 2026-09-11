# AI Kedi Asistani (Android)

Masaustu uygulamasiyla (`ai_desktop_assistant/`) ayni mantik: Gemini
destekli, konusma gecmisi tutan bir kedi asistani. Farki: burada kedi
tum masaustunde degil, **uygulamanin kendi ekraninda** rastgele gezinir
(sistem geneli "diger uygulamalarin uzerinde gezinen overlay" degildir
- Android'de bu, ayri izinler ve native bir proje gerektirir).

## Ozellikler

- Uygulama ekraninda rastgele gezinen kedi (durumlar: normal, uyku,
  dusunurken, mutlu, hata - masaustu suruumuyle ayni 5 gorsel).
- Kediye **dokununca** metin ve/veya fotograf (galeri ya da kamera)
  ile soru sorabileceginiz bir sohbet paneli aciliyor.
- Kediyi **uzun basinca** ayarlar (kedi ismi, Gemini API Key, **acik/koyu/
  sistem temasi**) aciliyor. Tema tercihi cihazda saklanir.
- 3 dakika dokunulmazsa kedi uyku moduna geciyor.
- Sohbet gecmisi cihazda saklaniyor (en fazla 200 kayit), panelde
  goruntulenip temizlenebiliyor.
- **Hatirlatici** (alarm ikonu): "X dakika sonra hatirlat" seklinde tekil
  bir yerel bildirim kurabilirsiniz - bulut/Firebase gerekmez, tamamen
  cihaz uzerinde calisir. Android 13+ icin bildirim izni ister.
- Gemini istekleri: 503 (asiri yuklenme) ve 404 (model kaldirildi)
  durumlarinda masaustu suruumundeki gibi otomatik tekrar deneme ve
  yedek modele (`gemini-3.6-flash`) gecis var.
- **"Bilgisayari Kumanda Et"** paneli (sag ustteki bilgisayar ikonu):
  ayni Wi-Fi agindaki `ai_desktop_assistant` uygulamasina bir baglanti
  gonderip bilgisayarda acilmasini saglar (orn. bir YouTube linki
  gondererek muzik/video baslatabilirsiniz). Bilgisayardaki kedi
  uygulamasinin sag tik menusundeki "Uzaktan Kumanda Bilgisi"nden IP,
  port ve PIN'i alip bu panelde bir kez girmeniz yeterli. YouTube,
  YouTube Music, Spotify ve Google icin hazir baglanti butonlari da var.
  **Birden fazla bilgisayarla** (orn. "Ev", "Is") eslesip aralarinda
  gecis yapabilirsiniz - her biri kendi IP/port/PIN/sertifika kaydini
  tasir.
  Baglanti **HTTPS (TLS)** ile sifrelenir; sunucu kendinden imzali bir
  sertifika kullandigi icin telefon ilk baglantida sertifikanin SHA-256
  parmak izini kaydeder ("ilk baglantida guven" / TOFU - SSH host key'lere
  benzer bir model) ve sonraki baglantilarda bu parmak izinin ayni
  kalmasini dogrular; degisirse (olasi bir araya girme/MITM saldirisi)
  baglanti reddedilir ve acik bir uyari gosterilir. Panelde "Sertifika
  eslestirmesini sifirla" ile bu kaydi silip yeniden eslestirebilirsiniz
  (orn. bilgisayar uygulamasi yeniden kurulduysa). Baglanti acmanin
  yaninda ayni panelden: **medya kontrolu** (oynat/duraklat, ileri/geri,
  ses acma/kisma/sessize alma), **kilitle/uyku** butonlari (onay sorar)
  ve bilgisayarin kucultulmus bir **ekran goruntusunu** isteyip
  gorebilirsiniz.

## 1) Gerekli araclari kurun (Windows)

1. **Flutter SDK**: https://docs.flutter.dev/get-started/install/windows
   adresinden indirip bir klasore (orn. `C:\src\flutter`) acin ve
   `C:\src\flutter\bin` klasorunu PATH'e ekleyin.
2. **Android Studio**: https://developer.android.com/studio adresinden
   kurun (Android SDK'yi da otomatik kurar). Kurulumda "Android Virtual
   Device" bilesenini de isaretleyin (fiziksel telefon yerine emulator
   kullanmak isterseniz).
3. Kurulumu dogrulayin:

```powershell
flutter doctor
```

Kirmizi/carpi isaretli maddeleri (orn. Android lisanslari) `flutter
doctor --android-licenses` ile kabul ederek giderin.

## 2) Projeyi calistirin

```powershell
cd ai_cat_mobile
flutter pub get
```

Telefonunuzu USB ile baglayip **Gelistirici Secenekleri > USB Hata
Ayiklama**yi acin (ya da Android Studio'dan bir emulator baslatin),
sonra:

```powershell
flutter devices   # telefonun gorunuyor mu kontrol edin
flutter run
```

Uygulama acildiginda sag ustteki disli simgesine basip (ya da kediye
uzun basip) Gemini API Key'inizi girin
([Google AI Studio](https://aistudio.google.com/) uzerinden alabilirsiniz).

## 3) Kendi kedi gorsellerinizi ekleyin (opsiyonel)

`assets/cat/` klasorune masaustu uygulamasindaki ayni 5 dosyayi
(`fuff_norm.png`, `fuff_zzz.png`, `fuff_smile.png`, `fuff_stern.png`,
`fuff_fear.png`) kopyalayin (bkz. `assets/cat/README.md`). Eklemezseniz
uygulama basit bir yer tutucu daire ile calismaya devam eder.

## 4) Yayinlanabilir APK olarak derleme

```powershell
flutter build apk --release
```

Derlenen dosya `build\app\outputs\flutter-apk\app-release.apk`
altinda olusur. Bu dosyayi telefona kopyalayip (ya da `flutter install`
ile dogrudan bagli telefona yukleyip) kurabilirsiniz - Play Store
disindan kurulum icin telefonda "Bilinmeyen kaynaklardan yukleme"
izni gerekebilir.

Daha kucuk/optimize bir dosya icin cihaz mimarisine gore bolunmus
APK'lar da alabilirsiniz:

```powershell
flutter build apk --release --split-per-abi
```

## Notlar

- API anahtari ve ayarlar cihazda `shared_preferences` ile duz metin
  olarak saklanir (masaustu suruumundeki `config.json` ile ayni
  guvenlik seviyesi) - sifreli bir kasa degildir.
- `AndroidManifest.xml`'e INTERNET (Gemini API ve uzaktan kumanda icin)
  ve CAMERA (fotograf cekme icin) izinleri zaten eklenmis durumda. Tum ag
  trafigi HTTPS uzerinden gittigi icin `usesCleartextTraffic="false"`
  (duz metin trafik kapali).
- Bu, sistem geneli "her uygulamanin ustunde gezinen" bir overlay
  DEGILDIR; kedi yalnizca bu uygulama acikken, uygulamanin kendi
  ekraninda gezinir.
