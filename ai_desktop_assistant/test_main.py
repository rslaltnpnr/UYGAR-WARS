"""
main.py icindeki saf mantik fonksiyonlari icin testler (surum
karsilastirma, release secimi, SSRF korumasi). GUI/PyQt widget'lari
olusturmaz - main() cagirilmadigi surece QApplication hic acilmaz, bu
yuzden bu testler ekransiz (headless) CI'da da calisir.

Calistirmak icin:
    pip install -r requirements.txt -r requirements-dev.txt
    pytest
"""

from datetime import datetime, timedelta

from main import (
    HISTORY_ENTRY_MAX_FIELD_LENGTH,
    _parse_version,
    append_access_log,
    build_pairing_uri,
    describe_automation_rule,
    find_release_with_asset,
    format_access_log_line,
    format_automation_rules,
    format_history_entries,
    format_notifications,
    is_newer_version,
    is_url_safe_to_open,
    merge_history_entries,
    parse_hh_mm,
    prune_old_backups,
    record_connection,
    select_context_turns,
    should_fire_rule,
    should_run_auto_backup,
    tail_access_log,
    validate_custom_command,
)


class TestParseVersion:
    def test_basit_surum(self):
        assert _parse_version("v1.2.3") == (1, 2, 3)

    def test_v_onekisiz(self):
        assert _parse_version("1.2.3") == (1, 2, 3)

    def test_eksik_parca_sifir_sayilir(self):
        assert _parse_version("v1.2") == (1, 2)

    def test_sayisal_olmayan_parca_sifir_sayilir(self):
        assert _parse_version("vabc.2.3") == (0, 2, 3)


class TestIsNewerVersion:
    def test_daha_yuksek_patch_daha_yeni(self):
        assert is_newer_version("v1.1.1", "1.1.0") is True

    def test_daha_yuksek_minor_daha_yeni(self):
        assert is_newer_version("v1.2.0", "1.1.9") is True

    def test_ayni_surum_daha_yeni_degil(self):
        assert is_newer_version("v1.1.1", "1.1.1") is False

    def test_daha_eski_surum_daha_yeni_degil(self):
        assert is_newer_version("v1.0.0", "1.1.0") is False

    def test_cift_haneli_parcalar_sozluksel_degil(self):
        assert is_newer_version("v1.10.0", "1.9.0") is True

    def test_gecersiz_girdi_false_doner(self):
        assert is_newer_version(None, "1.0.0") is False


class TestFindReleaseWithAsset:
    def test_depo_release_listesini_masaustu_ve_mobil_karisikken_dogru_ayiklar(self):
        # Gercek senaryo: mobil daha yeni bir release yayinladi (sadece
        # .apk), masaustunun kendi surumu listede daha asagida. Ham
        # /releases/latest kullansaydik yanlislikla mobil release'ini
        # bulurduk.
        releases = [
            {
                "tag_name": "v1.0.1",
                "draft": False,
                "prerelease": False,
                "assets": [{"name": "ai-kedi-asistani.apk"}],
            },
            {
                "tag_name": "v1.2.1",
                "draft": False,
                "prerelease": False,
                "assets": [{"name": "AI-Kedi-Asistani.exe"}],
            },
        ]
        found = find_release_with_asset(releases, "AI-Kedi-Asistani.exe")
        assert found is not None
        assert found["tag_name"] == "v1.2.1"

    def test_taslak_release_atlanir(self):
        releases = [
            {
                "tag_name": "v2.0.0",
                "draft": True,
                "prerelease": False,
                "assets": [{"name": "AI-Kedi-Asistani.exe"}],
            },
            {
                "tag_name": "v1.0.0",
                "draft": False,
                "prerelease": False,
                "assets": [{"name": "AI-Kedi-Asistani.exe"}],
            },
        ]
        found = find_release_with_asset(releases, "AI-Kedi-Asistani.exe")
        assert found["tag_name"] == "v1.0.0"

    def test_on_surum_atlanir(self):
        releases = [
            {
                "tag_name": "v2.0.0-beta",
                "draft": False,
                "prerelease": True,
                "assets": [{"name": "AI-Kedi-Asistani.exe"}],
            },
            {
                "tag_name": "v1.0.0",
                "draft": False,
                "prerelease": False,
                "assets": [{"name": "AI-Kedi-Asistani.exe"}],
            },
        ]
        found = find_release_with_asset(releases, "AI-Kedi-Asistani.exe")
        assert found["tag_name"] == "v1.0.0"

    def test_eslesen_asset_yoksa_none_doner(self):
        releases = [
            {
                "tag_name": "v1.0.1",
                "draft": False,
                "prerelease": False,
                "assets": [{"name": "ai-kedi-asistani.apk"}],
            }
        ]
        assert find_release_with_asset(releases, "AI-Kedi-Asistani.exe") is None

    def test_bos_liste_none_doner(self):
        assert find_release_with_asset([], "AI-Kedi-Asistani.exe") is None


