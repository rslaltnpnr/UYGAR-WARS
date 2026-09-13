/// Uygulama kilidi PIN'i icin bicim kurali: 4 ila 6 basamakli, yalnizca
/// rakam. AppLockScreen (dogru/yanlis karsilastirmasi) ve ayarlar
/// dialogundaki PIN belirleme formu (gecerli bir PIN kaydedilmeden once)
/// tarafindan paylasilir.
bool isValidAppLockPin(String pin) => RegExp(r'^\d{4,6}$').hasMatch(pin);
