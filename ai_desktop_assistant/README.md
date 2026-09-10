# AI Kedi Asistani

Windows masaustunde duran, seffaf arka planli, Gemini destekli bir kedi
karakteri (PyQt6).

## Ozellikler

- Masaustunde sabit duran, fare ile surukleyip istediginiz yere
  tasiyabileceginiz bir kedi karakteri (`assets/` klasorunden okunur).
- Durumlar: normal, uyku (3 dakika hareketsizlikten sonra), dusunurken,
  mutlu (cevap geldiginde), hata.
- Sag tik menusu: boyut degistir (%50 / %75 / %100 / %150), kediye isim
  ver, Gemini API key ayarlari, cikis.
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