class TestIsUrlSafeToOpen:
    """IP literalleriyle test edilir - getaddrinfo bunlari gercek bir DNS
    sorgusu yapmadan yerel olarak cozer, bu yuzden testler ag erisimi
    gerektirmez ve CI'da guvenilir sekilde calisir."""

    def test_genel_ip_izinli(self):
        assert is_url_safe_to_open("http://8.8.8.8/x") is True

    def test_loopback_reddedilir(self):
        assert is_url_safe_to_open("http://127.0.0.1/x") is False

    def test_ozel_ag_reddedilir(self):
        assert is_url_safe_to_open("http://192.168.1.1/x") is False
        assert is_url_safe_to_open("http://10.0.0.1/x") is False
        assert is_url_safe_to_open("http://172.16.0.1/x") is False

    def test_link_local_reddedilir(self):
        assert is_url_safe_to_open("http://169.254.1.1/x") is False

    def test_localhost_hostname_reddedilir(self):
        assert is_url_safe_to_open("http://localhost/x") is False

    def test_gecersiz_sema_reddedilir(self):
        assert is_url_safe_to_open("ftp://8.8.8.8/x") is False
        assert is_url_safe_to_open("file:///etc/passwd") is False

    def test_cozulemeyen_host_reddedilir(self):
        assert is_url_safe_to_open("http://bu-host-kesinlikle-yok.invalid/x") is False


class TestValidateCustomCommand:
    def test_gecerli_isim_ve_baglanti_kabul_edilir(self):
        assert validate_custom_command("Haberler", "http://8.8.8.8/x") is None

    def test_bos_isim_reddedilir(self):
        assert validate_custom_command("  ", "http://8.8.8.8/x") is not None

    def test_bos_baglanti_reddedilir(self):
        assert validate_custom_command("Haberler", "  ") is not None

    def test_guvensiz_baglanti_reddedilir(self):
        error = validate_custom_command("Router", "http://192.168.1.1/x")
        assert error is not None
        assert "http(s)" in error.lower() or "http" in error.lower()

    def test_bos_isim_once_kontrol_edilir(self):
        # Hem isim hem baglanti gecersizse, once isim hatasi donmeli.
        error = validate_custom_command("", "")
        assert error == "Bir isim yaz."


class TestBuildPairingUri:
    def test_semayi_ve_yolu_icerir(self):
        uri = build_pairing_uri("192.168.1.5", 8765, "123456", "AA:BB")
        assert uri.startswith("aikedi://pair?")

    def test_tum_alanlar_sorgu_dizesinde_bulunur(self):
        uri = build_pairing_uri("192.168.1.5", 8765, "123456", "AA:BB:CC")
        assert "ip=192.168.1.5" in uri
        assert "port=8765" in uri
        assert "pin=123456" in uri
        # ':' url-encode edilir (%3A).
        assert "fp=AA%3ABB%3ACC" in uri

    def test_ozel_karakterler_dogru_kacirilir(self):
        uri = build_pairing_uri("10.0.0.1", 8765, "111111", "AA:BB & CC")
        assert "AA:BB & CC" not in uri
        assert "%26" in uri or "+" in uri or "%20" in uri


