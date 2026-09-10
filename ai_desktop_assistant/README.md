# AI Masaustu Yardimcisi

Windows masaustunde dolasan, seffaf arka planli, Gemini destekli bir
masaustu karakteri (PyQt6).

## Ozellikler

- Gorev cubugunun hemen ustunde rastgele sola/saga yuruyen, bazen duran
  bir karakter (idle/walk animasyonu, `assets/` klasorunden okunur).
- Fare ile surukleyip istediginiz yere tasiyabilirsiniz.
- Sag tik menusu: boyut (%50 / %100 / %150), karakter ismi degistirme,
  Gemini API anahtari ayari, cikis.
- Cift tiklayinca acilan konusma balonundan soru sorabilirsiniz; karakter
  "think" gorseline gecer, `mss` ile ekran goruntusu alir, Gemini Flash
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

pyinstaller --onefile --windowed --name "AI-Masaustu-Yardimcisi" ^
    --add-data "assets;assets" main.py
```

Derlenen dosya `dist\AI-Masaustu-Yardimcisi.exe` altinda olusur.
Detaylı adimlar ve simge ekleme secenegi `main.py` dosyasinin en
altindaki yorum blogunda anlatilmistir.
