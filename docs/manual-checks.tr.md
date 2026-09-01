# Elle yapılan kontroller

> İngilizcesi: [`manual-checks.md`](manual-checks.md). İki dosya aynı listedir;
> biri değişirse diğeri de değişmeli.

Bu listedeki her şey için ekranı gören ve fareyi tutan bir insan gerekiyor.
Hiçbiri ekransız bir oturumdan otomatikleştirilemez ve ilk sürüm yazılırken hepsi
doğrulanmadan bırakıldı — yani bu liste, "testler geçiyor" ile "birisi bunun
çalıştığını gerçekten gördü" arasındaki en kısa yol.

Sürüm çıkarmadan önce çalıştır. Yaklaşık on dakika sürer.

Arayüz varsayılan olarak **İngilizce** açılır; Türkçe görmek için sistem dilin
Türkçe olmalı ya da System Settings → General → Language & Region → en alttaki
uygulama listesinden Ledge'e Türkçe atamalısın. Aşağıda etiketleri iki dilde de
verdim: **İngilizce** (Türkçe).

## Kurulum

```
open Ledge.xcodeproj      # ⌘R
```

Uygulamanın Dock ikonu yok. Menü çubuğunda bir ikon ara.

macOS **"Not enough room to show “Ledge”"** derse menü çubuğu doludur ve durum
ikonu hiç oluşturulmamıştır — uygulama çalışıyordur, sadece görünecek yeri yoktur.
Çentikli MacBook'larda sık görülür, çünkü çentik çubuğun ortasını yer. Bir slot aç
(⌘ basılı tutup bir ikonu çubuğun dışına sürükle ya da System Settings → Control
Center'dan modülleri kapat), sonra **Ledge'i yeniden başlat** — ikon, başarısızlık
sonrası yeniden denenmez. Menü çubuğu yöneticileri işe yaramaz: onlar ikonları
gizler, slot yaratmaz.

macOS ilk açılışta `~/Downloads` klasörünü okuma izni ister. **İzin ver** — reddedersen
sessizce hiçbir şey yapmayan bir uygulama yerine durumu açıklayan bir ekran
görmelisin, ki o da 9. kontrol.

---

## 1. Raf sürükleniyor — ürün bu

`~/Downloads` içine bir dosya bırak, yaklaşık beş saniye bekle, menü çubuğu
ikonuna tıkla. Satır, altında hedefiyle birlikte görünür.

**Satırı masaüstüne sürükle.** Dosya oraya düşmeli.

Bu çalışmıyorsa gerisinin önemi yok: sürükleyip çıkarma olmadan kural tabanlı
klasörleme sadece bir düzenleyicidir, oysa bütün önerme ikisini birden yapmaktı.

## 2. Geri alma dosyayı geri getiriyor

Satırdaki geri alma okuna tıkla. Dosya `~/Downloads`'a döner ve satır kaybolur.

Sonra raf açıkken **⌘Z**'ye bas — en son taşımayı geri almalı. O taşıma bir
**Organize Now** (Şimdi Düzenle) grubunun parçasıysa ⌘Z tek satırı değil, grubun
tamamını geri alır.

Boş rafta ⌘Z hiçbir şey yapmamalı — hata yok, bip yok.

## 3. Bayatlamış satır sesini kesiyor

Bir şeyi klasörlet, sonra o dosyayı Finder'dan başka bir yere taşı. Rafı kapat ve
**yeni bir şey indirmeden** tekrar aç.

Satır solmalı, sürüklenmeyi reddetmeli, geri alma butonu gri olmalı. Buradaki en
zayıf halka geri alma — özellikle onu kontrol et.

Sonra dosyayı geri taşı ve rafı tekrar aç. Satır yeniden canlanmalı.

## 4. Proje modu indirilenleri yönlendiriyor

Rafın üstündeki hedef menüsünü aç, **Choose Project…** (Proje Seç…) seç ve bir
klasör belirle. Başlık o klasörü adıyla anmalı ve menü çubuğu ikonunun şekli
değişmeli.

Bir şey indir. `~/Downloads` içine değil, o projenin kategori alt klasörüne
düşmeli.

Sonra geri al. **`~/Downloads`'a dönmeli** — bulunduğu yere — projenin içine
değil. Bu ayrım kasıtlı.

İşin bitince hedefi tekrar **Downloads** (İndirilenler) yap.

## 5. Şimdi Düzenle bir klasörü asla bölmüyor

İçinde hem serbest dosyalar hem de **dosya barındıran bir alt klasör** olan geçici
bir klasör hazırla:

```
mkdir -p ~/Downloads/scratch/"Some Project"
cd ~/Downloads/scratch
touch a.png b.png c.mp4 notes.txt
touch "Some Project/inner.png"
```

Ayarlardan `~/Downloads/scratch` klasörünü izlenecek klasör olarak ekle, sonra
**Organize Now…** (Şimdi Düzenle…) açıp onu seç.

Önizleme `Some Project` klasörünü **tek** bir girdi olarak listelemeli, asla
`inner.png` olarak değil. Taşı, sonra `inner.png` dosyasının hâlâ `Some Project`
içinde olduğunu doğrula. Ardından **Undo Last Batch** (Son Grubu Geri Al) ile her
şeyin geri döndüğünü doğrula.

Bitince izlenen klasörü kaldır ve `rm -rf ~/Downloads/scratch` çalıştır.

## 6. Bir diski çıkarmak seni kilitlemiyor

Harici bir diskteki klasörü izliyorsan: Ledge çalışırken diski çıkar.

**Settings** (Ayarlar) ve **Quit** (Çık) hâlâ erişilebilir olmalı. Eskiden böyle
değildi — bir izin ekranı, ikisi dahil rafın tamamının yerini alıyordu ve çıkışın
tek yolu Activity Monitor'dü.

Bir klasör engelliyken diğeri okunabiliyorsa, çalışan klasörün rafı hâlâ görünür
olmalı ve klasörlemeye devam etmeli. Engellenen klasör bir bildirim şeridi alır,
ekranı ele geçirmez.

## 7. Girişte başlatma

Ayarlardan aç, sonra kontrol et:

```
sfltool dumpbtm | grep -i ledge
```

İstemiyorsan tekrar kapat.

## 8. Türkçe yerleşim — yalnızca Ledge'i Türkçe çalıştırıyorsan

Arayüz yerelleştirildi, ama **sistem dilin Türkçe olmadıkça Türkçe görünmez**;
alternatif olarak System Settings → General → Language & Region → en alttaki
uygulama listesinden Ledge'e ayrıca Türkçe atayabilirsin.

Atarsan, kırılmaya en yatkın yerler sırasıyla şunlar:

1. **Ayarlar → Kurallar tanılamaları.** Pencere sabit 560 × 460 ve uyarı metni hiç
   kısaltılmıyor — genişliyor. Türkçe %27–35 daha uzun. Aynı anda iki üç kategoriyi
   uyarı durumuna sok: ikisini `Images` ve `IMAGES` diye adlandır, birine de üstteki
   bir kuralın zaten sahiplendiği bir uzantıyı ver. Panelin pencereyi taşırıp
   taşırmadığına bak.
2. **Raf satırının alt başlığı.** `Taşınmış veya silinmiş`, İngilizcesinden %38 daha
   uzun ve uygulamanın yatayda en dar bütçesinde, tarih ile geri alma butonuyla
   yarışarak duruyor. Uzun adlı, bayatlamış bir satıra bak.
3. **Şimdi Düzenle penceresindeki taşıma butonu** üç haneli bir sayıyla
   (`%lld Öğeyi Taşı`).

## 9. Reddedilen izin kendini açıklıyor

System Settings → Privacy & Security → Files and Folders altından Ledge'in
`~/Downloads` erişimini kaldır, sonra rafı tekrar aç.

Neyin yanlış olduğunu söyleyen ve düzeltme yolu sunan bir ekran görmelisin — yanında
**Settings** (Ayarlar) ve **Quit** (Çık) ile birlikte, ki bunlar asla kaybolmamalı.

## 10. Burada hiç doğrulanamayanlar

- Menü çubuğu panelinin, erişim **kapalıyken kaldırıldığında** bunu fark edip
  etmediği. Bu durumu yakalayan tek sinyal odur ve hiçbir ajan test edemedi.
- Yerleşimin gerçekte nasıl göründüğüne dair her şey: boşluklar, hizalama ve
  Şimdi Düzenle penceresi iliştiğinde panelin ekranlar arası çerçeve sıçramasının
  bir hata gibi durup durmadığı.