class TestMergeHistoryEntries:
    def test_yeni_kayitlar_eklenir(self):
        existing = [
            {"time": "2026-01-01 10:00", "question": "q1", "answer": "a1", "is_error": False}
        ]
        new = [
            {"time": "2026-01-01 11:00", "question": "q2", "answer": "a2", "is_error": False}
        ]
        added = merge_history_entries(existing, new)
        assert added == 1
        assert len(existing) == 2
        assert existing[1]["question"] == "q2"

    def test_ayni_zaman_soru_cevap_uclusu_tekrar_eklenmez(self):
        existing = [
            {"time": "2026-01-01 10:00", "question": "q1", "answer": "a1", "is_error": False}
        ]
        new = [
            {"time": "2026-01-01 10:00", "question": "q1", "answer": "a1", "is_error": False}
        ]
        added = merge_history_entries(existing, new)
        assert added == 0
        assert len(existing) == 1

    def test_ayni_liste_icindeki_tekrarlar_da_bir_kez_eklenir(self):
        existing = []
        new = [
            {"time": "2026-01-01 10:00", "question": "q1", "answer": "a1"},
            {"time": "2026-01-01 10:00", "question": "q1", "answer": "a1"},
        ]
        added = merge_history_entries(existing, new)
        assert added == 1
        assert len(existing) == 1

    def test_zaman_veya_soru_bos_kayit_atlanir(self):
        existing = []
        new = [
            {"time": "", "question": "q1", "answer": "a1"},
            {"time": "2026-01-01 10:00", "question": "", "answer": "a1"},
        ]
        added = merge_history_entries(existing, new)
        assert added == 0
        assert existing == []

    def test_dict_olmayan_kayit_atlanir(self):
        existing = []
        added = merge_history_entries(existing, ["gecersiz", 42, None])
        assert added == 0
        assert existing == []

    def test_alanlar_maksimum_uzunluga_kesilir(self):
        existing = []
        long_text = "x" * (HISTORY_ENTRY_MAX_FIELD_LENGTH + 100)
        new = [{"time": "2026-01-01 10:00", "question": long_text, "answer": long_text}]
        merge_history_entries(existing, new)
        assert len(existing[0]["question"]) == HISTORY_ENTRY_MAX_FIELD_LENGTH
        assert len(existing[0]["answer"]) == HISTORY_ENTRY_MAX_FIELD_LENGTH

    def test_eksik_is_error_false_varsayilir(self):
        existing = []
        new = [{"time": "2026-01-01 10:00", "question": "q1", "answer": "a1"}]
        merge_history_entries(existing, new)
        assert existing[0]["is_error"] is False


class TestSelectContextTurns:
    def test_kapaliysa_bos_liste_doner(self):
        entries = [{"question": "q1", "answer": "a1", "is_error": False}]
        assert select_context_turns(entries, enabled=False) == []

    def test_acikken_soru_cevaplar_donusturulur(self):
        entries = [
            {"question": "q1", "answer": "a1", "is_error": False},
            {"question": "q2", "answer": "a2", "is_error": False},
        ]
        result = select_context_turns(entries, enabled=True)
        assert result == [
            {"question": "q1", "answer": "a1"},
            {"question": "q2", "answer": "a2"},
        ]

    def test_hatali_kayitlar_haric_tutulur(self):
        entries = [
            {"question": "q1", "answer": "a1", "is_error": False},
            {"question": "q2", "answer": "hata mesaji", "is_error": True},
            {"question": "q3", "answer": "a3", "is_error": False},
        ]
        result = select_context_turns(entries, enabled=True)
        assert result == [
            {"question": "q1", "answer": "a1"},
            {"question": "q3", "answer": "a3"},
        ]

    def test_sadece_son_max_turns_kadar_alinir(self):
        entries = [
            {"question": f"q{i}", "answer": f"a{i}", "is_error": False}
            for i in range(10)
        ]
        result = select_context_turns(entries, enabled=True, max_turns=3)
        assert [t["question"] for t in result] == ["q7", "q8", "q9"]

    def test_gecmis_bossa_bos_liste_doner(self):
        assert select_context_turns([], enabled=True) == []


class TestFormatHistoryEntries:
    def test_en_yeni_en_ustte(self):
        entries = [
            {"time": "2026-01-01 10:00", "question": "q1", "answer": "a1"},
            {"time": "2026-01-01 11:00", "question": "q2", "answer": "a2"},
        ]
        text = format_history_entries(entries)
        assert text.index("q2") < text.index("q1")

    def test_hata_isaretiyle_isaretlenir(self):
        entries = [
            {"time": "2026-01-01 10:00", "question": "q1", "answer": "hata!", "is_error": True}
        ]
        text = format_history_entries(entries)
        assert "⚠ hata!" in text

    def test_bos_liste_bos_metin_doner(self):
        assert format_history_entries([]) == ""


