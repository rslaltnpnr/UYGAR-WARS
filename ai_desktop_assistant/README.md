# AI Kedi Asistani

Windows masaustunde duran, seffaf arka planli, Gemini destekli bir kedi
karakteri (PyQt6).

## Ozellikler

- Masaustunde sabit duran, fare ile surukleyip istediginiz yere
  tasiyabileceginiz bir kedi karakteri (`assets/` klasorunden okunur).
- Durumlar: normal, uyku (3 dakika hareketsizlikten sonra), dusunurken,
  mutlu (cevap geldiginde), hata.
- Sag tik menusu: boyut degistir (%50 / %75 / %100 / %150), birden
  fazla skin varsa aralarinda gecis, kediye isim ver, sohbet gecmisi,
  Gemini API key ayarlari, uzaktan kumanda bilgisi, Windows ile baslat,
  cikis.
- **Uzaktan kumanda**: `ai_cat_mobile` (Android) uygulamasindan ayni
  Wi-Fi agi uzerinden bir baglanti gonderip bilgisayarda acilmasini
  saglayabilirsiniz (orn. bir YouTube linki -> muzik/video calar).
  Sag tik > "Uzaktan Kumanda Bilgisi" ile IP, port, PIN ve sertifika
  parmak izini gorursunuz; bunlari telefon uygulamasindaki "Bilgisayari
  Kumanda Et" panelinde bir kez girmeniz yeterli.
  - Sunucu **HTTPS (TLS)** uzerinden calisir; ilk calistirmada otomatik
    olarak kendinden imzali bir sertifika (`remote_cert.pem`/
    `remote_key.pem`, `.gitignore`'da - asla paylasmayin/commitlemeyin)
    olusturulur. Telefon tarafinda "ilk baglantida guven" (TOFU) modeliyle
    sertifikanin parmak izi kaydedilir; sonradan degisirse (olasi bir
    araya girme/MITM saldirisi) baglanti reddedilir.
  - Acilacak URL'ler **SSRF korumasindan** gecer: hedef adres ozel/yerel
    ag (`192.168.x.x`, `10.x.x.x`), loopback (`127.0.0.1`), link-local
    veya benzeri ayrilmis bir IP'ye cozumleniyorsa istek reddedilir - bu
    sayede sizinle ayni agdaki biri PIN'i ele gecirse bile bunu
    yonlendiricinizin yonetim paneline ya da yerel bir servise erismek
    icin kullanamaz.
  - Sunucu, mumkunse `0.0.0.0` yerine sadece bilgisayarin gercek yerel ag
    arayuzune baglanir (agdaki gereksiz erisimi azaltmak icin).
  - PIN yanlissa istek reddedilir; ust uste 5 yanlis denemeden sonra o IP
    60 saniye kilitlenir (kaba kuvvet korumasi); PIN karsilastirmasi
    zamanlama yan kanal saldirilarina karsi sabit-zamanlidir.
- **Sistem tepsisi**: pencereyi kapatmadan simge durumuna alabilirsiniz;
  tepsi simgesine tiklayinca kedi geri gelir.
- **Windows ile otomatik baslatma**: sag tik menusundeki "Windows ile
  Baslat" onay kutusuyla acilip kapatilir (Baslangic kayit defteri
  anahtarina yazar/siler).
- **Genel kisayol tusu**: uygulama odakta olmasa bile `Ctrl+Shift+K`
  konusma balonunu acar (klavye kutuphanesi araciligiyla; kayit
  basarisiz olursa - orn. izin yoksa - uygulama bu ozellik olmadan
  sessizce calismaya devam eder).
- Sohbet gecmisi `chat_history.json`'da saklanir; sag tik menusundeki
  "Sohbet Gecmisi" panelinden gorulebilir ve temizlenebilir.
- Cift tiklayinca acilan konusma balonundan soru sorabilirsiniz; kedi
  "dusunme" gorseline gecer, `mss` ile ekran goruntusu alir, Gemini Flash
  modeline (goruntu + soru) gonderir ve yaniti balonda gosterir. Tum bu
  islem arka plan thread'inde (QThread) calisir, arayuz donmaz.

## Kurulum ve calistirma

```bash
python -m venv venv
venv\Scripts\activate        # Windows
pip install -r requirements.txt
python main.py
```

Ilk calistirmada `config.json` otomatik olusur. Sag tik menusunden
Gemini API anahtarinizi girmeniz yeterli
([Google AI Studio](https://aistudio.google.com/) uzerinden alabilirsiniz).

`assets/` klasorune kendi gorsellerinizi eklemezseniz uygulama basit bir
yer tutucu karakterle calismaya devam eder (bkz. `assets/README.md`).

## Tek dosya .exe olarak derleme (PyInstaller)

```bash
pip install pyinstaller

pyinstaller --onefile --windowed --name "AI-Kedi-Asistani" ^
    --add-data "assets;assets" main.py
```

Derlenen dosya `dist\AI-Kedi-Asistani.exe` altinda olusur.
Detaylı adimlar ve simge ekleme secenegi `main.py` dosyasinin en
altindaki yorum blogunda anlatilmistir.
