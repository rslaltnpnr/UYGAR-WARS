# assets

Kedi karakterinin gorsellerini bu klasore koyun (PNG, seffaf arka plan
onerilir):

- `fuff_norm.png` — normal durus (varsayilan)
- `fuff_zzz.png` — uyku (3 dakika hareketsizlikten sonra)
- `fuff_smile.png` — mutlu / cevap geldiginde
- `fuff_stern.png` — dusunurken / analiz ederken
- `fuff_fear.png` — hata durumunda

Bu dosyalar eksikse uygulama otomatik olarak basit bir yer tutucu
gorsel cizer ve calismaya devam eder; yani gorselleri eklemeden once
de uygulamayi test edebilirsiniz.

## Birden fazla skin (kedi gorseli seti) eklemek

Kok dizindeki (yukaridaki) gorseller her zaman "Varsayilan" skin
olarak kalir. Baska bir gorsel seti eklemek icin `assets/` altinda
yeni bir klasor acin ve icine ayni 5 dosyayi (`fuff_norm.png`,
`fuff_zzz.png`, `fuff_smile.png`, `fuff_stern.png`, `fuff_fear.png`)
koyun, orn:

```
assets/
  fuff_norm.png        <- Varsayilan skin
  ...
  turuncu/
    fuff_norm.png       <- "turuncu" adinda yeni bir skin
    fuff_zzz.png
    fuff_smile.png
    fuff_stern.png
    fuff_fear.png
```

Uygulamayi yeniden baslattiginizda sag tik menusunde "Kedi Skin'i"
alt menusu altinda yeni klasoru secebilirsiniz.