class TestRecordConnection:
    def test_yeni_ip_eklenir(self):
        conns = {}
        record_connection(conns, "1.2.3.4", "/open", 1000.0, max_connections=5)
        assert conns["1.2.3.4"]["count"] == 1
        assert conns["1.2.3.4"]["last_endpoint"] == "/open"
        assert conns["1.2.3.4"]["last_seen_epoch"] == 1000.0

    def test_ayni_ip_tekrar_gelince_sayac_artar_ve_guncellenir(self):
        conns = {}
        record_connection(conns, "1.2.3.4", "/open", 1000.0, max_connections=5)
        record_connection(conns, "1.2.3.4", "/media", 1010.0, max_connections=5)
        assert conns["1.2.3.4"]["count"] == 2
        assert conns["1.2.3.4"]["last_endpoint"] == "/media"
        assert conns["1.2.3.4"]["last_seen_epoch"] == 1010.0

    def test_kapasite_asilinca_en_eski_ip_cikarilir(self):
        conns = {}
        record_connection(conns, "1.1.1.1", "/open", 1000.0, max_connections=2)
        record_connection(conns, "2.2.2.2", "/open", 2000.0, max_connections=2)
        record_connection(conns, "3.3.3.3", "/open", 3000.0, max_connections=2)
        assert "1.1.1.1" not in conns
        assert set(conns) == {"2.2.2.2", "3.3.3.3"}

    def test_kapasite_doluyken_mevcut_ip_guncellenmesi_baskasini_cikarmaz(self):
        conns = {}
        record_connection(conns, "1.1.1.1", "/open", 1000.0, max_connections=2)
        record_connection(conns, "2.2.2.2", "/open", 2000.0, max_connections=2)
        record_connection(conns, "1.1.1.1", "/media", 3000.0, max_connections=2)
        assert set(conns) == {"1.1.1.1", "2.2.2.2"}
        assert conns["1.1.1.1"]["count"] == 2


class TestShouldRunAutoBackup:
    def test_hic_yedek_yoksa_true_doner(self):
        assert should_run_auto_backup(None, datetime(2026, 1, 2)) is True
        assert should_run_auto_backup("", datetime(2026, 1, 2)) is True

    def test_gecersiz_tarih_true_doner(self):
        assert should_run_auto_backup("gecersiz-tarih", datetime(2026, 1, 2)) is True

    def test_interval_dolmamissa_false_doner(self):
        last = datetime(2026, 1, 1, 10, 0).isoformat()
        now = datetime(2026, 1, 1, 20, 0)  # 10 saat sonra
        assert should_run_auto_backup(last, now, interval_days=1) is False

    def test_interval_dolmussa_true_doner(self):
        last = datetime(2026, 1, 1, 10, 0).isoformat()
        now = datetime(2026, 1, 2, 11, 0)  # 25 saat sonra
        assert should_run_auto_backup(last, now, interval_days=1) is True

    def test_tam_interval_sinirinda_true_doner(self):
        last = datetime(2026, 1, 1, 10, 0)
        now = last + timedelta(days=1)
        assert should_run_auto_backup(last.isoformat(), now, interval_days=1) is True


class TestParseHhMm:
    def test_gecerli_saat_normallestirilir(self):
        assert parse_hh_mm("9:5") == "09:05"
        assert parse_hh_mm(" 18:30 ") == "18:30"
        assert parse_hh_mm("00:00") == "00:00"
        assert parse_hh_mm("23:59") == "23:59"

    def test_iki_parca_degilse_none_doner(self):
        assert parse_hh_mm("1830") is None
        assert parse_hh_mm("18:30:00") is None

    def test_sayi_degilse_none_doner(self):
        assert parse_hh_mm("ab:cd") is None

    def test_aralik_disinda_none_doner(self):
        assert parse_hh_mm("24:00") is None
        assert parse_hh_mm("12:60") is None
        assert parse_hh_mm("-1:00") is None


class TestShouldFireRule:
    def test_devre_disi_kural_hicbir_zaman_ateslenmez(self):
        rule = {"enabled": False, "trigger_type": "time_daily", "trigger_value": "10:00"}
        now = datetime(2026, 1, 1, 10, 0)
        assert should_fire_rule(rule, now, idle_seconds=0) is False

    def test_gunluk_saat_tutmuyorsa_ateslenmez(self):
        rule = {"trigger_type": "time_daily", "trigger_value": "10:00"}
        now = datetime(2026, 1, 1, 9, 59)
        assert should_fire_rule(rule, now, idle_seconds=0) is False

    def test_gunluk_saat_tutunca_ilk_kez_ateslenir(self):
        rule = {"trigger_type": "time_daily", "trigger_value": "10:00", "last_fired": None}
        now = datetime(2026, 1, 1, 10, 0)
        assert should_fire_rule(rule, now, idle_seconds=0) is True

    def test_gunluk_kural_bugun_zaten_ateslendiyse_tekrar_ateslenmez(self):
        rule = {
            "trigger_type": "time_daily",
            "trigger_value": "10:00",
            "last_fired": datetime(2026, 1, 1, 10, 0).isoformat(),
        }
        now = datetime(2026, 1, 1, 10, 0)
        assert should_fire_rule(rule, now, idle_seconds=0) is False

    def test_gunluk_kural_ertesi_gun_tekrar_ateslenir(self):
        rule = {
            "trigger_type": "time_daily",
            "trigger_value": "10:00",
            "last_fired": datetime(2026, 1, 1, 10, 0).isoformat(),
        }
        now = datetime(2026, 1, 2, 10, 0)
        assert should_fire_rule(rule, now, idle_seconds=0) is True

    def test_hareketsizlik_esigi_asilmamissa_ateslenmez(self):
        rule = {"trigger_type": "idle_minutes", "trigger_value": 30, "last_fired": None}
        now = datetime(2026, 1, 1, 10, 0)
        assert should_fire_rule(rule, now, idle_seconds=29 * 60) is False

    def test_hareketsizlik_esigi_asilinca_ateslenir(self):
        rule = {"trigger_type": "idle_minutes", "trigger_value": 30, "last_fired": None}
        now = datetime(2026, 1, 1, 10, 0)
        assert should_fire_rule(rule, now, idle_seconds=30 * 60) is True

    def test_hareketsizlikte_ayni_pencerede_tekrar_ateslenmez(self):
        rule = {
            "trigger_type": "idle_minutes",
            "trigger_value": 30,
            "last_fired": datetime(2026, 1, 1, 10, 0).isoformat(),
        }
        now = datetime(2026, 1, 1, 10, 20)  # sadece 20 dk sonra, esik 30 dk
        assert should_fire_rule(rule, now, idle_seconds=50 * 60) is False

    def test_hareketsizlik_esigi_yeniden_asilinca_tekrar_ateslenir(self):
        rule = {
            "trigger_type": "idle_minutes",
            "trigger_value": 30,
            "last_fired": datetime(2026, 1, 1, 10, 0).isoformat(),
        }
        now = datetime(2026, 1, 1, 10, 35)  # 35 dk sonra, esik 30 dk asildi
        assert should_fire_rule(rule, now, idle_seconds=60 * 60) is True

    def test_bilinmeyen_tetikleyici_turu_false_doner(self):
        rule = {"trigger_type": "bilinmeyen", "trigger_value": "x"}
        assert should_fire_rule(rule, datetime(2026, 1, 1), idle_seconds=999999) is False


class TestDescribeAndFormatAutomationRules:
    def test_aktif_kural_ozeti(self):
        rule = {
            "name": "Ise gec kalma",
            "trigger_type": "time_daily",
            "trigger_value": "18:00",
            "action_type": "notify",
            "action_value": "Eve gitme zamani!",
            "enabled": True,
        }
        desc = describe_automation_rule(rule)
        assert "Ise gec kalma" in desc
        assert "18:00" in desc
        assert "Eve gitme zamani!" in desc
        assert "devre disi" not in desc

    def test_devre_disi_kural_ozetinde_belirtilir(self):
        rule = {
            "name": "Test",
            "trigger_type": "idle_minutes",
            "trigger_value": 30,
            "action_type": "lock",
            "enabled": False,
        }
        assert "[devre disi]" in describe_automation_rule(rule)

    def test_format_bos_listede_bos_metin_doner(self):
        assert format_automation_rules([]) == ""

    def test_format_numaralandirir(self):
        rules = [
            {"name": "A", "trigger_type": "time_daily", "trigger_value": "09:00",
             "action_type": "lock", "enabled": True},
            {"name": "B", "trigger_type": "idle_minutes", "trigger_value": 5,
             "action_type": "sleep", "enabled": True},
        ]
        text = format_automation_rules(rules)
        lines = text.split("\n")
        assert lines[0].startswith("1. ")
        assert lines[1].startswith("2. ")


class TestPruneOldBackups:
    def test_dizin_yoksa_hicbir_sey_yapmaz(self, tmp_path):
        missing = tmp_path / "yok"
        prune_old_backups(str(missing), keep_count=3)  # patlamamali

    def test_fazla_dosyalar_en_eskiden_baslayarak_silinir(self, tmp_path):
        names = [
            "otomatik-yedek-2026-01-01-000000.json",
            "otomatik-yedek-2026-01-02-000000.json",
            "otomatik-yedek-2026-01-03-000000.json",
        ]
        for name in names:
            (tmp_path / name).write_text("{}")
        prune_old_backups(str(tmp_path), keep_count=2)
        remaining = sorted(p.name for p in tmp_path.iterdir())
        assert remaining == names[1:]

    def test_kapasitenin_altindaysa_hicbir_sey_silinmez(self, tmp_path):
        (tmp_path / "otomatik-yedek-2026-01-01-000000.json").write_text("{}")
        prune_old_backups(str(tmp_path), keep_count=5)
        assert len(list(tmp_path.iterdir())) == 1

    def test_ilgisiz_dosyalara_dokunmaz(self, tmp_path):
        (tmp_path / "baska-dosya.txt").write_text("x")
        for i in range(3):
            (tmp_path / f"otomatik-yedek-2026-01-0{i + 1}-000000.json").write_text("{}")
        prune_old_backups(str(tmp_path), keep_count=1)
        remaining = sorted(p.name for p in tmp_path.iterdir())
        assert "baska-dosya.txt" in remaining
        assert len(remaining) == 2  # baska-dosya.txt + tutulan 1 yedek


class TestFormatAccessLogLine:
    def test_detay_olmadan(self):
        line = format_access_log_line("2026-01-01 10:00:00", "1.2.3.4", "istek")
        assert line == "2026-01-01 10:00:00\t1.2.3.4\tistek"

    def test_detayla(self):
        line = format_access_log_line("2026-01-01 10:00:00", "1.2.3.4", "istek", "/open")
        assert line == "2026-01-01 10:00:00\t1.2.3.4\tistek\t/open"


class TestAppendAccessLog:
    def test_dosya_yoksa_olusturur_ve_yazar(self, tmp_path):
        path = str(tmp_path / "log.txt")
        append_access_log(path, "satir1", max_bytes=1_000_000)
        append_access_log(path, "satir2", max_bytes=1_000_000)
        with open(path, "r", encoding="utf-8") as f:
            content = f.read()
        assert content == "satir1\nsatir2\n"

    def test_boyut_asilinca_en_eski_yari_atilir(self, tmp_path):
        path = str(tmp_path / "log.txt")
        # Her satir yaklasik ayni uzunlukta - dosyayi max_bytes'i asacak
        # sekilde doldurup rotasyonun tetiklendigini dogruluyoruz.
        for i in range(20):
            append_access_log(path, f"satir-{i:03d}", max_bytes=100)
        with open(path, "r", encoding="utf-8") as f:
            lines = f.readlines()
        assert len(lines) < 20  # eski satirlarin bir kismi atilmis olmali
        assert lines[-1].strip() == "satir-019"  # en yenisi hep korunur


class TestTailAccessLog:
    def test_dosya_yoksa_bos_liste_doner(self, tmp_path):
        assert tail_access_log(str(tmp_path / "yok.txt")) == []

    def test_son_n_satiri_dondurur(self, tmp_path):
        path = str(tmp_path / "log.txt")
        with open(path, "w", encoding="utf-8") as f:
            for i in range(10):
                f.write(f"satir-{i}\n")
        result = tail_access_log(path, max_lines=3)
        assert result == ["satir-7", "satir-8", "satir-9"]

    def test_dosya_max_lines_altindaysa_hepsini_doner(self, tmp_path):
        path = str(tmp_path / "log.txt")
        with open(path, "w", encoding="utf-8") as f:
            f.write("tek-satir\n")
        assert tail_access_log(path, max_lines=50) == ["tek-satir"]


class TestFormatNotifications:
    def test_en_yeni_en_ustte(self):
        entries = [
            {"time": "2026-01-01 10:00", "title": "Baslik1", "message": "Mesaj1"},
            {"time": "2026-01-01 11:00", "title": "Baslik2", "message": "Mesaj2"},
        ]
        text = format_notifications(entries)
        assert text.index("Baslik2") < text.index("Baslik1")

    def test_baslik_ve_mesaj_icerir(self):
        entries = [{"time": "2026-01-01 10:00", "title": "T", "message": "M"}]
        text = format_notifications(entries)
        assert "[2026-01-01 10:00] T" in text
        assert "M" in text

    def test_bos_liste_bos_metin_doner(self):
        assert format_notifications([]) == ""
